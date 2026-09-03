"""Rinomina TripIngestion -> TripUpload (e la parte) in tutto lo schema.

Scritta a mano: l'autodetector di Django, non potendo chiedere conferma in
modo non interattivo, avrebbe generato DELETE + CREATE al posto dei RENAME,
perdendo i dati. RenameModel rinomina la tabella conservandone il contenuto.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0031_remove_tripingestionpart_size_bytes"),
    ]

    operations = [
        # I vincoli vanno rimossi prima del rename: i loro nomi contengono
        # "ingestion" e vengono ricreati sotto il nuovo nome piu' avanti.
        migrations.RemoveConstraint(
            model_name="tripingestion",
            name="unique_ingestion_per_user_session",
        ),
        migrations.RemoveConstraint(
            model_name="tripingestion",
            name="unique_active_ingestion_per_user",
        ),
        migrations.RemoveConstraint(
            model_name="tripingestionpart",
            name="unique_part_per_ingestion_sequence",
        ),
        migrations.RenameModel(
            old_name="TripIngestion",
            new_name="TripUpload",
        ),
        migrations.RenameModel(
            old_name="TripIngestionPart",
            new_name="TripUploadPart",
        ),
        migrations.RenameField(
            model_name="tripuploadpart",
            old_name="ingestion",
            new_name="upload",
        ),
        migrations.AlterField(
            model_name="tripuploadpart",
            name="upload",
            field=models.ForeignKey(
                on_delete=models.CASCADE,
                related_name="parts",
                to="mobility.tripupload",
            ),
        ),
        migrations.AddConstraint(
            model_name="tripupload",
            constraint=models.UniqueConstraint(
                fields=("user", "client_session_id"),
                name="unique_upload_per_user_session",
            ),
        ),
        migrations.AddConstraint(
            model_name="tripupload",
            constraint=models.UniqueConstraint(
                condition=models.Q(
                    ("recording_abandoned_at__isnull", True),
                    ("recording_closed_at__isnull", True),
                    ("recording_started_at__isnull", False),
                ),
                fields=("user",),
                name="unique_active_upload_per_user",
            ),
        ),
        migrations.AddConstraint(
            model_name="tripuploadpart",
            constraint=models.UniqueConstraint(
                fields=("upload", "sequence"),
                name="unique_part_per_upload_sequence",
            ),
        ),
    ]
