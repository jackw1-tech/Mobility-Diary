from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0017_tripingestion_last_seen_at_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="trip",
            name="is_reloadable",
            field=models.BooleanField(default=False),
        ),
    ]
