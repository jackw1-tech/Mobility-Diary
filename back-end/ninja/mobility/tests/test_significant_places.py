"""Riconoscimento dei Luoghi Significativi: dominio user-scoped e mining.

Copre il comportamento esterno della feature, non i dettagli implementativi:
la fondazione del dominio, la rimozione della scoperta trip-scoped, lo
stay-detector puro e l'orchestrazione del ricomputo per-utente.
"""

from datetime import timedelta
from types import SimpleNamespace

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.utils import timezone

from mobility.ml.pipeline import run_pipeline
from mobility.models import (
    CandidateVisit,
    GpsPoint,
    HabitualPlace,
    MobilitySegment,
    Trip,
)
from mobility.significant_places import (
    NEUTRAL_PLACE_LABEL,
    _dbscan,
    detect_visits,
    match_confirmed_place,
    mine_user_significant_places,
    place_label,
)


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="place-owner@example.com",
        email="place-owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="other-owner@example.com",
        email="other-owner@example.com",
        password="password",
    )


# --------------------------------------------------------------------------- #
# Issue 01: dominio user-scoped, rimozione scoperta trip-scoped
# --------------------------------------------------------------------------- #


@pytest.mark.django_db
def test_habitual_place_persists_user_scoped_state_without_a_trip(user):
    """Lo stato dei luoghi e' user-scoped e indipendente da un singolo Viaggio."""
    HabitualPlace.objects.create(
        user=user,
        center=Point(9.19, 45.46, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
    )
    HabitualPlace.objects.create(
        user=user,
        center=Point(9.20, 45.47, srid=4326),
        state=HabitualPlace.State.REJECTED,
    )

    owned = HabitualPlace.objects.filter(user=user)
    assert owned.count() == 2
    assert {p.state for p in owned} == {
        HabitualPlace.State.CONFIRMED,
        HabitualPlace.State.REJECTED,
    }
    # Nessun campo lega il luogo a un Viaggio: vive nella storia dell'utente.
    assert not any(f.name == "trip" for f in HabitualPlace._meta.get_fields())


@pytest.mark.django_db
def test_final_pipeline_no_longer_creates_trip_scoped_places(user):
    """La pipeline del diario non e' piu' una sorgente di scoperta dei luoghi."""
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="no-trip-place",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(minutes=10),
    )
    # Sosta lunga e immobile: prima avrebbe prodotto un SignificantPlace.
    for offset in range(0, 11, 2):
        GpsPoint.objects.create(
            trip=trip,
            timestamp=base + timedelta(minutes=offset),
            point=Point(9.19, 45.46, srid=4326),
            speed_mps=0.0,
        )

    result = run_pipeline(trip)

    assert "significant_places" not in result
    assert not any(f.name == "place" for f in MobilitySegment._meta.get_fields())


# --------------------------------------------------------------------------- #
# Issue 02: stay-detection pura sui GpsPoint grezzi
# --------------------------------------------------------------------------- #


def _gp(base, seconds, lat, lon, accuracy=None):
    """GpsPoint finto: lo stay-detector e' puro, non serve il DB."""
    return SimpleNamespace(
        timestamp=base + timedelta(seconds=seconds),
        point=SimpleNamespace(x=lon, y=lat),
        accuracy_meters=accuracy,
    )


def test_detects_permanence_after_five_minutes_and_three_points():
    base = timezone.now()
    points = [
        _gp(base, 0, 45.4600, 9.1900),
        _gp(base, 150, 45.4601, 9.1901),
        _gp(base, 300, 45.4600, 9.1899),
    ]
    visits = detect_visits(points)
    assert len(visits) == 1
    assert visits[0].point_count == 3
    assert abs(visits[0].lat - 45.46) < 0.01
    assert abs(visits[0].lon - 9.19) < 0.01


def test_no_visit_when_permanence_is_too_short():
    base = timezone.now()
    points = [_gp(base, s, 45.46, 9.19) for s in (0, 120, 240)]  # 4 min < 5
    assert detect_visits(points) == []


def test_no_visit_with_fewer_than_three_points():
    base = timezone.now()
    points = [_gp(base, 0, 45.46, 9.19), _gp(base, 600, 45.46, 9.19)]
    assert detect_visits(points) == []


def test_poor_accuracy_points_do_not_count_as_evidence():
    base = timezone.now()
    points = [
        _gp(base, 0, 45.46, 9.19, accuracy=10),
        _gp(base, 150, 45.46, 9.19, accuracy=500),  # stessa area ma impreciso
        _gp(base, 300, 45.46, 9.19, accuracy=10),
    ]
    # Il punto impreciso e' ignorato: restano 2 punti validi, sotto la soglia.
    assert detect_visits(points) == []


def test_small_sampling_gap_is_tolerated():
    base = timezone.now()
    points = [_gp(base, s, 45.46, 9.19) for s in (0, 110, 220, 330)]  # gap 110s < 120
    visits = detect_visits(points)
    assert len(visits) == 1
    assert visits[0].point_count == 4


def test_long_gap_splits_into_separate_visits():
    base = timezone.now()
    morning = [_gp(base, s, 45.46, 9.19) for s in (0, 150, 300)]
    # Stessa area, ma una lunga interruzione (rientro in serata): episodi distinti.
    evening = [_gp(base, s, 45.46, 9.19) for s in (40000, 40150, 40300)]
    visits = detect_visits(morning + evening)
    assert len(visits) == 2


def test_pass_through_points_do_not_become_visits():
    base = timezone.now()
    # Spostamento continuo (~220 m fra punti consecutivi): mai una permanenza.
    points = [_gp(base, i * 30, 45.46 + i * 0.002, 9.19) for i in range(8)]
    assert detect_visits(points) == []


# --------------------------------------------------------------------------- #
# Issue 02: orchestrazione del ricomputo per-utente
# --------------------------------------------------------------------------- #


def _stay(trip, start, lat, lon, *, minutes=6, step=120):
    """Crea i GpsPoint di una permanenza valida (>= 5 min, >= 3 punti)."""
    seconds = 0
    while seconds <= minutes * 60:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=start + timedelta(seconds=seconds),
            point=Point(lon, lat, srid=4326),
            speed_mps=0.0,
        )
        seconds += step


@pytest.mark.django_db
def test_mining_recomputes_visits_from_full_user_history(user):
    base = timezone.now()
    trip_a = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    trip_b = Trip.objects.create(user=user, client_session_id="b", device_id="d")
    _stay(trip_a, base, 45.46, 9.19)
    _stay(trip_b, base + timedelta(hours=2), 45.50, 9.25)

    result = mine_user_significant_places(user.id)

    assert result["visits"] == 2
    assert CandidateVisit.objects.filter(user=user).count() == 2


@pytest.mark.django_db
def test_mining_is_a_full_recompute_without_duplicating_visits(user):
    base = timezone.now()
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    _stay(trip, base, 45.46, 9.19)

    first = mine_user_significant_places(user.id)
    second = mine_user_significant_places(user.id)

    assert first["visits"] == second["visits"] == 1
    assert CandidateVisit.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_mining_one_user_does_not_touch_another_users_visits(user, other_user):
    base = timezone.now()
    kept = CandidateVisit.objects.create(
        user=other_user,
        center=Point(9.0, 45.0, srid=4326),
        started_at=base,
        ended_at=base + timedelta(minutes=6),
        point_count=4,
    )
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    _stay(trip, base, 45.46, 9.19)

    mine_user_significant_places(user.id)

    assert CandidateVisit.objects.filter(pk=kept.pk).exists()
    assert CandidateVisit.objects.filter(user=user).count() == 1


# --------------------------------------------------------------------------- #
# Issue 03: clustering DBSCAN delle visite -> Luoghi Candidati, auto-conferma
# --------------------------------------------------------------------------- #


def test_dbscan_merges_compatible_visits_and_isolates_far_ones():
    coords = [
        (45.4600, 9.1900),
        (45.4601, 9.1901),
        (45.4599, 9.1902),
        (45.5000, 9.2500),  # ~5 km piu' in la': one-off, rumore
    ]
    clusters = _dbscan(coords, eps_meters=100, min_samples=3)
    assert len(clusters) == 1
    assert sorted(clusters[0]) == [0, 1, 2]


def test_dbscan_keeps_unrelated_areas_separate():
    coords = [
        (45.4600, 9.1900),
        (45.4601, 9.1901),
        (45.4599, 9.1902),  # area A
        (45.5000, 9.2500),
        (45.5001, 9.2501),
        (45.4999, 9.2502),  # area B
    ]
    assert len(_dbscan(coords, eps_meters=100, min_samples=3)) == 2


def test_dbscan_single_visit_is_noise():
    assert _dbscan([(45.46, 9.19)], eps_meters=100, min_samples=3) == []


@pytest.mark.django_db
def test_recurring_visits_on_three_distinct_days_auto_confirm(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    for day in range(3):
        _stay(trip, base + timedelta(days=day), 45.46, 9.19)

    result = mine_user_significant_places(user.id)

    assert result["places"] == 1
    place = HabitualPlace.objects.get(user=user)
    assert place.state == HabitualPlace.State.CONFIRMED
    assert place.distinct_days == 3
    assert place.visit_count == 3


@pytest.mark.django_db
def test_repeated_visits_on_a_single_day_do_not_create_a_place(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    _stay(trip, base, 45.46, 9.19)
    _stay(trip, base + timedelta(hours=3), 45.46, 9.19)
    _stay(trip, base + timedelta(hours=6), 45.46, 9.19)

    result = mine_user_significant_places(user.id)

    assert result["visits"] == 3
    assert result["places"] == 0
    assert HabitualPlace.objects.filter(user=user).count() == 0
    assert CandidateVisit.objects.filter(user=user, place__isnull=True).count() == 3


@pytest.mark.django_db
def test_three_visits_on_two_distinct_days_create_candidate(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    _stay(trip, base, 45.46, 9.19)
    _stay(trip, base + timedelta(hours=3), 45.46, 9.19)
    _stay(trip, base + timedelta(days=1), 45.46, 9.19)

    result = mine_user_significant_places(user.id)

    assert result["places"] == 1
    place = HabitualPlace.objects.get(user=user)
    assert place.state == HabitualPlace.State.CANDIDATE
    assert place.distinct_days == 2
    assert place.visit_count == 3


@pytest.mark.django_db
def test_one_off_visit_does_not_create_a_place(user):
    base = timezone.now()
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    _stay(trip, base, 45.46, 9.19)

    result = mine_user_significant_places(user.id)

    assert result["visits"] == 1
    assert result["places"] == 0
    assert HabitualPlace.objects.filter(user=user).count() == 0


@pytest.mark.django_db
def test_distinct_areas_become_distinct_places_and_link_their_visits(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    for day in range(2):
        _stay(trip, base + timedelta(days=day), 45.46, 9.19)
        _stay(trip, base + timedelta(days=day, hours=5), 45.50, 9.25)
    _stay(trip, base + timedelta(days=1, hours=8), 45.46, 9.19)
    _stay(trip, base + timedelta(days=1, hours=13), 45.50, 9.25)

    result = mine_user_significant_places(user.id)

    assert result["places"] == 2
    assert HabitualPlace.objects.filter(user=user).count() == 2
    # Ogni luogo conserva le sue visite come evidenza; nessuna visita orfana.
    for place in HabitualPlace.objects.filter(user=user):
        assert place.visits.count() == 3
    assert CandidateVisit.objects.filter(user=user, place__isnull=True).count() == 0


# --------------------------------------------------------------------------- #
# Issue 04: overlay read-time dei Luoghi Confermati sul diario
# --------------------------------------------------------------------------- #


def test_place_label_prefers_custom_name_then_category_then_neutral():
    assert place_label(HabitualPlace(custom_name="Bicocca", category="universita")) == "Bicocca"
    assert place_label(HabitualPlace(custom_name="", category="universita")) == "universita"
    assert place_label(HabitualPlace(custom_name="", category="")) == NEUTRAL_PLACE_LABEL


def test_match_confirmed_place_picks_closest_within_threshold():
    near = HabitualPlace(center=Point(9.1900, 45.4600, srid=4326))
    far = HabitualPlace(center=Point(9.1905, 45.4605, srid=4326))
    assert match_confirmed_place(45.4600, 9.1900, [far, near]) is near


def test_match_confirmed_place_returns_none_when_all_too_far():
    place = HabitualPlace(center=Point(9.30, 45.50, srid=4326))  # km di distanza
    assert match_confirmed_place(45.46, 9.19, [place]) is None


# --------------------------------------------------------------------------- #
# Issue 06: la review manuale sopravvive al ricomputo completo
# --------------------------------------------------------------------------- #


def _candidate_two_day_place(user, trip, base):
    for day in range(2):
        _stay(trip, base + timedelta(days=day), 45.46, 9.19)
    _stay(trip, base + timedelta(days=1, hours=3), 45.46, 9.19)
    mine_user_significant_places(user.id)
    return HabitualPlace.objects.get(user=user)


@pytest.mark.django_db
def test_rejected_place_stays_frozen_and_does_not_resurface(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    place = _candidate_two_day_place(user, trip, base)
    place.state = HabitualPlace.State.REJECTED
    place.manually_reviewed = True
    place.save(update_fields=["state", "manually_reviewed"])

    # Nuova evidenza nella stessa area + nuovo mining.
    _stay(trip, base + timedelta(days=2), 45.46, 9.19)
    mine_user_significant_places(user.id)

    places = HabitualPlace.objects.filter(user=user)
    assert places.count() == 1  # niente nuovo candidato risorto
    assert places.first().state == HabitualPlace.State.REJECTED


@pytest.mark.django_db
def test_manual_label_and_confirmation_survive_recompute(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    place = _candidate_two_day_place(user, trip, base)
    place.category = "universita"
    place.custom_name = "Bicocca"
    place.state = HabitualPlace.State.CONFIRMED
    place.manually_reviewed = True
    place.save()
    place_id = place.id

    # Nuovo giorno di evidenza nella stessa area + nuovo mining.
    _stay(trip, base + timedelta(days=2), 45.46, 9.19)
    mine_user_significant_places(user.id)

    refreshed = HabitualPlace.objects.get(user=user)
    assert refreshed.id == place_id  # stesso luogo (reattach), non ricreato
    assert refreshed.category == "universita"
    assert refreshed.custom_name == "Bicocca"
    assert refreshed.state == HabitualPlace.State.CONFIRMED
    assert refreshed.distinct_days == 3  # evidenza aggiornata dal reattach
    assert refreshed.visits.count() == 4


# --------------------------------------------------------------------------- #
# Issue 07: conflict resolution dell'overlay + stabilita' del ricomputo
# --------------------------------------------------------------------------- #


def test_overlay_prefers_manually_labeled_place_on_a_tie():
    auto = HabitualPlace(center=Point(9.1900, 45.4600, srid=4326))  # piu' vicino
    labeled = HabitualPlace(
        center=Point(9.1902, 45.4601, srid=4326), category="universita"
    )  # poco piu' lontano, ma etichettato manualmente
    assert match_confirmed_place(45.4600, 9.1900, [auto, labeled]) is labeled


def test_overlay_picks_closest_when_not_effectively_tied():
    auto = HabitualPlace(center=Point(9.1900, 45.4600, srid=4326))  # vicinissimo
    labeled = HabitualPlace(
        center=Point(9.1906, 45.4604, srid=4326), category="universita"
    )  # ~60 m: nettamente piu' lontano, non in parita'
    assert match_confirmed_place(45.4600, 9.1900, [auto, labeled]) is auto


@pytest.mark.django_db
def test_repeated_recompute_keeps_manual_curation_stable(user):
    base = timezone.now().replace(hour=8, minute=0)
    trip = Trip.objects.create(user=user, client_session_id="a", device_id="d")
    place = _candidate_two_day_place(user, trip, base)
    place.category = "casa"
    place.state = HabitualPlace.State.CONFIRMED
    place.manually_reviewed = True
    place.save()
    place_id = place.id

    # Piu' viaggi processati nella stessa area: ricomputi ripetuti.
    for day in range(2, 5):
        _stay(trip, base + timedelta(days=day), 45.46, 9.19)
        mine_user_significant_places(user.id)

    places = HabitualPlace.objects.filter(user=user)
    assert places.count() == 1  # nessuna duplicazione del luogo curato
    survivor = places.first()
    assert survivor.id == place_id
    assert survivor.category == "casa"
    assert survivor.state == HabitualPlace.State.CONFIRMED
