# TypeDuck Windows verification map

This directory is the maintained source for verifying user-facing TypeDuck Windows IME behavior. Read this index before driving the app, then open the matching feature file for the recipe.

TypeDuck is a **Windows TSF input method** (Chinese Traditional Hong Kong / `zh-HK`), not a web app. Live typing in host apps requires Windows 10/11 with the TypeDuck TSF profile installed.

## Baseline preconditions

- **Frontend repo:** TypeDuck-Windows (this repository) checked out with submodules and patches applied per `AGENTS.md`.
- **Backend repo:** TypeDuck-Windows-backend as a sibling checkout or `BACKEND_ROOT` pointing at it (CI uses `TypeDuck-Windows-backend/` under the workspace).
- **Tooling:** PowerShell 7+ (`pwsh`) for all `scripts/Test-TypeDuck*.ps1` and `scripts/build.ps1`.
- **Evidence run id:** set `VERIFY_TYPEDUCK_RUN_ID` (optional) so artifacts land under `.cursor/skills/verify-typeduck/artifacts/<run-id>/`.
- **Doctor first:** `pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/doctor.ps1`
- **Isolation:** `TypeDuckLauncher.exe` uses a single-instance mutex. Do not start a second launcher while the user's session is live unless you own that session and accept replacing it.

## Driving conventions

- Prefer existing harnesses: `scripts/Test-TypeDuck*.ps1`, CTest (`ctest --test-dir build-vs32 -C Debug`), backend `go test ./...`, and Windows-only probes (`Invoke-TypeDuckTypingMvpProof.ps1`, VM installer harness) before improvising steps.
- Run guards through `.cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId <slug>` to tee logs into artifacts.
- Interactive IME typing (Notepad, Office, browser) is **Windows-host manual** or VM checklist evidence — there is no browser/CDP recipe for TSF.
- Do not log typed content, clipboard, candidate bodies, or raw settings in proof artifacts (privacy guards in `Test-TypeDuckPrivacySecurityCleanup.ps1`).

## Proof and skip reporting

- Static guards: exit code `0` plus saved `*-guard.log` under the artifacts directory.
- CTest / `go test`: stdout/stderr transcript and exit code.
- Runtime / VM proofs: JSON evidence under `.planning/product/**` when produced by official runners.
- Interactive UI: screenshots of the candidate window on a Windows host; follow `.planning/product/release-fixtures/phase-07/interactive-vm-checklist.md` for host matrix.
- Report unreachable paths with the attempted command and the unmet precondition (wrong OS, missing VS build, no install, backend not cloned).

## Feature entry contract

Each feature file uses exactly four H2 sections: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-typeduck`, and `Gotchas`.

## Features

- [Jyutping composition and candidate display](./jyutping-compose-candidates.md) — compose with Jyutping, see candidates and dictionary-style comments.
- [Settings apply to Rime](./settings-apply-rime.md) — change preferences in settings; persistence and Rime mapping.
- [Launcher and runtime health](./launcher-runtime-health.md) — tray launcher, named pipe bridge, `TypeDuckRuntime/server.exe`.
- [zh-HK TSF profile registration](./zh-hk-tsf-profile.md) — profile GUID, bilingual name, SetupHelper/installer registration contract.
- [Typing latency and diagnostics](./typing-latency-diagnostics.md) — latency contract guards, launcher logs, trace logging, optional latency NDJSON when present in product builds.
