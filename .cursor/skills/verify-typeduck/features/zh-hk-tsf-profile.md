# zh-HK TSF profile registration

Windows lists **TypeDuck 粵語輸入法 / TypeDuck Cantonese IME** under Chinese (Traditional, Hong Kong) / `zh-HK`, backed by registered `TypeDuckTextService.dll` profiles and install metadata.

## Sub-features

- `profile-guid` — primary TSF profile `{C6E8F5DF-6504-44F9-B7CF-17A195373A83}` synchronized across TSF, installer, SetupHelper, and backend `ime.json`.
- `bilingual-name` — user-visible Traditional Chinese + English strings.
- `setup-helper` — elevated copy/register of 32-bit and 64-bit TSF DLLs via `TypeDuckSetupHelper.exe`.
- `installer-skeleton` — Inno Setup script stages both bitnesses and `TypeDuckRuntime`.

## How to get to it (user POV)

- Windows Settings → Time & language → Language & region → add **中文（繁體，香港）** → keyboard options → select TypeDuck.
- Or use the language bar / Win+Space to pick TypeDuck Cantonese IME.

## Driving it with verify-typeduck

Preconditions:

- Source tree; Windows required only for live registration inspection.

- **TSF identity guard.** `run-guard.ps1 -FeatureId tsf-identity` — checks `TypeDuckProfile.cpp`, `DllEntry.cpp`, installer, and backend profile metadata alignment.
- **Installer skeleton guard.** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckInstallerSkeleton.ps1 -RepoRoot . -Strict`.
- **SetupHelper sources.** Inspect `SetupHelper/SetupHelper.cpp` for `Software\TypeDuckIME`, `TypeDuckTextService.dll`, and `regsvr32` flows (no substitute for elevated install test).
- **Live registration (Windows, manual or VM).** After install: `Get-ItemProperty HKLM:\Software\TypeDuckIME InstallDir`; confirm `TypeDuckTextService.dll` under System32/SysWOW64 per bitness. VM harness: `scripts/Invoke-TypeDuckVmInstallerVerification.ps1` with guest parameters.

## Gotchas

- Do not perform single-file `Moqi`→`TypeDuck` renames; identity changes must touch CLSIDs, GUIDs, installer keys, and backend together (`AGENTS.md`).
- Reboot may be required after DLL replacement (`SetupHelper` exit code `2` restart path).
- Verifying registration on a developer machine can affect system TSF state — prefer VM harness or static guards in shared CI.
