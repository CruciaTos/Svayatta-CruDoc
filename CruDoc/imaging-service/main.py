import os
import re
import time
import hashlib
import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import storage, firestore
import google.api_core.exceptions

from convert import build_view

PATH_PATTERN = re.compile(r"^doctors/([^/]+)/patients/([^/]+)/clinical/imaging/(.+)$")

_storage_client: storage.Client | None = None
_firestore_client: firestore.Client | None = None

def _storage() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client

def _db() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _firestore_client = firestore.Client()
    return _firestore_client

def is_imaging_path(name: str) -> bool:
    """True if name matches ^doctors/([^/]+)/patients/([^/]+)/clinical/imaging/(.+)$"""
    return bool(PATH_PATTERN.match(name))

def parse_imaging_path(name: str) -> tuple[str, str, str] | None:
    m = PATH_PATTERN.match(name)
    if not m:
        return None
    return m.group(1), m.group(2), m.group(3)

def get_view_id(name: str) -> str:
    """Lowercase hex SHA-256 of the storage path string."""
    return hashlib.sha256(name.encode("utf-8")).hexdigest().lower()

def process_finalized(bucket_name: str, name: str, generation: str, content_type: str | None) -> str:
    t0 = time.perf_counter()
    parsed = parse_imaging_path(name)
    if not parsed:
        return "skipped"
    doctor_id, patient_id, filename = parsed

    view_id = get_view_id(name)
    doc_ref = _db().collection("radiology_views").document(view_id)

    # Idempotency check: if doc exists with same generation and status ready/skipped, return
    snap = doc_ref.get()
    if snap.exists:
        data = snap.to_dict() or {}
        if str(data.get("sourceGeneration")) == str(generation) and data.get("status") in ("ready", "skipped"):
            print(f"[{name}] status=already-{data.get('status')} generation={generation}")
            return str(data.get("status"))

    # Non-DICOM check
    if content_type != "application/dicom":
        doc_ref.set({
            "doctorId": doctor_id,
            "patientId": patient_id,
            "sourcePath": name,
            "sourceGeneration": str(generation),
            "status": "skipped",
            "reason": "not-dicom",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })
        print(f"[{name}] status=skipped reason=not-dicom")
        return "skipped"

    # Write pending doc
    doc_ref.set({
        "doctorId": doctor_id,
        "patientId": patient_id,
        "sourcePath": name,
        "sourceGeneration": str(generation),
        "status": "pending",
        "updatedAt": firestore.SERVER_TIMESTAMP,
    })
    print(f"[{name}] status=pending")

    bucket = _storage().bucket(bucket_name)
    blob = bucket.blob(name)

    try:
        gen_int = int(generation) if str(generation).isdigit() else None
        dicom_bytes = blob.download_as_bytes(if_generation_match=gen_int)
    except (google.api_core.exceptions.NotFound, google.api_core.exceptions.PreconditionFailed):
        # Object gone or replaced before we could read it
        curr = doc_ref.get()
        if curr.exists:
            curr_data = curr.to_dict() or {}
            if str(curr_data.get("sourceGeneration")) == str(generation):
                doc_ref.delete()
        print(f"[{name}] status=gone")
        return "skipped"

    try:
        codec = os.environ.get("VIEW_CODEC", "htj2k")
        view_result = build_view(dicom_bytes, codec=codec)

        if view_result.status == "skipped":
            # Stale check before writing skipped
            curr = doc_ref.get()
            if curr.exists:
                curr_data = curr.to_dict() or {}
                if str(curr_data.get("sourceGeneration")) != str(generation):
                    print(f"[{name}] status=stale")
                    return "skipped"
            doc_ref.update({
                "status": "skipped",
                "reason": view_result.reason,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            })
            elapsed = (time.perf_counter() - t0) * 1000
            print(f"[{name}] status=skipped reason={view_result.reason} elapsed={elapsed:.0f}ms")
            return "skipped"

        frame_files = []
        for idx, frame in enumerate(view_result.frames):
            frame_path = f"doctors/{doctor_id}/patients/{patient_id}/clinical/imaging-view/{view_id}/frame_{idx}.j2c"
            frame_blob = bucket.blob(frame_path)
            frame_blob.upload_from_string(frame.data, content_type="application/octet-stream")
            frame_files.append({
                "path": frame_path,
                "total": frame.total,
                "previewEnd": frame.preview_end,
                "sha256": frame.sha256,
            })

        # Never overwrite a newer result
        curr = doc_ref.get()
        if curr.exists:
            curr_data = curr.to_dict() or {}
            if str(curr_data.get("sourceGeneration")) != str(generation):
                print(f"[{name}] status=stale")
                return "skipped"

        update_payload = {
            "status": "ready",
            "reason": "",
            **view_result.meta,
            "frameFiles": frame_files,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        doc_ref.update(update_payload)
        elapsed = (time.perf_counter() - t0) * 1000
        print(f"[{name}] status=ready elapsed={elapsed:.0f}ms")
        return "ready"

    except Exception as e:
        err_msg = f"{type(e).__name__}: {str(e)[:200]}"
        elapsed = (time.perf_counter() - t0) * 1000
        print(f"[{name}] status=failed error={err_msg} elapsed={elapsed:.0f}ms")
        try:
            curr = doc_ref.get()
            if curr.exists:
                curr_data = curr.to_dict() or {}
                if str(curr_data.get("sourceGeneration")) != str(generation):
                    print(f"[{name}] status=stale")
                    return "failed"
            doc_ref.set({
                "doctorId": doctor_id,
                "patientId": patient_id,
                "sourcePath": name,
                "sourceGeneration": str(generation),
                "status": "failed",
                "reason": err_msg,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }, merge=True)
        except Exception:
            pass

        if isinstance(e, (google.api_core.exceptions.ServiceUnavailable, google.api_core.exceptions.DeadlineExceeded)):
            raise
        return "failed"

def process_deleted(bucket_name: str, name: str, generation: str) -> None:
    t0 = time.perf_counter()
    parsed = parse_imaging_path(name)
    if not parsed:
        return
    doctor_id, patient_id, _ = parsed
    view_id = get_view_id(name)

    doc_ref = _db().collection("radiology_views").document(view_id)
    snap = doc_ref.get()
    if snap.exists:
        data = snap.to_dict() or {}
        if str(data.get("sourceGeneration")) != str(generation):
            print(f"[{name}] status=kept-newer")
            return

    bucket = _storage().bucket(bucket_name)
    view_prefix = f"doctors/{doctor_id}/patients/{patient_id}/clinical/imaging-view/{view_id}/"

    blobs = list(bucket.list_blobs(prefix=view_prefix))
    for b in blobs:
        b.delete()

    doc_ref.delete()

    elapsed = (time.perf_counter() - t0) * 1000
    print(f"[{name}] status=deleted blobs_removed={len(blobs)} elapsed={elapsed:.0f}ms")

@functions_framework.cloud_event
def on_storage_event(event: CloudEvent) -> None:
    data = event.data if isinstance(event.data, dict) else {}
    name = str(data.get("name", ""))
    if not is_imaging_path(name):
        return

    event_type = event.get("type") if hasattr(event, "get") else getattr(event, "type", None)
    bucket = str(data.get("bucket", ""))
    generation = str(data.get("generation", ""))
    content_type = data.get("contentType")

    if event_type == "google.cloud.storage.object.v1.finalized":
        process_finalized(bucket, name, generation, content_type)
    elif event_type == "google.cloud.storage.object.v1.deleted":
        process_deleted(bucket, name, generation)