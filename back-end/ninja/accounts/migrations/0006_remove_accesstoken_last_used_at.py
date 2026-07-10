from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0005_remove_accesstoken_user_agent"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="accesstoken",
            name="last_used_at",
        ),
    ]
