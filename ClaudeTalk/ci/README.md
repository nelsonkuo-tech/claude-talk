# Claude Talk CI Pipeline

Apple-aligned 4-action pipeline, adapted for a Swift app with a bundled Python daemon.

## Why this exists

On 2026-04-12 we shipped a fork bomb to `/Applications` because we had no automated
gate between "build succeeds" and "user installs it". The fix was a one-liner
(`multiprocessing.freeze_support()`). The real lesson was that we needed a pipeline
that would have caught it. This directory is that pipeline.

## Apple's model (what we follow)

Apple's canonical Xcode Cloud workflow runs four actions in order:

```
  Build  →  Analyze  →  Test  →  Archive  →  Post-actions
```

Each action is a **gate**. Failure stops the pipeline. We mirror this structure
using shell scripts instead of Xcode Cloud, because (a) we ship a Python daemon
that Xcode Cloud doesn't know about, and (b) local scripts cost $0 and give
immediate feedback.

References:
- [Creating a workflow that builds your app for distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
- [Configuring your Xcode Cloud workflow's actions](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)
- [Developing a workflow strategy for Xcode Cloud](https://developer.apple.com/documentation/xcode/developing-a-workflow-strategy-for-xcode-cloud)

## Scripts

| Script | Apple action | What it does |
|---|---|---|
| `ci.sh` | orchestrator | Runs Build → Analyze → Test → Archive in order, fails fast |
| `analyze.sh` | **Analyze** | 7 static checks on the built `.app` (see below) |
| `smoke.sh` | **Test** (integration) | Launches `transcribe_server` standalone, checks for fork bombs, clean exit |

`Build` and `Archive` are handled by the existing `../build-release.sh`, which
`ci.sh` calls directly.

### `analyze.sh` gates (G2)

| Gate | Check | Why |
|---|---|---|
| G2.1 | Developer ID signing identity present in keychain | can't sign without it |
| G2.2 | target `.app` exists | sanity |
| G2.3 | no `get-task-allow` entitlement | Debug leaked into Release path (2026-04-12 root cause) |
| G2.4 | hardened runtime enabled | Apple requires it for notarization |
| G2.5 | signed with Team `YWM35G3G8G` | prevents identity drift |
| G2.6 | no duplicate `.app` bundles on disk | stops TCC confusion (2026-04-12 root cause) |
| G2.7 | no stale DerivedData Debug build | warn-level; Xcode test runs naturally create these |

### `smoke.sh` gates (G3)

| Gate | Check | Why |
|---|---|---|
| G3.1 | `transcribe_server` binary bundled | sanity |
| G3.3 | daemon launches without crashing | sanity |
| G3.4 | daemon writes ready marker within 30s | model load must finish |
| G3.5 | **fork bomb canary** — proc count ≤ `MAX_PROCS` for 10s | catches missing `multiprocessing.freeze_support()` |
| G3.6 | daemon processes WAV input and exits on QUIT | IPC protocol sanity |
| G3.7 | no orphan children after daemon exit | resource leak check |

G3.5 is the防線 that would have caught 2026-04-12. It's verified with a negative
test: `MAX_PROCS=1 ./ci/smoke.sh` correctly fails (real daemon has 2 procs normally).

### XCTest status (soft gate)

`ci.sh` also runs `xcodebuild test` against the existing `ClaudeTalkTests` target.
At Phase 0 this is an **informational** check — failures are reported but do not
block the pipeline. Reason: 3 tests in `SettingsTests.swift` currently read real
`UserDefaults` instead of an in-memory container and fail based on whatever the
developer has set in their real Claude Talk app. This is a pre-existing test-design
issue, not a regression.

Phase 1 will fix these tests and promote XCTest to a hard gate.

## Usage

```bash
# Full pipeline (rebuilds from scratch, ~3-5 min)
./ci/ci.sh

# Quick check against existing build output (~25-30 sec)
./ci/ci.sh --quick

# Build + verify, skip DMG/archive step
./ci/ci.sh --no-archive
```

Exit codes: `0` = all hard gates passed, `1` = a hard gate failed.

## Rules of engagement

1. **Never skip gates.** If a gate fails, fix the root cause. Do not add
   `|| true` or comment things out to make the pipeline go green.
2. **Promote soft gates over time.** XCTest is soft now, it should become hard
   once the underlying tests are fixed.
3. **Add a gate after every incident.** If something breaks and a new gate
   would have caught it, add the gate before closing the incident.
4. **Run `./ci/ci.sh --quick` before every install to `/Applications`.** This is
   the ratchet that prevents the 2026-04-12 class of incident from happening again.

## Roadmap

**Phase 0** (this commit): scripts only, local execution.

**Phase 1** (next):
- Fix `SettingsTests.swift` to use in-memory `UserDefaults`
- Promote XCTest to hard gate
- Split `com.claude-talk.app.beta` and `com.claude-talk.app` bundle IDs for
  environment isolation (Apple's TestFlight Internal vs Release pattern)
- Add a scripted end-to-end test: boot app, inject synthetic hotkey event,
  verify log markers (`Hotkey pressed`, `Recorded`, `transcribed`)

**Phase 2**:
- Regression suite with fixture WAVs (silence / en / zh / long-form)
- Rollback script — keep previous `/Applications/ClaudeTalk.app` in
  `~/Applications/ClaudeTalk-rollback.app` for one-command revert
- Notarization step for eventual external distribution

**Phase 3**:
- Migrate to real Xcode Cloud once the pipeline logic is stable
- Or GitHub Actions if cross-platform CI becomes relevant
