#!/usr/bin/env python3
"""
Transcription daemon for Claude Talk.
Loads faster-whisper model once, reads WAV file paths from stdin,
outputs transcription text to stdout.

Protocol:
  IN:  <wav_path>\n                        (no prompt hint)
  IN:  <wav_path>\t<initial_prompt>\n      (with prompt hint)
  OUT: <transcribed_text>\n
  OUT: (empty line if no speech detected)\n
"""

import sys
import os
import warnings
import multiprocessing

# CRITICAL: freeze_support() must run before any other code when frozen by PyInstaller.
# Without this, every multiprocessing child re-executes __main__ → fork bomb.
multiprocessing.freeze_support()

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

        # Parse optional prompt hint: "<wav_path>\t<initial_prompt>"
        initial_prompt = None
        if "\t" in wav_path:
            wav_path, initial_prompt = wav_path.split("\t", 1)
            initial_prompt = initial_prompt.strip() or None

        try:
            kwargs = {"beam_size": 5}
            if language:
                kwargs["language"] = language
            if initial_prompt:
                kwargs["initial_prompt"] = initial_prompt

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
