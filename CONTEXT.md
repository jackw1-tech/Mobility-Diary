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

**Evidenza Sensoriale Grezza**:
The sensor-window evidence collected during a Viaggio and used as input for activity recognition, before it becomes readable diary information.
_Avoid_: Activity label, diary segment, model result

**Arricchimento del Viaggio**:
Additional semantic interpretation added after a Viaggio already exists.
_Avoid_: Journey creation, sync completion, processing, processed

**Diario della Mobilità**:
The user-facing reconstruction of a day or mobility episode as readable time intervals, places, movements, activity labels, and statistics.
_Avoid_: Raw trace, upload result, model output

**Dettaglio Viaggio**:
The mobile screen for one Viaggio where the user can inspect its map,
mobility-segment timeline, and trip statistics.
_Avoid_: Map page, trip debug page, sync result

**Piattaforma Web**:
The browser-based surface for inspecting the Diario della Mobilita across one or
more Viaggi through maps, timelines, filters, and personal statistics.
_Avoid_: Sito, frontend generico, pannello admin

**Operatore Web**:
A trusted staff user allowed to access the Piattaforma Web and inspect mobility
diary information for demonstration and analysis.
_Avoid_: Utente mobile, partecipante, admin generico

**Vista Staff Globale**:
The web-dashboard view where an Operatore Web can inspect Viaggi across all
users instead of only their own mobility diary.
_Avoid_: Vista personale, diario utente, query mobile

**Proprietario del Viaggio**:
The user account whose mobile app recorded a Viaggio and whose identity may be
shown minimally in the Vista Staff Globale for filtering and attribution.
_Avoid_: Operatore Web, paziente, soggetto amministrato

**Segmento di Mobilità**:
A time-bounded entry in the mobility diary representing either a stop or a movement, enriched with an activity label when available.
_Avoid_: GPS chunk, raw window, prediction row

**Timeline del Viaggio**:
The ordered mobile presentation of the Segmenti di Mobilita for one Viaggio,
showing time interval, duration, activity label, movement distance, and stop
place information when available.
_Avoid_: Raw event list, sensor timeline, backend status log

**Luogo Significativo**:
A place inferred from a meaningful dwell interval and used to make the mobility diary readable without exposing every raw coordinate.
_Avoid_: GPS point, POI, marker

**Etichetta di Attività**:
The recognized or estimated mobility mode assigned to a mobility segment, such as idle, walking, running, biking, or moving vehicle.
_Avoid_: Classifier output, HAR string, transport type

**Vista Privacy-Aware**:
A shareable representation of the mobility diary where location detail is intentionally reduced, perturbed, or aggregated.
_Avoid_: Export, anonymized copy, public trace

**Preferenza Privacy**:
The user's current global choice for how precise or reduced their mobility data
should appear in privacy-aware views, such as precise, approximate, or
aggregated. The preference can change over time and is stored independently
from individual Viaggi.
_Avoid_: Privacy export, trip privacy snapshot, raw-data deletion

**Livello Privacy**:
One of the supported values for the Preferenza Privacy: precise, approximate,
or aggregated.
_Avoid_: Privacy score, privacy mode, visibility

**Viaggio Sincronizzato**:
A Viaggio whose Core Ingestion has completed and can appear in the diary, regardless of whether raw sensor evidence has finished uploading.
_Avoid_: Fully uploaded journey, HAR-complete journey

**Traiettoria del Viaggio**:
The map-ready route shape for a Viaggio, available only when Core Ingestion
contains enough valid GPS evidence. A Viaggio can be synchronized without having
an available trajectory.
_Avoid_: Raw track, HAR route, sync completion

**Statistiche del Viaggio**:
Aggregated user-facing measures derived from the Segmenti di Mobilita of one
Viaggio, such as time by activity, stopped time, movement time, distance, and
visited significant places.
_Avoid_: Stored metrics, classifier report, backend analytics
