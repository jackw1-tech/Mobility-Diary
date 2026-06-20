#!/usr/bin/env bash
# Crea le 3 issue verticali della feature "traiettoria su mappa".
# Prerequisiti:
#   1) brew install gh
#   2) gh auth login           (account con accesso a jackw1-tech/Mobility-Diary)
# Esecuzione:
#   bash docs/create_issues_traiettoria.sh
set -euo pipefail

REPO="jackw1-tech/Mobility-Diary"

# Label (ignora l'errore se gia' esistono)
gh label create backend  --repo "$REPO" --color 1d76db --description "Back-end Django/PostGIS" 2>/dev/null || true
gh label create mobile   --repo "$REPO" --color 5319e7 --description "App Flutter mobile/diary" 2>/dev/null || true
gh label create feature  --repo "$REPO" --color 0e8a16 --description "Nuova funzionalita'" 2>/dev/null || true
gh label create chore    --repo "$REPO" --color cccccc --description "Manutenzione" 2>/dev/null || true

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Backend: traiettoria del viaggio interrogabile (GeoJSON + distanza via PostGIS)" \
  --label feature --label backend \
  --body "$(cat <<'EOF'
Slice 1/3 della feature "traiettoria su mappa" (vedi PRD_TRAIETTORIA_MAPPA.md, RF1-RF5).

## Valore
L'API espone la traiettoria di un viaggio come GeoJSON + distanza totale, pronti per una mappa. Dimostrabile via curl, senza front-end.

## Scope
- [ ] `Trip.path = LineStringField(geography=True, srid=4326, null=True, blank=True)`
- [ ] (Opzionale) `Trip.distance_meters = FloatField(null=True, blank=True)`
- [ ] Indice `GistIndex(fields=["path"])`
- [ ] Migration mobility (campi + indice, nessun data-migration)
- [ ] `_build_trip_path(trip)`: GpsPoint ordinati per timestamp, (lon,lat), <2 punti -> path None, altrimenti LineString(coords, srid=4326); distanza via PostGIS (Length), mai Python
- [ ] Chiamata in process_trip_ingestion dentro la stessa transaction.atomic(), dopo i punti; idempotente
- [ ] Schema `TrackOut` (trip_id, point_count, distance_meters, geojson: dict|None, bbox opzionale)
- [ ] `GET /trips/{trip_id}/track`, auth mobile_bearer_auth, filtrato per utente, GeoJSON+distanza da UNA query PostGIS (AsGeoJSON("path") + Length("path")); NON usare trip.path.geojson
- [ ] Test: >=2 punti (path+distanza+ordine), 0/1 punto (path None), idempotenza, endpoint 200/404/empty, GeoJSON [lon,lat]

## Fuori scope
HAR/sensor window; persistenza GeoJSON; query di vicinanza; front-end.

## Criteri di accettazione
- GET /trips/{id}/track su viaggio con punti -> GeoJSON LineString valido + distance_meters coerente
- Viaggio di altro utente -> 404
- Viaggio con <2 punti -> 200 con geojson null, distance_meters 0
- GeoJSON prodotto dalla query PostGIS sulla colonna path (non Python)
- GpsPoint intatti; GeoJSON non persistito
EOF
)"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Frontend: disegnare la traiettoria del viaggio su mappa" \
  --label feature --label mobile \
  --body "$(cat <<'EOF'
Slice 2/3 della feature "traiettoria su mappa" (vedi PRD_TRAIETTORIA_MAPPA.md, RF7). Dipende da: issue backend (slice 1).

## Valore
L'utente apre un viaggio materializzato e ne vede la traiettoria su mappa, con i km totali.

## Scope
- [ ] Dipendenze flutter_map + latlong2 in pubspec.yaml (tile OSM); flutter pub get
- [ ] TripTrackDto in lib/network/dto (tripId, pointCount, distanceMeters, geojson nullable)
- [ ] Mapper GeoJSON LineString -> List<LatLng>: ordine [lon,lat] -> LatLng(coord[1], coord[0]); geojson null -> lista vuota
- [ ] Service per GET /api/.../trips/{tripId}/track -> TripTrackDto, coerente con trip_ingestion_api.dart e interceptor Bearer; riusa base URL/auth (no hardcoding)
- [ ] TripTrackCubit: loading / loaded(points, distanceMeters) / empty / error
- [ ] Pagina trip_map_page.dart: FlutterMap + tile OSM, PolylineLayer, fit bound, distanza overlay, stati spinner/empty/errore+retry
- [ ] Navigazione dalla apertura di un viaggio (lib/routers)
- [ ] Test: parsing GeoJSON -> List<LatLng> (ordine lon/lat + null); cubit mockato (loaded/empty/error)

## Fuori scope
Modifiche backend; query spaziali; offline/background maps.

## Criteri di accettazione
- Viaggio con traiettoria -> polyline corretta + km totali
- Viaggio senza traiettoria -> "traiettoria non disponibile", nessun crash
- Errore di rete -> stato errore con retry
- Nessuna inversione lat/lon
EOF
)"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Backfill path/distance per i viaggi esistenti (opzionale)" \
  --label chore --label backend \
  --body "$(cat <<'EOF'
Slice 3/3 (opzionale) della feature "traiettoria su mappa" (vedi PRD_TRAIETTORIA_MAPPA.md, RF6). Dipende da: issue backend (slice 1).

## Valore
I viaggi materializzati prima dello slice 1 (path NULL) ottengono la traiettoria, cosi' la mappa funziona anche su di loro.

## Scope
- [ ] Management command backfill_trip_paths: itera sui Trip con path__isnull=True, popola path/distance_meters riusando _build_trip_path
- [ ] Idempotente e rieseguibile; log dei trip aggiornati

## Criteri di accettazione
- Dopo l'esecuzione i viaggi pre-esistenti con >=2 punti hanno path valorizzato e GET /trips/{id}/track restituisce la traiettoria
- Viaggi con <2 punti restano con path NULL senza errori
EOF
)"

echo "Fatto. Issue create su $REPO."
