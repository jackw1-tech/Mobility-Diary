# Issue verticali — Traiettoria del viaggio su mappa

Derivate da `PRD_TRAIETTORIA_MAPPA.md`. Tre slice verticali, ognuna spedibile e
dimostrabile da sola. Dipendenze: #2 e #3 richiedono #1.

---

## Issue 1 — Backend: traiettoria del viaggio interrogabile (GeoJSON + distanza via PostGIS)

**Tipo:** feature · **Area:** back-end · **Dipendenze:** nessuna

### Valore
Dopo questa issue l'API espone la traiettoria di un viaggio come GeoJSON e la sua
distanza totale, pronti per essere disegnati su una mappa. Dimostrabile via `curl`
senza front-end.

### Scope
- [ ] `Trip.path = LineStringField(geography=True, srid=4326, null=True, blank=True)`
      (models.py).
- [ ] (Opzionale) `Trip.distance_meters = FloatField(null=True, blank=True)`.
- [ ] Indice spaziale `GistIndex(fields=["path"])` su `Trip`.
- [ ] Migration `mobility` per i campi e l'indice (nessun data-migration).
- [ ] Helper `_build_trip_path(trip)` in tasks.py:
      rilegge i `GpsPoint` **ordinati per `timestamp`**, estrae `(lon, lat)`,
      se `< 2` punti lascia `path = None`, altrimenti costruisce
      `LineString(coords, srid=4326)`; distanza via PostGIS (`Length`), mai Python.
- [ ] Chiamata a `_build_trip_path` dentro la stessa `transaction.atomic()` di
      `process_trip_ingestion`, dopo i punti; idempotente su retry.
- [ ] Schema `TrackOut` (schemas.py): `trip_id`, `point_count`, `distance_meters`,
      `geojson: dict | None`, `bbox` opzionale.
- [ ] Endpoint `GET /trips/{trip_id}/track` (api.py), auth `mobile_bearer_auth`,
      filtrato per utente, con GeoJSON+distanza da **una sola query PostGIS**
      (`AsGeoJSON("path")` + `Length("path")`). NON usare `trip.path.geojson`.
- [ ] Test: ≥2 punti → path+distanza+ordine corretto; 0/1 punto → path None;
      idempotenza task; endpoint 200/404/empty; GeoJSON in ordine `[lon, lat]`.

### Fuori scope
HAR/sensor window; persistenza del GeoJSON; query di vicinanza; front-end.

### Criteri di accettazione
- `GET /trips/{id}/track` su un viaggio con punti restituisce un GeoJSON
  `LineString` valido (coordinate `[lon, lat]`) + `distance_meters` coerente.
- Viaggio di un altro utente → 404 con id numerico.
- Viaggio con `< 2` punti → 200 con `geojson: null`, `distance_meters: 0`.
- Il GeoJSON è prodotto dalla query PostGIS sulla colonna `path` (verificabile nel
  codice), non da serializzazione Python.
- I `GpsPoint` restano intatti; il GeoJSON non è persistito.

Rif. PRD: RF1–RF5, D1–D4.

---

## Issue 2 — Frontend: disegnare la traiettoria del viaggio su mappa

**Tipo:** feature · **Area:** mobile (Flutter `mobile/diary`) · **Dipendenze:** #1

### Valore
L'utente apre un viaggio materializzato e ne vede la traiettoria disegnata su una
mappa, con i chilometri totali.

### Scope
- [ ] Dipendenze `flutter_map` + `latlong2` in `pubspec.yaml` (tile OSM);
      `flutter pub get`.
- [ ] `TripTrackDto` in `lib/network/dto` (`tripId`, `pointCount`,
      `distanceMeters`, `geojson` nullable).
- [ ] Mapper GeoJSON LineString → `List<LatLng>`: ordine `[lon, lat]` →
      `LatLng(coord[1], coord[0])`; `geojson == null` → lista vuota.
- [ ] Metodo service per `GET /api/.../trips/{tripId}/track` → `TripTrackDto`,
      coerente con `trip_ingestion_api.dart` e con l'interceptor Bearer; riusa base
      URL e auth esistenti (niente hardcoding).
- [ ] `TripTrackCubit` (`lib/state_management/cubits`): loading / loaded(points,
      distanceMeters) / empty / error.
- [ ] Pagina `trip_map_page.dart` (`lib/ui/pages`): `FlutterMap` + tile OSM,
      `PolylineLayer` dalla traiettoria, fit dei bound, distanza (km/m) in overlay,
      stati spinner / "traiettoria non disponibile" / errore con retry.
- [ ] Navigazione verso la pagina dal punto in cui si apre un viaggio
      (`lib/routers`).
- [ ] Test: parsing GeoJSON → `List<LatLng>` (ordine lon/lat + caso null);
      cubit con service mockato (loaded/empty/error).

### Fuori scope
Modifiche backend; query spaziali; offline/background maps.

### Criteri di accettazione
- Aprendo un viaggio con traiettoria, la mappa mostra la polyline corretta e i km
  totali.
- Viaggio senza traiettoria → messaggio "traiettoria non disponibile", nessun
  crash.
- Errore di rete → stato d'errore con retry.
- Coordinate corrette (nessuna inversione lat/lon).

Rif. PRD: RF7, D5.

---

## Issue 3 (opzionale) — Backfill path/distance per i viaggi esistenti

**Tipo:** chore · **Area:** back-end · **Dipendenze:** #1

### Valore
I viaggi materializzati prima di #1 (con `path = NULL`) ottengono la traiettoria,
così la mappa funziona anche su di loro.

### Scope
- [ ] Management command `backfill_trip_paths`: itera sui `Trip` con
      `path__isnull=True`, popola `path`/`distance_meters` riusando
      `_build_trip_path`.
- [ ] Idempotente e rieseguibile; log del numero di trip aggiornati.

### Criteri di accettazione
- Dopo l'esecuzione, i viaggi pre-esistenti con ≥2 punti hanno `path` valorizzato
  e `GET /trips/{id}/track` restituisce la traiettoria.
- I viaggi con `< 2` punti restano con `path = NULL` senza errori.

Rif. PRD: RF6.
