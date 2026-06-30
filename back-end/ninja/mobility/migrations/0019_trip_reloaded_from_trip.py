from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0018_trip_is_reloadable"),
    ]

    operations = [
        migrations.AddField(
            model_name="trip",
            name="reloaded_from_trip",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="reloads",
                to="mobility.trip",
            ),
        ),
    ]
