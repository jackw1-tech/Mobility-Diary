# 01 - Pubblicare lo stato terminale del diario su Redis, in parallelo al polling esistente

Status: ready-for-agent

## Parent

`.scratch/redis-pubsub-diary-events/PRD.md`

## What to build

L'endpoint SSE che notifica l'app quando l'Arricchimento del Viaggio termina (con successo o con fallimento definitivo) oggi scopre lo stato facendo polling sul database ogni 2 secondi. Questa slice prepara il terreno per eliminare quel polling, senza ancora toccare il lato che legge: aggiunge solo la pubblicazione su Redis, lasciando il polling esistente intatto e funzionante esattamente come oggi.

Introdurre un punto unico di verità (un modulo condiviso) per il nome del canale Redis e il formato del payload pubblicato — sarà importato sia dal lato che scrive (il task che chiude la pipeline di Arricchimento) sia, nella prossima slice, dal lato che legge. Il nome del canale è specifico per Viaggio (non un canale unico globale), cosicché un sottoscrittore riceva solo i messaggi che lo riguardano.

Quando il task che porta a termine l'Arricchimento del Viaggio scrive lo stato terminale (arricchito con successo, o fallito in modo definitivo), pubblica un messaggio sul canale di quel Viaggio **dopo** che la transazione che ha scritto lo stato è stata committata — mai prima, altrimenti un futuro sottoscrittore potrebbe ricevere la notifica mentre il dato non è ancora visibile a una query. Il payload pubblicato è lo stesso JSON che oggi finisce nel campo dati dell'evento SSE (`trip_id`, `status: enriched|failed`, eventuale `reason`).

Questa slice è deliberatamente la **prefattorizzazione**: è additiva e a rischio zero (nessun consumer esiste ancora), verificabile in autonomia.

## Acceptance criteria

- [ ] Quando un Viaggio completa l'Arricchimento con successo, viene pubblicato un messaggio sul canale Redis specifico di quel Viaggio, con `status: enriched`, solo dopo il commit della transazione che ha scritto lo stato.
- [ ] Quando l'Arricchimento di un Viaggio fallisce in modo definitivo, viene pubblicato un messaggio sul canale Redis specifico di quel Viaggio, con `status: failed` e il codice di motivo, solo dopo il commit della transazione.
- [ ] Il nome del canale e il formato del payload sono definiti in un unico punto del codice, non duplicati tra punti diversi.
- [ ] Il comportamento osservabile dell'app non cambia in nessun modo: il polling esistente continua a funzionare e a notificare l'app come oggi.
- [ ] Verificabile manualmente con un client Redis in ascolto sul canale del Viaggio mentre la pipeline di Arricchimento lo porta a termine.
- [ ] Test automatico che verifica la pubblicazione avviene con il payload corretto, sia per il caso di successo che di fallimento, e solo dopo il commit della transazione (non prima, anche in caso di rollback).

## Blocked by

None - can start immediately
