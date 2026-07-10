import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("mobility_diary")
app.config_from_object("django.conf:settings", namespace="CELERY")

#Cerca dentro le app installate di django il file task.py e registra i possibili task
app.autodiscover_tasks()

