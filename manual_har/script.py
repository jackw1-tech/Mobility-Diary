import json
import numpy as np
import tensorflow as tf
import sys

# 1. Carica i file JSON che hai esportato
# Permette di passare più file da terminale (es: python3 script.py file1.json file2.json)
if len(sys.argv) > 1:
    file_paths = sys.argv[1:]
else:
    print("Per favore, specifica i file da analizzare. Esempio: python3 script.py file1.json file2.json")
    sys.exit(1)

import gzip

finestre = []
for percorso_file in file_paths:
    print(f"Caricamento {percorso_file}...")
    
    # Supporta sia file .json puri che file compressi .json.gz
    if percorso_file.endswith('.gz'):
        with gzip.open(percorso_file, 'rt', encoding='utf-8') as f:
            dati_json = json.load(f)
    else:
        with open(percorso_file, 'r', encoding='utf-8') as f:
            dati_json = json.load(f)
    
    # Gestisce il nuovo formato {"windows": [...]} e fa da fallback al vecchio formato array
    if isinstance(dati_json, dict) and 'windows' in dati_json:
        finestre.extend(dati_json['windows'])
    else:
        finestre.extend(dati_json)

print(f"Trovate {len(finestre)} finestre sensore totali nei file caricati.")

# 2. Estrai i dati dei sensori da ogni finestra
dati_grezzi = []
for finestra in finestre:
    # Usa 'samples' per il nuovo formato, 'matrix' per il vecchio
    if 'samples' in finestra:
        matrice = finestra['samples']
    else:
        matrice = finestra['matrix']
    dati_grezzi.append(matrice)

# Convertiamo in formato tensore (N_finestre, 500, 6) prendendo solo i primi 6 canali (Acc + Gyr)
X_grezzo = np.array(dati_grezzi, dtype=np.float32)[:, :, :6]
print("Forma dei dati (Shape) dopo aver scartato il magnetometro:", X_grezzo.shape)

# Nessuna normalizzazione manuale: il modello a 6 canali usa layer di BatchNormalization interni
X_norm = X_grezzo

# 4. Carica la pipeline CNN (a 6 canali) + GRU
try:
    print("Caricamento estrattore CNN (6 canali) e nuovo modello GRU...")
    cnn = tf.keras.models.load_model('shl_cnn1d_full_100pct_5class_best.keras', compile=False)
    from tensorflow.keras.models import Model
    # La GRU ha bisogno degli embedding (layer -3 della CNN)
    extractor = Model(cnn.inputs, cnn.layers[-3].output)
    
    gru = tf.keras.models.load_model('shl_6ch_5class_gru_best.keras', compile=False)
    print("Modelli caricati con successo!")
    
    # 1) Estrai le features con la CNN
    print("Estrazione feature in corso...")
    embeddings = extractor.predict(X_norm)
    
    # 2) Fai predizioni con la GRU (che si aspetta sequenze da 32 finestre)
    L = 32
    valid_len = len(embeddings)
    labels = np.zeros(valid_len, dtype=int)
    all_probs = np.zeros((valid_len, 5), dtype=float)
    
    print("Predizione temporale GRU in corso...")
    for i in range(0, valid_len, L):
        seg = embeddings[i : i + L]
        cur_len = len(seg)
        # Se la sequenza è più corta di 32, aggiungiamo del padding (zeri) per completarla
        if cur_len < L:
            seg = np.concatenate([seg, np.zeros((L - cur_len, embeddings.shape[1]), embeddings.dtype)])
        
        # Esegui predizione
        pred_seq = gru.predict(np.expand_dims(seg, axis=0))[0] # shape (32, 5 classi)
        
        # Salva le label predette e le probabilità
        labels[i : i + cur_len] = np.argmax(pred_seq[:cur_len], axis=1)
        all_probs[i : i + cur_len] = pred_seq[:cur_len]
    
    # 5. Mappa l'output numerico all'attività reale
    # Sostituisci questi nomi con quelli esatti che hai usato in fase di train (es. 0: IDLE, 1: WALKING, ecc.)
    classi = ['IDLE', 'WALKING', 'RUNNING', 'BIKING', 'DRIVING'] 
    
    print("\n--- RISULTATI DELLA TUA SESSIONE REALE ---")
    for i, label_id in enumerate(labels):
        attivita = classi[label_id]
        probs = all_probs[i]
        top_3_idx = np.argsort(probs)[-3:][::-1]
        top_3_str = " | ".join([f"{classi[idx]}: {probs[idx]*100:.1f}%" for idx in top_3_idx])
        
        # Supporta sia il nuovo formato ("window_start") che il vecchio ("start")
        if 'window_start' in finestre[i]:
            orario_inizio = finestre[i]['window_start']
        elif 'start' in finestre[i]:
            orario_inizio = finestre[i]['start']
        else:
            orario_inizio = "Sconosciuto"
            
        print(f"[{orario_inizio}] Rilevato: {attivita}  ({top_3_str})")
        
except FileNotFoundError:
    print("Modello shl_9ch_5class_gru_best.keras non trovato. Assicurati che esista in ../models_gru/")
