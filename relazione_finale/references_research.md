# Fonti primarie per la bibliografia della relazione

Ricerca verificata il 13 settembre 2026. Le fonti consigliate qui sotto sono paper originali, pagine dell'editore o documentazione ufficiale. Per ogni riferimento è indicato che cosa può sostenere nella relazione e, quando necessario, che cosa **non** consente di affermare.

## Riferimenti scientifici essenziali

### SHL Dataset

**Riferimento IEEE**

H. Gjoreski, M. Ciliberto, L. Wang, F. J. Ordóñez Morales, S. Mekki, S. Valentin, and D. Roggen, “The University of Sussex-Huawei Locomotion and Transportation Dataset for Multimodal Analytics With Mobile Devices,” *IEEE Access*, vol. 6, pp. 42592–42604, 2018, doi: [10.1109/ACCESS.2018.2858933](https://doi.org/10.1109/ACCESS.2018.2858933).

Fonti ufficiali: [record IEEE Xplore](https://ieeexplore.ieee.org/document/8418369/) e [pagina del Wearable Technologies Laboratory, University of Sussex](https://www.sussex.ac.uk/strc/research/wearable/locomotion-transportation).

**Sostiene nella relazione:** l'origine e la composizione del dataset SHL; la raccolta in condizioni reali; l'uso di più sensori di smartphone collocati in quattro posizioni corporee; la presenza di annotazioni sulle modalità di locomozione. È il riferimento da collocare alla prima occorrenza di “dataset pubblico SHL” e nella descrizione del protocollo HAR.

### DBSCAN

**Riferimento IEEE**

M. Ester, H.-P. Kriegel, J. Sander, and X. Xu, “A Density-Based Algorithm for Discovering Clusters in Large Spatial Databases with Noise,” in *Proc. 2nd Int. Conf. Knowledge Discovery and Data Mining (KDD-96)*, Portland, OR, USA, 1996, pp. 226–231.

Fonti ufficiali: [pagina AAAI](https://aaai.org/papers/kdd96-037-a-density-based-algorithm-for-discovering-clusters-in-large-spatial-databases-with-noise/) e [PDF AAAI](https://cdn.aaai.org/KDD/1996/KDD96-037.pdf).

**Nota bibliografica:** il paper originale non ha un DOI affidabile; non va inventato né sostituito con identificatori di servizi secondari.

**Sostiene nella relazione:** DBSCAN è un metodo di clustering basato sulla densità, individua cluster di forma arbitraria e distingue il rumore. È il riferimento per il raggruppamento spaziale delle soste in luoghi ricorrenti. I valori concreti di `eps` e `min_samples` restano invece scelte progettuali di Mobility Diary.

### CNN e apprendimento automatico delle feature per HAR

**Riferimento IEEE**

J. B. Yang, M. N. Nguyen, P. P. San, X. L. Li, and S. Krishnaswamy, “Deep Convolutional Neural Networks on Multichannel Time Series for Human Activity Recognition,” in *Proc. 24th Int. Joint Conf. Artificial Intelligence (IJCAI 2015)*, Buenos Aires, Argentina, 2015, pp. 3995–4001.

Fonti ufficiali: [indice IJCAI 2015](https://www.ijcai.org/proceedings/2015) e [PDF IJCAI](https://www.ijcai.org/Proceedings/15/Papers/561.pdf).

**Nota bibliografica:** non risulta un DOI ufficiale del paper.

**Sostiene nella relazione:** una CNN applicata a serie temporali multicanale può apprendere gerarchie di rappresentazioni direttamente dai segnali, evitando di dipendere da feature statistiche progettate manualmente. È la citazione più precisa per la frase sulle feature HAR.

**Formula consigliata:** “Non vengono calcolate feature statistiche handcrafted, quali media o varianza: le finestre grezze dei sei canali AccX/Y/Z e GyrX/Y/Z costituiscono l'input, e gli strati convoluzionali apprendono automaticamente rappresentazioni locali dai segnali multicanale.”

### GRU

**Riferimento IEEE**

K. Cho, B. van Merriënboer, C. Gulcehre, D. Bahdanau, F. Bougares, H. Schwenk, and Y. Bengio, “Learning Phrase Representations using RNN Encoder–Decoder for Statistical Machine Translation,” in *Proc. 2014 Conf. Empirical Methods in Natural Language Processing (EMNLP)*, Doha, Qatar, 2014, pp. 1724–1734, doi: [10.3115/v1/D14-1179](https://doi.org/10.3115/v1/D14-1179).

Fonte ufficiale: [ACL Anthology, record e PDF](https://aclanthology.org/D14-1179/).

**Sostiene nella relazione:** l'origine dell'unità ricorrente con gate di reset e update e il suo ruolo nella modellazione di sequenze. Il dominio del paper è la traduzione automatica, quindi va citato per l'architettura GRU, non come evidenza sperimentale specifica per HAR.

### Precedente CNN + rete ricorrente per wearable HAR

**Riferimento IEEE**

F. J. Ordóñez and D. Roggen, “Deep Convolutional and LSTM Recurrent Neural Networks for Multimodal Wearable Activity Recognition,” *Sensors*, vol. 16, no. 1, Art. no. 115, 2016, doi: [10.3390/s16010115](https://doi.org/10.3390/s16010115).

Fonte ufficiale: [pagina dell'editore MDPI](https://www.mdpi.com/1424-8220/16/1/115).

**Sostiene nella relazione:** il precedente metodologico di una pipeline end-to-end in cui gli strati convoluzionali estraggono rappresentazioni dai sensori grezzi e quelli ricorrenti modellano la dinamica temporale in wearable HAR. Il paper usa LSTM, non GRU: deve essere presentato come precedente della famiglia CNN-RNN e non come fonte specifica del modello GRU implementato.

### Generalizzazione, obfuscation e spatial cloaking

**Riferimento IEEE**

M. Gruteser and D. Grunwald, “Anonymous Usage of Location-Based Services Through Spatial and Temporal Cloaking,” in *Proc. 1st Int. Conf. Mobile Systems, Applications and Services (MobiSys 2003)*, San Francisco, CA, USA, 2003, pp. 31–42, doi: [10.1145/1066116.1189037](https://doi.org/10.1145/1066116.1189037).

Fonti primarie: [record istituzionale Rutgers](https://www.researchwithrutgers.org/en/publications/anonymous-usage-of-location-based-services-through-spatial-and-te/) e [pagina delle pubblicazioni dell'autore](https://www.winlab.rutgers.edu/~gruteser/Publications.html).

**Sostiene nella relazione:** il principio di ridurre la risoluzione spaziale o temporale delle informazioni di posizione per aumentare la privacy e il conseguente compromesso con l'utilità del servizio.

**Limite importante:** il lavoro propone cloaking adattivo soggetto a vincoli di anonimato. Mobility Diary applica invece uno snapping deterministico al centro di celle di dimensione fissa. La citazione costituisce il fondamento concettuale, ma l'implementazione non deve essere descritta come una realizzazione dell'algoritmo del paper né come garanzia di k-anonimato.

Un riferimento ancora più aderente al termine “obfuscation” e al compromesso privacy/utilità è:

M. Duckham and L. Kulik, “A Formal Model of Obfuscation and Negotiation for Location Privacy,” in *Pervasive Computing, PERVASIVE 2005*, Lecture Notes in Computer Science, vol. 3468, Berlin, Germany: Springer, 2005, pp. 152–170, doi: [10.1007/11428572_10](https://doi.org/10.1007/11428572_10). [Record ufficiale Springer](https://link.springer.com/chapter/10.1007/11428572_10).

Questo secondo paper sostiene l'idea di degradare deliberatamente la qualità dell'informazione di posizione per proteggere la privacy e negoziare il livello di utilità, senza implicare che le metriche `Privacy Perturbation` e `Quality of Service` usate nel progetto siano tratte dal paper.

## Documentazione ufficiale delle tecnologie

Queste fonti sono utili soltanto vicino alle affermazioni tecniche specifiche indicate; non serve citare ogni tecnologia elencata nell'architettura.

### PostGIS

- PostGIS Project, “ST_Length,” *PostGIS Manual*. [Documentazione ufficiale](https://postgis.net/docs/ST_Length.html).
- PostGIS Project, “ST_DWithin,” *PostGIS Manual*. [Documentazione ufficiale](https://postgis.net/docs/ST_DWithin.html).
- PostGIS Project, “PostGIS Geometry/Geography/Box Data Types,” *PostGIS Manual*. [Documentazione ufficiale](https://postgis.net/docs/using_postgis_dbmanagement.html).

**Sostengono nella relazione:** sul tipo `geography`, `ST_Length` effettua il calcolo geodetico e restituisce metri; `ST_DWithin` interpreta la distanza in metri per `geography`, verifica se due oggetti sono entro la soglia e può sfruttare gli indici spaziali. Queste citazioni sono appropriate nella sezione sulle query di distanza e sulle rotte frequenti.

### TimescaleDB

Timescale, “Hypertables,” *Timescale Documentation*. [Documentazione ufficiale](https://docs.timescale.com/use-timescale/latest/hypertables/).

**Sostiene nella relazione:** una hypertable è una tabella PostgreSQL partizionata automaticamente nel tempo in chunk; è quindi adatta alla persistenza delle misure sensoriali indicizzate temporalmente. La documentazione non dimostra da sola che l'istanza del progetto sia configurata correttamente: questo va verificato nel codice e nelle migrazioni.

### Django Ninja

Django Ninja, “Tutorial — First Steps” e “API Docs,” *Official Documentation*. [Tutorial ufficiale](https://django-ninja.dev/tutorial/) e [documentazione OpenAPI](https://django-ninja.dev/guides/api-docs/).

**Sostengono nella relazione:** la definizione delle operazioni HTTP mediante router/decorator e la generazione della documentazione OpenAPI/Swagger UI. Sono utili se la relazione discute esplicitamente questi aspetti; non sono necessarie per il semplice nome del framework.

### Celery

Celery Project, “Introduction to Celery,” *Celery Documentation*. [Documentazione ufficiale](https://docs.celeryq.dev/en/stable/getting-started/introduction.html).

**Sostiene nella relazione:** una task queue distribuisce unità di lavoro a processi worker mediante messaggi e un broker; Celery può usare Redis come trasporto. È il riferimento adatto per il disaccoppiamento tra API sincrona e pipeline asincrona.

### Mapbox

- Mapbox, “Directions API,” *Mapbox API Documentation*. [Documentazione ufficiale](https://docs.mapbox.com/api/navigation/directions/).
- Mapbox, “Geocoding API,” *Mapbox API Documentation*. [Documentazione ufficiale](https://docs.mapbox.com/api/search/geocoding/).

**Sostengono nella relazione:** Directions offre profili distinti per guida, cammino e bicicletta e restituisce rotte tra waypoint; il forward geocoding converte testo di ricerca in coordinate. Vanno citate nella sezione Route Assistant perché descrivono servizi esterni concretamente invocati dal client.

## Inserimento consigliato nella relazione

Priorità minima, per evitare una bibliografia sovraccarica:

1. SHL alla prima descrizione del dataset e nel protocollo di valutazione;
2. Yang et al. nella frase sull'apprendimento automatico delle feature;
3. Cho et al. alla prima descrizione della GRU;
4. Ordóñez e Roggen come precedente CNN-RNN per wearable HAR;
5. Ester et al. alla prima descrizione del clustering DBSCAN;
6. Gruteser e Grunwald oppure Duckham e Kulik nella sezione privacy, accompagnando la citazione con la distinzione tra il concetto generale e lo snapping a griglia implementato;
7. PostGIS nelle affermazioni su `geography`, metri, `ST_Length` e `ST_DWithin`;
8. Mapbox Directions/Geocoding nella descrizione del Route Assistant.

TimescaleDB, Django Ninja e Celery possono essere inseriti dopo questi riferimenti se rimane spazio o se si vogliono documentare formalmente le specifiche tecnologiche. Le misure prodotte dal progetto — accuracy, precision, recall, F1, confusion matrix, benchmark e risultati privacy/QoS — devono invece rimandare al protocollo sperimentale e agli artefatti locali del progetto, non alla documentazione delle librerie.
