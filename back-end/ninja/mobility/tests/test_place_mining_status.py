import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from mobility.models import PlaceMiningStatus
from mobility.tasks import mine_significant_places


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="status-owner@example.com",
        email="status-owner@example.com",
        password="password",
    )


@pytest.mark.django_db
def test_place_mining_task_marks_running_then_succeeded(user, monkeypatch):
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.PENDING,
        requested_at=timezone.now(),
    )
    monkeypatch.setattr(
        "mobility.tasks.mine_user_significant_places",
        lambda user_id: {"visits": 2, "places": 1},
    )

    result = mine_significant_places.run(user.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert result == {"visits": 2, "places": 1}
    assert status.status == PlaceMiningStatus.Status.SUCCEEDED
    assert status.started_at is not None
    assert status.finished_at is not None
    assert status.error_message == ""


@pytest.mark.django_db
def test_place_mining_task_returns_to_pending_while_retry_is_scheduled(user, monkeypatch):
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.PENDING,
        requested_at=timezone.now(),
    )

    def fail(_user_id):
        raise RuntimeError("db temporaneamente non disponibile")

    monkeypatch.setattr("mobility.tasks.mine_user_significant_places", fail)

    with pytest.raises(RuntimeError, match="db temporaneamente"):
        mine_significant_places.run(user.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert status.status == PlaceMiningStatus.Status.PENDING
    assert status.started_at is None
    assert status.finished_at is None
    assert "db temporaneamente" in status.error_message


@pytest.mark.django_db
def test_place_mining_task_marks_failed_after_retry_exhausted(user, monkeypatch):
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.PENDING,
        requested_at=timezone.now(),
    )

    def fail(_user_id):
        raise RuntimeError("mining definitivamente fallito")

    monkeypatch.setattr("mobility.tasks.mine_user_significant_places", fail)
    monkeypatch.setattr(mine_significant_places, "max_retries", 0)

    with pytest.raises(RuntimeError, match="mining definitivamente"):
        mine_significant_places.run(user.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert status.status == PlaceMiningStatus.Status.FAILED
    assert status.started_at is not None
    assert status.finished_at is not None
    assert "mining definitivamente" in status.error_message


@pytest.mark.django_db
def test_place_mining_task_schedules_one_follow_up_when_rerun_requested(user, monkeypatch):
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.PENDING,
        requested_at=timezone.now(),
    )
    delayed: list[int] = []
    calls = 0

    def fake_mining(user_id):
        nonlocal calls
        calls += 1
        if calls == 1:
            PlaceMiningStatus.objects.filter(user_id=user_id).update(
                rerun_requested=True
            )
        return {"visits": calls, "places": 1}

    monkeypatch.setattr("mobility.tasks.mine_user_significant_places", fake_mining)
    monkeypatch.setattr("mobility.tasks.transaction.on_commit", lambda callback: callback())
    monkeypatch.setattr(
        "mobility.tasks.mine_significant_places.delay",
        lambda queued_user_id: delayed.append(queued_user_id),
    )

    first = mine_significant_places.run(user.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert first == {"visits": 1, "places": 1}
    assert delayed == [user.id]
    assert status.status == PlaceMiningStatus.Status.PENDING
    assert status.rerun_requested is False
    assert status.started_at is None
    assert status.finished_at is None

    second = mine_significant_places.run(user.id)

    status.refresh_from_db()
    assert second == {"visits": 2, "places": 1}
    assert delayed == [user.id]
    assert status.status == PlaceMiningStatus.Status.SUCCEEDED
    assert status.rerun_requested is False


@pytest.mark.django_db
def test_place_mining_task_skips_when_status_is_not_pending(user, monkeypatch):
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.SUCCEEDED,
        requested_at=timezone.now(),
    )
    called = False

    def fake_mining(_user_id):
        nonlocal called
        called = True
        return {"visits": 1, "places": 1}

    monkeypatch.setattr("mobility.tasks.mine_user_significant_places", fake_mining)

    result = mine_significant_places.run(user.id)

    assert result == {"skipped": "place mining not pending"}
    assert called is False
