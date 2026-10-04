import hashlib
from main import is_imaging_path, parse_imaging_path, get_view_id

def test_imaging_path_accepted():
    valid_paths = [
        "doctors/d1/patients/p1/clinical/imaging/2026/10/3f2a.dcm",
        "doctors/dr_abc123/patients/pt_xyz789/clinical/imaging/scan1.dcm",
        "doctors/1/patients/2/clinical/imaging/2025/12/test_image.dcm",
        "doctors/doctor-smith/patients/patient-john/clinical/imaging/2026/01/05/frame_001.dcm",
    ]
    for p in valid_paths:
        assert is_imaging_path(p) is True
        parsed = parse_imaging_path(p)
        assert parsed is not None
        d, pt, f = parsed
        assert len(d) > 0
        assert len(pt) > 0
        assert len(f) > 0

def test_imaging_paths_ignored():
    ignored_paths = [
        # imaging-view output
        "doctors/d1/patients/p1/clinical/imaging-view/abc/frame_0.j2c",
        "doctors/dr_abc123/patients/pt_xyz789/clinical/imaging-view/1234abcd/frame_1.j2c",
        # no file after imaging/
        "doctors/d1/patients/p1/clinical/imaging",
        "doctors/d1/patients/p1/clinical/imaging/",
        # backups
        "backups/2026-10-04/export.tar.gz",
        "doctors/dr1/patients/pt1/backups/backup.dcm",
        # voice-scratch
        "voice-scratch/audio_01.m4a",
        "doctors/dr1/patients/pt1/clinical/voice-scratch/note.m4a",
        # other clinical folders
        "doctors/dr1/patients/pt1/clinical/documents/report.pdf",
        "doctors/dr1/patients/pt1/clinical/prescriptions/rx.pdf",
        # missing segments
        "doctors/dr1/clinical/imaging/scan.dcm",
        "",
        "/doctors/dr1/patients/pt1/clinical/imaging/scan.dcm",
    ]
    for p in ignored_paths:
        assert is_imaging_path(p) is False
        assert parse_imaging_path(p) is None

def test_view_id_generation():
    path = "doctors/d1/patients/p1/clinical/imaging/2026/10/3f2a.dcm"
    expected = hashlib.sha256(path.encode("utf-8")).hexdigest().lower()
    assert get_view_id(path) == expected
    assert len(get_view_id(path)) == 64