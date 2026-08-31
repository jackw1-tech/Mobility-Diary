"""Servizio HAR remoto (Modal) per la classificazione di una singola finestra.

NON fa parte del backend Django/Celery: e' un deploy separato e indipendente,
una SECONDA copia del modello fuso (shl_har_fused.keras), caricata su
un'infrastruttura Modal con GPU, raggiungibile dal backend via HTTP.

Replica fedelmente la logica di `manual_har/inference.py` (HARClassifier),
ma per l'uso singola-finestra del Route Assistant (Live/Replay): una
richiesta = una finestra 500x6, non un batch di un intero viaggio.

Deploy (da questa cartella):
    pip install modal
    modal setup                      # autenticazione, una tantum
    modal deploy app.py

Il comando stampa l'URL dell'endpoint. Impostalo poi lato Django:
    MODAL_HAR_CLASSIFY_URL=https://<tuo-account>--har-classify-classify.modal.run

Finche' quella variabile resta vuota, il backend continua a usare SOLO il
modello locale (comportamento invariato) — vedi `mobility/ml/har_adapter.py`.
"""

import modal

CLASS_NAMES = ("IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE")
SEQ_LEN = 128  # deve combaciare con HAR_FUSED_SEQUENCE_LENGTH lato Django

app = modal.App("har-classify")

# Il file .keras (8.4MB) viene incluso nell'immagine al momento del deploy,
# leggendolo dalla stessa copia gia' usata dal backend Django (nessun
# duplicato da tenere sincronizzato manualmente). Se lanci `modal deploy` da
# una cartella diversa da questa, aggiusta il path.
MODEL_LOCAL_PATH = "../ninja/manual_har/shl_har_fused.keras"
MODEL_CONTAINER_PATH = "/models/shl_har_fused.keras"

image = (
    modal.Image.debian_slim(python_version="3.12")
    # Pinna la stessa major/minor di TensorFlow usata dal backend
    # (requirements.txt: tensorflow>=2.16,<3.0) per evitare risultati
    # numericamente diversi tra locale e remoto.
    .pip_install("tensorflow>=2.16,<3.0", "numpy>=2.0,<3.0", "fastapi[standard]")
    .add_local_file(MODEL_LOCAL_PATH, MODEL_CONTAINER_PATH)
)


@app.cls(image=image, gpu="T4", scaledown_window=120)
class HarClassifyService:
    """Una sola istanza per container: il modello viene caricato e
    "riscaldato" (primo trace del grafo) una volta sola all'avvio del
    container (`@modal.enter`), non ad ogni richiesta — stesso principio del
    warmup che gia' fate lato Celery in `tasks.py`."""

    @modal.enter()
    def load_model(self):
        import numpy as np
        import tensorflow as tf

        self._np = np
        self.model = tf.keras.models.load_model(MODEL_CONTAINER_PATH, compile=False)

        @tf.autograph.experimental.do_not_convert
        def infer(x):
            return self.model(x, training=False)

        self._infer = tf.function(
            infer,
            input_signature=[
                tf.TensorSpec(shape=[None, SEQ_LEN, 500, 6], dtype=tf.float32)
            ],
        )
        # Forza la compilazione ora, non alla prima richiesta reale.
        self._infer(tf.zeros((1, SEQ_LEN, 500, 6), dtype=tf.float32))

    @modal.fastapi_endpoint(method="POST")
    def classify(self, payload: dict) -> dict:
        import tensorflow as tf

        np = self._np
        samples = payload.get("samples")
        matrix = np.asarray(samples, dtype=np.float32)
        if matrix.ndim != 2 or matrix.shape != (500, 6):
            return {"error": f"forma attesa (500, 6), ricevuta {matrix.shape}"}

        # Una finestra sola: pad a SEQ_LEN come richiesto dalla firma fissa
        # del grafo compilato (stessa tecnica di manual_har/inference.py).
        padded = np.concatenate([matrix[None, :, :], np.zeros((SEQ_LEN - 1, 500, 6), np.float32)])
        sequence = padded.reshape(1, SEQ_LEN, 500, 6)

        probs = self._infer(tf.constant(sequence)).numpy()
        probs = probs.reshape(SEQ_LEN, len(CLASS_NAMES))[0]
        idx = int(np.argmax(probs))

        return {"label": CLASS_NAMES[idx], "confidence": float(probs[idx])}
