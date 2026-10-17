# Typing latency and diagnostics

A developer or support engineer needs evidence that key events stay within bounded latency, that diagnostic logging is available without leaking typed content, and that optional latency traces can be enabled on Windows installs.

## Sub-features

- `key-latency-contract` — Phase 4 `ordinary-key-response-latency` case in `typing-client.json` and TSF client bounds in `MoqiClient.cpp`.
- `launcher-logs` — rotating log at `%LOCALAPPDATA%\TypeDuckIME\Log\TypeDuckLauncher.log` (see `MoqLauncher/PipeServer.cpp`).
- `launcher-config-trace` — `%LOCALAPPDATA%\TypeDuckIME\TypeDuckLauncher.json` with `"logLevel": "trace"` increases backend `traceLogf` output when read via `input_methods/rime/debug_logging.go`.
- `latency-ndjson-env` — product builds may honor `TYPEDUCK_LATENCY_TRACE=1` writing `%LOCALAPPDATA%\TypeDuckIME\Log\latency-trace.ndjson` (verify in source before relying; not present in all checkouts).

## How to get to it (user POV)

- Normal typing should feel immediate; noticeable lag may indicate backend restart or degraded health.
- Advanced: edit `TypeDuckLauncher.json` log level or enable latency trace env var (when supported), reproduce typing, inspect logs under `%LOCALAPPDATA%\TypeDuckIME\Log\`.

## Driving it with verify-typeduck

Preconditions:

- Frontend repo; Windows for log files and live latency measurement.

- **Static typing-client contract.** `run-guard.ps1 -FeatureId typing-latency-contract` — asserts `ordinary-key-response-latency` and related runtime cases in `.planning/product/protocol-fixtures/phase-04/typing-client.json`.
- **Typing MVP evidence schema.** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckTypingMvpProof.ps1 -RepoRoot . -Strict` validates evidence JSON (full exercise needs `Invoke-TypeDuckTypingMvpProof.ps1` on Windows).
- **Privacy guard.** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TypeDuckPrivacySecurityCleanup.ps1 -RepoRoot . -BackendRoot $BACKEND_ROOT` — ensures logs do not embed secrets or typed payloads.
- **Optional latency NDJSON.** On Windows, if `TYPEDUCK_LATENCY_TRACE` is documented in launcher/runtime sources: set env var, restart only a verification-owned launcher, type a short fixed string (`nei`), confirm `latency-trace.ndjson` exists and contains timing records without hanzi payload bodies. If the symbol is absent from source, report **unreachable in this checkout** and use static contract + CTest instead.
- **Engine frame log (probe builds).** `.planning/product/engine-runtime-fixtures/phase-02/backend-stdio-frames.ndjson` from `Invoke-TypeDuckEngineProof.ps1` — controlled inputs only.

## Gotchas

- A search of TypeDuck-Windows and TypeDuck-Windows-backend may show **no** `TYPEDUCK_LATENCY_TRACE` or `latency-trace.ndjson` references yet; do not invent a fake trace file. Use `typing-latency-contract` guard and Windows MVP proof runners until the env var lands.
- Never commit or upload real user `TypeDuckLauncher.log` contents to PRs; redact or use controlled VMs.
- Latency proof in CI is via guards and CTest, not TSF in `windows-2022` alone unless MVP proof runner is explicitly invoked with built artifacts.
