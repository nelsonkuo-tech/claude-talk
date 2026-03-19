#!/usr/bin/env python3
"""
Transcription daemon for Claude Talk.
Loads faster-whisper model once, reads WAV file paths from stdin,
outputs transcription text to stdout.

Protocol:
  IN:  <wav_path>\n
  OUT: <transcribed_text>\n
  OUT: (empty line if no speech detected)\n
"""

import sys
import os
import warnings

warnings.filterwarnings("ignore")

from faster_whisper import WhisperModel

def main():
    model_size = os.environ.get("CLAUDE_TALK_MODEL_SIZE", "base")
    compute_type = os.environ.get("CLAUDE_TALK_COMPUTE", "int8")
    language = os.environ.get("CLAUDE_TALK_LANGUAGE", None)
    if language == "":
        language = None

    sys.stderr.write(f"[transcribe_server] Loading model: {model_size} ({compute_type})\n")
    sys.stderr.flush()

    model = WhisperModel(model_size, device="cpu", compute_type=compute_type)

    sys.stderr.write("[transcribe_server] Model loaded. Ready.\n")
    sys.stderr.flush()

    # Signal ready via marker file (stdout reserved for transcription results only)
    ready_marker = os.environ.get("CLAUDE_TALK_READY_FILE", "")
    if ready_marker:
        with open(ready_marker, "w") as f:
            f.write("READY")

    for line in sys.stdin:
        wav_path = line.strip()
        if not wav_path:
            continue

        if wav_path == "QUIT":
            break

        try:
            kwargs = {"beam_size": 5}
            if language:
                kwargs["language"] = language

            segments, info = model.transcribe(wav_path, **kwargs)
            text = "".join(seg.text for seg in segments).strip()

            sys.stdout.write(text + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"[transcribe_server] Error: {e}\n")
            sys.stderr.flush()
            sys.stdout.write("\n")
            sys.stdout.flush()

    sys.stderr.write("[transcribe_server] Exiting.\n")
    sys.stderr.flush()


if __name__ == "__main__":
    main()
