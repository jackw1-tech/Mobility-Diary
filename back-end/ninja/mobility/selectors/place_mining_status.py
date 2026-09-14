"""Repository del PlaceMiningStatus
"""

from __future__ import annotations

from ..models import PlaceMiningStatus


def locked_status_for_user(
    user_id: int,
    *,
    default_status: str,
    requested_at,
) -> PlaceMiningStatus:
    status, _ = PlaceMiningStatus.objects.get_or_create(
        user_id=user_id,
        defaults={"status": default_status, "requested_at": requested_at},
    )
    return PlaceMiningStatus.objects.select_for_update().get(pk=status.pk)
