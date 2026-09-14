import django.contrib.gis.db.models.fields
import django.contrib.postgres.indexes
import django.contrib.postgres.operations
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    replaces = [('mobility', '0001_initial'), ('mobility', '0002_trip_user'), ('mobility', '0003_enable_postgis'), ('mobility', '0004_diary_models'), ('mobility', '0005_tripingestion_tripingestionpart_and_more'), ('mobility', '0006_split_tripingestion_phase_status'), ('mobility', '0007_trip_distance_meters_trip_path_and_more'), ('mobility', '0008_tripingestion_core_inline_state'), ('mobility', '0009_mobilitysegment_path'), ('mobility', '0010_habitualplace'), ('mobility', '0011_candidatevisit'), ('mobility', '0012_candidatevisit_place'), ('mobility', '0013_habitualplace_manually_reviewed'), ('mobility', '0014_virtualstopinterval'), ('mobility', '0015_remove_mobilitysegment_place_delete_significantplace'), ('mobility', '0016_placeminingstatus'), ('mobility', '0017_tripingestion_last_seen_at_and_more'), ('mobility', '0018_trip_is_reloadable'), ('mobility', '0019_trip_reloaded_from_trip'), ('mobility', '0020_tripingestion_source_trip'), ('mobility', '0021_alter_trip_started_at'), ('mobility', '0022_trip_note'), ('mobility', '0023_remove_unused_ingestion_metadata_fields'), ('mobility', '0024_remove_tripingestion_core_payload_sha256'), ('mobility', '0025_remove_part_based_core_ingestion'), ('mobility', '0026_remove_tripingestionpart_kind'), ('mobility', '0027_remove_harjob_kind'), ('mobility', '0028_remove_tripingestion_manifest_sha256'), ('mobility', '0029_rawsensorreading_hypertable'), ('mobility', '0030_enable_timescale_for_rawsensorreading'), ('mobility', '0031_remove_tripingestionpart_size_bytes'), ('mobility', '0032_rename_ingestion_to_upload'), ('mobility', '0033_rename_mobility_tr_user_id_013802_idx_mobility_tr_user_id_683856_idx_and_more'), ('mobility', '0034_remove_statetransition_reason'), ('mobility', '0035_remove_tripupload_core_payload_size_bytes_and_more'), ('mobility', '0036_alter_gpspoint_speed_mps'), ('mobility', '0037_delete_sensorwindow')]

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Trip',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('device_id', models.CharField(max_length=128)),
                ('status', models.CharField(choices=[('OPEN', 'Open'), ('CLOSED', 'Closed'), ('PROCESSED', 'Processed')], default='OPEN', max_length=32)),
                ('started_at', models.DateTimeField(auto_now_add=True)),
                ('ended_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='trips', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='HarJob',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('kind', models.CharField(choices=[('LIVE_BATCH', 'Live batch'), ('FINAL_TRIP', 'Final trip')], max_length=32)),
                ('status', models.CharField(choices=[('PENDING', 'Pending'), ('STARTED', 'Started'), ('SUCCESS', 'Success'), ('FAILURE', 'Failure')], default='PENDING', max_length=32)),
                ('result', models.JSONField(blank=True, null=True)),
                ('error', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='har_jobs', to='mobility.trip')),
            ],
        ),
        migrations.CreateModel(
            name='SensorWindow',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('start_timestamp', models.DateTimeField()),
                ('end_timestamp', models.DateTimeField()),
                ('sample_count', models.PositiveIntegerField()),
                ('frequency_hz', models.PositiveIntegerField()),
                ('matrix', models.JSONField(blank=True, null=True)),
                ('object_key', models.CharField(blank=True, max_length=512)),
                ('is_synced', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='sensor_windows', to='mobility.trip')),
            ],
            options={
                'indexes': [models.Index(fields=['trip', 'start_timestamp'], name='mobility_se_trip_id_e05376_idx')],
                'constraints': [models.UniqueConstraint(fields=('trip', 'start_timestamp', 'end_timestamp'), name='unique_sensor_window_per_trip_time_range')],
            },
        ),
        migrations.CreateModel(
            name='GpsPoint',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField()),
                ('latitude', models.DecimalField(decimal_places=6, max_digits=9)),
                ('longitude', models.DecimalField(decimal_places=6, max_digits=9)),
                ('speed_mps', models.FloatField(default=0)),
                ('accuracy_meters', models.FloatField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='gps_points', to='mobility.trip')),
            ],
            options={
                'indexes': [models.Index(fields=['trip', 'timestamp'], name='mobility_gp_trip_id_f00ff8_idx')],
            },
        ),
        django.contrib.postgres.operations.CreateExtension(
            name='postgis',
        ),
        migrations.AddField(
            model_name='trip',
            name='client_session_id',
            field=models.CharField(blank=True, max_length=64, null=True, unique=True),
        ),
        migrations.RemoveField(
            model_name='gpspoint',
            name='latitude',
        ),
        migrations.RemoveField(
            model_name='gpspoint',
            name='longitude',
        ),
        migrations.AddField(
            model_name='gpspoint',
            name='point',
            field=django.contrib.gis.db.models.fields.PointField(default='POINT(0 0)', geography=True, srid=4326),
            preserve_default=False,
        ),
        migrations.AddConstraint(
            model_name='gpspoint',
            constraint=models.UniqueConstraint(fields=('trip', 'timestamp'), name='unique_gps_point_per_trip_timestamp'),
        ),
        migrations.CreateModel(
            name='StateTransition',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('from_state', models.CharField(max_length=32)),
                ('to_state', models.CharField(max_length=32)),
                ('reason', models.CharField(blank=True, max_length=128)),
                ('timestamp', models.DateTimeField()),
                ('sigma', models.FloatField(blank=True, null=True)),
                ('speed_mps', models.FloatField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='state_transitions', to='mobility.trip')),
            ],
            options={
                'indexes': [models.Index(fields=['trip', 'timestamp'], name='mobility_st_trip_id_idx')],
                'constraints': [models.UniqueConstraint(fields=('trip', 'timestamp', 'to_state'), name='unique_state_transition_per_trip_time')],
            },
        ),
        migrations.CreateModel(
            name='SignificantPlace',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('center', django.contrib.gis.db.models.fields.PointField(geography=True, srid=4326)),
                ('radius_meters', models.FloatField(default=0)),
                ('dwell_seconds', models.PositiveIntegerField(default=0)),
                ('label', models.CharField(blank=True, max_length=128)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='significant_places', to='mobility.trip')),
            ],
        ),
        migrations.CreateModel(
            name='MobilitySegment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('kind', models.CharField(choices=[('STOP', 'Stop'), ('MOVE', 'Move')], max_length=8)),
                ('start_timestamp', models.DateTimeField()),
                ('end_timestamp', models.DateTimeField()),
                ('activity_label', models.CharField(choices=[('IDLE', 'Idle'), ('WALKING', 'Walking'), ('RUNNING', 'Running'), ('BIKING', 'Biking'), ('MOVING_VEHICLE', 'Moving vehicle')], default='IDLE', max_length=32)),
                ('distance_meters', models.FloatField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('place', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='segments', to='mobility.significantplace')),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='segments', to='mobility.trip')),
            ],
            options={
                'ordering': ['start_timestamp'],
                'indexes': [models.Index(fields=['trip', 'start_timestamp'], name='mobility_seg_trip_id_idx')],
            },
        ),
        migrations.CreateModel(
            name='TripIngestion',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('client_session_id', models.CharField(max_length=64)),
                ('device_id', models.CharField(blank=True, max_length=128)),
                ('schema_version', models.PositiveIntegerField(default=1)),
                ('status', models.CharField(choices=[('CREATED', 'Created'), ('RECEIVING', 'Receiving'), ('READY_TO_PROCESS', 'Ready to process'), ('QUEUED', 'Queued'), ('PROCESSING', 'Processing'), ('PROCESSED', 'Processed'), ('COMPLETED', 'Completed'), ('FAILED_RETRYABLE', 'Failed (retryable)'), ('FAILED_FINAL', 'Failed (final)')], default='CREATED', max_length=32)),
                ('expected_parts', models.JSONField(default=dict)),
                ('raw_base_path', models.CharField(blank=True, max_length=512)),
                ('manifest_sha256', models.CharField(blank=True, max_length=64)),
                ('total_size_bytes', models.BigIntegerField(default=0)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('ended_at', models.DateTimeField(blank=True, null=True)),
                ('timezone', models.CharField(blank=True, max_length=64)),
                ('app_version', models.CharField(blank=True, max_length=32)),
                ('device_platform', models.CharField(blank=True, max_length=32)),
                ('error_message', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('queued_at', models.DateTimeField(blank=True, null=True)),
                ('started_processing_at', models.DateTimeField(blank=True, null=True)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('failed_at', models.DateTimeField(blank=True, null=True)),
                ('trip', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='ingestions', to='mobility.trip')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trip_ingestions', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='TripIngestionPart',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('kind', models.CharField(choices=[('gps_points', 'GPS points'), ('state_transitions', 'State transitions'), ('sensor_windows', 'Sensor windows')], max_length=32)),
                ('sequence', models.PositiveIntegerField()),
                ('sha256', models.CharField(max_length=64)),
                ('size_bytes', models.BigIntegerField(default=0)),
                ('object_key', models.CharField(max_length=512)),
                ('received_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('ingestion', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='parts', to='mobility.tripingestion')),
            ],
        ),
        migrations.AddIndex(
            model_name='tripingestion',
            index=models.Index(fields=['user', 'status'], name='mobility_tr_user_id_7fcf9f_idx'),
        ),
        migrations.AddConstraint(
            model_name='tripingestion',
            constraint=models.UniqueConstraint(fields=('user', 'client_session_id'), name='unique_ingestion_per_user_session'),
        ),
        migrations.AddConstraint(
            model_name='tripingestionpart',
            constraint=models.UniqueConstraint(fields=('ingestion', 'kind', 'sequence'), name='unique_part_per_ingestion_kind_sequence'),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='core_status',
            field=models.CharField(choices=[('PENDING', 'Pending'), ('RECEIVING', 'Receiving'), ('RECEIVED', 'Received'), ('QUEUED', 'Queued'), ('PROCESSING', 'Processing'), ('COMPLETED', 'Completed'), ('FAILED_RETRYABLE', 'Failed (retryable)'), ('FAILED_FINAL', 'Failed (final)')], default='PENDING', max_length=32),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='raw_status',
            field=models.CharField(choices=[('PENDING', 'Pending'), ('RECEIVING', 'Receiving'), ('RECEIVED', 'Received'), ('QUEUED', 'Queued'), ('PROCESSING', 'Processing'), ('COMPLETED', 'Completed'), ('FAILED_RETRYABLE', 'Failed (retryable)'), ('FAILED_FINAL', 'Failed (final)')], default='PENDING', max_length=32),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='expected_core_parts',
            field=models.JSONField(default=dict),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='expected_raw_parts',
            field=models.JSONField(default=dict),
        ),
        migrations.RunPython(
            migrations.RunPython.noop,
            migrations.RunPython.noop,
        ),
        migrations.RemoveIndex(
            model_name='tripingestion',
            name='mobility_tr_user_id_7fcf9f_idx',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='status',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='expected_parts',
        ),
        migrations.AddIndex(
            model_name='tripingestion',
            index=models.Index(fields=['user', 'core_status'], name='mobility_tr_user_id_683856_idx'),
        ),
        migrations.AddIndex(
            model_name='tripingestion',
            index=models.Index(fields=['user', 'raw_status'], name='mobility_tr_user_id_467800_idx'),
        ),
        migrations.AddField(
            model_name='trip',
            name='distance_meters',
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trip',
            name='path',
            field=django.contrib.gis.db.models.fields.LineStringField(blank=True, geography=True, null=True, spatial_index=False, srid=4326),
        ),
        migrations.AddIndex(
            model_name='trip',
            index=django.contrib.postgres.indexes.GistIndex(fields=['path'], name='mobility_tr_path_12b0ca_gist'),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='core_ingestion_mode',
            field=models.CharField(choices=[('LEGACY_PARTS', 'Legacy parts'), ('INLINE', 'Inline')], default='LEGACY_PARTS', max_length=32),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='core_payload_sha256',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='core_payload_size_bytes',
            field=models.BigIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='mobilitysegment',
            name='path',
            field=django.contrib.gis.db.models.fields.LineStringField(blank=True, geography=True, null=True, spatial_index=False, srid=4326),
        ),
        migrations.AddIndex(
            model_name='mobilitysegment',
            index=django.contrib.postgres.indexes.GistIndex(fields=['path'], name='mobility_seg_path_gist'),
        ),
        migrations.CreateModel(
            name='HabitualPlace',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('center', django.contrib.gis.db.models.fields.PointField(geography=True, srid=4326)),
                ('radius_meters', models.FloatField(default=0)),
                ('state', models.CharField(choices=[('CANDIDATE', 'Candidate'), ('CONFIRMED', 'Confirmed'), ('REJECTED', 'Rejected')], default='CANDIDATE', max_length=16)),
                ('visit_count', models.PositiveIntegerField(default=0)),
                ('distinct_days', models.PositiveIntegerField(default=0)),
                ('category', models.CharField(blank=True, choices=[('casa', 'Casa'), ('universita', 'Universita'), ('lavoro', 'Lavoro'), ('palestra', 'Palestra'), ('altro', 'Altro')], max_length=16)),
                ('custom_name', models.CharField(blank=True, max_length=128)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='habitual_places', to=settings.AUTH_USER_MODEL)),
                ('manually_reviewed', models.BooleanField(default=False)),
            ],
            options={
                'indexes': [models.Index(fields=['user', 'state'], name='mobility_ha_user_id_c2e7d0_idx')],
            },
        ),
        migrations.CreateModel(
            name='CandidateVisit',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('center', django.contrib.gis.db.models.fields.PointField(geography=True, srid=4326)),
                ('started_at', models.DateTimeField()),
                ('ended_at', models.DateTimeField()),
                ('point_count', models.PositiveIntegerField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='candidate_visits', to=settings.AUTH_USER_MODEL)),
                ('place', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='visits', to='mobility.habitualplace')),
            ],
            options={
                'indexes': [models.Index(fields=['user', 'started_at'], name='mobility_ca_user_id_330435_idx')],
            },
        ),
        migrations.CreateModel(
            name='VirtualStopInterval',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('start_timestamp', models.DateTimeField()),
                ('end_timestamp', models.DateTimeField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='virtual_stop_intervals', to='mobility.trip')),
            ],
            options={
                'ordering': ['start_timestamp'],
                'indexes': [models.Index(fields=['trip', 'start_timestamp'], name='mobility_vstop_trip_id_idx')],
                'constraints': [models.UniqueConstraint(fields=('trip', 'start_timestamp', 'end_timestamp'), name='unique_virtual_stop_interval_per_trip_time_range')],
            },
        ),
        migrations.RemoveField(
            model_name='mobilitysegment',
            name='place',
        ),
        migrations.DeleteModel(
            name='SignificantPlace',
        ),
        migrations.CreateModel(
            name='PlaceMiningStatus',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('status', models.CharField(choices=[('IDLE', 'Idle'), ('PENDING', 'Pending'), ('RUNNING', 'Running'), ('SUCCEEDED', 'Succeeded'), ('FAILED', 'Failed')], default='PENDING', max_length=16)),
                ('requested_at', models.DateTimeField(blank=True, null=True)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('finished_at', models.DateTimeField(blank=True, null=True)),
                ('error_message', models.TextField(blank=True)),
                ('rerun_requested', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='place_mining_status', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='last_seen_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='recording_abandoned_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='recording_closed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='recording_started_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddIndex(
            model_name='tripingestion',
            index=models.Index(fields=['user', 'recording_started_at'], name='mobility_tr_user_id_54eab0_idx'),
        ),
        migrations.AddConstraint(
            model_name='tripingestion',
            constraint=models.UniqueConstraint(condition=models.Q(('recording_abandoned_at__isnull', True), ('recording_closed_at__isnull', True), ('recording_started_at__isnull', False)), fields=('user',), name='unique_active_ingestion_per_user'),
        ),
        migrations.AddField(
            model_name='trip',
            name='is_reloadable',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='trip',
            name='reloaded_from_trip',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='reloads', to='mobility.trip'),
        ),
        migrations.AddField(
            model_name='tripingestion',
            name='source_trip',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='replay_ingestions', to='mobility.trip'),
        ),
        migrations.AlterField(
            model_name='trip',
            name='started_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='trip',
            name='note',
            field=models.TextField(blank=True),
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='app_version',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='device_platform',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='schema_version',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='timezone',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='core_payload_sha256',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='core_ingestion_mode',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='expected_core_parts',
        ),
        migrations.AlterField(
            model_name='tripingestionpart',
            name='kind',
            field=models.CharField(choices=[('sensor_windows', 'Sensor windows')], max_length=32),
        ),
        migrations.RunPython(
            migrations.RunPython.noop,
            migrations.RunPython.noop,
        ),
        migrations.RemoveConstraint(
            model_name='tripingestionpart',
            name='unique_part_per_ingestion_kind_sequence',
        ),
        migrations.RemoveField(
            model_name='tripingestionpart',
            name='kind',
        ),
        migrations.RunPython(
            migrations.RunPython.noop,
            migrations.RunPython.noop,
        ),
        migrations.AlterField(
            model_name='tripingestion',
            name='expected_raw_parts',
            field=models.JSONField(default=int),
        ),
        migrations.AddConstraint(
            model_name='tripingestionpart',
            constraint=models.UniqueConstraint(fields=('ingestion', 'sequence'), name='unique_part_per_ingestion_sequence'),
        ),
        migrations.RemoveField(
            model_name='harjob',
            name='kind',
        ),
        migrations.RemoveField(
            model_name='tripingestion',
            name='manifest_sha256',
        ),
        migrations.CreateModel(
            name='RawSensorReading',
            fields=[
                ('pk', models.CompositePrimaryKey('trip_id', 'timestamp', blank=True, editable=False, primary_key=True, serialize=False)),
                ('timestamp', models.DateTimeField()),
                ('accel_x', models.FloatField()),
                ('accel_y', models.FloatField()),
                ('accel_z', models.FloatField()),
                ('gyro_x', models.FloatField()),
                ('gyro_y', models.FloatField()),
                ('gyro_z', models.FloatField()),
                ('trip', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='raw_sensor_readings', to='mobility.trip')),
            ],
        ),
        migrations.RunSQL(
            sql="\nDO $$\nBEGIN\n    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN\n        PERFORM public.create_hypertable(\n            'mobility_rawsensorreading',\n            'timestamp',\n            chunk_time_interval => INTERVAL '1 day',\n            if_not_exists => TRUE,\n            migrate_data => TRUE\n        );\n    ELSE\n        RAISE NOTICE\n            'timescaledb non installata: mobility_rawsensorreading resta una tabella normale';\n    END IF;\nEND\n$$;\n",
            reverse_sql='',
        ),
        migrations.RunSQL(
            sql="\nDO $$\nBEGIN\n    IF EXISTS (\n        SELECT 1\n        FROM pg_available_extensions\n        WHERE name = 'timescaledb'\n    ) THEN\n        EXECUTE 'CREATE EXTENSION IF NOT EXISTS timescaledb';\n\n        PERFORM public.create_hypertable(\n            'mobility_rawsensorreading',\n            'timestamp',\n            chunk_time_interval => INTERVAL '1 day',\n            if_not_exists => TRUE,\n            migrate_data => TRUE\n        );\n    ELSE\n        RAISE NOTICE\n            'timescaledb non disponibile: mobility_rawsensorreading resta tabella normale';\n    END IF;\nEND\n$$;\n",
            reverse_sql='',
        ),
        migrations.RemoveField(
            model_name='tripingestionpart',
            name='size_bytes',
        ),
        migrations.RemoveConstraint(
            model_name='tripingestion',
            name='unique_ingestion_per_user_session',
        ),
        migrations.RemoveConstraint(
            model_name='tripingestion',
            name='unique_active_ingestion_per_user',
        ),
        migrations.RemoveConstraint(
            model_name='tripingestionpart',
            name='unique_part_per_ingestion_sequence',
        ),
        migrations.RenameModel(
            old_name='TripIngestion',
            new_name='TripUpload',
        ),
        migrations.RenameModel(
            old_name='TripIngestionPart',
            new_name='TripUploadPart',
        ),
        migrations.RenameField(
            model_name='tripuploadpart',
            old_name='ingestion',
            new_name='upload',
        ),
        migrations.AlterField(
            model_name='tripuploadpart',
            name='upload',
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='parts', to='mobility.tripupload'),
        ),
        migrations.AddConstraint(
            model_name='tripupload',
            constraint=models.UniqueConstraint(fields=('user', 'client_session_id'), name='unique_upload_per_user_session'),
        ),
        migrations.AddConstraint(
            model_name='tripupload',
            constraint=models.UniqueConstraint(condition=models.Q(('recording_abandoned_at__isnull', True), ('recording_closed_at__isnull', True), ('recording_started_at__isnull', False)), fields=('user',), name='unique_active_upload_per_user'),
        ),
        migrations.AddConstraint(
            model_name='tripuploadpart',
            constraint=models.UniqueConstraint(fields=('upload', 'sequence'), name='unique_part_per_upload_sequence'),
        ),
        migrations.AlterField(
            model_name='tripupload',
            name='source_trip',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='replay_uploads', to='mobility.trip'),
        ),
        migrations.AlterField(
            model_name='tripupload',
            name='trip',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='uploads', to='mobility.trip'),
        ),
        migrations.AlterField(
            model_name='tripupload',
            name='user',
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trip_uploads', to=settings.AUTH_USER_MODEL),
        ),
        migrations.RemoveField(
            model_name='statetransition',
            name='reason',
        ),
        migrations.RemoveField(
            model_name='tripupload',
            name='core_payload_size_bytes',
        ),
        migrations.RemoveField(
            model_name='tripupload',
            name='total_size_bytes',
        ),
        migrations.AlterField(
            model_name='gpspoint',
            name='speed_mps',
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.DeleteModel(
            name='SensorWindow',
        ),
    ]
