---
name: verify-typeduck
description: Drive and prove TypeDuck Windows Cantonese IME (TSF zh-HK) behavior via named-pipe RPC smoke, PowerShell guards, CTest, and backend tests — not a web app. Use when validating candidate/Jyutping UI, settings→Rime apply, launcher/runtime health, TSF profile identity, or typing latency contracts; requires Windows for live IME typing and pipe smoke.
---

# verify-typeduck

TypeDuck Windows is a **Text Services Framework (TSF) input method** for Chinese (Traditional, Hong Kong). Users interact with the **candidate window**, **launcher tray**, **TypeDuckSettings / TypeDuckAbout**, and the **installer / SetupHelper** — not a browser.

Cross-repo layout matches CI: frontend **TypeDuck-Windows** (this repo) plus sibling **TypeDuck-Windows-backend** (Go + Rime). See `AGENTS.md` for hard constraints (no single-file identity renames, no hand-edited protobuf, no dictionary parsing in transport files, no blocking work in the TSF DLL).

## Launch

**Goal:** reach a state where verification harnesses can run. Full IME typing additionally requires Windows 10/11 with the TypeDuck profile installed.

| Target | Command | Ready when |
|--------|---------|------------|
| Static guards (Windows PowerShell 5.1+ or `pwsh`) | Clone backend → set `BACKEND_ROOT` if not sibling | `doctor.ps1` prints `doctor: OK` |
| Frontend compile (Windows) | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Apply-TypeDuckSubmodulePatches.ps1 -RepoRoot .` then `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -RepoRoot . -Configuration Debug -ProtobufRoot <protoc root>` | `build-vs32` exists; `ctest` can run |
| Backend compile | In backend: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -RimeDataSource <schema>` | `TypeDuckRuntime/server.exe` staged per backend scripts |
| Shipped install (Windows) | Release installer from `scripts/_all_in_package.ps1` or CI artifacts; run installer | `HKLM\Software\TypeDuckIME\InstallDir` set; TypeDuck appears under zh-HK keyboards |
| Live IME / pipe smoke | User selects **TypeDuck 粵語輸入法 / TypeDuck Cantonese IME**; `TypeDuckLauncher` running | Typing in Notepad shows candidate window; `\\.\pipe\<USERNAME>\TypeDuckIME\Launcher` accepts RPC |

**Teardown:** stop only processes **you** started for verification. Do not `taskkill` by name on a shared developer PC. Remove scratch `VERIFY_TYPEDUCK_*` env vars; leave user `%LOCALAPPDATA%\TypeDuckIME` data untouched unless the run created a disposable VM.

## Doctor

Read-only gate — run before driving when anything looks wrong.

```powershell
# From TypeDuck-Windows repo root (powershell.exe is enough; pwsh optional)
$env:BACKEND_ROOT = "D:\path\TypeDuck-Windows-backend"   # optional if sibling checkout exists
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/doctor.ps1
```

Checks:

- Frontend/backend directory layout
- On Windows: `InstallDir` registry, whether `TypeDuckLauncher` / `TypeDuckRuntime\server.exe` are already running (warns about single-instance mutex)
- Fast static guards: `Test-TypeDuckProtocolContract.ps1`, `Test-TypeDuckTsfIdentity.ps1`, and `Test-TypeDuckSettingsPersistence.ps1` when backend is present

Pass criterion: exit code `0` and final line `doctor: OK`.

**Windows PowerShell 5.1 note:** scripts that embed Traditional Chinese (for example `Test-TypeDuckTsfIdentity.ps1`, `Test-TypeDuckSettingsPersistence.ps1`) must be UTF-8 **with BOM** or `powershell.exe` mis-parses them. Skill helpers themselves use BOM where needed; `go.mod` scratch files are written **without** BOM.

## Drive

**Order:** feature map (`features/README.md`) → `doctor.ps1` → mapped drive → evidence.

### Harness priority (use first)

1. **Named-pipe RPC smoke (primary programmatic candidate proof)** — proves Launcher framing + backend candidates without Notepad/IME SendKeys:

   ```powershell
   $env:VERIFY_TYPEDUCK_RUN_ID = "manual-$(Get-Date -Format yyyyMMdd-HHmmss)"
   # Launcher must already be running, OR:
   # $env:VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER = "1"
   powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/pipe-nei-smoke.ps1
   # or via run-guard:
   powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId jyutping-pipe-nei
   ```

   Pass: composition `nei`, candidates present (target hanzi checked in-process; transcript logs counts only). Evidence: `artifacts/<RUN_ID>/jyutping-pipe-nei.log`.

2. `.cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId <slug>` — wraps `scripts/Test-TypeDuck*.ps1` and pipe smoke
3. CI-parity strict guards (frontend root):

   ```powershell
   $strict = @{ RepoRoot = (Get-Location).Path; Strict = $true }
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckProtocolContract.ps1 @strict
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckTsfIdentity.ps1 @strict
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckInstallerSkeleton.ps1 @strict
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckCandidateData.ps1 @strict
   ```

4. **CTest** (after Windows build): `ctest --test-dir build-vs32 -C Debug --output-on-failure`
5. **Backend:** `go test ./...` in TypeDuck-Windows-backend; `scripts/Test-TypeDuckSettingsCustomization.ps1`
6. **Heavy Windows probes:** `Invoke-TypeDuckTypingMvpProof.ps1`, `Invoke-TypeDuckEngineProof.ps1`, `Invoke-TypeDuckVmInstallerVerification.ps1`
7. **Interactive Notepad (secondary)** — only when pipe smoke is insufficient (TSF UI / commit path). See `features/jyutping-compose-candidates.md`. Do **not** use `SendKeys` for IME proof (bypasses TSF).

### FeatureId slugs (`run-guard.ps1`)

`protocol-contract`, `candidate-jyutping`, `settings-persistence`, `launcher-protocol`, `tsf-identity`, `typing-latency-contract`, `jyutping-pipe-nei` — list with `-FeatureId ListFeatures`.

**Debug deploy (no Program Files):** `scripts/Install-TypeDuckDebug.ps1` stages build outputs under `%LOCALAPPDATA%\TypeDuckIME-debug`; set `TYPEDUCK_PROGRAM_DIR` to that path before starting Launcher.

**CI required pipe smoke:** `.github/workflows/ci.yml` runs `scripts/Invoke-TypeDuckCiPipeNeiSmoke.ps1` after the Win32 Debug build. That script builds `TypeDuckRuntime` from the checked-out backend + TypeDuck-HK schema, stages `%LOCALAPPDATA%\TypeDuckIME-debug` via `Install-TypeDuckDebug.ps1`, starts `TypeDuckLauncher` with `VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1`, and runs `pipe-nei-smoke.ps1` (no skip when Launcher was absent).

### Latency / diagnostics

- Static: `typing-latency-contract` guard + `Test-TypeDuckTypingMvpProof.ps1`
- Logs: `%LOCALAPPDATA%\TypeDuckIME\Log\TypeDuckLauncher.log`
- Trace: `%LOCALAPPDATA%\TypeDuckIME\TypeDuckLauncher.json` → `"logLevel": "trace"` (backend `debug_logging.go`)
- Optional product env `TYPEDUCK_LATENCY_TRACE=1` → `%LOCALAPPDATA%\TypeDuckIME\Log\latency-trace.ndjson` — **confirm in source** before use; many checkouts do not define it yet (see `features/typing-latency-diagnostics.md`)

### Isolation

- **One launcher per user** (`TypeDuckLauncherMutex`). Default: **refuse** to double-drive the user's live session.
- `pipe-nei-smoke.ps1` attaches to the **existing** launcher pipe. It starts a launcher only when `VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1` and none is running. It never kills a launcher it did not start.
- Second instance for tests only on disposable VMs or when the operator explicitly owns stopping/replacing their launcher.

## Evidence

Store under:

`.cursor/skills/verify-typeduck/artifacts/<VERIFY_TYPEDUCK_RUN_ID>/`

Set `VERIFY_TYPEDUCK_RUN_ID` (or accept UTC timestamp from helpers).

| Proof type | Artifact |
|------------|----------|
| Pipe nei smoke | `jyutping-pipe-nei.log` (+ optional `pipe-nei-probe-scratch/`) |
| Guard script | `<feature>-guard.log` from `run-guard.ps1` |
| Doctor | transcript of `doctor.ps1` stdout |
| CTest / go test | saved stdout/stderr + exit code |
| MVP / engine proof | JSON/NDJSON under `.planning/product/**` referenced by test scripts |
| Interactive UI | `*.png` screenshots on Windows; no typed content / candidate payloads in chat logs |

Standards: exercise user-visible paths; pair action + resulting state; respect `Test-TypeDuckPrivacySecurityCleanup.ps1`. Pipe smoke may log ASCII composition `nei` and candidate **counts**, never full candidate dumps.

## Cleanup

- Leave artifacts directory intact (proof survives teardown).
- Terminate only verification-started launcher/runtime child processes if you started them for an isolated run (`pipe-nei-smoke` tracks this).
- Do not delete user `%APPDATA%\TypeDuckIME\TypeDuckPreferences.json` or production logs unless on a throwaway VM.

## Helpers

```powershell
# Doctor (read-only) — works with Windows PowerShell 5.1
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/doctor.ps1

# Primary candidate proof via named pipe (Launcher must be up)
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/pipe-nei-smoke.ps1

# Same via run-guard FeatureId
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId jyutping-pipe-nei

# One static feature guard + log
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId protocol-contract

# List slugs
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId ListFeatures
```

Feature recipes: `features/*.md` (index in `features/README.md`).

**Maintenance:** when the product changes, run `/maintain-verification-skill` to refresh the feature map and re-prove journeys.
