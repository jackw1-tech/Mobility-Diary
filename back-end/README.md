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
docker compose exec web python manage.py migrate
docker compose exec web python manage.py createsuperuser
```

Log:

```bash
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
