# Test di Mobility Diary

La suite verifica i comportamenti attraverso quattro seam pubblici:

- API HTTP Django Ninja, con PostgreSQL/PostGIS, TimescaleDB, Redis e MinIO reali;
- database, repository e Cubit/presenter pubblici del client Flutter;
- servizi e componenti pubblici della Piattaforma Web;
- percorso browser dello staff in Chromium con Playwright.

I test non fanno asserzioni su metodi privati e non sostituiscono collaboratori
interni con mock. Vengono controllati solo i confini esterni non deterministici,
come rete, sensori del dispositivo e modello ML.

## Esecuzione completa

Prerequisiti:

- Docker Desktop;
- Python 3.12 e il virtualenv `back-end/.venv` configurato;
- Flutter disponibile nel `PATH`;
- Node.js 22 o successivo e dipendenze web installate.

Installare una volta il browser Playwright:

```bash
cd web
npx playwright install chromium
```

Poi, dalla root:

```bash
make test
```

Se Flutter non è nel `PATH`, il percorso può essere passato senza modificare
il repository:

```bash
make FLUTTER=/percorso/flutter/bin/flutter test
```

## Suite separate

Backend, incluso upload presigned su MinIO:

```bash
make test-backend
```

Flutter, incluso SQLite in memoria e coda di sincronizzazione persistente:

```bash
make test-mobile
```

Web unit/component e build di produzione:

```bash
make test-web
```

Browser end-to-end:

```bash
make test-web-e2e
```

Smoke test del modello HAR reale, separato dalla suite deterministica perché
carica gli artefatti TensorFlow completi:

```bash
make test-har-model
```

## Cosa viene coperto

Il backend verifica registrazione, login/logout, rotazione token staff,
preferenze privacy, ownership, singolo Viaggio attivo, heartbeat, abbandono,
Core Ingestion, idempotenza, tracce PostGIS, parti raw, checksum MinIO,
accodamento HAR, diario, analytics, luoghi significativi, note, cancellazione e
dashboard staff.

Il mobile verifica FSM, freshness dei segnali, background GPS-only, mapping del
contratto backend, persistenza UTC, filtraggio dell'evidenza GPS, SyncJob
idempotenti, pulizia dopo successo, conservazione offline, retry e presenter UI.

Il web verifica refresh token concorrente, filtri e riepiloghi, login
accessibile, stati di caricamento/errore, lista proprietari e un percorso
completo nel browser.

GPS, sensori e viaggi sono rappresentati da fixture deterministiche. Le prove
su hardware fisico e la qualità statistica del modello HAR restano test di
accettazione separati: non devono rendere intermittente la pipeline CI.
