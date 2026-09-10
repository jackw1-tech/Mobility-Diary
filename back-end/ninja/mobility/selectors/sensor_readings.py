"""Repository di scrittura della proiezione Timescale RawSensorReading.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from django.db import connection, transaction

from ..ml.pipeline import PipelineSensorWindow
from ..models import MobilitySegment, RawSensorReading, Trip

MOTION_AXES = ("accel_x", "accel_y", "accel_z", "gyro_x", "gyro_y", "gyro_z")

_MOTION_STATS_QUERY = """
    SELECT
        seg.activity_label,
        count(*) AS sample_count,
        {aggregates}
    FROM {reading_table} r
    JOIN {segment_table} seg
        ON seg.trip_id = r.trip_id
        AND r.timestamp >= seg.start_timestamp
        AND r.timestamp < seg.end_timestamp
    JOIN {trip_table} t ON t.id = r.trip_id
    WHERE t.user_id = %s AND seg.kind = 'MOVE'
    GROUP BY seg.activity_label
    ORDER BY seg.activity_label
"""

_INSERT_COLUMNS = (
    "trip_id",
    "timestamp",
    "accel_x",
    "accel_y",
    "accel_z",
    "gyro_x",
    "gyro_y",
    "gyro_z",
)


_SENSOR_GAP_QUERY = """
    WITH ordered AS (
        SELECT
            r.timestamp,
            LAG(r.timestamp) OVER (PARTITION BY seg.id ORDER BY r.timestamp) AS prev_timestamp
        FROM {reading_table} r
        JOIN {segment_table} seg
            ON seg.trip_id = r.trip_id
            AND r.timestamp >= seg.start_timestamp
            AND r.timestamp < seg.end_timestamp
        WHERE r.trip_id = %s AND seg.kind = 'MOVE'
    )
    SELECT prev_timestamp, timestamp, timestamp - prev_timestamp AS gap
    FROM ordered
    WHERE prev_timestamp IS NOT NULL
        AND timestamp - prev_timestamp > (%s * INTERVAL '1 millisecond')
    ORDER BY prev_timestamp
"""


def find_sensor_gaps(
    trip_id: int, *, threshold_ms: int = 10
) -> list[tuple[datetime, datetime, timedelta]]:
    """Buchi (>threshold_ms) tra letture sensore consecutive di un viaggio.

    Limitata ai soli intervalli classificati MOVE, e calcolata per singolo
    segmento (PARTITION BY seg.id): un buco durante una sosta e' atteso (il
    dispositivo non ha bisogno di campionare densamente da fermo), quindi non
    e' un'anomalia da segnalare; allo stesso modo lo scarto tra la fine di un
    segmento di movimento e l'inizio del successivo (che attraversa una sosta
    nel mezzo) non deve mai comparire come "buco".

    Usata sia dall'admin Django sia dalla dashboard web/staff, cosi' la
    query LAG() resta definita in un solo posto.
    """
    reading_table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    segment_table = connection.ops.quote_name(MobilitySegment._meta.db_table)
    with connection.cursor() as cursor:
        cursor.execute(
            _SENSOR_GAP_QUERY.format(
                reading_table=reading_table, segment_table=segment_table
            ),
            [trip_id, threshold_ms],
        )
        return cursor.fetchall()


def find_motion_stats_by_activity(user_id: int) -> list[dict]:
    """Media/deviazione standard di accelerometro e giroscopio per modalita'.

    Unisce le letture raw (TimescaleDB) ai segmenti di movimento (MOVE) di
    *tutti* i viaggi dell'utente, raggruppando per activity_label. Serve a
    confrontare come si comporta il segnale grezzo tra le diverse modalita'
    riconosciute (WALKING/RUNNING/BIKING/MOVING_VEHICLE).
    """
    aggregates = ", ".join(
        f"avg(r.{axis}) AS {axis}_mean, stddev(r.{axis}) AS {axis}_std"
        for axis in MOTION_AXES
    )
    sql = _MOTION_STATS_QUERY.format(
        aggregates=aggregates,
        reading_table=connection.ops.quote_name(RawSensorReading._meta.db_table),
        segment_table=connection.ops.quote_name(MobilitySegment._meta.db_table),
        trip_table=connection.ops.quote_name(Trip._meta.db_table),
    )
    with connection.cursor() as cursor:
        cursor.execute(sql, [user_id])
        columns = [col[0] for col in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


"Funzione che inserisce i dati raw nel db TimeScale"
def persist_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    readings = [
        RawSensorReading(
            trip=trip,
            timestamp=window.start_timestamp
            + timedelta(seconds=index / window.frequency_hz),
            accel_x=row[0],
            accel_y=row[1],
            accel_z=row[2],
            gyro_x=row[3],
            gyro_y=row[4],
            gyro_z=row[5],
        )
        for window in windows
        for index, row in enumerate(window.matrix)
    ]
    RawSensorReading.objects.bulk_create(readings, batch_size=5000)
    return len(readings)

# Puliamo i raw sensor reading di quel viaggio prima di reinserli (utile per i retry) e poi reinsceliscili
def replace_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    with transaction.atomic():
        RawSensorReading.objects.filter(trip=trip).delete()
        return persist_raw_sensor_readings(trip, windows)


#Cerco di clonare i dati raw dal db al db 
def replace_raw_sensor_readings_from_source(
    trip: Trip,
    source: Trip,
    *,
    shift: timedelta,
) -> int:
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    value_columns = ", ".join(
        connection.ops.quote_name(column) for column in _INSERT_COLUMNS[2:]
    )
    trip_id_column = connection.ops.quote_name(_INSERT_COLUMNS[0])
    timestamp_column = connection.ops.quote_name(_INSERT_COLUMNS[1])

    params: list[object] = [trip.id, shift, source.id]

    sql = (
        f"INSERT INTO {table} ({columns}) "
        f"SELECT %s, {timestamp_column} + %s, {value_columns} "
        f"FROM {table} WHERE {trip_id_column} = %s"
    )

    with transaction.atomic():
        RawSensorReading.objects.filter(trip=trip).delete()
        with connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.rowcount
