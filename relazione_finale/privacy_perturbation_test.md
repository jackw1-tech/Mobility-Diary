# Privacy Perturbation Test

Documentazione del test eseguito per misurare **Privacy Perturbation** e
**Quality of Service (QoS)** del modulo di privacy (`mobility/privacy.py`) sui
dati realmente presenti nel database di produzione, usati poi nella
Sezione IV (Risultati) della relazione.

## Obiettivo

Calcolare, per ciascun livello di privacy protetto (`approximate`, griglia
150 m; `aggregated`, griglia 400 m) e per ciascuna modalità di attività
riconosciuta, quanto la generalizzazione spaziale a griglia:

1. sposta i punti GPS reali rispetto a quelli pubblicati (**Privacy
   Perturbation**);
2. distorce la lunghezza del percorso ricostruito (**Quality of
   Service**, come errore relativo di distanza).

Il livello `precise` non viene misurato: non applica trasformazioni, è la
traccia reale usata come riferimento per calcolare le altre due metriche.

## Metodologia

I segmenti del diario (`MobilitySegment`) sono di due tipi:

- **MOVE**: ha un percorso (`path`, una `LineString`) e una lunghezza
  reale (`distance_meters`). Per questi si può usare direttamente
  `privacy_metrics(path, level=...)`, già definita nel modulo di privacy,
  che restituisce sia la Perturbation (media/massima) sia la QoS (errore
  relativo tra lunghezza reale e lunghezza approssimata).
- **STOP**: non ha un percorso (`path=None`, `distance_meters=0`), è un
  punto fermo. Per questi non ha senso una QoS basata su lunghezza di
  percorso: si calcola solo la Perturbation, come distanza (haversine) tra
  il centroide GPS della sosta e la sua versione approssimata
  (`approximate_point`).

Sono stati scartati i segmenti di movimento con meno di 5 punti GPS
(`MIN_POINTS`), per evitare che percorsi degeneri distorcessero la media.

## Script eseguiti

Eseguiti in `python manage.py shell` sul database di produzione, tramite
accesso al container Django.

### 1. Segmenti MOVE, raggruppati per attività + segmenti STOP

```python
from django.contrib.gis.geos import Point
from mobility.models import MobilitySegment
from mobility.privacy import privacy_metrics, approximate_point
from mobility.geo import haversine_meters
import statistics
from collections import defaultdict

MIN_POINTS = 5

move_by_activity = defaultdict(lambda: defaultdict(list))
stop_perturbation = defaultdict(list)

segments = MobilitySegment.objects.select_related("trip").iterator()

for seg in segments:
    if seg.kind == MobilitySegment.Kind.MOVE:
        if not seg.path or len(seg.path.coords) < MIN_POINTS:
            continue
        for level in ["approximate", "aggregated"]:
            m = privacy_metrics(seg.path, level=level)
            move_by_activity[seg.activity_label][level].append(m)
    else:  # STOP
        points = [
            p for p in seg.trip.gps_points.all()
            if seg.start_timestamp <= p.timestamp <= seg.end_timestamp
        ]
        if not points:
            continue
        lat = sum(p.point.y for p in points) / len(points)
        lon = sum(p.point.x for p in points) / len(points)
        for level in ["approximate", "aggregated"]:
            approx_lon, approx_lat = approximate_point(Point(lon, lat, srid=4326), level=level)
            stop_perturbation[level].append(haversine_meters(lat, lon, approx_lat, approx_lon))
```

### 2. Stampa dei risultati aggregati

```python
print("=== MOVE, per attività ===")
for activity, by_level in move_by_activity.items():
    print(f"-- {activity} --")
    for level, ms in by_level.items():
        pert = [m.perturbation_mean_meters for m in ms]
        qos = [m.relative_distance_error for m in ms]
        print(f"  {level}: n={len(ms)}, perturbation media={statistics.mean(pert):.1f} m, "
              f"QoS medio={statistics.mean(qos):.4f}")

print()
print("=== STOP (fermo) ===")
for level, dists in stop_perturbation.items():
    print(f"  {level}: n={len(dists)}, perturbation media={statistics.mean(dists):.1f} m, "
          f"mediana={statistics.median(dists):.1f} m")
```

## Output grezzo

```
=== MOVE, per attività ===
-- MOVING_VEHICLE --
  approximate: n=38, perturbation media=37.3 m, QoS medio=0.6425
  aggregated: n=38, perturbation media=100.3 m, QoS medio=0.6053
-- WALKING --
  approximate: n=56, perturbation media=41.9 m, QoS medio=0.9283
  aggregated: n=56, perturbation media=93.0 m, QoS medio=1.0603
-- BIKING --
  approximate: n=3, perturbation media=44.8 m, QoS medio=0.5013
  aggregated: n=3, perturbation media=82.3 m, QoS medio=1.2849

=== STOP (fermo) ===
  approximate: n=51, perturbation media=35.7 m, mediana=36.2 m
  aggregated: n=51, perturbation media=97.5 m, mediana=85.2 m
```

## Tabella riepilogativa

| Modalità     | n  | Perturbation approx. (m) | Perturbation aggr. (m) | QoS approx. | QoS aggr. |
|--------------|----|--------------------------|-------------------------|-------------|-----------|
| Auto/veicolo | 38 | 37,3                     | 100,3                   | 0,64        | 0,61      |
| A piedi      | 56 | 41,9                     | 93,0                    | 0,93        | 1,06      |
| Bicicletta   | 3  | 44,8                     | 82,3                    | 0,50        | 1,28      |
| Sosta        | 51 | 35,7                     | 97,5                    | --          | --        |

## Osservazioni

- **Perturbation** cresce con la dimensione della cella in tutte le
  modalità, comprese le soste: più che raddoppia passando da
  `approximate` (150 m) ad `aggregated` (400 m), come atteso.
- **QoS** non peggiora sempre in modo monotono con l'aggregazione. Per
  l'auto è leggermente **migliore** con celle più grandi (0,61 vs 0,64):
  plausibile per percorsi lunghi e relativamente rettilinei, dove celle
  più larghe producono meno zig-zag tra punti vicini. Per la camminata,
  fatta di percorsi più brevi e tortuosi, l'errore aumenta con
  l'aggregazione come intuitivamente atteso.
- Il campione **bicicletta (n=3)** è troppo piccolo per trarne
  conclusioni robuste; riportato solo per completezza.
- I valori assoluti di QoS sono elevati (spesso oltre il 50%) perché i
  singoli segmenti tra un cambio di attività e l'altro sono
  tipicamente brevi: su un percorso corto anche uno spostamento di
  poche decine di metri incide in proporzione molto di più che su un
  percorso lungo.

## Dove viene usato

Questi dati sono riportati nella Sezione IV (Risultati) della relazione
(`IEEE-conference-template-062824.tex`, Tabella III) e ripresi in sintesi
nella Conclusione.
