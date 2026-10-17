---
name: verify-typeduck
description: Drive and prove TypeDuck Windows Cantonese IME (TSF zh-HK) behavior via existing PowerShell guards, CTest, and backend tests — not a web app. Use when validating candidate/Jyutping UI, settings→Rime apply, launcher/runtime health, TSF profile identity, or typing latency contracts; requires Windows for live IME typing.
---

# verify-typeduck

TypeDuck Windows is a **Text Services Framework (TSF) input method** for Chinese (Traditional, Hong Kong). Users interact with the **candidate window**, **launcher tray**, **TypeDuckSettings / TypeDuckAbout**, and the **installer / SetupHelper** — not a browser.

Cross-repo layout matches CI: frontend **TypeDuck-Windows** (this repo) plus sibling **TypeDuck-Windows-backend** (Go + Rime). See `AGENTS.md` for hard constraints (no single-file identity renames, no hand-edited protobuf, no dictionary parsing in transport files, no blocking work in the TSF DLL).

## Launch

**Goal:** reach a state where verification harnesses can run. Full IME typing additionally requires Windows 10/11 with the TypeDuck profile installed.

| Target | Command | Ready when |
|--------|---------|------------|
| Static guards (any OS with `pwsh`) | Clone backend → set `BACKEND_ROOT` if not sibling | `doctor.ps1` prints `doctor: OK` |
| Frontend compile (Windows) | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Apply-TypeDuckSubmodulePatches.ps1 -RepoRoot .` then `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -RepoRoot . -Configuration Debug -ProtobufRoot <protoc root>` | `build-vs32` exists; `ctest` can run |
| Backend compile | In backend: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -RimeDataSource <schema>` | `TypeDuckRuntime/server.exe` staged per backend scripts |
| Shipped install (Windows) | Release installer from `scripts/_all_in_package.ps1` or CI artifacts; run installer | `HKLM\Software\TypeDuckIME\InstallDir` set; TypeDuck appears under zh-HK keyboards |
| Live IME | User selects **TypeDuck 粵語輸入法 / TypeDuck Cantonese IME** | Typing in Notepad shows candidate window |

**Teardown:** stop only processes **you** started for verification. Do not `taskkill` by name on a shared developer PC. Remove scratch `VERIFY_TYPEDUCK_*` env vars; leave user `%LOCALAPPDATA%\TypeDuckIME` data untouched unless the run created a disposable VM.

## Doctor

Read-only gate — run before driving when anything looks wrong.

```powershell
# From TypeDuck-Windows repo root
$env:BACKEND_ROOT = "D:\path\TypeDuck-Windows-backend"   # optional if sibling checkout exists
pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/doctor.ps1
```

Checks:

- Frontend/backend directory layout
- On Windows: `InstallDir` registry, whether `TypeDuckLauncher` / `TypeDuckRuntime\server.exe` are already running (warns about single-instance mutex)
- Fast static guards: `Test-TypeDuckProtocolContract.ps1`, `Test-TypeDuckTsfIdentity.ps1`, and `Test-TypeDuckSettingsPersistence.ps1` when backend is present

Pass criterion: exit code `0` and final line `doctor: OK`.

## Drive

**Order:** feature map (`features/README.md`) → `doctor.ps1` → mapped guard or test → evidence.

### Harness priority (use first)

1. `.cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId <slug>` — wraps `scripts/Test-TypeDuck*.ps1`
2. CI-parity strict guards (frontend root):

   ```powershell
   $strict = @{ RepoRoot = (Get-Location).Path; Strict = $true }
   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckProtocolContract.ps1 @strict
   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckTsfIdentity.ps1 @strict
   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckInstallerSkeleton.ps1 @strict
   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckCandidateData.ps1 @strict
   ```

3. **CTest** (after Windows build): `ctest --test-dir build-vs32 -C Debug --output-on-failure`
4. **Backend:** `go test ./...` in TypeDuck-Windows-backend; `scripts/Test-TypeDuckSettingsCustomization.ps1`
5. **Heavy Windows probes:** `Invoke-TypeDuckTypingMvpProof.ps1`, `Invoke-TypeDuckEngineProof.ps1`, `Invoke-TypeDuckVmInstallerVerification.ps1`

### FeatureId slugs (`run-guard.ps1`)

`protocol-contract`, `candidate-jyutping`, `settings-persistence`, `launcher-protocol`, `tsf-identity`, `typing-latency-contract` — list with `-FeatureId ListFeatures`.

### Interactive IME (Windows only)

There is **no** web/CDP driver for TSF. On a Windows host with TypeDuck installed:

- Follow `.planning/product/release-fixtures/phase-07/interactive-vm-checklist.md`
- Switch to zh-HK TypeDuck, type fixed sample Jyutping in Notepad, screenshot the **candidate window** (do not log candidate text to console)

### Latency / diagnostics

- Static: `typing-latency-contract` guard + `Test-TypeDuckTypingMvpProof.ps1`
- Logs: `%LOCALAPPDATA%\TypeDuckIME\Log\TypeDuckLauncher.log`
- Trace: `%LOCALAPPDATA%\TypeDuckIME\TypeDuckLauncher.json` → `"logLevel": "trace"` (backend `debug_logging.go`)
- Optional product env `TYPEDUCK_LATENCY_TRACE=1` → `%LOCALAPPDATA%\TypeDuckIME\Log\latency-trace.ndjson` — **confirm in source** before use; many checkouts do not define it yet (see `features/typing-latency-diagnostics.md`)

### Isolation

- **One launcher per user** (`TypeDuckLauncherMutex`). Default: **refuse** to double-drive the user's live session.
- Second instance for tests only on disposable VMs or when the operator explicitly owns stopping/replacing their launcher.

## Evidence

Store under:

`.cursor/skills/verify-typeduck/artifacts/<VERIFY_TYPEDUCK_RUN_ID>/`

Set `VERIFY_TYPEDUCK_RUN_ID` (or accept UTC timestamp from `run-guard.ps1`).

| Proof type | Artifact |
|------------|----------|
| Guard script | `<feature>-guard.log` from `run-guard.ps1` |
| Doctor | transcript of `doctor.ps1` stdout |
| CTest / go test | saved stdout/stderr + exit code |
| MVP / engine proof | JSON/NDJSON under `.planning/product/**` referenced by test scripts |
| Interactive UI | `*.png` screenshots on Windows; no typed content in logs |

Standards: exercise user-visible paths; pair action + resulting state; respect `Test-TypeDuckPrivacySecurityCleanup.ps1`.

## Cleanup

- Leave artifacts directory intact (proof survives teardown).
- Terminate only verification-started launcher/runtime child processes if you started them for an isolated run.
- Do not delete user `%APPDATA%\TypeDuckIME\TypeDuckPreferences.json` or production logs unless on a throwaway VM.

## Helpers

```powershell
# Doctor (read-only)
pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/doctor.ps1

# One feature guard + log
pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId protocol-contract

# List slugs
pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId ListFeatures
```

Feature recipes: `features/*.md` (index in `features/README.md`).

**Maintenance:** when the product changes, run `/maintain-verification-skill` to refresh the feature map and re-prove journeys.
