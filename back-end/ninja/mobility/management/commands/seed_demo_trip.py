"""Import the real demo trip into the local database and object storage."""

from __future__ import annotations

import gzip
import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.core.serializers import deserialize
from django.db import transaction

from mobility.models import (
    GpsPoint,
    MobilitySegment,
    StateTransition,
    Trip,
    TripUpload,
    TripUploadPart,
)
from mobility.selectors.sensor_readings import (
    persist_raw_sensor_readings,
    replace_raw_sensor_readings,
)
from mobility.upload import storage
from mobility.upload.raw_sensor_codec import (
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)


DEFAULT_FIXTURE = "/demo-seed/trip_fixture.json"
DEFAULT_OBJECTS_ROOT = "/demo-seed"
DEFAULT_USER_EMAIL = "user@mobility.local"
SEED_SESSION_ID = "demo-real-trip"
SEED_RAW_BASE_PATH = "demo-seed/real-trip/"


class Command(BaseCommand):
    help = (
        "Seed the local demo user with the bundled real trip and its raw "
        "sensor object. The imported trip is an original reloadable source."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--fixture",
            default=os.getenv("DJANGO_DEMO_TRIP_FIXTURE", DEFAULT_FIXTURE),
        )
        parser.add_argument(
            "--objects-root",
            default=os.getenv("DJANGO_DEMO_TRIP_OBJECTS_ROOT", DEFAULT_OBJECTS_ROOT),
        )
        parser.add_argument(
            "--user-email",
            default=os.getenv("DJANGO_DEMO_USER_EMAIL", DEFAULT_USER_EMAIL),
        )

    def handle(self, *args, **options):
        fixture_path = Path(options["fixture"]).expanduser().resolve()
        objects_root = Path(options["objects_root"]).expanduser().resolve()
        user_email = options["user_email"].strip()

        fixture = self._load_fixture(fixture_path)
        trip_record = self._single_record(fixture, "trip")
        upload_record = self._single_record(fixture, "uploads")
        part_records = fixture.get("upload_parts", [])
        if not part_records:
            raise CommandError("The demo fixture has no raw upload parts")

        user = get_user_model()._default_manager.filter(
            email__iexact=user_email,
            is_active=True,
        ).first()
        if user is None:
            raise CommandError(
                f"Active demo user {user_email} not found; run ensure_demo_accounts first"
            )
        if user.is_staff or user.is_superuser:
            raise CommandError("The demo trip must belong to a normal mobile user")

        raw_parts = self._validated_raw_parts(
            part_records,
            upload_record,
            objects_root,
        )
        self._write_raw_parts(raw_parts)

        with transaction.atomic():
            trip, created = self._seed_database(
                fixture=fixture,
                trip_record=trip_record,
                upload_record=upload_record,
                raw_parts=raw_parts,
                user=user,
            )

        action = "Created" if created else "Demo trip already exists"
        self.stdout.write(
            self.style.SUCCESS(
                f"{action}: trip {trip.id}, user {user_email}, "
                f"{trip.gps_points.count()} GPS points, "
                f"{trip.segments.count()} segments, {len(raw_parts)} raw part(s), "
                "reloadable original"
            )
        )

    def _load_fixture(self, fixture_path: Path) -> dict:
        try:
            with fixture_path.open(encoding="utf-8") as fixture_file:
                fixture = json.load(fixture_file)
        except (OSError, json.JSONDecodeError) as exc:
            raise CommandError(f"Cannot read demo fixture: {fixture_path}") from exc

        required = {
            "trip",
            "gps_points",
            "state_transitions",
            "segments",
            "uploads",
            "upload_parts",
        }
        missing = sorted(required.difference(fixture))
        if missing:
            raise CommandError(f"Demo fixture is missing: {', '.join(missing)}")
        return fixture

    def _single_record(self, fixture: dict, key: str) -> dict:
        records = fixture.get(key, [])
        if len(records) != 1:
            raise CommandError(f"Demo fixture must contain exactly one {key} record")
        return records[0]

    def _validated_raw_parts(
        self,
        part_records: list[dict],
        upload_record: dict,
        objects_root: Path,
    ) -> list[dict]:
        upload_pk = upload_record.get("pk")
        validated = []
        for part_record in part_records:
            fields = part_record.get("fields", {})
            if fields.get("upload") != upload_pk:
                raise CommandError("Raw part points to an unexpected fixture upload")

            sequence = fields.get("sequence")
            expected_sha256 = fields.get("sha256", "")
            if not isinstance(sequence, int) or sequence < 1:
                raise CommandError("Raw part has an invalid sequence")
            if len(expected_sha256) != 64:
                raise CommandError(f"Raw part #{sequence} has an invalid checksum")
            source_path = (objects_root / fields.get("object_key", "")).resolve()
            if not source_path.is_relative_to(objects_root):
                raise CommandError("Raw part path escapes the objects root")
            try:
                body = source_path.read_bytes()
            except OSError as exc:
                raise CommandError(f"Cannot read demo raw part: {source_path}") from exc

            actual_sha256 = hashlib.sha256(body).hexdigest()
            if actual_sha256 != expected_sha256:
                raise CommandError(f"Checksum mismatch for raw part #{sequence}")
            try:
                decompressed = gzip.decompress(body)
                payload = json.loads(decompressed)
            except (OSError, json.JSONDecodeError) as exc:
                raise CommandError(f"Invalid gzip/JSON in raw part #{sequence}") from exc
            if (
                not isinstance(payload, dict)
                or not isinstance(payload.get("windows"), list)
                or not payload["windows"]
            ):
                raise CommandError(f"Raw part #{sequence} has no sensor windows")
            try:
                windows = decode_sensor_windows_payload(decompressed)
            except InvalidRawSensorPayload as exc:
                raise CommandError(
                    f"Raw part #{sequence} has malformed sensor windows"
                ) from exc

            validated.append(
                {
                    "record": part_record,
                    "sequence": sequence,
                    "sha256": expected_sha256,
                    "body": body,
                    "windows": windows,
                    "object_key": storage.raw_part_object_key(
                        SEED_RAW_BASE_PATH,
                        sequence,
                    ),
                }
            )
        return validated

    def _write_raw_parts(self, raw_parts: list[dict]) -> None:
        try:
            for raw_part in raw_parts:
                storage.write_object(
                    raw_part["object_key"],
                    raw_part["body"],
                    sha256=raw_part["sha256"],
                )
        except Exception as exc:
            raise CommandError("Cannot write demo raw parts to object storage") from exc

    def _seed_database(
        self,
        *,
        fixture: dict,
        trip_record: dict,
        upload_record: dict,
        raw_parts: list[dict],
        user,
    ) -> tuple[Trip, bool]:
        existing = Trip.objects.filter(client_session_id=SEED_SESSION_ID).first()
        if existing is not None:
            self._validate_existing(existing, fixture, raw_parts, user)
            changed_fields = []
            if not existing.is_reloadable:
                existing.is_reloadable = True
                changed_fields.append("is_reloadable")
            if existing.reloaded_from_trip_id is not None:
                existing.reloaded_from_trip = None
                changed_fields.append("reloaded_from_trip")
            if changed_fields:
                existing.save(update_fields=[*changed_fields, "updated_at"])
            if not existing.raw_sensor_readings.exists():
                replace_raw_sensor_readings(existing, self._all_windows(raw_parts))
            return existing, False

        trip = self._fixture_object(trip_record, Trip)
        trip.pk = None
        trip.user = user
        trip.client_session_id = SEED_SESSION_ID
        trip.is_reloadable = True
        trip.reloaded_from_trip = None
        trip.save(force_insert=True)

        self._seed_trip_records(fixture["gps_points"], GpsPoint, trip)
        self._seed_trip_records(
            fixture["state_transitions"],
            StateTransition,
            trip,
        )
        self._seed_trip_records(fixture["segments"], MobilitySegment, trip)

        upload = self._fixture_object(upload_record, TripUpload)
        upload.pk = None
        upload.user = user
        upload.trip = trip
        upload.source_trip = None
        upload.client_session_id = SEED_SESSION_ID
        upload.raw_base_path = SEED_RAW_BASE_PATH
        upload.expected_raw_parts = len(raw_parts)
        upload.recording_started_at = trip.started_at
        upload.recording_closed_at = trip.ended_at
        upload.recording_abandoned_at = None
        upload.save(force_insert=True)

        for raw_part in raw_parts:
            part = self._fixture_object(raw_part["record"], TripUploadPart)
            part.pk = None
            part.upload = upload
            part.object_key = raw_part["object_key"]
            part.save(force_insert=True)

        persist_raw_sensor_readings(trip, self._all_windows(raw_parts))

        return trip, True

    def _all_windows(self, raw_parts: list[dict]) -> list:
        return [
            window
            for raw_part in raw_parts
            for window in raw_part["windows"]
        ]

    def _seed_trip_records(self, records: list[dict], model, trip: Trip) -> None:
        for record in records:
            instance = self._fixture_object(record, model)
            instance.pk = None
            instance.trip = trip
            instance.save(force_insert=True)

    def _fixture_object(self, record: dict, expected_model):
        record = deepcopy(record)
        record["pk"] = None
        try:
            deserialized = next(deserialize("json", json.dumps([record])))
        except Exception as exc:
            raise CommandError(
                f"Cannot deserialize fixture record {record.get('model')}"
            ) from exc
        instance = deserialized.object
        if not isinstance(instance, expected_model):
            raise CommandError(
                f"Expected {expected_model._meta.label_lower}, got {record.get('model')}"
            )
        return instance

    def _validate_existing(
        self,
        trip: Trip,
        fixture: dict,
        raw_parts: list[dict],
        user,
    ) -> None:
        if trip.user_id != user.id:
            raise CommandError("The demo seed session belongs to another user")
        expected_counts = {
            "GPS points": (trip.gps_points.count(), len(fixture["gps_points"])),
            "state transitions": (
                trip.state_transitions.count(),
                len(fixture["state_transitions"]),
            ),
            "segments": (trip.segments.count(), len(fixture["segments"])),
        }
        mismatches = [
            label
            for label, (actual, expected) in expected_counts.items()
            if actual != expected
        ]
        upload = trip.uploads.filter(
            user=user,
            client_session_id=SEED_SESSION_ID,
            source_trip__isnull=True,
        ).first()
        if upload is None or upload.parts.count() != len(raw_parts):
            mismatches.append("upload/raw parts")
        if mismatches:
            raise CommandError(
                "Existing demo trip is incomplete: " + ", ".join(mismatches)
            )
