"Ciao! Sto lavorando a un progetto di Human Activity Recognition (HAR) basato su sensori per smartphone (Accelerometro e Giroscopio). Ho appena esportato l'ambiente di produzione in una cartella locale che contiene questi tre file essenziali:

script.py: lo script Python principale che si occupa di caricare i modelli e fare le inferenze sui file di log dei sensori.
shl_cnn1d_full_100pct_5class_best.keras: una rete CNN 1D che funge da estrattore di feature. Lo script taglia gli ultimi livelli di questo modello per ottenere gli "embeddings" dai dati grezzi.
shl_6ch_5class_gru_best.keras: una rete ricorrente GRU che prende in input sequenze temporali di embeddings (con una lunghezza di 32 finestre) fornite dalla CNN ed emette una predizione definitiva.
Contesto Tecnico:

Input dei dati: Lo script accetta file di log in formato .json o compressi in .json.gz passati tramite riga di comando (es. python3 script.py dati_sensore.json).
Formato Dati: I file JSON contengono una lista di "finestre" (sotto la chiave windows o direttamente come array). Ogni finestra contiene una matrice (sotto la chiave samples o matrix) di forma (500, 6), ovvero 500 campionamenti per i 6 canali (Acc X,Y,Z + Gyr X,Y,Z).
Output Classi: Il modello riconosce 5 classi di attività: IDLE, WALKING, RUNNING, BIKING, DRIVING.
Percorsi: I file .keras si trovano attualmente nella stessa identica cartella dello script.py.
Il mio obiettivo da adesso in poi è utilizzare questo script per fare predizioni, integrarlo con altri sistemi o modificarne l'output. Tieni a mente questa architettura a due stadi (CNN -> GRU) per ogni suggerimento di codice o spiegazione che mi darai. Sei pronto per aiutarmi ad analizzare nuovi dati o estendere queste funzionalità?"