from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0026_remove_tripingestionpart_kind"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="harjob",
            name="kind",
        ),
    ]
