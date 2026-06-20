# PRD — Traiettoria del viaggio: LineString, GeoJSON on-demand e mappa

> Versione 1 — 2026-06-20.
> Riguarda il backend Django/PostGIS (`back-end/ninja`) e l'app Flutter
> (`mobile/diary`). Non tocca il flusso HAR / sensor window, che resta congelato
> (vedi REPORT_STRATEGIA_INGESTION_ASINCRONA.md, D9).

---

## 1. Contesto

Oggi il sistema salva la traiettoria di un viaggio come righe singole nella
tabella `GpsPoint` (`point = PointField(geography=True)`, srid 4326), una riga per
campione GPS, legate al `Trip` via FK. Il `Trip` viene materializzato dal task
Celery `process_trip_ingestion` (`back-end/ninja/mobility/tasks.py`) dentro una
`transaction.atomic()`; i punti sono inseriti da `_materialize_gps`.

Limiti attuali:

- **Nessun endpoint restituisce la traiettoria.** Gli unici endpoint di lettura
  (`/trips/{id}/diary`) servono dati HAR (segmenti/luoghi), oggi vuoti nel flusso
  nuovo. La scia GPS è salvata ma non interrogabile dall'esterno.
- **La distanza del viaggio non esiste** nel flusso attuale: viene calcolata solo
  nella pipeline HAR legacy, in Python (haversine), per-segmento, mai per-viaggio.
- **PostGIS è usato solo come storage**: nessuna query spaziale, nessuna
  LineString, nessun indice spaziale (`GpsPoint` ha solo un btree su
  `(trip, timestamp)`).

## 2. Problema

Per mostrare un viaggio su una mappa e i suoi chilometri totali manca:

1. una rappresentazione efficiente della traiettoria a livello di viaggio;
2. un endpoint che restituisca la traiettoria in un formato pronto per una mappa;
3. l'integrazione front-end che la disegni.

## 3. Obiettivi

- Tenere **entrambe** le rappresentazioni della traiettoria:
  1. i `GpsPoint` come oggi (sorgente di verità, con timestamp/speed/accuracy
     per punto);
  2. una **LineString** derivata, salvata sul `Trip`, come scorciatoia veloce per
     mappa e distanza.
- Esporre un endpoint **GET `/trips/{id}/track`** che restituisce il **GeoJSON**
  della traiettoria + la **distanza totale**, generati con **query PostGIS** che
  sfruttano la LineString salvata.
- Integrare il front-end Flutter perché **chiami l'endpoint e disegni la
  traiettoria su una mappa**.

## 4. Non obiettivi

- Non si tocca HAR, sensor window, segmenti, luoghi (congelati).
- Non si persiste mai il GeoJSON: è un formato di trasporto, generato on-demand.
- Niente query spaziali avanzate (vicinanza/geofencing) in questa iterazione: la
  LineString predispone, ma non è in scope qui.
- Niente background/offline maps; tile server standard.

## 5. Decisioni di design

### D1 — Si tengono punti + LineString (denormalizzazione controllata)
Il rischio classico della duplicazione è il disallineamento, ma un viaggio è
**immutabile** dopo la materializzazione (`PROCESSED`): la sorgente non cambia
più, quindi la copia derivata non può divergere. Condizioni vincolanti:
- la LineString è **derivata dai `GpsPoint`**, non ricevuta dal client;
- è costruita nella **stessa `transaction.atomic()`** della materializzazione;
- la sua generazione è **idempotente** (ricalcolo deterministico, sovrascrive).

### D2 — GeoJSON generato da PostGIS, non in Python
L'endpoint usa `ST_AsGeoJSON`/`ST_Length` (via funzioni di DB GeoDjango) sulla
colonna `path`. Una sola query legge la LineString già pronta e ne ricava GeoJSON
+ distanza. Senza la colonna, lo stesso GeoJSON richiederebbe di aggregare e
ordinare i singoli punti a ogni richiesta.

### D3 — Distanza via PostGIS (mai haversine in Python)
`ST_Length(path::geography)` in metri. Opzionale: persistere `Trip.distance_meters`
alla materializzazione per evitare di ricalcolare a ogni richiesta (lecito perché
`path` è immutabile).

### D4 — On-demand per il GeoJSON, precalcolo per la geometria
Il GeoJSON non si salva (varia col formato di output, è economico da rigenerare).
La LineString sì: è il precalcolo geometrico che si guadagna il posto perché
abilita letture veloci e future query spaziali.

### D5 — Mappa front-end open-source
`flutter_map` + `latlong2` (tile OpenStreetMap), nessuna API key / billing —
adatto a un progetto universitario. Google Maps resta alternativa se servisse.

## 6. Requisiti funzionali

### RF1 — Modello `Trip` (back-end/ninja/mobility/models.py)
- Aggiungere `path = models.LineStringField(geography=True, srid=4326, null=True, blank=True)`
  (nullable: un viaggio con 0/1 punto non ha linea valida).
- (Opzionale) `distance_meters = models.FloatField(null=True, blank=True)`.
- Indice spaziale GiST su `path`
  (`from django.contrib.gis.db.models.indexes import GistIndex` → `GistIndex(fields=["path"])`).

### RF2 — Migrazione
- `makemigrations mobility` per `path` (+ `distance_meters` se aggiunto) e indice
  GiST. Nessun data-migration: i viaggi pre-esistenti avranno `path = NULL` finché
  non rigenerati (vedi RF6).

### RF3 — Materializzazione (tasks.py → `process_trip_ingestion`)
- Dopo `_materialize_gps` e `_materialize_transitions`, nella **stessa**
  `transaction.atomic()`, costruire e salvare la LineString.
- Helper `_build_trip_path(trip) -> int`:
  1. rilegge i `GpsPoint` del trip **ordinati per `timestamp`** (ordine critico:
     `bulk_create` non garantisce ordine; vertici fuori sequenza = zig-zag);
  2. estrae le coordinate `(lon, lat)` in quell'ordine;
  3. se i punti distinti sono `< 2` → `trip.path = None`,
     `distance_meters = 0/None`, ritorna;
  4. altrimenti `from django.contrib.gis.geos import LineString` →
     `LineString(coords, srid=4326)` assegnato a `trip.path`;
  5. se presente `distance_meters`, calcolarlo via PostGIS (NON in Python), es.
     `Trip.objects.filter(pk=trip.pk).annotate(d=Length("path")).update(...)` o
     update annotato — in **metri** (geography);
  6. `trip.save(update_fields=["path", "distance_meters", "updated_at"])`.
- Idempotente per natura (rilegge i punti e sovrascrive): sicuro su retry
  almeno-once di Celery.

### RF4 — Schema di output (schemas.py)
```python
class TrackOut(Schema):
    trip_id: int
    point_count: int
    distance_meters: float          # 0 se traiettoria assente
    geojson: dict | None            # GeoJSON LineString, None se < 2 punti
    bbox: list[float] | None = None # opzionale [minx, miny, maxx, maxy]
```

### RF5 — Endpoint GeoJSON on-demand (api.py)
- `GET /trips/{trip_id}/track`, auth `mobile_bearer_auth`, **filtrato per utente**
  (`user_id=request.auth.user_id`): non basta l'id numerico.
- GeoJSON e distanza prodotti da **una sola query PostGIS** sulla colonna `path`:
  ```python
  from django.contrib.gis.db.models.functions import AsGeoJSON, Length

  row = (
      Trip.objects.filter(pk=trip_id, user_id=request.auth.user_id)
      .annotate(
          track_geojson=AsGeoJSON("path"),   # ST_AsGeoJSON(path)
          dist=Length("path"),               # ST_Length(path::geography) -> metri
      )
      .values("id", "track_geojson", "dist")
      .first()
  )
  ```
  - NON usare `trip.path.geojson` (serializza lato Python).
  - `row is None` → 404.
  - trip esistente ma `path` NULL → `track_geojson` NULL → rispondere
    `geojson=None`, `distance_meters=0`.
  - GeoJSON nella risposta via `json.loads(row["track_geojson"])`.
  - distanza da `row["dist"].m` (o dal campo `Trip.distance_meters` se persistito).
  - `point_count` = conteggio `GpsPoint` del trip.
- Coordinate GeoJSON in ordine **[longitude, latitude]** (verificato nei test).

### RF6 — (Opzionale) Management command di backfill
- `python manage.py backfill_trip_paths`: itera sui `Trip` con `path__isnull=True`
  e popola `path`/`distance_meters` riusando `_build_trip_path`. Separato dalla
  migration.

### RF7 — Front-end Flutter (mobile/diary)
Stack: `flutter_bloc` (cubit) + `provider`, `drift`, layer rete in `lib/network/`
(service + dto + interceptor), API dominio in `lib/features/`. Nessuna libreria
mappa presente: va aggiunta. Seguire i pattern esistenti
(`lib/network/service`, `lib/network/dto`, `trip_ingestion_api.dart`, cubit in
`lib/state_management/cubits`, pagine in `lib/ui/pages`, rotte in `lib/routers`).

- **RF7.1 Dipendenza mappa**: aggiungere `flutter_map` + `latlong2` a
  `pubspec.yaml`, tile OpenStreetMap; `flutter pub get`.
- **RF7.2 DTO + parsing**: `TripTrackDto` in `lib/network/dto`
  (`tripId`, `pointCount`, `distanceMeters`, `geojson` nullable). Mapper GeoJSON
  LineString → `List<LatLng>`: attenzione all'ordine `[lon, lat]` →
  `LatLng(coord[1], coord[0])`; `geojson == null` → lista vuota.
- **RF7.3 Service**: metodo nel layer di rete (coerente con
  `trip_ingestion_api.dart` e con l'interceptor che inietta il Bearer token) per
  `GET /api/.../trips/{tripId}/track` → `TripTrackDto`. Riusare base URL e auth
  esistenti, niente hardcoding.
- **RF7.4 Stato**: `TripTrackCubit` con stati loading / loaded(points,
  distanceMeters) / empty / error.
- **RF7.5 UI**: pagina `trip_map_page.dart` in `lib/ui/pages` che riceve un
  `tripId`, mostra `FlutterMap` con tile OSM, disegna la traiettoria come
  `PolylineLayer`, fa fit dei bound, mostra la distanza (km/m) in overlay, gestisce
  spinner / "traiettoria non disponibile" (empty) / errore con retry. Navigazione
  verso la pagina dal punto in cui si apre un viaggio, coerente con `lib/routers`.

## 7. Requisiti non funzionali

- **Sicurezza**: ogni accesso filtrato per utente; trip altrui → 404 con id
  numerico. Endpoint sotto Bearer token come il resto dell'API.
- **Performance**: a ~1000 utenti il sistema è volume-bound; il GeoJSON on-demand
  via PostGIS è in ordine dei millisecondi. La LineString riduce la lettura
  dell'intero viaggio a una riga.
- **Coerenza dati**: nessun rischio di disallineamento (sorgente immutabile +
  derivazione in stessa transazione).
- **Compatibilità**: non altera il flusso di ingestion né HAR; campo `path`
  nullable, retro-compatibile.

## 8. Test

### Back-end
- materializzazione con ≥2 punti → `path` valorizzato, `distance_meters > 0`,
  ordine vertici = ordine temporale;
- 0/1 punto → `path` resta `None`, nessun errore;
- idempotenza: rieseguire `process_trip_ingestion` non sporca/duplica la linea;
- endpoint `/trips/{id}/track`: proprietario → 200 GeoJSON `LineString` valido +
  `distance_meters` coerente; altro utente → 404; trip senza path → 200 con
  `geojson=None`;
- GeoJSON con coordinate in ordine `[lon, lat]`.

### Front-end
- parsing GeoJSON → `List<LatLng>` (ordine lon/lat e caso null);
- cubit con service mockato (loaded / empty / error).

## 9. Vincoli di stile

- Convenzioni del codice esistente (commenti italiani sintetici, `update_fields`
  espliciti, filtro per utente su ogni endpoint).
- Nessun calcolo geografico in Python: la distanza la fa PostGIS.

## 10. Rollout

1. Modello + migration (`path`, indice GiST, opz. `distance_meters`).
2. `_build_trip_path` nel task + test.
3. Schema + endpoint `/trips/{id}/track` + test.
4. (Opz.) backfill dei viaggi esistenti.
5. Front-end: dipendenza mappa → DTO/parsing → service → cubit → pagina → rotta.
6. Verifica end-to-end: viaggio reale → traiettoria visibile su mappa + km.

## 11. Rischi e mitigazioni

| Rischio | Mitigazione |
|---|---|
| Vertici fuori ordine → traiettoria a zig-zag | LineString costruita da punti ordinati per `timestamp` (RF3) |
| Coordinate invertite → percorso "in mezzo al mare" | Ordine `[lon, lat]` esplicitato lato DB e lato Flutter, coperto da test |
| Disallineamento punti/LineString | Sorgente immutabile + derivazione nella stessa transazione |
| GeoJSON serializzato in Python (lento, non sfrutta la LineString) | Uso obbligatorio di `ST_AsGeoJSON`/`ST_Length` via DB |
| Viaggi pre-esistenti senza `path` | `path` nullable + management command di backfill (RF6) |

## 12. Criteri di accettazione

- Aprendo un viaggio materializzato nell'app, la sua traiettoria appare disegnata
  correttamente su mappa e i km totali sono mostrati.
- Il GeoJSON è prodotto da una query PostGIS sulla colonna `path` (verificabile nel
  codice dell'endpoint), non da serializzazione Python.
- I `GpsPoint` restano intatti; il GeoJSON non è mai persistito.
- Un viaggio di un altro utente non è accessibile via id numerico (404).
