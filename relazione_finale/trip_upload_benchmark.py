"""
Client di simulazione per misurare il tempo della fase di raw upload
(fase misurabile solo lato client: i byte grezzi vanno direttamente su
S3/MinIO tramite URL presignata, senza passare dal backend Django).

Le altre fasi (core, HAR+diario, batch raw insert, data mining luoghi) sono
misurate lato backend tramite le stampe "[BENCHMARK] ..." aggiunte in
mobility/upload/api.py e mobility/tasks.py: questo script serve solo a
generare traffico realistico e a cronometrare la fase di upload raw.

Uso:
    pip install requests
    python trip_upload_benchmark.py

Genera 10 account fittizi, ciascuno esegue 5 cicli di viaggio completi in
sequenza (registrazione -> start -> core -> upload raw a parti -> complete
-> polling diario), con i 10 account eseguiti in parallelo (10 thread), per
un totale di 50 viaggi. Il rate di richieste al secondo non e' limitato
artificialmente: ogni thread procede il piu' velocemente possibile nel
proprio ciclo, quindi il carico effettivo dipende dalla latenza reale del
server (upload sequenziale entro un account, 10 account in parallelo).

Al termine stampa, per ciascun viaggio, la durata della fase raw upload
(client-side) e scrive tutte le misure anche in un CSV.
"""

from __future__ import annotations

import csv
import gzip
import hashlib
import json
import random
import statistics
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import requests

BASE_URL = "http://localhost:8080/api"

NUM_USERS = 25
TRIPS_PER_USER = 10
TRIP_DURATION = timedelta(hours=1)
GPS_INTERVAL_SECONDS = 10
WINDOW_SECONDS = 5  # 500 campioni a 100 Hz
SAMPLE_RATE_HZ = 100
SAMPLES_PER_WINDOW = 500
CHANNELS_PER_SAMPLE = 6
# Stesso budget usato dal client Flutter reale (trip_package_builder.dart):
# 12 MB di JSON non compresso per parte, non un numero fisso di finestre.
SENSOR_WINDOWS_PART_BUDGET_BYTES = 12 * 1024 * 1024
# Default reale di trip_sync_queue_impl.dart (rawUploadConcurrency).
RAW_UPLOAD_CONCURRENCY = 3
DIARY_POLL_INTERVAL_S = 2
DIARY_POLL_TIMEOUT_S = 180

BOLOGNA_LAT = 44.4949
BOLOGNA_LON = 11.3426


@dataclass
class TripTiming:
    account_email: str
    trip_index: int
    upload_id: int
    trip_id: int | None
    raw_upload_duration_s: float
    num_parts: int
    diary_wait_s: float
    diary_processed: bool


def register_or_login(session: requests.Session, email: str, password: str) -> str:
    resp = session.post(
        f"{BASE_URL}/auth/register",
        json={
            "email": email,
            "password": password,
            "first_name": "Benchmark",
            "last_name": "User",
        },
    )
    if resp.status_code == 201:
        return resp.json()["access_token"]

    # Account gia' esistente da una run precedente: login normale.
    resp = session.post(
        f"{BASE_URL}/auth/login", json={"email": email, "password": password}
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def build_gps_points(started_at: datetime) -> list[dict]:
    points = []
    lat, lon = BOLOGNA_LAT, BOLOGNA_LON
    num_points = int(TRIP_DURATION.total_seconds() // GPS_INTERVAL_SECONDS) + 1
    for i in range(num_points):
        # Piccola passeggiata casuale, cosi' il path non e' degenere.
        lat += random.uniform(-0.0003, 0.0003)
        lon += random.uniform(-0.0003, 0.0003)
        points.append(
            {
                "timestamp": (
                    started_at + timedelta(seconds=i * GPS_INTERVAL_SECONDS)
                ).isoformat(),
                "latitude": lat,
                "longitude": lon,
                "speed_mps": random.uniform(0.5, 12.0),
                "accuracy_meters": random.uniform(3.0, 15.0),
            }
        )
    return points


def build_state_transitions(started_at: datetime) -> list[dict]:
    return [
        {
            "timestamp": started_at.isoformat(),
            "from_state": "STATIONARY",
            "to_state": "MOVING",
            "sigma": 1.8,
            "speed_mps": 4.0,
        }
    ]


def build_sensor_windows(started_at: datetime) -> list[dict]:
    windows = []
    num_windows = int(TRIP_DURATION.total_seconds() // WINDOW_SECONDS)
    for i in range(num_windows):
        window_start = started_at + timedelta(seconds=i * WINDOW_SECONDS)
        window_end = window_start + timedelta(seconds=WINDOW_SECONDS)
        # Arrotondato a 6 decimali come sensor_matrix_json.dart (_rounded):
        # il client reale non manda mai float a piena precisione.
        samples = [
            [round(random.uniform(-2.0, 2.0), 6) for _ in range(CHANNELS_PER_SAMPLE)]
            for _ in range(SAMPLES_PER_WINDOW)
        ]
        windows.append(
            {
                "window_start": window_start.isoformat(),
                "window_end": window_end.isoformat(),
                "sample_rate_hz": SAMPLE_RATE_HZ,
                "samples": samples,
            }
        )
    return windows


def chunk_windows_by_budget(windows: list[dict]) -> list[list[dict]]:
    # Stesso criterio del client reale: accumula finestre finche' il JSON non
    # compresso della parte supera il budget, poi apre una parte nuova.
    parts: list[list[dict]] = []
    current: list[dict] = []
    current_size = 0
    for window in windows:
        window_size = len(json.dumps(window).encode("utf-8"))
        if current and current_size + window_size > SENSOR_WINDOWS_PART_BUDGET_BYTES:
            parts.append(current)
            current = []
            current_size = 0
        current.append(window)
        current_size += window_size
    if current:
        parts.append(current)
    return parts


def gzip_part(windows: list[dict]) -> bytes:
    payload = json.dumps({"windows": windows}).encode("utf-8")
    return gzip.compress(payload)


def run_single_trip(
    session: requests.Session, email: str, trip_index: int
) -> TripTiming:
    client_session_id = f"bench-{email}-{trip_index}-{int(time.time())}"
    started_at = datetime.now(timezone.utc) - TRIP_DURATION
    ended_at = datetime.now(timezone.utc)

    start_resp = session.post(
        f"{BASE_URL}/upload/trips/start",
        json={
            "client_session_id": client_session_id,
            "started_at": started_at.isoformat(),
            "device_id": "benchmark-device",
        },
    )
    start_resp.raise_for_status()
    upload_id = start_resp.json()["upload_id"]

    gps_points = build_gps_points(started_at)
    state_transitions = build_state_transitions(started_at)
    all_windows = build_sensor_windows(started_at)
    parts = chunk_windows_by_budget(all_windows)

    core_resp = session.post(
        f"{BASE_URL}/upload/trips/core",
        json={
            "upload_id": upload_id,
            "client_session_id": client_session_id,
            "started_at": started_at.isoformat(),
            "ended_at": ended_at.isoformat(),
            "device_id": "benchmark-device",
            "gps_points": gps_points,
            "state_transitions": state_transitions,
            "expected_raw_parts": len(parts),
        },
    )
    core_resp.raise_for_status()
    trip_id = core_resp.json()["trip_id"]

    # Fase raw upload: l'unica fase invisibile al backend, misurata qui.
    # Le parti sono precompresse prima del timer, come fa il client reale
    # (TripPackageBuilder le scrive su disco prima di metterle in coda per
    # l'upload) - qui il timer misura solo presign+PUT+confirm.
    prepared_parts = []
    for sequence, part_windows in enumerate(parts, start=1):
        gz_bytes = gzip_part(part_windows)
        sha256_hex = hashlib.sha256(gz_bytes).hexdigest()
        prepared_parts.append((sequence, gz_bytes, sha256_hex))

    def upload_single_part(sequence: int, gz_bytes: bytes, sha256_hex: str) -> None:
        presign_resp = session.post(
            f"{BASE_URL}/upload/trips/{upload_id}/parts/presign",
            json={"sequence": sequence, "sha256": sha256_hex},
        )
        presign_resp.raise_for_status()
        presign_data = presign_resp.json()

        put_resp = requests.put(
            presign_data["upload_url"],
            data=gz_bytes,
            headers=presign_data["upload_headers"],
        )
        put_resp.raise_for_status()

        confirm_resp = session.post(
            f"{BASE_URL}/upload/trips/{upload_id}/parts/confirm",
            json={"sequence": sequence, "sha256": sha256_hex},
        )
        confirm_resp.raise_for_status()

    raw_upload_started_at = time.monotonic()
    # Stesso schema del client reale (trip_sync_queue_impl.dart): blocchi di
    # RAW_UPLOAD_CONCURRENCY parti caricate in parallelo con Future.wait,
    # un blocco alla volta.
    for i in range(0, len(prepared_parts), RAW_UPLOAD_CONCURRENCY):
        batch = prepared_parts[i : i + RAW_UPLOAD_CONCURRENCY]
        with ThreadPoolExecutor(max_workers=len(batch)) as part_executor:
            list(part_executor.map(lambda p: upload_single_part(*p), batch))

    complete_resp = session.post(
        f"{BASE_URL}/upload/trips/{upload_id}/complete-raw",
        json={"total_parts": len(parts)},
    )
    complete_resp.raise_for_status()
    raw_upload_duration_s = time.monotonic() - raw_upload_started_at

    # Non incluso nella misura raw upload: attesa che il backend finisca di
    # elaborare il viaggio (fasi HAR/diario/batch/mining, misurate lato server).
    diary_wait_started_at = time.monotonic()
    processed = False
    while time.monotonic() - diary_wait_started_at < DIARY_POLL_TIMEOUT_S:
        diary_resp = session.get(f"{BASE_URL}/mobility/trips/{trip_id}/diary")
        if diary_resp.status_code == 200 and diary_resp.json().get("processed"):
            processed = True
            break
        time.sleep(DIARY_POLL_INTERVAL_S)
    diary_wait_s = time.monotonic() - diary_wait_started_at

    return TripTiming(
        account_email=email,
        trip_index=trip_index,
        upload_id=upload_id,
        trip_id=trip_id,
        raw_upload_duration_s=raw_upload_duration_s,
        num_parts=len(parts),
        diary_wait_s=diary_wait_s,
        diary_processed=processed,
    )


def run_user(user_index: int) -> list[TripTiming]:
    # Gira in un processo separato (vedi main): ogni "utente" ha la sua CPU
    # reale per serializzazione/gzip, come un telefono vero, invece di
    # contendersi il GIL con gli altri 9 nello stesso processo.
    email = f"bench-user-{user_index}@mobilitydiary.local"
    password = "Benchmark123!"
    session = requests.Session()
    token = register_or_login(session, email, password)
    session.headers.update({"Authorization": f"Bearer {token}"})

    user_results: list[TripTiming] = []
    for trip_index in range(1, TRIPS_PER_USER + 1):
        try:
            timing = run_single_trip(session, email, trip_index)
        except Exception as exc:  # noqa: BLE001 - script di benchmark, va solo loggato
            print(f"[ERRORE] {email} trip {trip_index}: {exc}")
            continue

        user_results.append(timing)
        print(
            f"{email} trip {trip_index}: raw_upload={timing.raw_upload_duration_s:.2f}s "
            f"parts={timing.num_parts} diary_wait={timing.diary_wait_s:.2f}s "
            f"processed={timing.diary_processed}"
        )
    return user_results


def main() -> None:
    results: list[TripTiming] = []

    with ProcessPoolExecutor(max_workers=NUM_USERS) as executor:
        futures = [executor.submit(run_user, i) for i in range(1, NUM_USERS + 1)]
        for future in as_completed(futures):
            results.extend(future.result())

    if not results:
        print("Nessun viaggio completato con successo.")
        return

    durations = [r.raw_upload_duration_s for r in results]
    print()
    print(f"Viaggi completati: {len(results)}/{NUM_USERS * TRIPS_PER_USER}")
    print(f"Raw upload - media: {statistics.mean(durations):.2f}s, "
          f"dev.std: {statistics.stdev(durations):.2f}s "
          f"(min={min(durations):.2f}s, max={max(durations):.2f}s)")

    with open("trip_upload_benchmark_results.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "account_email",
                "trip_index",
                "upload_id",
                "trip_id",
                "raw_upload_duration_s",
                "num_parts",
                "diary_wait_s",
                "diary_processed",
            ]
        )
        for r in results:
            writer.writerow(
                [
                    r.account_email,
                    r.trip_index,
                    r.upload_id,
                    r.trip_id,
                    f"{r.raw_upload_duration_s:.3f}",
                    r.num_parts,
                    f"{r.diary_wait_s:.3f}",
                    r.diary_processed,
                ]
            )
    print("Risultati salvati in trip_upload_benchmark_results.csv")


if __name__ == "__main__":
    main()
