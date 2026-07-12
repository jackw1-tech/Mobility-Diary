from django.db import migrations, models


def drop_legacy_non_raw_parts(apps, schema_editor):
    TripIngestionPart = apps.get_model("mobility", "TripIngestionPart")
    TripIngestionPart.objects.exclude(kind="sensor_windows").delete()


def normalize_expected_raw_parts(apps, schema_editor):
    TripIngestion = apps.get_model("mobility", "TripIngestion")
    for ingestion in TripIngestion.objects.only("id", "expected_raw_parts").iterator():
        value = ingestion.expected_raw_parts
        if isinstance(value, dict):
            count = sum(int(part_count or 0) for part_count in value.values())
        else:
            count = int(value or 0)
        if value != count:
            ingestion.expected_raw_parts = count
            ingestion.save(update_fields=["expected_raw_parts"])


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0025_remove_part_based_core_ingestion"),
    ]

    operations = [
        migrations.RunPython(
            drop_legacy_non_raw_parts,
            migrations.RunPython.noop,
        ),
        migrations.RemoveConstraint(
            model_name="tripingestionpart",
            name="unique_part_per_ingestion_kind_sequence",
        ),
        migrations.RemoveField(
            model_name="tripingestionpart",
            name="kind",
        ),
        migrations.RunPython(
            normalize_expected_raw_parts,
            migrations.RunPython.noop,
        ),
        migrations.AlterField(
            model_name="tripingestion",
            name="expected_raw_parts",
            field=models.JSONField(default=int),
        ),
        migrations.AddConstraint(
            model_name="tripingestionpart",
            constraint=models.UniqueConstraint(
                fields=("ingestion", "sequence"),
                name="unique_part_per_ingestion_sequence",
            ),
        ),
    ]
