"""Repository di scrittura della proiezione Timescale RawSensorReading.
"""

from __future__ import annotations

from datetime import timedelta

from django.db import connection, transaction

from ..ml.pipeline import PipelineSensorWindow
from ..models import RawSensorReading, Trip

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
