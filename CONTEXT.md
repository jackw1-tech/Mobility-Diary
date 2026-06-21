# Mobility Diary

This context describes the language of the mobility diary domain: how a mobile
viaggio becomes a reliable diary entry and later receives sensor-based enrichment.

## Language

**Viaggio**:
A mobility episode recorded by the mobile app and intended to appear in the user's diary.
_Avoid_: Corsa, trip, journey

**Ingestione del Viaggio**:
The lifecycle that delivers all data for one Viaggio to the backend while allowing different phases to complete at different times.
_Avoid_: Multiple ingestions, upload pratica, sync blob

**Core Ingestion**:
The minimum ingestion phase required for a Viaggio to exist in the diary; it can complete with at least one core evidence source.
_Avoid_: X processing, basic sync, partial upload

**Raw Sensor Ingestion**:
The later ingestion phase that carries raw sensor evidence used to enrich a Viaggio.
_Avoid_: Y processing, HAR upload, sensor sync

**Arricchimento del Viaggio**:
Additional semantic interpretation added after a Viaggio already exists.
_Avoid_: Journey creation, sync completion

**Viaggio Sincronizzato**:
A Viaggio whose Core Ingestion has completed and can appear in the diary, regardless of whether raw sensor evidence has finished uploading.
_Avoid_: Fully uploaded journey, HAR-complete journey

**Traiettoria del Viaggio**:
The map-ready route shape for a Viaggio, available only when Core Ingestion
contains enough valid GPS evidence. A Viaggio can be synchronized without having
an available trajectory.
_Avoid_: Raw track, HAR route, sync completion
