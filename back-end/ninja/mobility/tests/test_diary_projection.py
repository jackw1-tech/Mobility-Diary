from datetime import datetime, timedelta

from mobility.diary_projection import project_diary_segments
from mobility.models import ActivityLabel, MobilitySegment, VirtualStopInterval


def _move(start: datetime, end: datetime, *, label=ActivityLabel.WALKING):
    return MobilitySegment(
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=label,
        distance_meters=100.0,
        path=None,
    )


def _stop(start: datetime, end: datetime):
    return MobilitySegment(
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=ActivityLabel.IDLE,
        distance_meters=0.0,
        path=None,
    )


def _virtual_stop(start: datetime, end: datetime):
    return VirtualStopInterval(
        start_timestamp=start,
        end_timestamp=end,
    )


def test_projection_merges_real_stop_containing_virtual_stop():
    base = datetime(2026, 1, 1, 12, 0, 0)

    projected = project_diary_segments(
        [_stop(base, base + timedelta(minutes=10))],
        [_virtual_stop(base + timedelta(minutes=2), base + timedelta(minutes=8))],
    )

    assert len(projected) == 1
    assert projected[0].kind == MobilitySegment.Kind.STOP
    assert projected[0].start_timestamp == base
    assert projected[0].end_timestamp == base + timedelta(minutes=10)


def test_projection_merges_virtual_stop_containing_real_stop():
    base = datetime(2026, 1, 1, 12, 0, 0)

    projected = project_diary_segments(
        [_stop(base + timedelta(minutes=2), base + timedelta(minutes=8))],
        [_virtual_stop(base, base + timedelta(minutes=10))],
    )

    assert len(projected) == 1
    assert projected[0].kind == MobilitySegment.Kind.STOP
    assert projected[0].start_timestamp == base
    assert projected[0].end_timestamp == base + timedelta(minutes=10)


def test_projection_inserts_isolated_virtual_stop_between_moves():
    base = datetime(2026, 1, 1, 12, 0, 0)

    projected = project_diary_segments(
        [
            _move(base, base + timedelta(minutes=5), label=ActivityLabel.BIKING),
            _move(
                base + timedelta(minutes=10),
                base + timedelta(minutes=15),
                label=ActivityLabel.WALKING,
            ),
        ],
        [_virtual_stop(base + timedelta(minutes=5), base + timedelta(minutes=10))],
    )

    assert [segment.kind for segment in projected] == [
        MobilitySegment.Kind.MOVE,
        MobilitySegment.Kind.STOP,
        MobilitySegment.Kind.MOVE,
    ]
    assert projected[1].activity_label == ActivityLabel.IDLE
    assert projected[1].start_timestamp == base + timedelta(minutes=5)
    assert projected[1].end_timestamp == base + timedelta(minutes=10)


def test_projection_merges_virtual_stop_bridging_two_real_stops():
    base = datetime(2026, 1, 1, 12, 0, 0)

    projected = project_diary_segments(
        [
            _stop(base, base + timedelta(minutes=5)),
            _stop(base + timedelta(minutes=10), base + timedelta(minutes=15)),
        ],
        [_virtual_stop(base + timedelta(minutes=5), base + timedelta(minutes=10))],
    )

    assert len(projected) == 1
    assert projected[0].kind == MobilitySegment.Kind.STOP
    assert projected[0].start_timestamp == base
    assert projected[0].end_timestamp == base + timedelta(minutes=15)
