#!/usr/bin/env python3
"""claude-talk: Press-to-talk voice input for Claude Code.

Usage:
    claude-talk                              # Default: Option (alt), base model
    claude-talk --key f5                     # Use F5
    claude-talk --language zh                # Force Chinese
    claude-talk --no-sound                   # Disable sound feedback
    claude-talk --terminals ghostty,kitty    # Custom terminal whitelist
    claude-talk --download                   # Pre-download Whisper model and exit

Requirements (macOS):
    brew install portaudio ffmpeg

macOS permissions needed:
    - Microphone access (auto-prompted on first run)
    - Accessibility: System Settings > Privacy & Security > Accessibility > add your terminal app
"""

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import wave

import warnings
warnings.filterwarnings("ignore", category=RuntimeWarning, module="faster_whisper")

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel
from pynput.keyboard import Controller, Key, Listener

# --- Constants ---
SAMPLE_RATE = 16000
CHANNELS = 1
SILENCE_THRESHOLD = 0.01
MIN_DURATION = 0.3
KEYSTROKE_MAX_LEN = 500

# macOS system sounds for audio feedback
SOUNDS = {
    "start": "/System/Library/Sounds/Tink.aiff",
    "success": "/System/Library/Sounds/Pop.aiff",
    "error": "/System/Library/Sounds/Basso.aiff",
}
_sound_enabled = True

# --- Global state ---
_audio_frames = []
_recording_stream = None
_whisper_model = None
_is_transcribing = False
_is_recording = False
_current_wav_path = None
_process_lock = threading.Lock()


def play_sound(event):
    """Play a system sound asynchronously. Never raises."""
    try:
        if not _sound_enabled:
            return
        path = SOUNDS.get(event)
        if path and os.path.exists(path):
            subprocess.Popen(
                ["afplay", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except Exception:
        pass


# --- CLI ---
def parse_args():
    parser = argparse.ArgumentParser(
        prog="claude-talk",
        description="Press-to-talk voice input for Claude Code",
    )
    parser.add_argument("--key", default="alt",
                        help="Hotkey to hold for recording (default: alt/option)")
    parser.add_argument("--model", default="base",
                        choices=["tiny", "base", "small", "medium"],
                        help="Whisper model size (default: base)")
    parser.add_argument("--language", default=None,
                        help="Language hint for Whisper (e.g. zh, en, ja). Auto-detect if omitted.")
    parser.add_argument("--max-duration", type=int, default=60,
                        help="Maximum recording length in seconds (default: 60)")
    parser.add_argument("--no-sound", action="store_true",
                        help="Disable sound feedback")
    parser.add_argument("--terminals", default="terminal,iterm2,ghostty",
                        help="Comma-separated list of allowed terminal app names, case-insensitive "
                             "(default: terminal,iterm2,ghostty). "
                             "Tip: run claude-talk and switch focus to see your terminal's process name.")
    parser.add_argument("--download", action="store_true",
                        help="Pre-download the Whisper model and exit (useful for offline setup)")
    parser.add_argument("--version", action="version",
                        version=f"%(prog)s {_get_version()}")
    return parser.parse_args()


def _get_version():
    try:
        from claude_talk import __version__
        return __version__
    except ImportError:
        return "dev"


def resolve_key(key_name):
    """Convert a key name string (e.g. 'f8') to a pynput Key object."""
    try:
        return getattr(Key, key_name.lower())
    except AttributeError:
        print(f"Unknown key: {key_name}. Use pynput key names like f1-f20.")
        sys.exit(1)


# --- Startup checks ---
def check_platform():
    """Ensure we're running on macOS."""
    if sys.platform != "darwin":
        print("claude-talk currently only supports macOS.")
        sys.exit(1)


def check_system_deps():
    """Check for required system dependencies (portaudio, ffmpeg)."""
    missing = []
    # portaudio is needed by sounddevice — if we got this far, it's likely OK,
    # but ffmpeg is used by faster-whisper for audio decoding
    if not shutil.which("ffmpeg"):
        missing.append("ffmpeg")
    if missing:
        print(f"Missing system dependencies: {', '.join(missing)}")
        print("Install with Homebrew:")
        print(f"    brew install {' '.join(missing)}")
        sys.exit(1)


def check_microphone():
    """Verify a microphone is available. Exit if not."""
    try:
        sd.query_devices(kind="input")
    except sd.PortAudioError:
        print("No microphone detected. Exiting.")
        sys.exit(1)


def check_accessibility():
    """Check if accessibility permissions are granted for pynput."""
    try:
        result = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to key code 0'],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0 and "not allowed assistive access" in result.stderr.lower():
            raise PermissionError("Accessibility not granted")
    except PermissionError:
        print("Accessibility permission not granted.")
        print("  Go to: System Settings > Privacy & Security > Accessibility")
        print("  Add your terminal app (Terminal.app, iTerm2, Ghostty, etc).")
        sys.exit(1)
    except Exception:
        pass


# --- Audio recording ---
def start_recording():
    """Start recording audio from the default microphone."""
    global _audio_frames, _recording_stream
    _audio_frames = []

    def callback(indata, frames, time_info, status):
        _audio_frames.append(indata.copy())

    _recording_stream = sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=CHANNELS,
        dtype="float32",
        callback=callback,
    )
    _recording_stream.start()


def stop_recording():
    """Stop recording and save to a temp WAV file. Returns the file path."""
    global _recording_stream
    if _recording_stream is not None:
        _recording_stream.stop()
        _recording_stream.close()
        _recording_stream = None

    if not _audio_frames:
        return None

    audio_data = np.concatenate(_audio_frames, axis=0)
    fd, wav_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    with wave.open(wav_path, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes((audio_data * 32767).astype(np.int16).tobytes())
    return wav_path


def get_audio_rms(wav_path):
    """Calculate RMS energy of a WAV file. Returns float."""
    with wave.open(wav_path, "rb") as wf:
        frames = wf.readframes(wf.getnframes())
    audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
    return float(np.sqrt(np.mean(audio ** 2)))


# --- Transcription ---
def load_whisper_model(model_size="base"):
    """Load Whisper model into memory. Called once at startup."""
    global _whisper_model
    print(f"Loading Whisper {model_size} model...")
    try:
        _whisper_model = WhisperModel(model_size, device="cpu", compute_type="int8")
    except Exception as e:
        print(f"Failed to load Whisper model: {e}")
        print("  First run requires an internet connection to download the model.")
        print("  You can pre-download with: claude-talk --download")
        sys.exit(1)
    print("Model loaded.")


def transcribe(wav_path, language=None):
    """Transcribe a WAV file using Whisper. Returns text string."""
    kwargs = {}
    if language:
        kwargs["language"] = language
    segments, info = _whisper_model.transcribe(wav_path, beam_size=5, **kwargs)
    text = "".join(segment.text for segment in segments).strip()
    return text


# --- Window guard ---
def get_focused_app():
    """Return the name of the currently focused application."""
    result = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to get name of first application process whose frontmost is true'],
        capture_output=True, text=True, timeout=3,
    )
    return result.stdout.strip()


def is_terminal_focused(whitelist):
    """Check if the focused window is in the terminal whitelist."""
    app = get_focused_app()
    return app.lower() in whitelist


# --- Text input ---
def _sanitize_text(text):
    """Remove control characters that would trigger terminal actions."""
    for ch in ("\n", "\r", "\t"):
        text = text.replace(ch, " ")
    return text.strip()


def paste_text(text):
    """Paste text into the focused terminal window, preserving clipboard."""
    text = _sanitize_text(text)
    if not text:
        return

    original = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout
    try:
        subprocess.run(["pbcopy"], input=text, text=True)
        kb = Controller()
        kb.press(Key.cmd)
        kb.press("v")
        kb.release("v")
        kb.release(Key.cmd)
        time.sleep(0.15)
    finally:
        try:
            subprocess.run(["pbcopy"], input=original, text=True)
        except Exception:
            pass


# --- Main ---
def main():
    global _is_transcribing, _is_recording, _current_wav_path

    args = parse_args()

    check_platform()
    check_system_deps()

    # --download mode: just download the model and exit
    if args.download:
        print(f"Downloading Whisper {args.model} model...")
        load_whisper_model(args.model)
        print("Done! Model is cached locally for offline use.")
        return

    hotkey = resolve_key(args.key)

    check_microphone()
    check_accessibility()
    load_whisper_model(args.model)

    global _sound_enabled
    if args.no_sound:
        _sound_enabled = False

    terminal_whitelist = [t.strip().lower() for t in args.terminals.split(",") if t.strip()]

    print(f"claude-talk started. Hold {args.key.upper()} to speak. Ctrl+C to quit.")
    print(f"  Model: {args.model} | Language: {args.language or 'auto'} | Sound: {'off' if not _sound_enabled else 'on'}")
    print(f"  Terminals: {', '.join(terminal_whitelist)}")

    max_duration_timer = None

    def on_press(key):
        global _is_transcribing, _is_recording
        nonlocal max_duration_timer

        if key != hotkey:
            return

        with _process_lock:
            if _is_transcribing:
                print("Still processing previous recording, please wait...")
                return
            if _is_recording:
                return

            _is_recording = True
            print("Recording...")
            start_recording()
            play_sound("start")

            def auto_stop():
                with _process_lock:
                    global _is_recording
                    if _is_recording:
                        print(f"Max duration ({args.max_duration}s) reached, auto-stopping...")
                        _is_recording = False
                        threading.Thread(target=process_recording, args=(args,), daemon=True).start()

            max_duration_timer = threading.Timer(args.max_duration, auto_stop)
            max_duration_timer.start()

    def on_release(key):
        global _is_recording
        nonlocal max_duration_timer

        if key != hotkey:
            return

        with _process_lock:
            if not _is_recording:
                return
            _is_recording = False
            if max_duration_timer:
                max_duration_timer.cancel()
            threading.Thread(target=process_recording, args=(args,), daemon=True).start()

    def process_recording(args):
        global _is_transcribing, _current_wav_path
        _is_transcribing = True

        try:
            wav_path = stop_recording()
            if wav_path is None:
                return
            _current_wav_path = wav_path

            with wave.open(wav_path, "rb") as wf:
                duration = wf.getnframes() / wf.getframerate()
            if duration < MIN_DURATION:
                print("Recording too short, skipped.")
                play_sound("error")
                os.unlink(wav_path)
                _current_wav_path = None
                return

            rms = get_audio_rms(wav_path)
            if rms < SILENCE_THRESHOLD:
                print("Skipped: no speech detected (silent audio)")
                play_sound("error")
                os.unlink(wav_path)
                _current_wav_path = None
                return

            text = transcribe(wav_path, args.language)
            os.unlink(wav_path)
            _current_wav_path = None

            if not text:
                print("Whisper returned empty text, skipped.")
                play_sound("error")
                return

            if not is_terminal_focused(terminal_whitelist):
                print(f"Skipped: focused window is not a supported terminal (got: {get_focused_app()})")
                return

            paste_text(text)
            print(f'>> {text}')
            play_sound("success")

        except Exception as e:
            print(f"Error: {e}")
        finally:
            _is_transcribing = False

    listener = Listener(on_press=on_press, on_release=on_release)

    def shutdown(sig, frame):
        global _recording_stream, _current_wav_path
        print("\nclaude-talk stopped.")
        try:
            listener.stop()
        except Exception:
            pass
        if _recording_stream:
            try:
                _recording_stream.stop()
                _recording_stream.close()
            except Exception:
                pass
        if _current_wav_path and os.path.exists(_current_wav_path):
            os.unlink(_current_wav_path)
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)

    listener.start()
    listener.join()


if __name__ == "__main__":
    main()
