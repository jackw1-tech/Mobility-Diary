from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("mobility", "0024_remove_tripingestion_core_payload_sha256"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="tripingestion",
            name="core_ingestion_mode",
        ),
        migrations.RemoveField(
            model_name="tripingestion",
            name="expected_core_parts",
        ),
        migrations.AlterField(
            model_name="tripingestionpart",
            name="kind",
            field=models.CharField(
                choices=[("sensor_windows", "Sensor windows")],
                max_length=32,
            ),
        ),
    ]
