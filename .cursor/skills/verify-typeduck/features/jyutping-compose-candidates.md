# Jyutping composition and candidate display

A user types Cantonese Jyutping in any text field, sees a TypeDuck candidate window with hanzi choices and dictionary-style lookup comments (including romanization), and commits a candidate into the document.

## Sub-features

- `compose-jyutping` — keystrokes build an in-progress Jyutping buffer shown in the candidate UI.
- `candidate-page` — multiple candidates with page metadata from the TypeDuck protocol.
- `lookup-comments` — raw `rime-dictionary-lookup-filter` comments preserved for frontend formatting (not parsed in transport).
- `commit-selection` — chosen candidate inserts text into the host application.

## How to get to it (user POV)

- Install TypeDuck, switch keyboard to **中文（繁體，香港）**, select **TypeDuck 粵語輸入法 / TypeDuck Cantonese IME**.
- Open Notepad or any app that accepts text, click the document, type Jyutping (for example `nei`), use number keys or space to highlight a candidate, confirm to commit.

## Driving it with verify-typeduck

Preconditions:

- For **static proof** (any OS): TypeDuck-Windows checkout with `Tests/TypeDuckCandidateData/` and fixtures under `.planning/product/candidate-fixtures/`.
- For **runtime proof** (Windows + built tree): Win32 Debug build via `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1`, then CTest candidate tests or `Invoke-TypeDuckTypingMvpProof.ps1` on a Windows machine with staged `TypeDuckRuntime`.
- For **live TSF typing**: installed IME on Windows 10/11; follow interactive checklist — not available in Linux CI agents.

- **Candidate parser contract.** Run `pwsh -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId candidate-jyutping`. Exit code `0` and log shows `PASS` / no thrown errors.
- **Unit tests (Windows build).** After `scripts/build.ps1`, run `ctest --test-dir build-vs32 -C Debug -R TypeDuckCandidateInfo --output-on-failure`. Exit code `0`.
- **Protocol fields for candidates.** Run `run-guard.ps1 -FeatureId protocol-contract` to ensure `TypeDuckCandidatePage` and `raw_lookup_comment` remain in `proto/moqi.proto`.
- **Live host proof (manual).** On Windows with IME installed: type `nei` in Notepad, capture screenshot showing candidate window and Jyutping/comment line. Store under artifacts as `jyutping-compose-candidates.png`. Do not paste candidate payload text into logs.

## Gotchas

- Dictionary comment parsing belongs in `MoqiTextService/TypeDuckCandidateInfo.cpp` and UI in `MoqiCandidateWindow.cpp` — do not add parsing to `MoqiClient.cpp` or `proto/moqi.proto` (enforced by `Test-TypeDuckCandidateData.ps1`).
- Cloud/Linux agents cannot host TSF; treating guard scripts as a substitute for live typing is correct in CI, but mark interactive drive as **Windows-host prerequisite**.
- `Invoke-TypeDuckTypingMvpProof.ps1` requires Windows, sibling backend, and built probes — not the default quick path.
