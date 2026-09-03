"""Le cache pickle devono degradare a cache miss, mai far fallire il chiamante.

Regressione: dopo la rinomina ingestion -> upload il modulo di
`RawSensorLoadResult` e' cambiato, quindi le entry Redis scritte prima
sollevavano ModuleNotFoundError durante l'unpickle. Non essendo intercettata,
l'eccezione sarebbe risalita fino al task Celery che legge la cache.
"""

import pickle

import pytest

from mobility import raw_sensor_windows_cache, replay_windows_cache


class _FakeRedis:
    def __init__(self, payload: bytes):
        self._payload = payload

    def get(self, _key):
        return self._payload


# Pickle di una classe il cui modulo non esiste piu': e' esattamente la forma
# di una entry scritta prima di una rinomina di package.
MISSING_MODULE_PICKLE = (
    b"\x80\x04\x95:\x00\x00\x00\x00\x00\x00\x00"
    b"\x8c$mobility.ingestion.raw_sensor_loader\x94"
    b"\x8c\x13RawSensorLoadResult\x94\x93\x94)\x81\x94."
)


def test_the_stale_pickle_really_raises_an_uncatchable_import_error():
    with pytest.raises(ModuleNotFoundError):
        pickle.loads(MISSING_MODULE_PICKLE)


@pytest.mark.parametrize(
    "module, reader",
    [
        (raw_sensor_windows_cache, "get_cached_raw_sensor_windows"),
        (replay_windows_cache, "get_cached_windows"),
    ],
)
def test_a_cache_entry_from_a_renamed_module_is_a_miss(module, reader, monkeypatch):
    monkeypatch.setattr(
        module, "_get_redis_client", lambda: _FakeRedis(MISSING_MODULE_PICKLE)
    )

    assert getattr(module, reader)(1) is None


@pytest.mark.parametrize(
    "module, reader",
    [
        (raw_sensor_windows_cache, "get_cached_raw_sensor_windows"),
        (replay_windows_cache, "get_cached_windows"),
    ],
)
def test_a_corrupted_cache_entry_is_a_miss(module, reader, monkeypatch):
    monkeypatch.setattr(
        module, "_get_redis_client", lambda: _FakeRedis(b"non-un-pickle")
    )

    assert getattr(module, reader)(1) is None
