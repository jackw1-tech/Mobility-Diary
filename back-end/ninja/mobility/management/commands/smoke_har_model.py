from __future__ import annotations

from types import SimpleNamespace

import numpy as np
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from mobility.ml.har_adapter import (
    HarModelUnavailable,
    predict_activity_windows,
    reset_model_cache,
)


class Command(BaseCommand):
    help = "Verifica che il runtime riesca a caricare i modelli HAR e predire una finestra sintetica."

    def add_arguments(self, parser):
        parser.add_argument(
            "--windows",
            type=int,
            default=1,
            help="Numero di finestre sintetiche 500x6 da predire.",
        )

    def handle(self, *args, **options):
        window_count = options["windows"]
        if window_count < 1:
            raise CommandError("--windows deve essere almeno 1")

        reset_model_cache()
        matrix = np.zeros(
            (settings.HAR_WINDOW_SAMPLE_COUNT, 6),
            dtype=np.float32,
        )
        windows = [SimpleNamespace(matrix=matrix) for _ in range(window_count)]

        self.stdout.write(f"CNN model: {settings.HAR_CNN_MODEL_PATH}")
        self.stdout.write(f"GRU model: {settings.HAR_GRU_MODEL_PATH}")

        try:
            result = predict_activity_windows(windows)
        except HarModelUnavailable as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(self.style.SUCCESS("HAR model smoke test OK"))
        self.stdout.write(f"windows: {len(result.labels)}")
        self.stdout.write(f"labels: {result.summary['label_distribution']}")
        self.stdout.write(f"confidence: {result.summary['confidence']}")
