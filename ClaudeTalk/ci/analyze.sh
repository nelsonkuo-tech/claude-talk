#!/bin/bash
# ci/analyze.sh — static checks (Apple workflow: Analyze action)
#
# Catches problems BEFORE they hit runtime:
#   1. Required Developer ID signing identity present
#   2. Build output has no get-task-allow (= Debug leak into Release)
#   3. Build output is signed with hardened runtime
#   4. No duplicate .app bundles with same bundle-id anywhere on disk
#   5. No stale DerivedData Debug copy that could get launched instead
#
# Usage: ./ci/analyze.sh [path/to/ClaudeTalk.app]
# Default target: build/release/ClaudeTalk.app

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_APP="${1:-$REPO_ROOT/build/release/ClaudeTalk.app}"
REQUIRED_IDENTITY="Developer ID Application: CHENG HAO KUO (YWM35G3G8G)"
BUNDLE_ID="com.claude-talk.app"

fail=0
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ $1"; }
die()  { echo "  ✗ $1"; fail=1; }

echo "[analyze] target: $TARGET_APP"
echo

# --- G2.1 signing identity present in keychain ---
echo "[analyze] G2.1 signing identity"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$REQUIRED_IDENTITY"; then
    pass "Developer ID present"
else
    die "Developer ID missing: $REQUIRED_IDENTITY"
fi

# --- G2.2 target app exists ---
echo "[analyze] G2.2 target app exists"
if [ -d "$TARGET_APP" ]; then
    pass "$(basename "$TARGET_APP") exists"
else
    die "target app not found: $TARGET_APP"
    echo "[analyze] RESULT: FAIL"
    exit 1
fi

# --- G2.3 no get-task-allow (= Release, not Debug) ---
echo "[analyze] G2.3 entitlements sanity"
entitlements=$(codesign -d --entitlements - "$TARGET_APP" 2>&1 || true)
if echo "$entitlements" | grep -q "get-task-allow.*true\|get-task-allow.*<true"; then
    die "get-task-allow is true (Debug build leaked into Release path)"
else
    pass "no get-task-allow"
fi

# --- G2.4 hardened runtime enabled ---
echo "[analyze] G2.4 hardened runtime"
sig=$(codesign -dv "$TARGET_APP" 2>&1 || true)
if echo "$sig" | grep -q "flags=0x10000(runtime)"; then
    pass "hardened runtime enabled"
else
    die "hardened runtime NOT enabled (codesign needs --options runtime)"
fi

# --- G2.5 signed with required identity ---
echo "[analyze] G2.5 signing identity matches"
if echo "$sig" | grep -q "TeamIdentifier=YWM35G3G8G"; then
    pass "signed by YWM35G3G8G"
else
    die "not signed with required Team ID"
fi

# --- G2.6 no duplicate .app on disk (same bundle-id, different locations) ---
echo "[analyze] G2.6 no duplicate app bundles"
# Only consider real .app bundles, not dSYM/pyinstaller artifacts
dupes=$(mdfind -name "ClaudeTalk.app" 2>/dev/null \
    | grep -E "\.app$" \
    | grep -v "\.dSYM" \
    | grep -v "/build/" \
    | grep -v "$TARGET_APP" || true)
if [ -z "$dupes" ]; then
    pass "no duplicate installed copies"
else
    warn "additional installed copies found (expected only /Applications during post-deploy):"
    echo "$dupes" | sed 's/^/      /'
fi

# --- G2.7 no DerivedData Debug build lying around ---
echo "[analyze] G2.7 no stale DerivedData Debug"
stale_debug=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name "ClaudeTalk.app" -path "*/Debug/*" 2>/dev/null || true)
if [ -z "$stale_debug" ]; then
    pass "no stale DerivedData Debug build"
else
    warn "stale DerivedData Debug build(s) — could be launched instead of Release:"
    echo "$stale_debug" | sed 's/^/      /'
fi

echo
if [ $fail -eq 0 ]; then
    echo "[analyze] RESULT: PASS"
    exit 0
else
    echo "[analyze] RESULT: FAIL"
    exit 1
fi
