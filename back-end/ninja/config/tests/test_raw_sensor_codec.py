"""Contratto del payload raw sensori: e' l'unico punto in cui il formato
prodotto dal mobile (`TripPackageBuilder._encodeSensorWindowsJson`) viene
verificato lato backend.
"""

import gzip
import json

import numpy as np
import pytest

from mobility.ingestion.raw_sensor_codec import (
    EXPECTED_CHANNEL_COUNT,
    EXPECTED_SAMPLE_COUNT,
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)


def build_window(**overrides):
    window = {
        "window_start": "2026-09-02T10:15:00.000Z",
        "window_end": "2026-09-02T10:15:05.000Z",
        "sample_rate_hz": 100,
        "sample_count": EXPECTED_SAMPLE_COUNT,
        "channel_count": EXPECTED_CHANNEL_COUNT,
        "samples": [
            [0.1, -9.81, 0.5, 0.01, -0.02, 0.03]
            for _ in range(EXPECTED_SAMPLE_COUNT)
        ],
    }
    window.update(overrides)
    return window


def encode(*windows) -> bytes:
    return json.dumps({"windows": list(windows)}).encode("utf-8")


def test_decodes_a_window_into_a_float32_matrix():
    [window] = decode_sensor_windows_payload(encode(build_window()))

    assert window.sample_count == EXPECTED_SAMPLE_COUNT
    assert window.frequency_hz == 100
    assert window.matrix.shape == (EXPECTED_SAMPLE_COUNT, EXPECTED_CHANNEL_COUNT)
    assert window.matrix.dtype == np.dtype("<f4")
    assert window.start_timestamp.isoformat() == "2026-09-02T10:15:00+00:00"
    assert window.end_timestamp.isoformat() == "2026-09-02T10:15:05+00:00"
    np.testing.assert_allclose(
        window.matrix[0], [0.1, -9.81, 0.5, 0.01, -0.02, 0.03], rtol=1e-6
    )


def test_decodes_the_gzipped_payload_a_mobile_part_actually_carries():
    raw = gzip.decompress(gzip.compress(encode(build_window(), build_window())))

    assert len(decode_sensor_windows_payload(raw)) == 2


def test_preserves_the_microseconds_the_replay_shift_depends_on():
    [window] = decode_sensor_windows_payload(
        encode(build_window(window_start="2026-09-02T10:15:00.123456Z"))
    )

    assert window.start_timestamp.microsecond == 123456


def test_accepts_an_empty_window_list():
    assert decode_sensor_windows_payload(encode()) == []


@pytest.mark.parametrize(
    "overrides, message",
    [
        ({"sample_count": 499}, "sample_count"),
        ({"channel_count": 3}, "channel_count"),
        ({"sample_rate_hz": 0}, "sample_rate_hz"),
        ({"window_end": "2026-09-02T10:15:00.000Z"}, "intervallo temporale"),
        ({"window_start": "non-una-data"}, "timestamp raw non valido"),
        ({"samples": [[0.0] * 6]}, "forma diversa"),
        ({"samples": "non-una-matrice"}, "senza matrice samples"),
    ],
)
def test_rejects_payloads_outside_the_har_contract(overrides, message):
    with pytest.raises(InvalidRawSensorPayload) as error:
        decode_sensor_windows_payload(encode(build_window(**overrides)))

    assert message in str(error.value)


@pytest.mark.parametrize(
    "raw, message",
    [
        (b"non json", "non e' JSON valido"),
        (b"[]", "senza oggetto radice"),
        (b'{"windows": {}}', "senza lista windows"),
    ],
)
def test_rejects_malformed_payloads(raw, message):
    with pytest.raises(InvalidRawSensorPayload) as error:
        decode_sensor_windows_payload(raw)

    assert message in str(error.value)
