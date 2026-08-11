"""Repository del PlaceMiningStatus (read model operativo del mining).

Unico punto in cui compare `PlaceMiningStatus.objects`.
"""

from __future__ import annotations

from ..models import PlaceMiningStatus


def locked_status_for_user(
    user_id: int,
    *,
    default_status: str,
    requested_at,
) -> PlaceMiningStatus:
    """Get-or-create lo stato dell'utente, poi lo ritorna lockato per l'update.

    Nessuna decisione qui: chi chiama (mobility.tasks) decide cosa fare con lo
    stato restituito.
    """
    status, _ = PlaceMiningStatus.objects.get_or_create(
        user_id=user_id,
        defaults={"status": default_status, "requested_at": requested_at},
    )
    return PlaceMiningStatus.objects.select_for_update().get(pk=status.pk)
