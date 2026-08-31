from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0006_remove_accesstoken_last_used_at"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="accesstoken",
            name="device_name",
        ),
    ]
