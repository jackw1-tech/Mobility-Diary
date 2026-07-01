from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("mobility", "0021_alter_trip_started_at"),
    ]

    operations = [
        migrations.AddField(
            model_name="trip",
            name="note",
            field=models.TextField(blank=True),
        ),
    ]
