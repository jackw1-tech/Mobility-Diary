from __future__ import annotations

import base64
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

# Nome del file
def raw_part_object_key(base_path: str, sequence: int) -> str:
    return f"{base_path}sensor_windows_part_{sequence:04d}.json.gz"



def checksum_header_value(sha256_hex: str) -> str:
    return base64.b64encode(bytes.fromhex(sha256_hex)).decode("ascii")


def presigned_put_url(
    object_key: str,
    *,
    sha256: str,
    content_type: str = "application/gzip",
) -> str:
    return _public_client().generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": bucket_name(),
            "Key": object_key,
            "ContentType": content_type,
            "ChecksumSHA256": checksum_header_value(sha256),
        },
        ExpiresIn=settings.S3_PRESIGN_EXPIRES_SECONDS,
    )

# Chiamata HEAD; ci dice se l'oggetto esiste e dà i metadati
def head_object(object_key: str) -> dict | None:
    client = _internal_client()
    try:
        return client.head_object(
            Bucket=bucket_name(), Key=object_key, ChecksumMode="ENABLED"
        )
    except client.exceptions.ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code")
        if error_code in {"404", "NoSuchKey", "NotFound"}:
            return None
        raise


def read_object(object_key: str) -> bytes:
    response = _internal_client().get_object(Bucket=bucket_name(), Key=object_key)
    return response["Body"].read()


# Scrittura sullo storage
def write_object(
    object_key: str,
    body: bytes,
    *,
    sha256: str,
    content_type: str = "application/gzip",
) -> None:
    _internal_client().put_object(
        Bucket=bucket_name(),
        Key=object_key,
        Body=body,
        ContentType=content_type,
        Metadata={"sha256": sha256},
    )


def delete_object(object_key: str) -> None:
    _internal_client().delete_object(Bucket=bucket_name(), Key=object_key)


