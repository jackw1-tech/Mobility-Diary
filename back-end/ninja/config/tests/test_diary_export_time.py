from datetime import datetime, timezone

from mobility.diary_export import _export_segment
from mobility.diary_projection import ProjectedDiarySegment
from mobility.models import MobilitySegment


def test_protected_export_preserves_exact_segment_times() -> None:
    start = datetime(2026, 9, 10, 10, 3, 12, 345_000, tzinfo=timezone.utc)
    end = datetime(2026, 9, 10, 10, 7, 54, 321_000, tzinfo=timezone.utc)
    segment = ProjectedDiarySegment(
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=start,
        end_timestamp=end,
        activity_label="IDLE",
        distance_meters=0.0,
        path=None,
    )

    exported = _export_segment(segment, None, level="approximate")

    assert exported.start_timestamp == start
    assert exported.end_timestamp == end
    assert exported.start_label == "10:03"
    assert exported.end_label == "10:07"
    assert exported.duration == end - start
