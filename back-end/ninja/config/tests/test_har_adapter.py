from types import SimpleNamespace

import numpy as np
import pytest

from mobility.ml import har_adapter


class _Classifier:
    def __init__(self, prediction):
        self.prediction = prediction

    def predict(self, _matrices):
        return self.prediction


def _install_classifier(monkeypatch, prediction):
    bundle = har_adapter.HarModelBundle(
        classifier=_Classifier(prediction),
        sequence_length=128,
        model_path="shl_har_fused.keras",
        inference_path="inference.py",
    )
    monkeypatch.setattr(har_adapter, "_MODEL_BUNDLE", bundle)


def test_fused_har_prediction_uses_the_model_class_contract(monkeypatch):
    _install_classifier(
        monkeypatch,
        {
            "labels": np.array([4]),
            "probs": np.array([[0.01, 0.01, 0.01, 0.02, 0.95]]),
            "classes": [
                "IDLE",
                "WALKING",
                "RUNNING",
                "BIKING",
                "MOVING_VEHICLE",
            ],
        },
    )

    label, confidence = har_adapter.predict_window_label(
        np.zeros((500, 6), dtype=np.float32)
    )

    assert label == "MOVING_VEHICLE"
    assert confidence == pytest.approx(0.95)


def test_fused_har_prediction_rejects_unknown_model_classes(monkeypatch):
    _install_classifier(
        monkeypatch,
        {
            "labels": np.array([0]),
            "probs": np.array([[1.0]]),
            "classes": ["LEGACY_DRIVING"],
        },
    )

    with pytest.raises(ValueError, match="classi non supportate"):
        har_adapter.predict_window_label(np.zeros((500, 6), dtype=np.float32))


@pytest.mark.django_db
def test_final_har_task_loads_windows_through_the_current_loader(monkeypatch):
    from mobility import tasks

    saved = []
    trip = SimpleNamespace(id=17, user_id=23)
    upload = SimpleNamespace(
        id=11,
        trip=trip,
        raw_status=None,
        error_message="",
        completed_at=None,
        failed_at=None,
        save=lambda **kwargs: saved.append(("upload", kwargs)),
    )
    job = SimpleNamespace(
        id=13,
        trip=trip,
        status=None,
        result={},
        error="",
        save=lambda **kwargs: saved.append(("job", kwargs)),
    )
    windows = [SimpleNamespace(matrix=np.zeros((500, 6), dtype=np.float32))]
    loaded = []

    monkeypatch.setattr(
        tasks.upload_repository,
        "locked_trip_upload_by_id",
        lambda _upload_id: upload,
    )
    monkeypatch.setattr(
        tasks.har_jobs_repository,
        "locked_har_job_for_processing",
        lambda _job_id: job,
    )
    monkeypatch.setattr(
        tasks,
        "load_raw_sensor_windows",
        lambda current_upload: loaded.append(current_upload) or windows,
    )
    monkeypatch.setattr(
        tasks,
        "run_pipeline",
        lambda current_trip, *, sensor_windows: {
            "trip_id": current_trip.id,
            "window_count": len(sensor_windows),
        },
    )
    monkeypatch.setattr(
        tasks.persist_trip_raw_sensor_readings,
        "delay",
        lambda *_args: None,
    )
    monkeypatch.setattr(tasks, "_request_place_mining", lambda _user_id: False)

    result = tasks.process_trip_har_final.run(job.id, upload.id)

    assert loaded == [upload]
    assert result["window_count"] == 1
    assert saved
