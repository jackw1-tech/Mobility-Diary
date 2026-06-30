"""Accesso all'object storage S3-compatibile per l'ingestione asincrona.

Il backend non riceve mai i byte pesanti: genera presigned URL e il mobile
carica i blob direttamente sullo storage (REPORT_STRATEGIA_INGESTION_ASINCRONA.md
D7). Qui vivono le sole operazioni leggere: generare presigned PUT, verificare
un oggetto via HEAD, leggerlo (lato Celery) e cancellarlo (predisposto ma
gated da HAR_CLEANUP_ENABLED, vedi D9).

Due client distinti:
  - interno: backend e Celery parlano allo storage sulla rete privata
    (es. http://minio:9000);
  - pubblico: i presigned PUT devono puntare all'host che il MOBILE riesce a
    raggiungere (in locale l'IP LAN del Mac). La firma S3 e' legata all'host,
    quindi il presign usa un client configurato sull'endpoint pubblico.
In deploy (Railway Buckets) i due endpoint coincidono.
"""
from __future__ import annotations

from functools import lru_cache

import boto3
from botocore.client import Config
from django.conf import settings


def _build_client(endpoint_url: str):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=settings.S3_ACCESS_KEY_ID,
        aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY,
        region_name=settings.S3_REGION,
        # MinIO richiede path-style addressing e Signature V4.
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


@lru_cache(maxsize=1)
def _internal_client():
    return _build_client(settings.S3_ENDPOINT_URL)


@lru_cache(maxsize=1)
def _public_client():
    return _build_client(settings.S3_PUBLIC_ENDPOINT_URL)


def bucket_name() -> str:
    return settings.S3_BUCKET_NAME


def presigned_put_url(
    object_key: str,
    *,
    sha256: str,
    content_type: str = "application/gzip",
) -> str:
    """URL firmato per un PUT diretto del mobile sullo storage."""
    return _public_client().generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": bucket_name(),
            "Key": object_key,
            "ContentType": content_type,
            "Metadata": {"sha256": sha256},
        },
        ExpiresIn=settings.S3_PRESIGN_EXPIRES_SECONDS,
    )


def head_object(object_key: str) -> dict | None:
    """Metadata dell'oggetto (ContentLength, ETag, ...) o None se assente.

    Usato in 'confirm' per verificare che il blob sia davvero arrivato e con la
    dimensione attesa, senza scaricare i byte.
    """
    client = _internal_client()
    try:
        return client.head_object(Bucket=bucket_name(), Key=object_key)
    except client.exceptions.ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code")
        if error_code in {"404", "NoSuchKey", "NotFound"}:
            return None
        raise


def read_object(object_key: str) -> bytes:
    """Scarica i byte di un oggetto (lato Celery, durante il processing)."""
    response = _internal_client().get_object(Bucket=bucket_name(), Key=object_key)
    return response["Body"].read()


def write_object(
    object_key: str,
    body: bytes,
    *,
    sha256: str,
    content_type: str = "application/gzip",
) -> None:
    """Scrive un oggetto raw rigenerato lato backend."""
    _internal_client().put_object(
        Bucket=bucket_name(),
        Key=object_key,
        Body=body,
        ContentType=content_type,
        Metadata={"sha256": sha256},
    )


def delete_object(object_key: str) -> None:
    """Cancella un oggetto appena scritto quando una transazione DB fallisce."""
    _internal_client().delete_object(Bucket=bucket_name(), Key=object_key)


def delete_objects(object_keys: list[str]) -> None:
    """Cancella oggetti raw. CONGELATO: no-op finche' HAR_CLEANUP_ENABLED e' False.

    La cancellazione event-driven post-HAR e' predisposta ma disattivata
    (REPORT D9): i blob raw NON vanno mai cancellati finche' HAR non e' operativo.
    """
    if not settings.HAR_CLEANUP_ENABLED or not object_keys:
        return
    _internal_client().delete_objects(
        Bucket=bucket_name(),
        Delete={"Objects": [{"Key": key} for key in object_keys]},
    )
