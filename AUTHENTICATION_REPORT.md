# Report: Autenticazione Mobility Diary

## 1. Contesto Corretto

Il client non e Flutter Web: e una **app Flutter mobile nativa**.

Questo cambia la scelta architetturale:

- niente Supabase;
- niente DRF;
- niente dipendenza da cookie browser come meccanismo principale;
- niente CSRF obbligatorio per le API mobile;
- login con utenti Django salvati su PostgreSQL/PostGIS;
- autenticazione API tramite `Authorization: Bearer <token>`.

Stack reale:

```text
Flutter mobile app
    |
    | POST /api/auth/login oppure /api/auth/register
    v
Django Ninja
    |
    | verifica password con django.contrib.auth
    v
PostgreSQL/PostGIS
    |
    | salva hash del token mobile e popola Redis
    v
Redis cache sessione mobile
    |
    | /api/auth/me legge user payload da Redis se presente
    v
Flutter conserva token e user payload in secure storage
```

Il database e quello in `back-end/infra`, basato su:

```text
postgis/postgis:16-3.4
```

Questa immagine contiene **PostgreSQL 16 + PostGIS 3.4**. PostGIS non
sostituisce PostgreSQL: e PostgreSQL con estensioni geografiche gia pronte.

---

## 2. Scelta Attuale

Per l'app mobile usiamo **token opachi**, non JWT.

Token opaco significa:

- il backend genera una stringa casuale sicura;
- il client riceve quella stringa una sola volta;
- il database salva solo `sha256(token)`;
- Redis usa una chiave basata su `sha256(token)`, non sul token raw;
- Redis salva il payload utente necessario all'app;
- se il DB viene letto, il token originale non e presente in chiaro;
- ogni chiamata API usa header `Authorization`.

Esempio:

```http
Authorization: Bearer 8Yx...
```

Per ora il token dura 30 giorni:

```python
MOBILE_ACCESS_TOKEN_TTL_DAYS = 30
```

Configurabile da `.env.local` con:

```text
MOBILE_ACCESS_TOKEN_TTL_DAYS=30
```

La chiave Redis ha lo stesso TTL residuo del token nel DB:

```text
ttl Redis = expires_at token - now
```

Quindi se il token scade nel DB tra 12 giorni, anche la cache Redis viene
scritta con TTL di circa 12 giorni.

---

## 3. File Implementati

Auth mobile:

```text
back-end/ninja/accounts/
  api.py
  auth.py
  models.py
  session_cache.py
  schemas.py
  migrations/0001_initial.py
```

Frontend mobile:

```text
mobile/diary/lib/features/auth/domain/
  auth_session.dart
  auth_user.dart

mobile/diary/lib/repositories/
  auth_repository.dart
  impl/auth_repository_impl.dart

mobile/diary/lib/state_management/cubits/auth_cubit/
  auth_cubit.dart
  auth_cubit_state.dart

mobile/diary/lib/ui/pages/auth_page.dart
```

Router montato in:

```text
back-end/ninja/config/urls.py
```

Settings:

```text
back-end/ninja/config/settings.py
```

Mobility API protette in:

```text
back-end/ninja/mobility/api.py
```

Trip collegati all'utente in:

```text
back-end/ninja/mobility/models.py
back-end/ninja/mobility/migrations/0002_trip_user.py
```

---

## 4. Endpoint Auth E Contratti API

Base path:

```text
/api/auth/
```

| Metodo | Endpoint | Auth | Scopo |
|--------|----------|------|-------|
| `POST` | `/api/auth/register` | No | Crea utente e token mobile |
| `POST` | `/api/auth/login` | No | Login e creazione token mobile |
| `GET` | `/api/auth/me` | Bearer | Ritorna utente corrente |
| `POST` | `/api/auth/logout` | Bearer | Revoca il token corrente |

`/api/auth/me` e l'endpoint usato per autologin all'apertura dell'app. Prima
controlla Redis; se trova la sessione, ritorna i dati utente senza leggere il
DB. Se Redis ha perso la chiave, fa fallback su PostgreSQL/PostGIS e ripopola
Redis.

Non usiamo `/csrf` per il flusso mobile, perche l'app nativa non e un browser
che invia cookie automaticamente.

Nota importante: nelle API pubbliche **non esiste il campo `username`**.
L'app usa solo email, password, token e payload utente. Django internamente
mantiene un username tecnico uguale all'email, ma non fa parte del contratto
mobile.

---

## 5. Registrazione

Request:

```http
POST /api/auth/register
Content-Type: application/json

{
  "email": "utente@example.com",
  "password": "password-sicura",
  "first_name": "Giacomo",
  "last_name": "Bianco",
  "device_name": "iPhone"
}
```

Struttura request:

| Campo | Tipo | Obbligatorio | Note |
|-------|------|--------------|------|
| `email` | string | si | Identificativo utente lato app |
| `password` | string | si | Validata dai validator Django |
| `first_name` | string | no | Nome mostrabile in app |
| `last_name` | string | no | Cognome mostrabile in app |
| `device_name` | string | no | Nome logico del dispositivo |

Comportamento backend:

1. normalizza e valida l'email;
2. controlla che l'email non sia gia registrata;
3. valida la password con i validator Django;
4. crea un utente Django in `auth_user`;
5. genera subito un token mobile;
6. salva il token hashato nel DB;
7. scrive in Redis il payload utente con TTL uguale alla scadenza del token;
8. ritorna la stessa response del login.

Errori principali:

- `400`: email non valida o password non accettata;
- `409`: email gia registrata.

La registrazione e gia collegata alla schermata Flutter: dopo account creato,
l'app entra direttamente.

Response `201 Created`:

```json
{
  "user": {
    "id": 1,
    "email": "utente@example.com",
    "first_name": "Giacomo",
    "last_name": "Bianco",
    "is_staff": false,
    "is_superuser": false
  },
  "access_token": "TOKEN_RAW_DA_SALVARE_SUL_TELEFONO",
  "token_type": "Bearer",
  "expires_at": "2026-07-09T12:00:00Z"
}
```

Response errore `400`:

```json
{
  "detail": "Email non valida"
}
```

Response errore `409`:

```json
{
  "detail": "Email gia registrata"
}
```

---

## 6. Login

Request:

```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "utente@example.com",
  "password": "password",
  "device_name": "iPhone di Giacomo"
}
```

Comportamento backend:

1. cerca l'utente Django tramite `email__iexact`;
2. usa l'email come identificativo di login;
3. verifica password con il sistema standard Django;
4. genera un token casuale con `secrets.token_urlsafe(48)`;
5. salva solo `sha256(token)` nella tabella `accounts_accesstoken`;
6. scrive in Redis user payload + token metadata;
7. restituisce il token raw al client.

Response:

```json
{
  "user": {
    "id": 1,
    "email": "utente@example.com",
    "first_name": "Giacomo",
    "last_name": "Bianco",
    "is_staff": false,
    "is_superuser": false
  },
  "access_token": "TOKEN_RAW_DA_SALVARE_SUL_TELEFONO",
  "token_type": "Bearer",
  "expires_at": "2026-07-09T12:00:00Z"
}
```

Response errore `401`:

```json
{
  "detail": "Credenziali non valide"
}
```

Response errore `403`:

```json
{
  "detail": "Utente disabilitato"
}
```

## 6.1 Autologin / Me

Request:

```http
GET /api/auth/me
Authorization: Bearer TOKEN_RAW_DA_SALVARE_SUL_TELEFONO
```

Response `200 OK`:

```json
{
  "id": 1,
  "email": "utente@example.com",
  "first_name": "Giacomo",
  "last_name": "Bianco",
  "is_staff": false,
  "is_superuser": false
}
```

Response errore `401`:

```json
{
  "detail": "Unauthorized"
}
```

## 6.2 Logout

Request:

```http
POST /api/auth/logout
Authorization: Bearer TOKEN_RAW_DA_SALVARE_SUL_TELEFONO
```

Response `200 OK`:

```json
{
  "detail": "Logout effettuato"
}
```

Il client Flutter deve salvare `access_token` in uno storage sicuro, ad esempio:

```text
flutter_secure_storage
```

Non va salvato in plain text dentro SharedPreferences.

---

## 7. Frontend Flutter Mobile

La home ora funziona come auth gate:

- se non c'e token valido, mostra `AuthPage`;
- se login/registrazione riescono, mostra la dashboard sensori;
- se esiste un token salvato, all'avvio chiama `/api/auth/me`;
- se `/me` fallisce, cancella la sessione locale;
- se `/me` riesce, salva il payload utente nel secure storage;
- se `/me` riesce, mette lo stesso utente in `AuthCubit.state.user`;
- logout revoca il token lato server e lo rimuove dal telefono.

Il dato utente non resta solo nel repository. Il flusso Pine e:

```text
AuthRepositoryImpl
    |
    | restoreSession() / login() / register()
    v
AuthCubit
    |
    | emit(AuthStatus.authenticated, user: session.user)
    v
UI / altri cubit leggono AuthCubit.state.user
```

Quindi da qualunque widget puoi leggere:

```dart
final user = context.watch<AuthCubit>().state.user;
final userId = context.read<AuthCubit>().currentUserId;
```

Getter disponibili nel cubit:

```dart
currentUser
currentUserId
currentUserEmail
accessToken
```

`AuthCubit.refreshCurrentUser()` richiama `/api/auth/me`, aggiorna il payload
utente e lo rimette nello stato globale.

Il router usa lo stesso `AuthRepository` passato al `DependencyInjector`, quindi
`AuthGuard`, `AuthCubit` e repository condividono la stessa sessione.

Il token viene salvato con:

```text
flutter_secure_storage
```

La base URL e configurabile:

```dart
const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api',
)
```

Per iOS simulator di solito va bene:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Per Android emulator usare:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Per telefono fisico bisogna usare l'IP del Mac nella stessa rete:

```bash
flutter run --dart-define=API_BASE_URL=http://IP_DEL_MAC:8000/api
```

Sono stati aggiunti:

- `android.permission.INTERNET`;
- `android:usesCleartextTraffic="true"` per sviluppo HTTP locale;
- `NSAllowsLocalNetworking` su iOS per backend locale.

---

## 8. Uso Del Token

Ogni chiamata protetta deve mandare:

```http
Authorization: Bearer TOKEN_RAW_DA_SALVARE_SUL_TELEFONO
```

Esempio:

```http
POST /api/mobility/trips
Authorization: Bearer TOKEN_RAW_DA_SALVARE_SUL_TELEFONO
Content-Type: application/json

{
  "device_id": "iphone-giacomo"
}
```

Il backend:

1. prende il token dall'header;
2. calcola `sha256(token)`;
3. cerca `mobile_auth:<sha256(token)>` in Redis;
4. se Redis trova la chiave, usa direttamente user id/email/nome dal payload;
5. se Redis non trova la chiave, legge `accounts_accesstoken` dal DB;
6. se il token DB e valido, ripopola Redis con TTL allineato a `expires_at`;
7. imposta `request.auth` con il contesto utente.

Nel caso veloce, cioe Redis hit, `/api/auth/me` non legge direttamente il DB.

---

## 9. Logout

Request:

```http
POST /api/auth/logout
Authorization: Bearer TOKEN_RAW
```

Il backend non cancella per forza la riga: imposta `revoked_at`.
In piu cancella subito la chiave Redis collegata al token.

Effetto:

- quel token non funziona piu;
- eventuali altri token dello stesso utente, per esempio altro telefono, restano validi.

---

## 10. Modello AccessToken

Tabella:

```text
accounts_accesstoken
```

Campi principali:

| Campo | Scopo |
|-------|-------|
| `user` | utente Django proprietario |
| `token_hash` | SHA-256 del token raw |
| `device_name` | nome dispositivo inviato dal client |
| `created_at` | creazione token |
| `expires_at` | scadenza |
| `revoked_at` | logout/revoca |

Il token raw non viene mai salvato.

## 10.1 Payload Redis

Redis viene usato come cache chiave-valore per ritrovare rapidamente la sessione
mobile partendo dal token mandato dall'app.

La struttura logica e:

```text
key   = mobile_auth:<sha256(token_raw)>
value = dati sessione + dati utente necessari al client
ttl   = expires_at token - now
```

Chiave generica:

```text
mobile_auth:<sha256(token_raw)>
```

Esempio concreto per un utente:

```text
token_raw ricevuto dal client:
QHT0mGkqSx...valore-lungo...

sha256(token_raw):
9f5c2a0b7d8e4f6a1c3b2...

chiave Redis:
mobile_auth:9f5c2a0b7d8e4f6a1c3b2...
```

Valore JSON associato a quella chiave:

```json
{
  "token_hash": "9f5c2a0b7d8e4f6a1c3b2...",
  "token_id": 12,
  "expires_at": "2026-07-09T12:00:00+00:00",
  "user": {
    "id": 1,
    "email": "utente@example.com",
    "first_name": "Giacomo",
    "last_name": "Bianco",
    "is_staff": false,
    "is_superuser": false
  }
}
```

Quindi Redis contiene gia i dati utente che servono a `/api/auth/me`:

| Campo Redis | Significato |
|-------------|-------------|
| `token_hash` | Hash del token raw ricevuto dal client |
| `token_id` | ID della riga `accounts_accesstoken` nel DB |
| `expires_at` | Scadenza assoluta del token |
| `user.id` | ID utente Django |
| `user.email` | Email utente |
| `user.first_name` | Nome |
| `user.last_name` | Cognome |
| `user.is_staff` | Flag staff |
| `user.is_superuser` | Flag superuser |

TTL:

```text
expires_at - now
```

Esempio TTL:

```text
expires_at = 2026-07-09 12:00:00
now        = 2026-06-09 12:00:00
ttl Redis  = 30 giorni
```

Quando l'app si apre:

1. Flutter legge il token raw da `flutter_secure_storage`;
2. chiama `/api/auth/me` con `Authorization: Bearer <token_raw>`;
3. Django calcola `sha256(token_raw)`;
4. Django cerca `mobile_auth:<sha256(token_raw)>` in Redis;
5. se la chiave esiste, risponde usando il JSON Redis;
6. il DB non viene interrogato in questo caso.

Scelta importante: Redis non contiene il token raw. Contiene il suo hash,
coerente con il DB.

---

## 11. Protezione Mobility

Le API principali sono protette con:

```python
mobile_bearer_auth
```

Endpoint protetti:

| Metodo | Endpoint |
|--------|----------|
| `POST` | `/api/mobility/trips` |
| `POST` | `/api/mobility/trips/{trip_id}/gps-points` |
| `POST` | `/api/mobility/trips/{trip_id}/sensor-windows` |
| `POST` | `/api/mobility/trips/{trip_id}/process-har` |

Endpoint pubblico:

```text
GET /api/mobility/health
```

Quando viene creato un viaggio:

```python
Trip.objects.create(device_id=payload.device_id, user=request.user)
```

Quando si scrivono GPS, finestre sensoriali o job HAR:

```python
get_object_or_404(Trip, id=trip_id, user=request.user)
```

Quindi un utente non puo scrivere dati nel viaggio di un altro utente.

---

## 12. Differenze Rispetto A Supabase/DRF

| Report originale | Implementazione attuale |
|------------------|-------------------------|
| Supabase GoTrue | Django `auth_user` su PostgreSQL/PostGIS |
| DRF | Django Ninja |
| JWT Supabase | Token opaco mobile |
| Cookie HttpOnly come meccanismo principale | Header `Authorization: Bearer` |
| CSRF centrale | Non necessario per app mobile bearer-token |
| Refresh token Supabase | Token mobile con scadenza e revoca |
| Redis per auth/sessioni | Redis cache per autologin mobile + Celery broker |

---

## 13. Comandi Locali

Avvia infrastruttura:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/back-end/infra
docker compose up -d db redis
```

Avvia Django:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/back-end
source .venv/bin/activate
cd ninja
python3 manage.py migrate
python3 manage.py runserver
```

Avvia Celery in un secondo terminale:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/back-end
source .venv/bin/activate
cd ninja
celery -A config worker -l info
```

Crea un primo utente:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/back-end
source .venv/bin/activate
cd ninja
python3 manage.py createsuperuser
```

Consiglio: assegna una email reale all'utente, perche il login cerca prima per
email.

In alternativa, ora puoi creare l'utente direttamente dalla schermata
`Registrati` dell'app Flutter.

Avvio Flutter iOS simulator:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/mobile/diary
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Avvio Flutter Android emulator:

```bash
cd /Users/giacomobianco/Downloads/Mobility-Diary/mobile/diary
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

---

## 14. Cose Da Aggiungere Dopo

Non ancora implementato:

- reset password;
- rate limiting sul login;
- revoca di tutti i token dell'utente;
- lista dispositivi collegati;
- rotazione token;
- invalidazione automatica Redis quando un utente viene disabilitato da admin;
- CORS, utile solo se aggiungeremo anche un frontend web;
- push notification / device id reale.

Per ora la base giusta per Flutter mobile e: **Django Ninja + Postgres/PostGIS +
token Bearer opaco hashato nel DB + Redis cache per autologin**.
