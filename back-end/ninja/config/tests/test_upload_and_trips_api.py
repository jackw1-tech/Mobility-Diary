import json

import pytest


pytestmark = pytest.mark.django_db

STARTED_AT = "2026-08-30T10:00:00Z"
ENDED_AT = "2026-08-30T10:10:00Z"


def post_json(client, path, payload, headers):
    return client.post(
        path,
        data=json.dumps(payload),
        content_type="application/json",
        **headers,
    )


def start_recording(
    client,
    headers,
    *,
    session_id="session-001",
    device_id="iphone-mario",
):
    return post_json(
        client,
        "/api/upload/trips/start",
        {
            "client_session_id": session_id,
            "device_id": device_id,
            "started_at": STARTED_AT,
        },
        headers,
    )


def complete_core(
    client,
    headers,
    upload_id,
    *,
    session_id="session-001",
    device_id="iphone-mario",
    expected_raw_parts=0,
):
    return post_json(
        client,
        "/api/upload/trips/core",
        {
            "upload_id": upload_id,
            "client_session_id": session_id,
            "device_id": device_id,
            "started_at": STARTED_AT,
            "ended_at": ENDED_AT,
            "expected_raw_parts": expected_raw_parts,
            "gps_points": [
                {
                    "timestamp": STARTED_AT,
                    "latitude": 45.4642,
                    "longitude": 9.1900,
                    "speed_mps": 1.2,
                    "accuracy_meters": 4.0,
                },
                {
                    "timestamp": ENDED_AT,
                    "latitude": 45.4680,
                    "longitude": 9.1950,
                    "speed_mps": 1.4,
                    "accuracy_meters": 4.0,
                },
            ],
            "state_transitions": [
                {
                    "timestamp": STARTED_AT,
                    "from_state": "IDLE",
                    "to_state": "WALKING",
                    "reason": "movement detected",
                }
            ],
        },
        headers,
    )


def test_user_has_no_active_recording_before_start(api_client, mobile_session):
    response = api_client.get(
        "/api/upload/trips/active", **mobile_session["headers"]
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "nessun viaggio in corso"}


def test_start_is_idempotent_for_the_same_session_and_device(
    api_client, mobile_session
):
    first = start_recording(api_client, mobile_session["headers"])
    retry = start_recording(api_client, mobile_session["headers"])

    assert first.status_code == 200
    assert retry.status_code == 200
    assert retry.json()["upload_id"] == first.json()["upload_id"]
    assert retry.json()["already_exists"] is True


def test_only_one_recording_can_be_active_per_user(api_client, mobile_session):
    first = start_recording(api_client, mobile_session["headers"])
    conflict = start_recording(
        api_client,
        mobile_session["headers"],
        session_id="session-002",
        device_id="android-mario",
    )

    assert conflict.status_code == 409
    assert conflict.json()["active_upload"]["upload_id"] == first.json()[
        "upload_id"
    ]
    assert conflict.json()["active_upload"]["device_id"] == "iphone-mario"


def test_only_the_origin_device_can_heartbeat_or_abandon_a_recording(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]

    forbidden_heartbeat = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/heartbeat",
        {"client_session_id": "session-001", "device_id": "other-device"},
        headers,
    )
    forbidden_abandon = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/abandon",
        {"device_id": "other-device"},
        headers,
    )

    assert forbidden_heartbeat.status_code == 403
    assert forbidden_abandon.status_code == 403


def test_abandoning_a_recording_releases_the_active_trip_lock(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    abandoned = post_json(
        api_client,
        f"/api/upload/trips/{upload_id}/abandon",
        {"device_id": "iphone-mario"},
        headers,
    )

    next_recording = start_recording(
        api_client,
        headers,
        session_id="session-002",
        device_id="android-mario",
    )

    assert abandoned.status_code == 200
    assert next_recording.status_code == 200
    assert next_recording.json()["upload_id"] != upload_id


def test_core_upload_makes_the_trip_visible_with_a_track(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]

    core = complete_core(api_client, headers, upload_id)
    trips = api_client.get("/api/mobility/trips", **headers)
    track = api_client.get(
        f"/api/mobility/trips/{core.json()['trip_id']}/track", **headers
    )

    assert core.status_code == 200
    assert core.json()["core_status"] == "COMPLETED"
    assert core.json()["raw_status"] == "COMPLETED"
    assert core.json()["map_available"] is True
    assert trips.status_code == 200
    assert len(trips.json()) == 1
    assert trips.json()[0]["has_track"] is True
    assert track.status_code == 200
    assert track.json()["point_count"] == 2
    assert track.json()["geojson"]["type"] == "LineString"


def test_core_retry_does_not_duplicate_trip_evidence(api_client, mobile_session):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]

    first = complete_core(api_client, headers, upload_id)
    retry = complete_core(api_client, headers, upload_id)
    track = api_client.get(
        f"/api/mobility/trips/{first.json()['trip_id']}/track", **headers
    )

    assert retry.status_code == 200
    assert retry.json()["trip_id"] == first.json()["trip_id"]
    assert track.json()["point_count"] == 2


def test_core_rejects_empty_evidence(api_client, mobile_session):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]

    response = post_json(
        api_client,
        "/api/upload/trips/core",
        {
            "upload_id": upload_id,
            "client_session_id": "session-001",
            "device_id": "iphone-mario",
            "gps_points": [],
            "state_transitions": [],
        },
        headers,
    )

    assert response.status_code == 400
    assert response.json() == {"detail": "core vuoto: GPS e state transitions assenti"}


def test_upload_and_trip_are_isolated_between_users(
    api_client, mobile_session, register_mobile_user
):
    owner_headers = mobile_session["headers"]
    upload_id = start_recording(api_client, owner_headers).json()["upload_id"]
    trip_id = complete_core(api_client, owner_headers, upload_id).json()["trip_id"]

    other_registration = register_mobile_user("other@example.com")
    other_headers = {
        "HTTP_AUTHORIZATION": f"Bearer {other_registration.json()['access_token']}"
    }

    assert (
        api_client.get(f"/api/upload/trips/{upload_id}", **other_headers).status_code
        == 404
    )
    assert (
        api_client.get(f"/api/mobility/trips/{trip_id}/track", **other_headers).status_code
        == 404
    )
    assert api_client.get("/api/mobility/trips", **other_headers).json() == []


def test_completed_upload_allows_note_update_and_trip_deletion(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    trip_id = complete_core(api_client, headers, upload_id).json()["trip_id"]

    note = api_client.patch(
        f"/api/mobility/trips/{trip_id}/note",
        data=json.dumps({"note": "  Passeggiata verso il centro  "}),
        content_type="application/json",
        **headers,
    )
    deleted = api_client.delete(f"/api/mobility/trips/{trip_id}", **headers)

    assert note.status_code == 200
    assert note.json()["note"] == "Passeggiata verso il centro"
    assert deleted.status_code == 204
    assert api_client.get("/api/mobility/trips", **headers).json() == []


def test_privacy_export_reflects_the_current_user_preference(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    trip_id = complete_core(api_client, headers, upload_id).json()["trip_id"]

    precise = api_client.get(
        f"/api/mobility/trips/{trip_id}/privacy-export", **headers
    )
    api_client.put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "aggregated"}),
        content_type="application/json",
        **headers,
    )
    aggregated = api_client.get(
        f"/api/mobility/trips/{trip_id}/privacy-export", **headers
    )

    assert precise.status_code == 200
    assert precise.json()["protected"] is False
    assert precise.json()["cell_size_meters"] is None
    assert aggregated.status_code == 200
    assert aggregated.json()["protected"] is True
    assert aggregated.json()["approximated_coordinates"] is True
    assert aggregated.json()["cell_size_meters"] == 400


def test_analytics_returns_a_stable_empty_state_before_enrichment(
    api_client, mobile_session
):
    response = api_client.get(
        "/api/mobility/analytics?granularity=day&tz=Europe/Rome",
        **mobile_session["headers"],
    )

    assert response.status_code == 200
    assert response.json() == {
        "granularity": "day",
        "has_data": False,
        "buckets": [],
        "prevalent_mode": None,
        "frequent_routes": [],
        "heatmap": [],
        "weekly_heatmaps": [],
    }
