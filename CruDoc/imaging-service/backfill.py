#!/usr/bin/env python3
"""
Backfill script for progressive radiology viewing files for existing scans.

Usage:
  python backfill.py --doctor <uid> [--dry-run]
  python backfill.py --doctor <uid> --run
"""

import argparse
import os
import sys
from google.cloud import storage, firestore

from main import process_finalized, is_imaging_path, get_view_id


def parse_args(args: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Backfill progressive radiology viewing files for existing scans."
    )
    parser.add_argument(
        "--doctor",
        required=True,
        help="Doctor UID to backfill scans for.",
    )
    parser.add_argument(
        "--dry-run",
        dest="dry_run",
        action="store_true",
        default=True,
        help="Perform a dry run without modifying data or converting images (default).",
    )
    parser.add_argument(
        "--run",
        dest="dry_run",
        action="store_false",
        help="Actually run the backfill conversion.",
    )
    parser.add_argument(
        "--bucket",
        default=os.environ.get("STORAGE_BUCKET", os.environ.get("BUCKET", "svayatta-crudoc-dev.firebasestorage.app")),
        help="Cloud Storage bucket name (default: svayatta-crudoc-dev.firebasestorage.app).",
    )
    return parser.parse_args(args)


def main() -> None:
    args = parse_args()
    doctor_id = args.doctor
    bucket_name = args.bucket
    dry_run = args.dry_run

    storage_client = storage.Client()
    db = firestore.Client()

    prefix = f"doctors/{doctor_id}/patients/"
    blobs = storage_client.list_blobs(bucket_name, prefix=prefix)
    original_blobs = [b for b in blobs if is_imaging_path(b.name)]
    total_originals = len(original_blobs)

    if dry_run:
        already_ready = 0
        doc_refs = [
            db.collection("radiology_views").document(get_view_id(b.name))
            for b in original_blobs
        ]

        chunk_size = 100
        for i in range(0, len(doc_refs), chunk_size):
            chunk = doc_refs[i:i + chunk_size]
            for doc in db.get_all(chunk):
                if doc.exists:
                    data = doc.to_dict() or {}
                    if data.get("status") == "ready":
                        already_ready += 1

        to_convert = total_originals - already_ready
        print(f"Total originals: {total_originals}")
        print(f"Already ready: {already_ready}")
        print(f"To convert: {to_convert}")
    else:
        ready_count = 0
        skipped_count = 0
        failed_count = 0

        for idx, blob in enumerate(original_blobs, start=1):
            print(f"[{idx}/{total_originals}] {blob.name}")
            content_type = blob.content_type
            if not content_type and blob.name.lower().endswith(".dcm"):
                content_type = "application/dicom"

            generation_str = str(blob.generation) if blob.generation is not None else ""
            status = process_finalized(bucket_name, blob.name, generation_str, content_type)
            if status == "ready":
                ready_count += 1
            elif status == "skipped":
                skipped_count += 1
            else:
                failed_count += 1

        print(f"Ready: {ready_count}")
        print(f"Skipped: {skipped_count}")
        print(f"Failed: {failed_count}")


if __name__ == "__main__":
    main()
