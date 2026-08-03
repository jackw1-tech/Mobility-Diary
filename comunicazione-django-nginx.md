# Comunicazione Django Nginx

## Scopo

Questo documento spiega come comunicano Nginx, Django, Coolify e i client nella produzione attuale di Mobility Diary.

Il punto importante e' questo: Django non viene esposto direttamente a Internet. Le richieste passano prima da un gateway/proxy e poi arrivano al container Django tramite rete Docker interna.

## Flusso Di Produzione

Nel deploy Coolify il file principale e':

```text
docker-compose.coolify.yml
```

I servizi coinvolti sono:

```text
gateway  -> Nginx del progetto
web      -> Django/Gunicorn/Uvicorn
minio    -> object storage S3-compatibile
```

Il flusso per le API Django e':

```text
Browser / Flutter / Vue
  -> dominio pubblico HTTPS
  -> proxy esterno Coolify
  -> gateway Nginx del progetto
  -> web:8000
  -> Django
```

Nel compose, Django viene avviato dal servizio `web` con:

```bash
gunicorn config.asgi:application -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

Quindi il runtime applicativo usa ASGI:

```text
Gunicorn -> UvicornWorker -> config/asgi.py -> Django
```

## Tratto Nginx -> Django

Nel file:

```text
back-end/infra/nginx/conf.d/mobility-diary.conf
```

Nginx definisce:

```nginx
set $django_api http://web:8000;
```

e poi inoltra le richieste con:

```nginx
proxy_pass $django_api;
```

Questo significa che il tratto:

```text
gateway Nginx -> Django web:8000
```

e' HTTP interno, non HTTPS.

HTTPS viene gestito prima, sul dominio pubblico/proxy esterno. Django non riceve TLS direttamente.

## Header Inoltrati Da Nginx

Nginx inoltra alcuni header importanti:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

Significato:

```text
Host
  Dominio richiesto dal client, visto dal proxy.

X-Real-IP
  IP del client visto da Nginx.

X-Forwarded-For
  Catena degli IP attraversati dalla richiesta.

X-Forwarded-Proto
  Protocollo originale visto dal proxy: http oppure https.
```

Questi header servono per non far perdere a Django informazioni sul mondo esterno. Senza questi header, Django vedrebbe solo la richiesta interna provenire dal gateway/container.

## SECURE_PROXY_SSL_HEADER

Nel settings Django:

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

Questa riga dice a Django:

```text
Se nella request vedo HTTP_X_FORWARDED_PROTO uguale a "https",
allora considera la richiesta come sicura.
```

In pratica influenza:

```python
request.is_secure()
```

Con header:

```http
X-Forwarded-Proto: https
```

Django considera:

```python
request.is_secure() == True
```

Questa impostazione serve per cookie sicuri, CSRF, redirect, admin e generazione di URL assoluti.

Nota: in Django gli header HTTP vengono esposti con prefisso `HTTP_`, quindi:

```text
X-Forwarded-Proto
```

diventa:

```text
HTTP_X_FORWARDED_PROTO
```

## USE_X_FORWARDED_HOST

Nel settings Django:

```python
USE_X_FORWARDED_HOST = env_bool("USE_X_FORWARDED_HOST", True)
```

Questa impostazione riguarda il dominio, non il protocollo.

Django internamente potrebbe vedere un host tecnico come:

```text
web:8000
```

ma il dominio pubblico reale e' qualcosa come:

```text
mobility.tuodominio.it
```

Con `USE_X_FORWARDED_HOST = True`, Django usa l'host passato dal proxy tramite `X-Forwarded-Host`, quando disponibile, per calcolare:

```python
request.get_host()
```

Serve per:

```text
ALLOWED_HOSTS
CSRF
redirect
admin
URL assoluti
```

Nel compose Coolify questa scelta e' coerente con:

```yaml
USE_X_FORWARDED_HOST: ${USE_X_FORWARDED_HOST:-1}
```

cioe' in produzione e' attiva di default.

## Differenza Tra Le Due Impostazioni

```python
SECURE_PROXY_SSL_HEADER
```

risponde alla domanda:

```text
La richiesta originale era HTTPS?
```

```python
USE_X_FORWARDED_HOST
```

risponde alla domanda:

```text
Qual era il dominio pubblico originale della richiesta?
```

Sono due problemi diversi:

```text
protocollo -> http oppure https
host       -> dominio richiesto
```

## Routing Nginx

La configurazione Nginx separa tre casi.

### Eventi SSE

```nginx
location ~ ^/api/mobility/trips/[0-9]+/events/?$ {
    proxy_pass $django_api;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 360s;
}
```

Questa route e' speciale per gli eventi streaming/SSE. Disattiva buffering e cache, e aumenta il timeout.

### Object Storage

```nginx
location /mobility-trips/ {
    proxy_pass $object_storage;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
}
```

Questa route inoltra verso MinIO:

```nginx
set $object_storage http://minio:9000;
```

Serve per i presigned URL usati dal mobile per caricare parti raw/sensoriali senza mandare file pesanti direttamente a Django.

### Tutto Il Resto

```nginx
location / {
    proxy_pass $django_api;
}
```

Tutto il resto va a Django:

```text
/api/...
/admin/...
```

## Riassunto

In produzione Django sta dietro Nginx/Coolify:

```text
Client HTTPS -> proxy pubblico -> gateway Nginx -> HTTP interno -> Django
```

Django usa:

```python
SECURE_PROXY_SSL_HEADER
```

per capire se la richiesta originale era HTTPS.

Django usa:

```python
USE_X_FORWARDED_HOST
```

per capire qual era il dominio pubblico originale.

Nginx usa:

```nginx
proxy_pass http://web:8000;
```

per parlare con Django sulla rete Docker interna.

Questa architettura evita di esporre direttamente il container Django a Internet e centralizza routing, streaming SSE e accesso a MinIO nel gateway.
