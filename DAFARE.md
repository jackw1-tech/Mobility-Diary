Ti ho preparato un documento Markdown pulito, pronto per essere salvato nella tua repo (ad esempio come `docs/sse_architecture_railway.md`) o condiviso con il team.

---

# Nota Architetturale: Gestione SSE e Scalabilità su Django Ninja

**Data:** Giugno 2026

**Ambiente:** Railway (1 vCPU) / Docker / Gunicorn / Django Ninja

**Oggetto:** Risoluzione del collo di bottiglia WSGI per lo streaming di eventi (Server-Sent Events)

---

## Executive Summary (TL;DR)

L’attuale configurazione del backend su Railway utilizza un modello di esecuzione **sincrono (WSGI)**. In questo scenario, l'introduzione di endpoint SSE (*Server-Sent Events*) per il tracking dei viaggi limita l'intera applicazione a un **massimo teorico di 3 connessioni SSE simultanee**.

Alla quarta connessione aperta, l'applicazione entra in stato di **Worker Starvation**: il backend smette di rispondere a qualsiasi altra richiesta REST (es. login, fetch dei dati) finché una delle connessioni SSE non viene chiusa.

La soluzione consiste nel migrare l'interfaccia di Gunicorn da **WSGI** ad **ASGI**, delegando la gestione asincrona a `UvicornWorker`.

---

## 1. Lo Stato Attuale (Come gira oggi su Railway)

Attualmente il contenitore Docker viene lanciato con il comando:

```bash
gunicorn config.wsgi:application --bind 0.0.0.0:8000

```

Non avendo specificato parametri custom, Gunicorn applica la sua formula matematica di default per il calcolo dei processi worker:


$$\text{Workers} = (2 \times \text{CPU\_COUNT}) + 1$$

Girando sul piano standard di Railway (**1 vCPU**), la matematica restituisce esattamente:

* **Workers:** `(2 × 1) + 1` = **3 processi sincroni**.
* **Threads per worker:** `1` (Single-thread).

**Cosa significa in produzione:** Il nostro server è fisicamente in grado di processare **esattamente 3 richieste HTTP in parallelo**.

---

## 2. Il Problema: Il "Worker Starvation"

Nelle API REST classiche (`GET /trips/123`), il ciclo di vita di una richiesta è cortissimo:

1. Arriva la richiesta $\rightarrow$ Il Worker 1 se ne fa carico.
2. Interroga il DB e risponde in **40ms**.
3. Il Worker 1 torna immediatamente libero e disponibile per un altro utente.
*(Con 3 worker sincroni si possono gestire agevolmente decine di richieste al secondo).*

**Con gli SSE (Server-Sent Events) il paradigma cambia:**
L'endpoint `/trips/123/events` apre una richiesta HTTP e **non la chiude**. La tiene deliberatamente appesa per fare streaming di testo.

#### La simulazione di blocco:

1. **Utente A** apre la mappa del Viaggio 10 $\rightarrow$ *Worker 1 sequestrato.*
2. **Utente B** apre la mappa del Viaggio 11 $\rightarrow$ *Worker 2 sequestrato.*
3. **Utente C** apre la mappa del Viaggio 12 $\rightarrow$ *Worker 3 sequestrato.*

In questo esatto istante, **il server ha esaurito i processi**.
Se un **Utente D** tenta di fare un banale login (`POST /auth/login`), la sua richiesta rimarrà appesa in *pending* nel vuoto fino al raggiungimento del timeout di Nginx/Railway, farfugliando un errore `504 Gateway Timeout`.

> [!WARNING]
> **Perché non basta aumentare i worker o i thread?**
> Passare a `--workers 6` sposta il problema dalla 4° alla 7° persona. Passare ai thread di sistema (`--worker-class gthread`) consuma enormi quantità di memoria RAM per fare *context-switching* tra i thread, portando una macchina da 1 vCPU a saturare la memoria istantaneamente.

---

## 3. La Soluzione: Lo switch ad ASGI

Non dobbiamo eliminare Gunicorn (che resta un eccellente gestore di demoni e crash di processo), ma dobbiamo cambiargli il "motore" interno, ordinandogli di usare **l'Event Loop asincrono di Uvicorn**.

### Step 1: Aggiornamento dipendenze

Aggiungere al file `requirements.txt` (o `pyproject.toml`):

```text
uvicorn[standard]>=0.30.0

```

### Step 2: Modifica del Dockerfile

Sostituire l'istruzione di avvio del server `back-end/ninja/Dockerfile`.

* **Da (Sincrono / WSGI):**
```dockerfile

```



CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]

```

* **A (Asincrono / ASGI):**
  ```dockerfile
CMD ["gunicorn", "config.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000"]

```

*(Nota: Assicurarsi che nel file `back-end/ninja/config/asgi.py` sia esposta l'istanza `application`, generata di default da Django).*

---

## 4. Perché funziona (La teoria sotto il cofano)

Passando ad ASGI, il worker non ragiona più a "sportelli postali fisici" (1 richiesta = 1 dipendente bloccato), ma ragiona a **Event Loop** (modello Node.js / FastAPI).

Quando la funzione asincrona dell'SSE entra in fase di attesa:

```python
await asyncio.sleep(2) # o attesa di un messaggio da Redis

```

In quel preciso millisecondo, **il worker rilascia il controllo del thread**.

Il processore si gira, vede che è arrivata una richiesta di `GET /diary` da un altro utente, la risolve in 15 millisecondi, la spedisce, e quando l'operazione di I/O dell'SSE si sblocca, riprende in mano lo stream.

**Il risultato:** Quello stesso singolo worker che prima veniva messo in ginocchio da 1 singola connessione SSE, sotto ASGI può tenere aperte **migliaia di connessioni SSE dormienti** contemporaneamente, continuando a servire il traffico REST standard senza mostrare rallentamenti.

---

## 5. Checklist di collaudo post-deploy

Una volta pushato su Railway, verificare:

1. **I Log di boot:** In avvio, la console di Railway non deve più mostrare la dicitura *“Booting worker with pid...”* tipica di WSGI, ma deve mostrare:
`[INFO] Application startup complete.` (Log nativo di Uvicorn).
2. **Lo Stress Test casalingo:** Aprire 4 o 5 schede del browser in incognito sull'endpoint SSE di un viaggio. Aprire un'ulteriore scheda e ricaricare la homepage o un endpoint REST: la risposta deve arrivare istantaneamente.