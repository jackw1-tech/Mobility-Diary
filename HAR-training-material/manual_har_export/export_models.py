import os
import sys

def copy_with_progress(src, dst):
    if not os.path.exists(src):
        print(f"Errore: il file sorgente non esiste -> {src}")
        return

    # Crea le cartelle di destinazione se non esistono
    os.makedirs(os.path.dirname(dst), exist_ok=True)

    file_size = os.path.getsize(src)
    if file_size == 0:
        print(f"File vuoto: {src}")
        return

    copied = 0
    chunk_size = 1024 * 1024 * 5 # 5 MB chunks

    with open(src, 'rb') as fsrc, open(dst, 'wb') as fdst:
        while True:
            buf = fsrc.read(chunk_size)
            if not buf:
                break
            fdst.write(buf)
            copied += len(buf)
            
            percent = min(100.0, (copied / file_size) * 100)
            sys.stdout.write(f"\rCopia di {os.path.basename(src)}... {percent:.1f}% completo")
            sys.stdout.flush()
    print("\nCompletato.")

def main():
    # Percorsi sorgente (assoluti o relativi da dove si lancia lo script)
    base_dir = "/Volumes/Extreme SSD/HAR"
    
    src_script = os.path.join(base_dir, "manual_har/script.py")
    src_cnn = os.path.join(base_dir, "models_5class/shl_cnn1d_full_100pct_5class_best.keras")
    src_gru = os.path.join(base_dir, "models_gru/shl_6ch_5class_gru_best.keras")

    # Percorso destinazione
    target_dir = "/Users/giacomobianco/Downloads/Mobility-Diary/manual_har"
    
    # Crea la directory di destinazione
    os.makedirs(target_dir, exist_ok=True)
    
    # Definisci i percorsi di destinazione (mettiamo tutto nella stessa cartella per comodità)
    dst_script = os.path.join(target_dir, "script.py")
    dst_cnn = os.path.join(target_dir, "shl_cnn1d_full_100pct_5class_best.keras")
    dst_gru = os.path.join(target_dir, "shl_6ch_5class_gru_best.keras")

    print(f"Inizio esportazione in: {target_dir}\n")

    # 1. Copia i file fisici
    copy_with_progress(src_cnn, dst_cnn)
    copy_with_progress(src_gru, dst_gru)
    copy_with_progress(src_script, dst_script)

    # 2. Modifica i percorsi nel nuovo script.py affinché funzioni direttamente
    print("\nAggiornamento dei percorsi dei modelli all'interno del nuovo script.py...")
    try:
        with open(dst_script, 'r', encoding='utf-8') as f:
            script_content = f.read()

        # Dato che i modelli ora sono nella stessa cartella dello script, modifichiamo i percorsi
        script_content = script_content.replace(
            "../models_5class/shl_cnn1d_full_100pct_5class_best.keras", 
            "shl_cnn1d_full_100pct_5class_best.keras"
        )
        script_content = script_content.replace(
            "../models_gru/shl_6ch_5class_gru_best.keras", 
            "shl_6ch_5class_gru_best.keras"
        )

        with open(dst_script, 'w', encoding='utf-8') as f:
            f.write(script_content)
            
        print("Percorsi aggiornati con successo! Il nuovo script è pronto all'uso.")
    except Exception as e:
        print(f"Errore durante l'aggiornamento dello script: {e}")

    print("\n--- ESPORTAZIONE COMPLETATA ---")
    print(f"Tutti i file sono ora pronti in: {target_dir}")

if __name__ == "__main__":
    main()
