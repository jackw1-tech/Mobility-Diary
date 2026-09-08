"""Shift temporale delle parti raw nel replay.

Prima del passaggio a JSON questo percorso era di fatto morto: tutte le parti
reali erano binarie e finivano in `_shifted_binary_part_body`. Ora e' l'unico,
quindi il round-trip completo (payload mobile -> shift -> decode HAR) va
verificato esplicitamente.
"""

import gzip
import json
from datetime import timedelta

import pytest

from mobility import replay_raw
from mobility.upload.raw_sensor_codec import (
    EXPECTED_CHANNEL_COUNT,
    EXPECTED_SAMPLE_COUNT,
    decode_sensor_windows_payload,
)


def mobile_part(*starts_and_ends) -> bytes:
    """Riproduce il payload che TripPackageBuilder scrive su disco."""
    windows = [
        {
            "window_start": start,
            "window_end": end,
            "sample_rate_hz": 100,
            "samples": [
                [0.1, -9.81, 0.5, 0.01, -0.02, 0.03]
                for _ in range(EXPECTED_SAMPLE_COUNT)
            ],
        }
        for start, end in starts_and_ends
    ]
    return gzip.compress(json.dumps({"windows": windows}).encode("utf-8"))


@pytest.fixture
def stored_part(monkeypatch):
    def store(body: bytes):
        monkeypatch.setattr(
            replay_raw.storage, "read_object", lambda object_key: body
        )

    return store


def test_shifted_part_stays_decodable_by_the_har_codec(stored_part):
    stored_part(
        mobile_part(
            ("2026-09-02T10:15:00.000Z", "2026-09-02T10:15:05.000Z"),
            ("2026-09-02T10:15:05.000Z", "2026-09-02T10:15:10.000Z"),
        )
    )

    body = replay_raw._shifted_part_body("key", timedelta(hours=2), None)

    windows = decode_sensor_windows_payload(gzip.decompress(body))
    assert [w.start_timestamp.isoformat() for w in windows] == [
        "2026-09-02T12:15:00+00:00",
        "2026-09-02T12:15:05+00:00",
    ]
    assert [w.end_timestamp.isoformat() for w in windows] == [
        "2026-09-02T12:15:05+00:00",
        "2026-09-02T12:15:10+00:00",
    ]
    assert windows[0].matrix.shape == (
        EXPECTED_SAMPLE_COUNT,
        EXPECTED_CHANNEL_COUNT,
    )


def test_shift_preserves_microseconds_between_adjacent_windows(stored_part):
    # Con il troncamento al secondo che c'era prima, queste due finestre
    # collassavano sullo stesso istante e l'ordinamento diventava arbitrario.
    stored_part(
        mobile_part(
            ("2026-09-02T10:15:00.100000Z", "2026-09-02T10:15:05.100000Z"),
            ("2026-09-02T10:15:00.600000Z", "2026-09-02T10:15:05.600000Z"),
        )
    )

    body = replay_raw._shifted_part_body("key", timedelta(minutes=1), None)

    windows = decode_sensor_windows_payload(gzip.decompress(body))
    assert [w.start_timestamp.microsecond for w in windows] == [100000, 600000]
    assert windows[0].start_timestamp != windows[1].start_timestamp


def test_cutoff_drops_windows_started_after_the_stop(stored_part):
    stored_part(
        mobile_part(
            ("2026-09-02T10:15:00.000Z", "2026-09-02T10:15:05.000Z"),
            ("2026-09-02T10:20:00.000Z", "2026-09-02T10:20:05.000Z"),
        )
    )
    cutoff = replay_raw.parse_datetime("2026-09-02T10:17:00.000Z")

    body = replay_raw._shifted_part_body("key", timedelta(0), cutoff)

    assert len(decode_sensor_windows_payload(gzip.decompress(body))) == 1


def test_a_part_entirely_after_the_cutoff_is_skipped(stored_part):
    stored_part(mobile_part(("2026-09-02T10:20:00.000Z", "2026-09-02T10:20:05.000Z")))
    cutoff = replay_raw.parse_datetime("2026-09-02T10:17:00.000Z")

    assert replay_raw._shifted_part_body("key", timedelta(0), cutoff) is None
