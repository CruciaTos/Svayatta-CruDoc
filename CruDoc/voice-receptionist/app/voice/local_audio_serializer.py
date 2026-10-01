import json

from pipecat.frames.frames import (
    BotStartedSpeakingFrame,
    BotStoppedSpeakingFrame,
    EndFrame,
    ErrorFrame,
    InputAudioRawFrame,
    OutputAudioRawFrame,
    TranscriptionFrame,
    TTSTextFrame,
)
from pipecat.serializers.base_serializer import FrameSerializer


class LocalPcmSerializer(FrameSerializer):
    """Browser protocol: binary PCM16 audio in/out and JSON status events."""

    input_sample_rate = 16000
    output_sample_rate = 24000
    max_audio_frame_bytes = 32000

    async def deserialize(self, data: str | bytes):
        if isinstance(data, str):
            try:
                message = json.loads(data)
            except json.JSONDecodeError:
                return None
            if message.get("type") == "stop":
                return EndFrame()
            return None

        if not data:
            return None
        if len(data) > self.max_audio_frame_bytes:
            raise ValueError("Audio frame exceeds the local test size limit")
        if len(data) % 2:
            raise ValueError("PCM16 audio frames must contain an even number of bytes")

        return InputAudioRawFrame(
            audio=data,
            sample_rate=self.input_sample_rate,
            num_channels=1,
        )

    async def serialize(self, frame):
        if isinstance(frame, OutputAudioRawFrame):
            return frame.audio
        if isinstance(frame, TranscriptionFrame):
            return json.dumps({"type": "transcript", "role": "user", "text": frame.text})
        if isinstance(frame, TTSTextFrame):
            return json.dumps({"type": "transcript", "role": "assistant", "text": frame.text})
        if isinstance(frame, BotStartedSpeakingFrame):
            return json.dumps({"type": "speaking", "value": True})
        if isinstance(frame, BotStoppedSpeakingFrame):
            return json.dumps({"type": "speaking", "value": False})
        if isinstance(frame, ErrorFrame):
            # This serializer is development-only, so the real provider error is
            # reported verbatim -- a generic message here is what makes a failed
            # key or retired model look like an unexplained silent call.
            detail = str(getattr(frame, "error", "") or "").strip()
            return json.dumps(
                {
                    "type": "error",
                    "message": detail or "Voice provider processing failed.",
                    "fatal": bool(getattr(frame, "fatal", False)),
                }
            )
        return None
