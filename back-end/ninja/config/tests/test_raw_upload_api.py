import hashlib
from urllib.request import Request, urlopen

import pytest

from mobility.upload import storage

from .test_upload_and_trips_api import complete_core, post_json, start_recording


pytestmark = pytest.mark.django_db


@pytest.fixture
def local_minio(settings):
    settings.S3_ENDPOINT_URL = "http://localhost:9000"
    settings.S3_PUBLIC_ENDPOINT_URL = "http://localhost:9000"
    storage._internal_client.cache_clear()
    storage._public_client.cache_clear()
    yield
    storage._internal_client.cache_clear()
    storage._public_client.cache_clear()


def test_raw_upload_reports_missing_parts_then_queues_enrichment(
    api_client, mobile_session, local_minio
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    core = complete_core(
        api_client,
        headers,
        upload_id,
        expected_raw_parts=1,
    )

    before_upload = api_client.get(
        f"/api/upload/trips/{upload_id}", **headers
    )
    raw_bytes = b"deterministic raw sensor fixture"
    checksum = hashlib.sha256(raw_bytes).hexdigest()
    presigned = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/parts/presign",
        {"sequence": 1, "sha256": checksum},
        headers,
    )
    upload = Request(
        presigned.json()["upload_url"],
        data=raw_bytes,
        method="PUT",
        headers=presigned.json()["upload_headers"],
    )
    with urlopen(upload, timeout=5) as uploaded:
        assert uploaded.status == 200

    confirmed = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/parts/confirm",
        {"sequence": 1, "sha256": checksum},
        headers,
    )
    queued = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/complete-raw",
        {"total_parts": 1},
        headers,
    )

    assert core.json()["raw_status"] == "PENDING"
    assert before_upload.json()["missing_raw_parts"] == [{"sequence": 1}]
    assert presigned.status_code == 200
    assert confirmed.status_code == 200
    assert confirmed.json()["status"] == "RECEIVED"
    assert queued.status_code == 202
    assert queued.json()["raw_status"] == "QUEUED"


def test_raw_confirmation_rejects_a_different_checksum(
    api_client, mobile_session, local_minio
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    complete_core(api_client, headers, upload_id, expected_raw_parts=1)
    checksum = hashlib.sha256(b"declared").hexdigest()
    post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/parts/presign",
        {"sequence": 1, "sha256": checksum},
        headers,
    )

    response = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/parts/confirm",
        {"sequence": 1, "sha256": hashlib.sha256(b"other").hexdigest()},
        headers,
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "checksum non corrisponde a quello dichiarato in presign"
    }


def test_raw_completion_rejects_a_count_different_from_the_manifest(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    complete_core(api_client, headers, upload_id, expected_raw_parts=2)

    response = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/complete-raw",
        {"total_parts": 1},
        headers,
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "numero parti raw diverso dal manifest iniziale"
    }
