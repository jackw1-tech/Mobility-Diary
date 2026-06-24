# Mobility Diary Back-End

Struttura pensata per tenere separati il backend applicativo, l'infrastruttura
locale e il futuro servizio HAR in FastAPI.

```text
back-end/
  ninja/      Django + Django Ninja, API principali, Celery tasks
  infra/      Docker Compose, Redis, PostgreSQL, PostGIS init
  fastapi/    Futuro servizio HAR/AI inference
  .venv/      Ambiente Python locale condiviso
```

## Ruoli

`ninja`

Backend principale: trip, GPS, finestre sensoriali, job HAR, admin Django,
API docs Ninja.

`infra`

Servizi locali condivisi:

- PostgreSQL + PostGIS su `localhost:5432`;
- Redis container su `localhost:6381`, internamente sempre `redis:6379`.

`fastapi`

Servizio futuro per inferenza HAR pesante. Per ora contiene solo uno skeleton
con endpoint `/health`.

## Setup Locale Consigliato

Da `back-end/`:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r ninja/requirements.txt
```

Avvia solo infrastruttura:

```bash
cd infra
docker compose up -d db redis
```

Avvia Django Ninja in locale:

```bash
cd ../ninja
../.venv/bin/python manage.py makemigrations
../.venv/bin/python manage.py migrate
../.venv/bin/python manage.py runserver
```

In un secondo terminale, Celery worker:

```bash
cd back-end/ninja
../.venv/bin/celery -A config worker -l info
```

API docs:

```text
http://localhost:8000/api/docs
```

Django admin:

```text
http://localhost:8000/admin/
```

## Docker Completo

Da `back-end/infra/`:

```bash
cp .env.example .env
docker compose up -d --build
docker compose exec web python manage.py createsuperuser
```

Il compose locale espone Nginx come unico entrypoint applicativo:

```text
http://localhost:8080/api/docs
http://localhost:8080/admin/
```

Il servizio Django resta raggiungibile solo dalla rete interna Docker come
`web:8000`; anche PostgreSQL, Redis e MinIO restano privati nella rete Docker.
I presigned upload locali passano da Nginx usando il path del bucket
`/mobility-trips/...`, cosi' il mobile non deve raggiungere MinIO direttamente.
Nel compose locale Django gira con Gunicorn + Uvicorn worker ASGI, non con il
development server, cosi' SSE e richieste async vengono esercitati in modo piu'
simile al deploy reale.
Le migrazioni girano come servizio one-shot `migrate` prima di avviare `web`,
`worker` e `beat`; tutti i servizi parlano direttamente con Postgres su
`db:5432` (nessun connection pooler in mezzo).
Railway resta un target di deploy separato: quando servono dati reali, il mobile
o la piattaforma web devono puntare all'URL Railway tramite `API_BASE_URL` /
`VITE_API_BASE_URL`, senza far usare ai container locali il database di
produzione.

Per pubblicare la piattaforma web su Vercel prima della VPS:

```text
Root Directory: web
Framework Preset: Vite
Install Command: npm ci
Build Command: npm run build
Output Directory: dist
Environment Variable:
  VITE_API_BASE_URL=https://django-api-production-df02.up.railway.app/api
```

Sul backend Railway, aggiungi l'origine Vercel a:

```text
CORS_ALLOWED_ORIGINS=https://nome-progetto.vercel.app
CSRF_TRUSTED_ORIGINS=https://nome-progetto.vercel.app
```

Il compose avvia due repliche del servizio `web` per esercitare il load
balancing locale di Nginx e due repliche del servizio `worker` per consumare la
coda Celery in parallelo. `beat` resta singolo: duplicarlo potrebbe accodare due
volte gli stessi task schedulati.

Se cambi il numero di repliche web a caldo, riavvia il gateway per forzare
Nginx a risolvere di nuovo gli upstream:

```bash
docker compose restart gateway
```

Log:

```bash
docker compose logs -f gateway
docker compose logs -f web
docker compose logs -f worker
docker compose logs -f redis
docker compose logs -f db
```

Stop:

```bash
docker compose down
```

Stop cancellando anche il volume locale del DB:

```bash
docker compose down -v
```

## Deploy VPS / Coolify

Il deploy su VPS usa un compose separato da quello locale:

```text
back-end/infra/docker-compose.coolify.yml
```

Questo file e' pensato per Coolify o per una VPS gestita a mano:

- espone solo `gateway` sulla porta interna `80`;
- lascia `web`, `worker`, `beat`, `db`, `redis` e `minio`
  privati nella rete Docker;
- non monta il codice sorgente come volume, quindi usa l'immagine buildata;
- esegue `migrate` come servizio one-shot prima di avviare web/worker/beat;
- tutti i servizi parlano direttamente con Postgres (`db:5432`), nessun pooler.

Template env:

```bash
cp infra/.env.coolify.example infra/.env.coolify
```

Valori da cambiare prima del deploy:

```text
DJANGO_SECRET_KEY
DJANGO_ALLOWED_HOSTS=mobility.tuodominio.it
CSRF_TRUSTED_ORIGINS=https://mobility.tuodominio.it
POSTGRES_PASSWORD
S3_PUBLIC_ENDPOINT_URL=https://mobility.tuodominio.it
S3_ACCESS_KEY_ID
S3_SECRET_ACCESS_KEY
```

In Coolify il dominio pubblico va collegato al servizio `gateway`, non al
servizio `web`. Il mobile in release puo' puntare alla VPS passando:

```bash
flutter build ios --release \
  --dart-define API_BASE_URL=https://mobility.tuodominio.it/api
```

Per una prova manuale su VPS, dalla cartella `back-end/infra/`:

```bash
docker compose --env-file .env.coolify -f docker-compose.coolify.yml up -d --build
```

## FastAPI Futuro

Quando servirà provarlo:

```bash
source .venv/bin/activate
pip install -r fastapi/requirements.txt
cd fastapi
../.venv/bin/uvicorn app.main:app --reload --port 8001
```

Health check:

```text
http://localhost:8001/health
```
