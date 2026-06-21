from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0007_trip_distance_meters_trip_path_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="tripingestion",
            name="core_ingestion_mode",
            field=models.CharField(
                choices=[
                    ("LEGACY_PARTS", "Legacy parts"),
                    ("INLINE", "Inline"),
                ],
                default="LEGACY_PARTS",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="tripingestion",
            name="core_payload_sha256",
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name="tripingestion",
            name="core_payload_size_bytes",
            field=models.BigIntegerField(default=0),
        ),
    ]
