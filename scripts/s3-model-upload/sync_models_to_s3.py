#!/usr/bin/env python3

"""Download the project's pinned Hugging Face models and synchronize them to S3."""

import hashlib
import json
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import boto3
from boto3.s3.transfer import TransferConfig
from botocore.exceptions import ClientError
from huggingface_hub import snapshot_download


# Project-owned destination.
AWS_REGION = "eu-west-1"
AWS_ACCOUNT_ID = "538578370232"
ENVIRONMENT = "dev"

S3_BUCKET = "ai-inference-models-dev-538578370232"

# Limit parallel work to avoid excessive local disk and network contention.
UPLOAD_WORKERS = 8

# Immutable revisions make model synchronization reproducible.
MODELS = (
    {
        "model_id": "casperhansen/deepseek-r1-distill-qwen-14b-awq",
        "revision": "bc43ec1bbf08de53452630806d5989208b4186db",
        "s3_prefix": "models/deepseek-14b-awq",
    },
    {
        "model_id": "casperhansen/deepseek-r1-distill-qwen-7b-awq",
        "revision": "305e6f12907dc78ae61a1f0bb7a19faa2b25e8a3",
        "s3_prefix": "models/deepseek-7b-awq",
    },
)


def calculate_sha256(file_path: Path) -> str:
    """Calculate a stable content hash for one model file."""

    digest = hashlib.sha256()

    # Read large model files in chunks instead of loading them into memory.
    with file_path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()


def object_matches(
    s3_client: Any,
    object_key: str,
    file_size: int,
    sha256: str,
) -> bool:
    """Return whether S3 already contains the same file."""

    try:
        response = s3_client.head_object(
            Bucket=S3_BUCKET,
            Key=object_key,
        )
    except ClientError as error:
        error_code = error.response["Error"]["Code"]

        # A missing object needs uploading; other AWS errors must stop the run.
        if error_code in {"404", "NoSuchKey", "NotFound"}:
            return False

        raise

    # Size and SHA-256 metadata together provide an idempotent file check.
    return (
        response["ContentLength"] == file_size
        and response.get("Metadata", {}).get("sha256") == sha256
    )


def manifest_matches_revision(
    s3_client: Any,
    s3_prefix: str,
    revision: str,
) -> bool:
    """Return whether S3 has a completion manifest for the configured revision."""

    manifest_key = f"{s3_prefix}/_MANIFEST.json"

    try:
        response = s3_client.head_object(
            Bucket=S3_BUCKET,
            Key=manifest_key,
        )
    except ClientError as error:
        error_code = error.response["Error"]["Code"]

        if error_code in {"404", "NoSuchKey", "NotFound"}:
            return False

        raise

    return response.get("Metadata", {}).get("revision") == revision


def upload_model_file(
    s3_client: Any,
    transfer_config: TransferConfig,
    snapshot_path: Path,
    file_path: Path,
    s3_prefix: str,
) -> dict[str, Any]:
    """Upload one file unless an identical S3 object already exists."""

    relative_path = file_path.relative_to(snapshot_path).as_posix()
    object_key = f"{s3_prefix}/{relative_path}"
    file_size = file_path.stat().st_size
    sha256 = calculate_sha256(file_path)

    if object_matches(s3_client, object_key, file_size, sha256):
        status = "skipped"
    else:
        # Store the hash as metadata so future runs can skip unchanged files.
        s3_client.upload_file(
            str(file_path),
            S3_BUCKET,
            object_key,
            ExtraArgs={
                "Metadata": {
                    "sha256": sha256,
                }
            },
            Config=transfer_config,
        )
        status = "uploaded"

    print(f"{status:8} s3://{S3_BUCKET}/{object_key}")

    # File details are collected for the final completion manifest.
    return {
        "path": relative_path,
        "size": file_size,
        "sha256": sha256,
    }


def download_snapshot(
    model_id: str,
    revision: str,
    download_root: Path,
) -> Path:
    """Download one exact Hugging Face model revision."""

    print(f"\nDownloading {model_id}@{revision}")

    # Both repositories are public, so no Hugging Face token is required.
    snapshot_path = snapshot_download(
        repo_id=model_id,
        revision=revision,
        local_dir=download_root / "snapshot",
        cache_dir=download_root / "cache",
        max_workers=UPLOAD_WORKERS,
    )

    return Path(snapshot_path)


def find_model_files(snapshot_path: Path) -> list[Path]:
    """Find model artifacts while excluding local Hugging Face metadata."""

    return sorted(
        file_path
        for file_path in snapshot_path.rglob("*")
        if file_path.is_file()
        and ".cache" not in file_path.relative_to(snapshot_path).parts
    )


def upload_snapshot(
    s3_client: Any,
    transfer_config: TransferConfig,
    snapshot_path: Path,
    s3_prefix: str,
) -> list[dict[str, Any]]:
    """Upload every file from a downloaded model snapshot."""

    model_files = find_model_files(snapshot_path)
    uploaded_files: list[dict[str, Any]] = []

    print(f"Synchronizing {len(model_files)} files to s3://{S3_BUCKET}/{s3_prefix}")

    # Files upload concurrently, while each individual transfer uses one thread.
    with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as executor:
        futures = [
            executor.submit(
                upload_model_file,
                s3_client,
                transfer_config,
                snapshot_path,
                file_path,
                s3_prefix,
            )
            for file_path in model_files
        ]

        # Calling result propagates any failed upload and prevents a manifest.
        for future in as_completed(futures):
            uploaded_files.append(future.result())

    return uploaded_files


def write_manifest(
    s3_client: Any,
    model_id: str,
    revision: str,
    s3_prefix: str,
    uploaded_files: list[dict[str, Any]],
) -> None:
    """Write the completion manifest after all model files succeed."""

    manifest = {
        "schema_version": 1,
        "model_id": model_id,
        "revision": revision,
        "uploaded_at": datetime.now(UTC).isoformat(),
        "file_count": len(uploaded_files),
        "total_size": sum(file["size"] for file in uploaded_files),
        "files": sorted(
            uploaded_files,
            key=lambda file: file["path"],
        ),
    }
    manifest_key = f"{s3_prefix}/_MANIFEST.json"

    # The manifest is written last and acts as the successful-sync marker.
    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key=manifest_key,
        Body=json.dumps(manifest, indent=2).encode(),
        ContentType="application/json",
        Metadata={
            "revision": revision,
        },
    )

    print(f"complete s3://{S3_BUCKET}/{s3_prefix}")
    print(f"manifest s3://{S3_BUCKET}/{manifest_key}")


def sync_model(
    s3_client: Any,
    transfer_config: TransferConfig,
    model: dict[str, str],
) -> None:
    """Download, upload, and record one configured model."""

    model_id = model["model_id"]
    revision = model["revision"]
    s3_prefix = model["s3_prefix"]

    if manifest_matches_revision(s3_client, s3_prefix, revision):
        print(f"\nSkipping {model_id}@{revision}; completion manifest already exists")
        return

    # Temporary model data is removed after this model finishes syncing.
    with tempfile.TemporaryDirectory(prefix="hf-model-") as temporary_directory:
        snapshot_path = download_snapshot(
            model_id,
            revision,
            Path(temporary_directory),
        )
        uploaded_files = upload_snapshot(
            s3_client,
            transfer_config,
            snapshot_path,
            s3_prefix,
        )

    write_manifest(
        s3_client,
        model_id,
        revision,
        s3_prefix,
        uploaded_files,
    )


def main() -> None:
    """Synchronize both project models using the standard AWS credential chain."""

    # Boto3 discovers credentials from environment variables, profiles, or IAM.
    session = boto3.Session(region_name=AWS_REGION)
    s3_client = session.client("s3")

    # Outer file concurrency handles parallelism, so each transfer stays single-threaded.
    transfer_config = TransferConfig(
        max_concurrency=1,
        use_threads=False,
    )

    # Models are processed sequentially to limit temporary disk consumption.
    for model in MODELS:
        sync_model(
            s3_client,
            transfer_config,
            model,
        )

    print("\nBoth models synchronized successfully.")


if __name__ == "__main__":
    main()
