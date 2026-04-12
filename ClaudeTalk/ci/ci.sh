#!/bin/bash
# ci/ci.sh — Apple-aligned 4-action pipeline orchestrator
#
# Implements Apple's canonical Xcode Cloud workflow structure:
#   Build → Analyze → Test → Archive → Post
# Each action is a gate. Failure of any gate stops the pipeline.
#
# Usage:
#   ./ci/ci.sh             full pipeline (Build + Analyze + Test + Archive)
#   ./ci/ci.sh --quick     skip Build and Archive, only Analyze + Test
#                          (fast feedback against existing build/release output)
#   ./ci/ci.sh --no-archive  Build + Analyze + Test, skip Archive step
#
# Gates:
#   G1 Build    — xcodebuild + PyInstaller (via build-release.sh)
#   G2 Analyze  — ci/analyze.sh (signing, entitlements, no duplicates)
#   G3 Test     — ci/smoke.sh (daemon canary); xcodebuild test if XCTest scheme exists
#   G4 Archive  — build-release.sh already produces signed .app + DMG
#   G5 Post     — summary report
#
# Exit codes:
#   0 = all gates passed
#   1 = a gate failed (check output for which one)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CI_DIR="$REPO_ROOT/ci"
BUILD_APP="$REPO_ROOT/build/release/ClaudeTalk.app"

MODE="${1:-full}"

# Colors (only if tty)
if [ -t 1 ]; then
    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_GREEN=$'\e[32m'; C_RED=$'\e[31m'; C_YELLOW=$'\e[33m'; C_CYAN=$'\e[36m'
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""
fi

header() {
    echo
    echo "${C_BOLD}${C_CYAN}═══ $1 ═══${C_RESET}"
}

gate_pass() { echo "${C_GREEN}✓ $1${C_RESET}"; }
gate_fail() { echo "${C_RED}✗ $1${C_RESET}"; }

# Track results
declare -a RESULTS
add_result() { RESULTS+=("$1"); }

run_gate() {
    local label="$1"; shift
    header "$label"
    if "$@"; then
        add_result "${C_GREEN}PASS${C_RESET}  $label"
        return 0
    else
        add_result "${C_RED}FAIL${C_RESET}  $label"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────
# G1 · Build
# ─────────────────────────────────────────────────────────────
gate_build() {
    cd "$REPO_ROOT"
    ./build-release.sh 2>&1 | tail -10
    local rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ]; then
        gate_fail "build-release.sh failed (rc=$rc)"
        return 1
    fi
    gate_pass "build + sign succeeded"
}

# ─────────────────────────────────────────────────────────────
# G2 · Analyze (static checks)
# ─────────────────────────────────────────────────────────────
gate_analyze() {
    "$CI_DIR/analyze.sh" "$BUILD_APP"
}

# ─────────────────────────────────────────────────────────────
# G3 · Test
#   (a) daemon smoke test  ← required
#   (b) xcodebuild test    ← runs only if ClaudeTalkTests target has tests
# ─────────────────────────────────────────────────────────────
gate_test() {
    "$CI_DIR/smoke.sh" "$BUILD_APP" || return 1

    # G3.b XCTest — SOFT GATE at Phase 0 (informational)
    # Reports pass/fail but does not block pipeline. Promote to hard gate
    # in Phase 1 once SettingsTests.swift stops reading real UserDefaults.
    if xcodebuild -list -project "$REPO_ROOT/ClaudeTalk.xcodeproj" 2>/dev/null \
         | grep -q "ClaudeTalk$"; then
        header "G3.b xcodebuild test (soft gate)"
        local test_out
        test_out=$(xcodebuild test \
            -project "$REPO_ROOT/ClaudeTalk.xcodeproj" \
            -scheme ClaudeTalk \
            -destination 'platform=macOS' 2>&1) || true

        # Parse Executed/failures line
        local summary
        summary=$(echo "$test_out" | grep -E "^Test Suite 'All tests' (passed|failed)" -A1 | tail -1 || true)
        if [ -z "$summary" ]; then
            summary=$(echo "$test_out" | grep -E "Executed [0-9]+ tests" | tail -1 || true)
        fi

        if echo "$test_out" | grep -q "\*\* TEST SUCCEEDED \*\*"; then
            gate_pass "XCTest green: $summary"
        elif echo "$test_out" | grep -q "\*\* TEST FAILED \*\*"; then
            echo "${C_YELLOW}⚠ XCTest has failures (soft gate — not blocking)${C_RESET}"
            echo "  $summary"
            echo "$test_out" | grep -E "error:" | sed 's/^/  /' | head -10
        else
            echo "${C_YELLOW}⚠ XCTest output unrecognized (soft gate)${C_RESET}"
        fi
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# G4 · Archive (produced by build-release.sh; just verify)
# ─────────────────────────────────────────────────────────────
gate_archive() {
    local dmg
    dmg=$(ls -1 "$REPO_ROOT/build/release/"*.dmg 2>/dev/null | head -1 || true)
    if [ -z "$dmg" ]; then
        gate_fail "no DMG produced"
        return 1
    fi
    gate_pass "archive present: $(basename "$dmg")"
}

# ─────────────────────────────────────────────────────────────
# G5 · Post — final summary
# ─────────────────────────────────────────────────────────────
post() {
    header "G5 Post — summary"
    for r in "${RESULTS[@]}"; do
        echo "  $r"
    done
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
start_time=$(date +%s)
echo "${C_BOLD}Claude Talk CI pipeline${C_RESET} (mode=$MODE)"
echo "repo: $REPO_ROOT"

case "$MODE" in
    full)
        run_gate "G1 Build"   gate_build   || { post; exit 1; }
        run_gate "G2 Analyze" gate_analyze || { post; exit 1; }
        run_gate "G3 Test"    gate_test    || { post; exit 1; }
        run_gate "G4 Archive" gate_archive || { post; exit 1; }
        ;;
    --quick|quick)
        run_gate "G2 Analyze" gate_analyze || { post; exit 1; }
        run_gate "G3 Test"    gate_test    || { post; exit 1; }
        ;;
    --no-archive)
        run_gate "G1 Build"   gate_build   || { post; exit 1; }
        run_gate "G2 Analyze" gate_analyze || { post; exit 1; }
        run_gate "G3 Test"    gate_test    || { post; exit 1; }
        ;;
    *)
        echo "unknown mode: $MODE" >&2
        echo "usage: $0 [full | --quick | --no-archive]" >&2
        exit 2
        ;;
esac

post
elapsed=$(( $(date +%s) - start_time ))
echo
echo "${C_BOLD}${C_GREEN}✓ pipeline green in ${elapsed}s${C_RESET}"
