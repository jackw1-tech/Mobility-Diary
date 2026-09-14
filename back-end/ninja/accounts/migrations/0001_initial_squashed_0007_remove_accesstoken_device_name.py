import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    replaces = [('accounts', '0001_initial'), ('accounts', '0002_userprivacysettings'), ('accounts', '0003_userprivacysettings_is_first_login'), ('accounts', '0004_webrefreshtoken'), ('accounts', '0005_remove_accesstoken_user_agent'), ('accounts', '0006_remove_accesstoken_last_used_at'), ('accounts', '0007_remove_accesstoken_device_name')]

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='UserPrivacySettings',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('level', models.CharField(choices=[('precise', 'Precise'), ('approximate', 'Approximate'), ('aggregated', 'Aggregated')], default='precise', max_length=16)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='privacy_settings', to=settings.AUTH_USER_MODEL)),
                ('is_first_login', models.BooleanField(default=True)),
            ],
        ),
        migrations.CreateModel(
            name='WebRefreshToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('jti', models.CharField(max_length=64, unique=True)),
                ('expires_at', models.DateTimeField()),
                ('revoked_at', models.DateTimeField(blank=True, null=True)),
                ('rotated_to_jti', models.CharField(blank=True, max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('last_used_at', models.DateTimeField(blank=True, null=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='web_refresh_tokens', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'indexes': [models.Index(fields=['user', 'expires_at'], name='accounts_we_user_id_c51122_idx'), models.Index(fields=['jti'], name='accounts_we_jti_b554c4_idx')],
            },
        ),
        migrations.CreateModel(
            name='AccessToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('token_hash', models.CharField(max_length=64, unique=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('expires_at', models.DateTimeField()),
                ('revoked_at', models.DateTimeField(blank=True, null=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='access_tokens', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'indexes': [models.Index(fields=['user', 'expires_at'], name='accounts_ac_user_id_685e01_idx'), models.Index(fields=['token_hash'], name='accounts_ac_token_h_f17b15_idx')],
            },
        ),
    ]
