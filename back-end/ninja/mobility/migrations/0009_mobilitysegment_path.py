from django.contrib.gis.db import models as gis_models
from django.contrib.postgres.indexes import GistIndex
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("mobility", "0008_tripingestion_core_inline_state"),
    ]

    operations = [
        migrations.AddField(
            model_name="mobilitysegment",
            name="path",
            field=gis_models.LineStringField(
                blank=True,
                geography=True,
                null=True,
                spatial_index=False,
                srid=4326,
            ),
        ),
        migrations.AddIndex(
            model_name="mobilitysegment",
            index=GistIndex(fields=["path"], name="mobility_seg_path_gist"),
        ),
    ]
