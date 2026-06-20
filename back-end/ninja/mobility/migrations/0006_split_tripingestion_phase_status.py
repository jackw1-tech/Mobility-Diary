from django.db import migrations, models


def split_status(apps, schema_editor):
    TripIngestion = apps.get_model("mobility", "TripIngestion")

    core_status_map = {
        "CREATED": "PENDING",
        "RECEIVING": "RECEIVING",
        "READY_TO_PROCESS": "RECEIVED",
        "QUEUED": "QUEUED",
        "PROCESSING": "PROCESSING",
        "PROCESSED": "COMPLETED",
        "COMPLETED": "COMPLETED",
        "FAILED_RETRYABLE": "FAILED_RETRYABLE",
        "FAILED_FINAL": "FAILED_FINAL",
    }

    for ingestion in TripIngestion.objects.all().iterator():
        expected_parts = ingestion.expected_parts or {}
        expected_core_parts = {
            key: int(expected_parts.get(key, 0) or 0)
            for key in ("gps_points", "state_transitions")
            if int(expected_parts.get(key, 0) or 0) > 0
        }
        expected_raw_parts = {
            key: int(expected_parts.get(key, 0) or 0)
            for key in ("sensor_windows",)
            if int(expected_parts.get(key, 0) or 0) > 0
        }

        raw_status = "COMPLETED"
        if expected_raw_parts:
            expected_raw_count = sum(expected_raw_parts.values())
            received_raw_count = ingestion.parts.filter(
                kind="sensor_windows", received_at__isnull=False
            ).count()
            raw_status = (
                "RECEIVED"
                if received_raw_count >= expected_raw_count
                else "RECEIVING"
            )

        ingestion.core_status = core_status_map.get(ingestion.status, "PENDING")
        ingestion.raw_status = raw_status
        ingestion.expected_core_parts = expected_core_parts
        ingestion.expected_raw_parts = expected_raw_parts
        ingestion.save(
            update_fields=[
                "core_status",
                "raw_status",
                "expected_core_parts",
                "expected_raw_parts",
            ]
        )


class Migration(migrations.Migration):
    dependencies = [
        ("mobility", "0005_tripingestion_tripingestionpart_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="tripingestion",
            name="core_status",
            field=models.CharField(
                choices=[
                    ("PENDING", "Pending"),
                    ("RECEIVING", "Receiving"),
                    ("RECEIVED", "Received"),
                    ("QUEUED", "Queued"),
                    ("PROCESSING", "Processing"),
                    ("COMPLETED", "Completed"),
                    ("FAILED_RETRYABLE", "Failed (retryable)"),
                    ("FAILED_FINAL", "Failed (final)"),
                ],
                default="PENDING",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="tripingestion",
            name="raw_status",
            field=models.CharField(
                choices=[
                    ("PENDING", "Pending"),
                    ("RECEIVING", "Receiving"),
                    ("RECEIVED", "Received"),
                    ("QUEUED", "Queued"),
                    ("PROCESSING", "Processing"),
                    ("COMPLETED", "Completed"),
                    ("FAILED_RETRYABLE", "Failed (retryable)"),
                    ("FAILED_FINAL", "Failed (final)"),
                ],
                default="PENDING",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="tripingestion",
            name="expected_core_parts",
            field=models.JSONField(default=dict),
        ),
        migrations.AddField(
            model_name="tripingestion",
            name="expected_raw_parts",
            field=models.JSONField(default=dict),
        ),
        migrations.RunPython(split_status, migrations.RunPython.noop),
        migrations.RemoveIndex(
            model_name="tripingestion",
            name="mobility_tr_user_id_7fcf9f_idx",
        ),
        migrations.RemoveField(
            model_name="tripingestion",
            name="status",
        ),
        migrations.RemoveField(
            model_name="tripingestion",
            name="expected_parts",
        ),
        migrations.AddIndex(
            model_name="tripingestion",
            index=models.Index(
                fields=["user", "core_status"],
                name="mobility_tr_user_id_013802_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="tripingestion",
            index=models.Index(
                fields=["user", "raw_status"],
                name="mobility_tr_user_id_4b7a85_idx",
            ),
        ),
    ]
