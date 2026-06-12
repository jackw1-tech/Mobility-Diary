import django.contrib.gis.db.models.fields
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0003_enable_postgis"),
    ]

    operations = [
        migrations.AddField(
            model_name="trip",
            name="client_session_id",
            field=models.CharField(blank=True, max_length=64, null=True, unique=True),
        ),
        migrations.RemoveField(model_name="gpspoint", name="latitude"),
        migrations.RemoveField(model_name="gpspoint", name="longitude"),
        migrations.AddField(
            model_name="gpspoint",
            name="point",
            field=django.contrib.gis.db.models.fields.PointField(
                default="POINT(0 0)", geography=True, srid=4326
            ),
            preserve_default=False,
        ),
        migrations.AddConstraint(
            model_name="gpspoint",
            constraint=models.UniqueConstraint(
                fields=("trip", "timestamp"),
                name="unique_gps_point_per_trip_timestamp",
            ),
        ),
        migrations.CreateModel(
            name="StateTransition",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("from_state", models.CharField(max_length=32)),
                ("to_state", models.CharField(max_length=32)),
                ("reason", models.CharField(blank=True, max_length=128)),
                ("timestamp", models.DateTimeField()),
                ("sigma", models.FloatField(blank=True, null=True)),
                ("speed_mps", models.FloatField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("trip", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="state_transitions", to="mobility.trip")),
            ],
            options={
                "indexes": [models.Index(fields=["trip", "timestamp"], name="mobility_st_trip_id_idx")],
                "constraints": [models.UniqueConstraint(fields=("trip", "timestamp", "to_state"), name="unique_state_transition_per_trip_time")],
            },
        ),
        migrations.CreateModel(
            name="SignificantPlace",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("center", django.contrib.gis.db.models.fields.PointField(geography=True, srid=4326)),
                ("radius_meters", models.FloatField(default=0)),
                ("dwell_seconds", models.PositiveIntegerField(default=0)),
                ("label", models.CharField(blank=True, max_length=128)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("trip", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="significant_places", to="mobility.trip")),
            ],
        ),
        migrations.CreateModel(
            name="MobilitySegment",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("kind", models.CharField(choices=[("STOP", "Stop"), ("MOVE", "Move")], max_length=8)),
                ("start_timestamp", models.DateTimeField()),
                ("end_timestamp", models.DateTimeField()),
                ("activity_label", models.CharField(choices=[("IDLE", "Idle"), ("WALKING", "Walking"), ("RUNNING", "Running"), ("BIKING", "Biking"), ("MOVING_VEHICLE", "Moving vehicle")], default="IDLE", max_length=32)),
                ("distance_meters", models.FloatField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("place", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="segments", to="mobility.significantplace")),
                ("trip", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="segments", to="mobility.trip")),
            ],
            options={
                "ordering": ["start_timestamp"],
                "indexes": [models.Index(fields=["trip", "start_timestamp"], name="mobility_seg_trip_id_idx")],
            },
        ),
    ]
