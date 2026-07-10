from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0004_webrefreshtoken"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="accesstoken",
            name="user_agent",
        ),
    ]
