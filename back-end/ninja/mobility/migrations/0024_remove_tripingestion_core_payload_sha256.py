from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("mobility", "0023_remove_unused_ingestion_metadata_fields"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="tripingestion",
            name="core_payload_sha256",
        ),
    ]
