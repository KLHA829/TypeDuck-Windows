# Launcher and runtime health

A user runs TypeDuck in the background: `TypeDuckLauncher.exe` owns the tray icon and named pipe server, spawns `TypeDuckRuntime\server.exe`, and recovers when the backend restarts or returns degraded health over the protobuf bridge.

## Sub-features

- `single-launcher` — one launcher instance per user (mutex `TypeDuckLauncherMutex`).
- `named-pipe` — TSF DLL talks to launcher on a per-user pipe under `\\.\pipe\...\TypeDuckIME\`.
- `stdio-backend` — launcher frames protobuf to `server.exe` stdin/stdout.
- `health-degraded` — `TypeDuckEngineHealth` and recovery paths per Phase 4 fixtures.

## How to get to it (user POV)

- After install, launcher typically starts at logon (HKCU registration).
- Tray icon present; typing in apps works when runtime is healthy.
- If runtime fails, IME may enter degraded state until launcher restarts the backend.

## Driving it with verify-typeduck

Preconditions:

- Static checks: any OS with `pwsh`.
- Process checks: Windows with optional install.

- **Launcher protocol guard.** `run-guard.ps1 -FeatureId launcher-protocol`.
- **Protocol recovery fixture contract.** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckProtocolRecovery.ps1 -RepoRoot . -Strict` (from frontend root).
- **Doctor on Windows.** `doctor.ps1` reports `launcherRunning` / `runtimeRunning` and `HKLM\Software\TypeDuckIME\InstallDir` without starting processes.
- **Runtime staging contract (after stage).** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckRuntimeContract.ps1 -RepoRoot . -StageRoot <staged-tree>` when a staged `TypeDuckRuntime` exists.
- **Windows probe (heavy).** `Invoke-TypeDuckProtocolRecoveryProbe.ps1` / `Invoke-TypeDuckTypingMvpProof.ps1` — build Win32 targets first; writes NDJSON under `build-vs32/` and `.planning/product/protocol-fixtures/`.

## Gotchas

- Never kill `TypeDuckLauncher` or `server.exe` by blanket process name on a user's machine; only terminate processes you started for an isolated verification session.
- Backend child environment is filtered (`BackendServer.cpp` allowed env keys) — do not assume arbitrary env vars reach `server.exe`.
- Linux CI validates guards only; live process health requires Windows.
