#!/usr/bin/env python3


from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.layers import GRU, Bidirectional, Dense, Dropout, Input, TimeDistributed
from tensorflow.keras.models import Model

# preprocessing.py e metrics.py sono condivisi al livello superiore.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from preprocessing import CLASS_NAMES
from metrics import confusion_matrix, classification_metrics

#Calcola pesi diversi per ogni classe ma in più li normalizza intorno a 1
def compute_class_weights(y: np.ndarray, num_classes: int) -> np.ndarray:
    counts = np.bincount(y.astype(np.int64), minlength=num_classes)
    total = counts.sum()
    alpha = total / (num_classes * np.maximum(counts, 1))
    return (alpha / alpha.mean()).astype(np.float32) 


def load_split(data_dir: Path, prefix: str, split: str):
    X = np.load(data_dir / f"{prefix}_{split}_X.npy", mmap_mode="r")
    y = np.load(data_dir / f"{prefix}_{split}_y.npy")
    return X, y


def embedding_extractor(cnn: tf.keras.Model) -> tf.keras.Model:
    return Model(cnn.inputs, cnn.layers[-3].output)


#(N,500,6) -> (N,128) Embeddings
def embed_6ch(extractor: tf.keras.Model, X, batch_size: int, mean, std) -> np.ndarray:
    N = X.shape[0]
    embs = []
    for i in range(0, N, batch_size):
        chunk = X[i : i + batch_size].copy()
        chunk_unnorm = chunk * std + mean
        e = extractor.predict(chunk_unnorm, verbose=0)
        embs.append(e)
    return np.concatenate(embs, axis=0).astype(np.float32)


# ritaglio in spezzoni gli embedding da 64 finestre (5 minuti) (Slinding window con overlap del 50 %)
def make_train_sequences(emb, y, blocks, L, stride):
    xs, ys = [], []
    for s, e in blocks:
        n = e - s
        for i in range(0, max(1, n - L + 1), stride):
            seg_x = emb[s + i: s + i + L]
            seg_y = y[s + i: s + i + L]
            if len(seg_x) < L:  # pad tail
                pad = L - len(seg_x)
                seg_x = np.concatenate([seg_x, np.zeros((pad, emb.shape[1]), emb.dtype)])
                seg_y = np.concatenate([seg_y, np.zeros(pad, y.dtype)])
            xs.append(seg_x)
            ys.append(seg_y)
    return np.asarray(xs), np.asarray(ys)


# ritaglio in spezzoni gli embedding da 64 finestre (5 minuti) senza overlapping -> per il test
def make_eval_sequences(emb, blocks, L):
    xs, meta = [], []
    for s, e in blocks:
        n = e - s
        for i in range(0, n, L):
            seg = emb[s + i: s + i + L]
            valid = len(seg)
            if valid < L:
                seg = np.concatenate([seg, np.zeros((L - valid, emb.shape[1]), emb.dtype)])
            xs.append(seg)
            meta.append((s + i, valid))
    return np.asarray(xs), meta


def sequence_focal_loss(alpha, gamma=2.0):
    alpha_t = tf.constant(alpha, dtype=tf.float32)

    def loss(y_true, y_pred):
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        y_pred = tf.clip_by_value(tf.reshape(y_pred, [-1, tf.shape(y_pred)[-1]]), 1e-7, 1 - 1e-7)
        p_t = tf.gather(y_pred, y_true, batch_dims=1)
        a_t = tf.gather(alpha_t, y_true)
        return tf.reduce_mean(a_t * tf.pow(1.0 - p_t, gamma) * (-tf.math.log(p_t)))

    return loss


def build_gru(L, emb_dim, num_classes, units=64):
    #64 x 128
    inp = Input(shape=(L, emb_dim))
    # 64 x 128  (64 avanti + 64 indietro, concatenati)
    x = Bidirectional(GRU(units, return_sequences=True))(inp)
    # 64 x 128 con il 30% di zeri
    x = Dropout(0.3)(x)
    #  64 x 5
    out = TimeDistributed(Dense(num_classes, activation="softmax"))(x)
    return Model(inp, out)


DATA_DIR = REPO_ROOT / "processed_6ch"
PREFIX = "shl_6ch_5class"
CNN_PATH = REPO_ROOT / "cnn 1d" / "models_5class" / "shl_cnn1d_full_100pct_5class_best.keras"
OUT_DIR = Path(__file__).resolve().parent / "models_gru"
SEQ_LEN = 64
EPOCHS = 30
BATCH_SIZE = 64
PATIENCE = 6
SEED = 50


def main():
    tf.keras.utils.set_random_seed(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    num_classes = len(CLASS_NAMES)
    L = SEQ_LEN

    meta = json.loads((DATA_DIR / f"{PREFIX}_meta.json").read_text())
    norm_stats = json.loads((DATA_DIR / f"{PREFIX}_norm_stats.json").read_text())
    mean = np.array(norm_stats["mean"], dtype=np.float32)
    std = np.array(norm_stats["std"], dtype=np.float32)

    train_blocks = meta["train_position_boundaries"]["train"]
    val_blocks = meta["train_position_boundaries"]["validation"]
    test_blocks = [[s, e] for s, e, _ in meta["test_position_boundaries"]]

    
    cnn = tf.keras.models.load_model(CNN_PATH, compile=False)
    extractor = embedding_extractor(cnn) #Carica la CNN pre addestrata ma tagliata (Dense128)

    X_train, y_train = load_split(DATA_DIR, PREFIX, "train")
    X_val, y_val = load_split(DATA_DIR, PREFIX, "validation")
    X_test, y_test = load_split(DATA_DIR, PREFIX, "test")

    emb_batch = BATCH_SIZE * 16
    emb_train = embed_6ch(extractor, X_train, emb_batch, mean, std)
    emb_val = embed_6ch(extractor, X_val, emb_batch, mean, std)
    emb_test = embed_6ch(extractor, X_test, emb_batch, mean, std)
    emb_dim = emb_train.shape[1] #128

    
    Xtr, ytr = make_train_sequences(emb_train, y_train, train_blocks, L, stride=L // 2) # raddoppio i dati per il training
    Xval, yval = make_train_sequences(emb_val, y_val, val_blocks, L, stride=L)
    
    alpha = compute_class_weights(y_train, num_classes)
    model = build_gru(L, emb_dim, num_classes)
    model.compile(optimizer="adam", loss=sequence_focal_loss(alpha), metrics=["accuracy"])
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=PATIENCE, restore_best_weights=True),
        tf.keras.callbacks.ModelCheckpoint(OUT_DIR / "shl_6ch_5class_gru_best.keras",
                                           monitor="val_accuracy", save_best_only=True),
    ]
    model.fit(Xtr, ytr, validation_data=(Xval, yval), epochs=EPOCHS,
              batch_size=BATCH_SIZE, callbacks=callbacks, shuffle=True)

  
    Xev, ev_meta = make_eval_sequences(emb_test, test_blocks, L)
    probs = model.predict(Xev, batch_size=BATCH_SIZE, verbose=1)
    seq_pred = np.argmax(probs, axis=-1)

    y_pred = np.empty(len(y_test), dtype=np.int64)
    for (gstart, valid), row in zip(ev_meta, seq_pred):
        y_pred[gstart:gstart + valid] = row[:valid]

    np.save(OUT_DIR / "shl_6ch_5class_gru_test_pred.npy", y_pred)
    matrix = confusion_matrix(y_test, y_pred, num_classes)
    metrics = classification_metrics(matrix, CLASS_NAMES)

    (OUT_DIR / "result_training_gru.json").write_text(json.dumps(metrics, indent=2))
    np.save(OUT_DIR / "shl_6ch_5class_gru_confusion_matrix.npy", matrix)

if __name__ == "__main__":
    main()
