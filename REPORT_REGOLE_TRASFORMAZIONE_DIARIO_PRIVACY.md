# Regole trasformazione diario privacy-aware

Questo report descrive le regole implementate in
`back-end/ninja/mobility/diary_export.py`.

Il punto unico di costruzione e':

```python
build_trip_privacy_export(trip, level=...)
```

Questo builder e' usato da:

- endpoint mobile `/api/mobility/trips/{trip_id}/privacy-export`
- sezione `privacy_aware.diary` della dashboard web

Restano specifiche della dashboard web, ma non ricostruiscono il diario:

- `privacy_aware.track`
- `privacy_aware.significant_places`
- `privacy_aware.metrics`

La regola architetturale e': il diario viene prima proiettato in forma privata
coerente tramite `project_diary_segments(...)`; il livello privacy non ricostruisce
la timeline, ma trasforma quanto e' pubblicabile.

## Diario dettagliato privato

Fonte canonica:

- `MobilitySegment`
- `VirtualStopInterval`
- `GpsPoint`
- `HabitualPlace` confermati
- label HAR del segmento

Contiene:

- sequenza completa `STOP/MOVE`
- orari al minuto
- durata reale per segmento
- path reale per i movimenti
- distanza reale per i movimenti
- luogo reale per le soste se presente, ad esempio `Casa`, `Universita`
- modalita' prevalente del movimento, ad esempio `a piedi`, `in bici`, `in veicolo`

Esempio:

```text
08:01-08:11, permanenza in Casa, durata: 10m
08:11-08:31, spostamento da Casa a Universita, modalita' prevalente: in bici, distanza: 2.0 km
08:31-09:10, permanenza in Universita, durata: 39m
```

## Dettagliato -> Condivisibile approssimato

Attivato da:

```text
level = approximate
```

Obiettivo: mantenere la storia leggibile del viaggio, ma rimuovere posizione e
luoghi identificabili.

Regole:

| Campo | Regola |
| --- | --- |
| Sequenza segmenti | invariata rispetto al diario dettagliato |
| Tipo segmento | `STOP/MOVE` invariato |
| Orari | start arrotondato per difetto a 5 minuti, end arrotondato per eccesso a 5 minuti |
| Durata | ricalcolata sugli orari pubblicati arrotondati |
| HAR | invariata, tradotta in italiano nel testo |
| Path movimento | cloaking spaziale con celle da 150 m |
| Coordinate movimento | coordinate cloaked, mai letture GPS originali |
| Distanza movimento | ricalcolata sul path cloaked |
| Nome luogo sosta | mascherato per categoria |
| Sosta senza luogo confermato | `Sosta significativa in area approssimata` |
| Centro luogo nel diario web | non pubblicato (`center_geojson = null`) |
| Testo | narrativo, ma senza nomi reali |

Mappatura luoghi:

| Categoria privata | Label pubblicata |
| --- | --- |
| `casa` | `area residenziale` |
| `universita` | `zona universitaria` |
| `lavoro` | `area lavorativa` |
| `palestra` | `area sportiva` |
| `altro` | `area visitata` |
| nessun match | `Sosta significativa in area approssimata` |

Esempio:

```text
08:00-08:15, permanenza in area residenziale, durata: 15m
08:10-08:35, spostamento da area residenziale a zona universitaria, modalita' prevalente: in bici, distanza: 2.0 km
08:30-09:10, permanenza in zona universitaria, durata: 40m
```

Nota: nell'output JSON la distanza del segmento resta numerica e il testo usa
il formato puntuale; per il livello aggregato invece la distanza e' pubblicata a
bucket testuale.

## Dettagliato -> Aggregato

Attivato da:

```text
level = aggregated
```

Obiettivo: non raccontare piu' il percorso evento-per-evento. La vista aggregata
riassume pattern temporali e attivita', senza path e senza luoghi puntuali.

Regole:

| Campo | Regola |
| --- | --- |
| Sequenza segmenti | compressa per fasce temporali |
| Fasce temporali | notte `00-06`, mattina `06-12`, pomeriggio `12-18`, sera `18-24` |
| Orari dei segmenti pubblicati | inizio/fine della fascia, non orari reali |
| STOP | sommati in una riga `permanenza aggregata` per fascia |
| MOVE | sommati in una riga `movimento aggregato` per fascia |
| HAR movimento | modalita' prevalente per durata dentro la fascia |
| Path | non incluso |
| Coordinate | lista vuota |
| Point count | `0` |
| Luoghi | non inclusi, neanche in forma approssimata (`place = null` nel diario web) |
| Distanza | somma per fascia, pubblicata a bucket nel testo |
| Totali | tempo movimento, tempo sosta, distanza approssimata, numero aree significative |

Bucket distanza aggregata:

| Distanza | Bucket |
| --- | --- |
| `0` | `0 km` |
| `< 1 km` | `<1 km` |
| `1-3 km` | `1-3 km` |
| `3-5 km` | `3-5 km` |
| `5-10 km` | `5-10 km` |
| `> 10 km` | `>10 km` |

Esempio:

```text
Diario viaggio #123
Vista: aggregata
Privacy level: aggregated
Cloaking spaziale: celle da 400 m
Percorsi e luoghi puntuali non sono inclusi.

mattina: movimento aggregato: 25m, modalita' prevalente: in bici, distanza: 1-3 km
mattina: permanenza aggregata: 55m

Totale giornata
- tempo in movimento: 25m
- tempo in sosta: 55m
- distanza approssimata: 1-3 km
- aree significative visitate: 2
```

## Differenza concettuale tra livelli

| Livello | Cosa preserva | Cosa rimuove |
| --- | --- | --- |
| `precise` | tutto il diario privato | nulla, export non protetto |
| `approximate` | storia del viaggio e ordine degli eventi | coordinate reali e nomi luogo |
| `aggregated` | pattern temporali, attivita' e statistiche | path, luoghi, sequenza evento-per-evento |

## Test di riferimento

Le regole sono coperte in:

```text
back-end/ninja/mobility/tests/test_diary_export.py
```

Test principali:

- `test_precise_export_is_a_detailed_mobility_diary`
- `test_approximate_export_keeps_the_story_but_masks_places_and_path`
- `test_aggregated_export_summarizes_patterns_without_places_or_paths`
- `test_privacy_export_endpoint_uses_the_centralized_diary_export`
- `accounts/tests/test_web_users_api.py` verifica che la dashboard web usi le
  stesse regole per `privacy_aware.diary`
