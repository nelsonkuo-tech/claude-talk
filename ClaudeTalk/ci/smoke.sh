#!/bin/bash
# ci/smoke.sh — daemon canary (Apple workflow: Test action / integration layer)
#
# The防線 that would have caught 2026-04-12 fork bomb incident.
# Runs transcribe_server STANDALONE (outside Swift app) and checks:
#   1. Binary exists in the app bundle
#   2. Daemon loads model + writes ready marker within 30s
#   3. Process count stays ≤ MAX_PROCS for 10s (fork bomb canary)
#   4. Daemon accepts a silence WAV without crashing
#   5. Daemon exits cleanly on QUIT
#   6. No orphan multiprocessing children after exit
#
# Usage: ./ci/smoke.sh [path/to/ClaudeTalk.app]
# Default target: build/release/ClaudeTalk.app

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_APP="${1:-$REPO_ROOT/build/release/ClaudeTalk.app}"
DAEMON="$TARGET_APP/Contents/Resources/transcribe_server_dist/transcribe_server"

# Thresholds (overridable via env for testing)
MAX_PROCS="${MAX_PROCS:-5}"          # 1 main + ≤4 multiprocessing resource trackers is normal
CANARY_SECONDS="${CANARY_SECONDS:-10}"  # how long to watch proc count
READY_TIMEOUT="${READY_TIMEOUT:-30}"    # max seconds to wait for model load

TMPDIR_SMOKE=$(mktemp -d -t ct-smoke-XXXXXX)
MARKER="$TMPDIR_SMOKE/ready"
STDERR_LOG="$TMPDIR_SMOKE/stderr.log"
TEST_WAV="$TMPDIR_SMOKE/silence.wav"
DAEMON_PID=""
DAEMON2_PID=""

cleanup() {
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill -9 "$DAEMON_PID" 2>/dev/null || true
    fi
    if [ -n "$DAEMON2_PID" ] && kill -0 "$DAEMON2_PID" 2>/dev/null; then
        kill -9 "$DAEMON2_PID" 2>/dev/null || true
    fi
    # Kill any orphan transcribe_server descendants of our shell
    pkill -9 -P $$ -f transcribe_server 2>/dev/null || true
    rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

fail=0
pass() { echo "  ✓ $1"; }
die()  { echo "  ✗ $1"; fail=1; }

echo "[smoke] daemon: $DAEMON"
echo

# --- G3.1 daemon binary exists ---
echo "[smoke] G3.1 binary exists"
if [ -x "$DAEMON" ]; then
    pass "transcribe_server found"
else
    die "transcribe_server not found or not executable"
    echo "[smoke] RESULT: FAIL"
    exit 1
fi

# --- G3.2 create test silence wav ---
python3 -c "
import wave, struct
w = wave.open('$TEST_WAV','w')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
w.writeframes(struct.pack('<'+'h'*16000, *([0]*16000)))
w.close()
" 2>/dev/null

# --- G3.3 launch daemon with ready marker ---
echo "[smoke] G3.3 launch daemon"
CLAUDE_TALK_READY_FILE="$MARKER" \
CLAUDE_TALK_MODEL_SIZE=base \
CLAUDE_TALK_COMPUTE=int8 \
    "$DAEMON" > "$TMPDIR_SMOKE/stdout.log" 2> "$STDERR_LOG" < <(
        # keep stdin open; will feed wav then QUIT
        while [ ! -f "$TMPDIR_SMOKE/feed-done" ]; do sleep 0.5; done
        echo "$TEST_WAV"
        sleep 2
        echo "QUIT"
    ) &
DAEMON_PID=$!
pass "launched (pid=$DAEMON_PID)"

# --- G3.4 wait for ready marker ---
echo "[smoke] G3.4 wait for ready marker (≤${READY_TIMEOUT}s)"
waited=0
while [ ! -f "$MARKER" ] && [ $waited -lt $READY_TIMEOUT ]; do
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        die "daemon died before ready (check stderr below)"
        cat "$STDERR_LOG"
        echo "[smoke] RESULT: FAIL"
        exit 1
    fi
    sleep 1
    waited=$((waited + 1))
done
if [ -f "$MARKER" ]; then
    pass "ready in ${waited}s"
else
    die "daemon did not signal ready within ${READY_TIMEOUT}s"
    cat "$STDERR_LOG"
    echo "[smoke] RESULT: FAIL"
    exit 1
fi

# --- G3.5 fork bomb canary: watch proc count for CANARY_SECONDS ---
echo "[smoke] G3.5 fork bomb canary (≤${MAX_PROCS} procs for ${CANARY_SECONDS}s)"
max_seen=0
for i in $(seq 1 $CANARY_SECONDS); do
    procs=$(pgrep -f "$DAEMON" 2>/dev/null || true)
    count=$(echo "$procs" | grep -c . || true)
    if [ "$count" -gt "$max_seen" ]; then max_seen=$count; fi
    if [ "$count" -gt "$MAX_PROCS" ]; then
        die "process count ballooned to $count (MAX_PROCS=$MAX_PROCS) — fork bomb detected"
        echo "[smoke] RESULT: FAIL"
        exit 1
    fi
    sleep 1
done
pass "proc count stable (peak=$max_seen)"

# --- G3.6 feed test wav & QUIT, expect clean exit ---
echo "[smoke] G3.6 feed WAV + QUIT"
touch "$TMPDIR_SMOKE/feed-done"

# Wait for daemon to exit (bounded)
waited=0
while kill -0 "$DAEMON_PID" 2>/dev/null && [ $waited -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    die "daemon did not exit on QUIT within 20s"
else
    wait "$DAEMON_PID" 2>/dev/null || true
    pass "daemon exited cleanly"
fi

# --- G3.7 no orphan children ---
echo "[smoke] G3.7 no orphan children"
sleep 1
orphans=$(pgrep -f "$DAEMON" 2>/dev/null || true)
orphan_count=$(echo "$orphans" | grep -c . || true)
if [ "$orphan_count" -eq 0 ]; then
    pass "no orphans"
else
    die "$orphan_count orphan process(es) remain"
fi

# --- G3.8 IPC contract test (regression防線 for 2026-04-12 LLM polish bug) ---
#
# The 2026-04-12 incident: LLM-polished hints contained literal \n, which the
# daemon's line-reader split into multiple records, causing the Swift→daemon
# protocol stream to desynchronize. The fix lives in TranscriptionService.swift
# (sanitize hints before sending). The daemon's line-based protocol is
# fundamentally trust-the-client.
#
# This test verifies the CONTRACT Swift promises to honor: long realistic hints
# WITHOUT \n or \t. We send N pre-sanitized requests and require exactly N
# stdout lines back — proving the protocol stays in sync under production
# conditions after the Swift fix.
echo
echo "[smoke] G3.8 IPC contract test (LLM-polish-hint regression)"

MARKER2="$TMPDIR_SMOKE/ready2"
STDERR2="$TMPDIR_SMOKE/stderr2.log"
STDOUT2="$TMPDIR_SMOKE/stdout2.log"
FIFO_IN="$TMPDIR_SMOKE/fifo-in"
mkfifo "$FIFO_IN"

CLAUDE_TALK_READY_FILE="$MARKER2" \
CLAUDE_TALK_MODEL_SIZE=base \
CLAUDE_TALK_COMPUTE=int8 \
    "$DAEMON" > "$STDOUT2" 2> "$STDERR2" < "$FIFO_IN" &
DAEMON2_PID=$!
# Hold the FIFO open from this shell so reader doesn't hit EOF prematurely
exec 9>"$FIFO_IN"

# Wait for ready
waited=0
while [ ! -f "$MARKER2" ] && [ $waited -lt $READY_TIMEOUT ]; do
    if ! kill -0 "$DAEMON2_PID" 2>/dev/null; then
        die "G3.8 daemon died before ready"
        exec 9>&-
        echo "--- stderr ---"; cat "$STDERR2"
        echo "[smoke] RESULT: FAIL"
        exit 1
    fi
    sleep 1
    waited=$((waited + 1))
done
if [ -f "$MARKER2" ]; then
    pass "G3.8 daemon ready"
else
    die "G3.8 daemon never ready"
    exec 9>&-
    echo "[smoke] RESULT: FAIL"
    exit 1
fi

# Send 3 sequential requests with realistic long hints (no \n / \t — what
# Swift will send after the sanitizer fix). Expect exactly 3 stdout lines.
# A mismatch means the protocol stream desynchronized somewhere.

hint_short="brief context"
hint_long="this is a much longer hint that simulates LLM-polished output of about three hundred characters with multiple sentences and clauses and lots of words to ensure the daemon can handle realistic production hint sizes without buffering issues or stream desynchronization the LLM polish step in the v1.3 pipeline can produce hints this long after combining the rolling context with the latest transcription"
hint_unicode="包含中文和符号的提示词，模拟真实场景下经过 LLM polish 之后的滚动上下文。中英混杂常见情况。"

printf '%s\t%s\n' "$TEST_WAV" "$hint_short" >&9
sleep 2
printf '%s\t%s\n' "$TEST_WAV" "$hint_long" >&9
sleep 2
printf '%s\t%s\n' "$TEST_WAV" "$hint_unicode" >&9
sleep 2

if ! kill -0 "$DAEMON2_PID" 2>/dev/null; then
    die "daemon died during contract test"
    exec 9>&-
    echo "--- stderr ---"; cat "$STDERR2"
    echo "[smoke] RESULT: FAIL"
    exit 1
fi
pass "daemon survived 3 sanitized requests"

# Verify exactly 3 stdout lines = 3 in-sync responses
out_lines=$(wc -l < "$STDOUT2" | tr -d ' ')
if [ "$out_lines" -eq 3 ]; then
    pass "protocol stream in sync (3 requests → 3 responses)"
else
    die "protocol DESYNC: got $out_lines stdout lines for 3 requests"
    echo "--- stdout ---"; cat "$STDOUT2"
    echo "--- stderr ---"; cat "$STDERR2"
fi

# Cleanup G3.8
printf 'QUIT\n' >&9
exec 9>&-
waited=0
while kill -0 "$DAEMON2_PID" 2>/dev/null && [ $waited -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
done
if kill -0 "$DAEMON2_PID" 2>/dev/null; then
    kill -9 "$DAEMON2_PID" 2>/dev/null || true
fi

echo
if [ $fail -eq 0 ]; then
    echo "[smoke] RESULT: PASS"
    exit 0
else
    echo "[smoke] RESULT: FAIL"
    echo "--- stderr ---"
    cat "$STDERR_LOG" "$STDERR2" 2>/dev/null
    exit 1
fi
