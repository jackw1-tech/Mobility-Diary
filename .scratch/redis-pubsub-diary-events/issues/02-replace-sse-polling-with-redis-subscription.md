# 02 - Sostituire il polling SSE con la sottoscrizione Redis, end-to-end

Status: ready-for-agent

## Parent

`.scratch/redis-pubsub-diary-events/PRD.md`

## What to build

Con la pubblicazione su Redis già in piedi (slice 01), l'endpoint SSE che notifica l'app sull'esito dell'Arricchimento del Viaggio smette di fare polling sul database ogni 2 secondi e si sottoscrive invece al canale Redis di quel Viaggio. Il contratto verso il client (nome dell'evento, formato del payload) non cambia in nessun modo: cambia solo come il backend scopre che lo stato è cambiato.

Sequenza obbligata, per evitare di perdere un evento che si verifica nell'istante esatto tra l'apertura della connessione e l'inizio dell'ascolto (Redis Pub/Sub non bufferizza nulla, un messaggio pubblicato prima che qualcuno sia in ascolto va perso per sempre):

1. Sottoscriversi al canale del Viaggio **prima** di qualunque altra cosa.
2. Solo dopo, controllare una volta lo stato attuale sul database (lo stesso controllo che oggi avviene nel ciclo di polling).
3. Se lo stato è già risolto al passo 2, emettere subito l'evento e chiudere, senza mai entrare in ascolto sul canale.
4. Altrimenti, restare in ascolto sul canale già sottoscritto fino a un timeout di sicurezza (lo stesso timeout di 300 secondi che esiste oggi, preservato anche se il polling scompare — serve a non restare bloccati per sempre nel caso, fuori scope, in cui nessun evento venga mai pubblicato).

Se la sottoscrizione a Redis fallisce per qualunque motivo, non è previsto nessun ripiego sul vecchio comportamento di polling: la connessione SSE termina con un errore e il client la riapre normalmente entrando di nuovo nella pagina.

## Acceptance criteria

- [ ] Aprendo una connessione SSE per un Viaggio non ancora arricchito, non viene eseguita nessuna query di polling ripetuta sul database: l'attesa avviene tramite sottoscrizione Redis.
- [ ] Se il Viaggio è già arricchito (con successo o fallito) nel momento esatto in cui la connessione SSE si apre, l'evento corrispondente viene emesso immediatamente, senza dipendere dall'arrivo di una pubblicazione successiva.
- [ ] Se l'evento di completamento viene pubblicato mentre la connessione SSE è in attesa, l'evento corrispondente viene emesso al client immediatamente.
- [ ] Se nessun evento di completamento arriva entro il timeout esistente (300 secondi), il comportamento di timeout verso il client resta identico a oggi.
- [ ] Se la sottoscrizione a Redis non può essere stabilita, la connessione SSE termina con un errore, senza ripiegare sul vecchio comportamento di polling.
- [ ] Aprendo due connessioni SSE sullo stesso Viaggio contemporaneamente (es. stesso utente su due dispositivi), entrambe ricevono l'evento di completamento.
- [ ] Test automatico per ciascuno dei casi sopra (stato già risolto all'apertura, evento che arriva durante l'attesa, timeout senza eventi), usando un'istanza Redis reale.
- [ ] I test esistenti basati sul vecchio meccanismo di polling sono aggiornati o rimossi in coerenza con il nuovo comportamento.

## Blocked by

- `.scratch/redis-pubsub-diary-events/issues/01-publish-diary-status-to-redis.md` (serve che la pubblicazione esista prima che la sottoscrizione abbia qualcosa da ricevere)
