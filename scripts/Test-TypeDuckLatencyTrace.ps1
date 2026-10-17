param(
  [string] $RepoRoot = ".",
  [switch] $Strict
)

$ErrorActionPreference = "Stop"

function Fail-LatencyGuard {
  param([string] $Message)
  Write-Error "TypeDuck latency trace guard failure: $Message"
}

function Require-Text {
  param(
    [string] $Content,
    [string] $Pattern,
    [string] $Message
  )
  if ($Content -notmatch $Pattern) {
    Fail-LatencyGuard $Message
  }
}

$root = (Resolve-Path $RepoRoot).Path
$protoPath = Join-Path $root "proto/moqi.proto"
$traceCpp = Join-Path $root "MoqLauncher/TypeDuckLatencyTrace.cpp"
$traceH = Join-Path $root "MoqLauncher/TypeDuckLatencyTrace.h"
$clientCpp = Join-Path $root "MoqiTextService/MoqiClient.cpp"
$pipeClientCpp = Join-Path $root "MoqLauncher/PipeClient.cpp"
$backendCpp = Join-Path $root "MoqLauncher/BackendServer.cpp"

foreach ($path in @($protoPath, $traceCpp, $traceH, $clientCpp, $pipeClientCpp, $backendCpp)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Fail-LatencyGuard "Missing required file: $path"
  }
}

$proto = Get-Content -Raw -LiteralPath $protoPath
$traceSource = Get-Content -Raw -LiteralPath $traceCpp
$traceHeader = Get-Content -Raw -LiteralPath $traceH
$clientSource = Get-Content -Raw -LiteralPath $clientCpp
$pipeClientSource = Get-Content -Raw -LiteralPath $pipeClientCpp
$backendSource = Get-Content -Raw -LiteralPath $backendCpp
$joined = "$traceSource`n$traceHeader`n$clientSource`n$pipeClientSource"

Require-Text $proto "message\s+TypeDuckLatencyReport" "proto/moqi.proto must define TypeDuckLatencyReport."
Require-Text $proto "typeduck_latency_trace\s*=\s*32" "ClientRequest must expose typeduck_latency_trace."
Require-Text $proto "typeduck_latency_report\s*=\s*35" "ServerResponse must expose typeduck_latency_report."

Require-Text $traceSource "TYPEDUCK_LATENCY_TRACE" "Latency trace must gate on TYPEDUCK_LATENCY_TRACE."
Require-Text $traceSource "latency-trace\.ndjson" "Latency trace must write a dedicated local log file."
Require-Text $traceSource "typeduck_latency" "Latency trace log event name must be typeduck_latency."
Require-Text $clientSource "typeduck_latency_trace" "TSF client must set typeduck_latency_trace on key-path RPC."
Require-Text $pipeClientSource "annotateLatencyResponse" "Launcher must annotate backend latency hops on responses."
Require-Text $backendSource "TYPEDUCK_LATENCY_TRACE" "Backend bridge must forward TYPEDUCK_LATENCY_TRACE to runtime."

$forbiddenLogPatterns = @(
  "compositionString",
  "candidateList",
  "candidateEntries",
  "commitString",
  "rawLookupComment",
  "clipboard"
)
foreach ($pattern in $forbiddenLogPatterns) {
  if ($traceSource -match $pattern -or $traceHeader -match $pattern) {
    Fail-LatencyGuard "Latency trace source must not reference sensitive payload field '$pattern'."
  }
}

if ($traceSource -match 'appendLatencyLogLine\([\s\S]*?(composition|candidate|commit|clipboard)') {
  Fail-LatencyGuard "Latency trace logging must remain metadata-only."
}

if ($Strict) {
  Require-Text $joined "tsf_named_pipe_rtt" "Strict mode requires TSF named-pipe hop instrumentation."
  Require-Text $joined "launcher_backend_stdio_rtt" "Strict mode requires launcher backend stdio RTT hop."
  Require-Text $joined "tsf_candidate_ui" "Strict mode requires candidate UI hop hook."
}

Write-Host "TypeDuck latency trace guard passed."
