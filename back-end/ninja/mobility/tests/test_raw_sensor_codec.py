import json
import struct
from datetime import datetime, timedelta, timezone

import pytest

from mobility.ingestion.raw_sensor_codec import (
    InvalidRawSensorPayload,
    RawSensorPayloadFormat,
    decode_sensor_windows_payload,
    raw_sensor_payload_format,
)


def _iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _binary_sensor_windows(start: datetime) -> bytes:
    header = struct.pack("<8sI", b"MDHARW1\x00", 1)
    window_header = struct.pack(
        "<qqIII",
        int(start.timestamp() * 1_000_000),
        int((start + timedelta(seconds=5)).timestamp() * 1_000_000),
        100,
        500,
        6,
    )
    matrix = b"".join(struct.pack("<f", 0.1) for _ in range(500 * 6))
    return header + window_header + matrix


def _json_sensor_windows(start: datetime) -> bytes:
    payload = {
        "windows": [
            {
                "window_start": _iso(start),
                "window_end": _iso(start + timedelta(seconds=5)),
                "sample_rate_hz": 100,
                "sample_count": 500,
                "samples": [[0.1, 0.2, 0.3, 0.4, 0.5, 0.6] for _ in range(500)],
            }
        ]
    }
    return json.dumps(payload).encode("utf-8")


def test_binary_payload_decodes_sensor_windows():
    start = datetime(2026, 1, 1, 12, tzinfo=timezone.utc)
    raw = _binary_sensor_windows(start)

    assert raw_sensor_payload_format(raw) == RawSensorPayloadFormat.BINARY

    windows = decode_sensor_windows_payload(raw)

    assert len(windows) == 1
    assert windows[0].start_timestamp == start
    assert windows[0].end_timestamp == start + timedelta(seconds=5)
    assert windows[0].sample_count == 500
    assert windows[0].frequency_hz == 100
    assert windows[0].matrix.shape == (500, 6)
    assert windows[0].matrix[0][0] == pytest.approx(0.1)


def test_json_payload_decodes_legacy_sensor_windows():
    start = datetime(2026, 1, 1, 12, tzinfo=timezone.utc)
    raw = _json_sensor_windows(start)

    assert raw_sensor_payload_format(raw) == RawSensorPayloadFormat.JSON

    windows = decode_sensor_windows_payload(raw)

    assert len(windows) == 1
    assert windows[0].start_timestamp == start
    assert windows[0].end_timestamp == start + timedelta(seconds=5)
    assert windows[0].sample_count == 500
    assert windows[0].frequency_hz == 100
    assert windows[0].matrix[0] == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]


def test_binary_payload_rejects_invalid_magic():
    start = datetime(2026, 1, 1, 12, tzinfo=timezone.utc)
    raw = _binary_sensor_windows(start).replace(b"MDHARW1\x00", b"MDHARW2\x00", 1)

    assert raw_sensor_payload_format(raw) == RawSensorPayloadFormat.BINARY

    with pytest.raises(InvalidRawSensorPayload, match="binario non valido"):
        decode_sensor_windows_payload(raw)


def test_binary_payload_rejects_truncated_window():
    raw = struct.pack("<8sI", b"MDHARW1\x00", 1)

    with pytest.raises(InvalidRawSensorPayload, match="binario troncato"):
        decode_sensor_windows_payload(raw)


def test_json_payload_rejects_malformed_matrix_row():
    start = datetime(2026, 1, 1, 12, tzinfo=timezone.utc)
    payload = {
        "windows": [
            {
                "window_start": _iso(start),
                "window_end": _iso(start + timedelta(seconds=5)),
                "sample_rate_hz": 100,
                "sample_count": 500,
                "samples": [[0.1, 0.2, 0.3]],
            }
        ]
    }

    with pytest.raises(InvalidRawSensorPayload, match="riga matrice non valida"):
        decode_sensor_windows_payload(json.dumps(payload).encode("utf-8"))
