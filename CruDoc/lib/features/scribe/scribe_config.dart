/// Whether the consultation recording is copied to Cloud Storage (under
/// `voice-scratch/`, purged after 14 days and deleted on confirm/discard).
///
/// Off: transcription runs on the device and patient voice recordings are
/// never sent to the cloud. The upload code stays in place behind this flag;
/// turning it on also needs the patient consent text to cover cloud storage.
const bool kUploadScribeAudio = false;
