# Settings apply to Rime

A user opens **IME Settings / 輸入法設定**, changes options (page size, romanization visibility, correction, memory, Cangjie version, and related toggles), saves, and sees those choices persist across restarts with engine-affecting values applied through the TypeDuck runtime.

## Sub-features

- `settings-ui` — `TypeDuckSettings.exe` bilingual controls.
- `preferences-json` — per-user `TypeDuckPreferences.json` under `%APPDATA%\TypeDuckIME\`.
- `rime-apply` — launcher forwards settings to backend; Rime config paths updated in backend `input_methods/rime/`.
- `apply-failure` — bounded bilingual error when apply fails.

## How to get to it (user POV)

- Start Menu → TypeDuck **IME Settings / 輸入法設定**, or tray icon → settings.
- Change a visible option (for example candidates per page), click apply/save, close and reopen settings to confirm persistence.
- Type in an app to confirm behavior changed (for example fewer candidates per page).

## Driving it with verify-typeduck

Preconditions:

- `BACKEND_ROOT` or sibling `TypeDuck-Windows-backend` checkout.
- Frontend sources present: `MoqLauncher/TypeDuckPreferences.cpp`, `TypeDuckSettings/`.

- **Cross-repo persistence guard.** Run `pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId settings-persistence`. Requires backend root; exit code `0`.
- **Preference unit tests (Windows build).** `ctest --test-dir build-vs32 -C Debug -R TypeDuckPreferences --output-on-failure`.
- **Backend customization guard.** From backend root: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckSettingsCustomization.ps1 -RepoRoot <backend>`.
- **Backend tests.** `go test ./input_methods/rime/...` when Go is installed (native Rime tests may need `MOQI_RIME_PACKAGE_DIR` — see `AGENTS.md`).
- **Live UI (manual, Windows).** Change page size in settings UI, reopen settings, confirm value; optional screenshot without logging raw JSON.

## Gotchas

- Interface-only settings must not write Rime `common.custom.yaml` patches (`Test-TypeDuckSettingsPersistence.ps1 -Strict`).
- Do not hand-edit generated protobuf; settings cross the wire via aligned `proto/moqi.proto` in both repos.
- Applying settings while the user's production launcher is running can disrupt their session — prefer guards and unit tests unless you own the test machine.
