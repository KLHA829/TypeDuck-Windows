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
- For **pipe RPC proof** (Windows, preferred programmatic path): installed TypeDuck with `TypeDuckLauncher` running (or `VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1`), sibling **TypeDuck-Windows-backend** (protobuf Go module), Go at `Program Files\Go`, pipe `\\.\pipe\<USERNAME>\TypeDuckIME\Launcher`.
- For **runtime proof** (Windows + built tree): Win32 Debug build via `scripts/build.ps1`, then CTest candidate tests or `Invoke-TypeDuckTypingMvpProof.ps1` on a Windows machine with staged `TypeDuckRuntime`.
- For **live TSF typing** (secondary): installed IME on Windows 10/11; interactive checklist — not available in Linux CI agents.

### Primary: named-pipe `nei` smoke

Proves Launcher length-prefix framing + backend candidates without Notepad. Catches the double-`framePayload` regression class.

```powershell
# From TypeDuck-Windows repo root
$env:VERIFY_TYPEDUCK_RUN_ID = "pipe-nei-$(Get-Date -Format yyyyMMdd-HHmmss)"
# Optional only when no launcher is running:
# $env:VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER = "1"
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/pipe-nei-smoke.ps1
# equivalent:
powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId jyutping-pipe-nei
```

Pass criterion: exit `0`; log ends with `pipe-nei-probe: PASS` / `pipe-nei-smoke: OK`; composition is `nei` and candidates are non-empty (target hanzi checked in-process). Evidence: `.cursor/skills/verify-typeduck/artifacts/<RUN_ID>/jyutping-pipe-nei.log`. Transcript must not dump full candidate payloads.

### Static / unit paths

- **Candidate parser contract.** Run `powershell -NoProfile -ExecutionPolicy Bypass -File .cursor/skills/verify-typeduck/bin/run-guard.ps1 -FeatureId candidate-jyutping`. Exit code `0` and log shows `PASS` / no thrown errors.
- **Unit tests (Windows build).** After `scripts/build.ps1`, run `ctest --test-dir build-vs32 -C Debug -R TypeDuckCandidateInfo --output-on-failure`. Exit code `0`.
- **Protocol fields for candidates.** Run `run-guard.ps1 -FeatureId protocol-contract` to ensure `TypeDuckCandidatePage` and `raw_lookup_comment` remain in `proto/moqi.proto`.

### Secondary: interactive Notepad (TSF UI)

On Windows with IME installed: select TypeDuck, type `nei` in Notepad with **real key events** (not `SendKeys`), capture screenshot showing candidate window. Store under artifacts as `jyutping-compose-candidates.png`. Do not paste candidate payload text into chat logs.

## Gotchas

- Dictionary comment parsing belongs in `MoqiTextService/TypeDuckCandidateInfo.cpp` and UI in `MoqiCandidateWindow.cpp` — do not add parsing to `MoqiClient.cpp` or `proto/moqi.proto` (enforced by `Test-TypeDuckCandidateData.ps1`).
- **SendKeys bypasses IME** — PowerShell `SendKeys` / synthetic clipboard typing is not a valid TSF proof. Prefer `pipe-nei-smoke` or real keyboard events.
- **Double-frame history:** Launcher once called `framePayload` on `serializeMessageBounded` output (double length-prefix); TSF failed to parse `ServerResponse` → INIT then CLOSE, no candidates. Fixed by writing the framed payload once; regression covered by `ProtoFraming` test + protocol contract grep + this pipe smoke.
- **Mutex:** one `TypeDuckLauncher` per user. Do not start a second instance against a live session unless the operator owns stopping/replacing it. `pipe-nei-smoke` attaches to the existing process and only starts one when `VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1`.
- **Privacy:** do not log full candidate payloads, clipboard, or free-form typed content to AGENTS chat or product logs. Pipe smoke logs ASCII fixture composition and counts only.
- Cloud/Linux agents cannot host TSF or the named pipe; treating static guards as CI substitute is correct, but mark pipe/interactive drive as **Windows-host prerequisite**.
- `Invoke-TypeDuckTypingMvpProof.ps1` requires Windows, sibling backend, and built probes — not the default quick path.
