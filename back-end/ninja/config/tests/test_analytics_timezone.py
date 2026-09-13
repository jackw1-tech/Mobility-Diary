from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from mobility.services.analytics import (
    _ANALYTICS_ZONE,
    personal_analytics_for_user,
    prevalent_mode,
)


def test_analytics_uses_italian_timezone_with_daylight_saving() -> None:
    winter = datetime(2026, 1, 15, 12, tzinfo=timezone.utc)
    summer = datetime(2026, 7, 15, 12, tzinfo=timezone.utc)

    assert winter.astimezone(_ANALYTICS_ZONE).utcoffset() == timedelta(hours=1)
    assert summer.astimezone(_ANALYTICS_ZONE).utcoffset() == timedelta(hours=2)


def test_prevalent_mode_returns_the_domain_activity_label() -> None:
    start = datetime(2026, 1, 15, 12, tzinfo=timezone.utc)
    rows = [
        {
            "activity_label": "IDLE",
            "start_timestamp": start,
            "end_timestamp": start + timedelta(hours=10),
        },
        {
            "activity_label": "UNKNOWN",
            "start_timestamp": start,
            "end_timestamp": start + timedelta(hours=5),
        },
        {
            "activity_label": "WALKING",
            "start_timestamp": start,
            "end_timestamp": start + timedelta(minutes=20),
        },
        {
            "activity_label": "MOVING_VEHICLE",
            "start_timestamp": start,
            "end_timestamp": start + timedelta(minutes=30),
        },
    ]

    with patch(
        "mobility.services.analytics.analytics_repository.mobility_segment_activity_rows",
        return_value=rows,
    ):
        result = prevalent_mode(user_id=1)

    assert result == "MOVING_VEHICLE"


def test_daily_analytics_do_not_calculate_weekly_heatmaps() -> None:
    with (
        patch(
            "mobility.services.analytics.analytics_repository.user_has_trips",
            return_value=False,
        ),
        patch("mobility.services.analytics.analytics_buckets", return_value=[]),
        patch("mobility.services.analytics.prevalent_mode", return_value=None),
        patch("mobility.services.analytics.frequent_routes", return_value=[]),
        patch("mobility.services.analytics.weekly_heatmaps") as heatmaps,
    ):
        result = personal_analytics_for_user(user_id=1, granularity="day")

    assert result.weekly_heatmaps == []
    heatmaps.assert_not_called()
