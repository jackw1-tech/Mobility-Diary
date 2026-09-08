# Generated manually: SensorWindow non era mai scritto da nessun path del
# backend (le sensor window raw vivono su object storage, lette via
# raw_sensor_windows_cache/raw_sensor_loader), quindi la tabella era sempre
# vuota. Vedi mobility/ml/pipeline.py e mobility/selectors/trips.py.

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('mobility', '0036_alter_gpspoint_speed_mps'),
    ]

    operations = [
        migrations.DeleteModel(
            name='SensorWindow',
        ),
    ]
