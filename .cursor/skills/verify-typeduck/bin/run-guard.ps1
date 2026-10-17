#Requires -Version 5.1
<#
.SYNOPSIS
  Run one mapped TypeDuck guard script and tee output to verification artifacts.

.PARAMETER FeatureId
  Feature slug: protocol-contract, candidate-jyutping, settings-persistence,
  launcher-protocol, tsf-identity, typing-latency-contract. Pass ListFeatures
  to print slugs.

.PARAMETER FrontendRoot
  TypeDuck-Windows root.

.PARAMETER BackendRoot
  TypeDuck-Windows-backend root (required for settings-persistence).

.PARAMETER EvidenceDir
  Directory for command transcripts (default: VERIFY_TYPEDUCK_ARTIFACTS or skill artifacts/).
#>
param(
  [Parameter(Mandatory = $true)][string] $FeatureId,
  [string] $FrontendRoot = "",
  [string] $BackendRoot = "",
  [string] $EvidenceDir = ""
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

$skillRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$frontend = Resolve-FullPath $(if ($FrontendRoot) { $FrontendRoot } else { (Join-Path $skillRoot "..\..\..") })
$backend = $null
if ($BackendRoot) {
  $backend = Resolve-FullPath $BackendRoot
} elseif ($env:BACKEND_ROOT) {
  $backend = Resolve-FullPath $env:BACKEND_ROOT
} else {
  $candidate = Join-Path ([System.IO.Path]::GetDirectoryName($frontend)) "TypeDuck-Windows-backend"
  if (Test-Path -LiteralPath $candidate) {
    $backend = Resolve-FullPath $candidate
  }
}

$known = @(
  "protocol-contract",
  "candidate-jyutping",
  "settings-persistence",
  "launcher-protocol",
  "tsf-identity",
  "typing-latency-contract"
)

if ($FeatureId -eq "ListFeatures") {
  $known | Sort-Object
  exit 0
}

if ($known -notcontains $FeatureId) {
  throw "Unknown FeatureId '$FeatureId'. Known: $($known -join ', '). Use FeatureId ListFeatures."
}

$artifactRoot = $EvidenceDir
if ([string]::IsNullOrWhiteSpace($artifactRoot)) {
  $artifactRoot = $env:VERIFY_TYPEDUCK_ARTIFACTS
}
if ([string]::IsNullOrWhiteSpace($artifactRoot)) {
  $runId = if ($env:VERIFY_TYPEDUCK_RUN_ID) { $env:VERIFY_TYPEDUCK_RUN_ID } else { [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss") }
  $artifactRoot = Join-Path $skillRoot "artifacts\$runId"
}
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$logPath = Join-Path $artifactRoot "$FeatureId-guard.log"

function Invoke-Guard {
  param(
    [string] $RelativeScript,
    [scriptblock] $Runner
  )
  $scriptPath = Join-Path $frontend $RelativeScript
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Guard script missing: $scriptPath"
  }
  Write-Host ">> $scriptPath (evidence: $logPath)"
  & $Runner
  $exit = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
  if ($exit -ne 0) {
    throw "Guard failed with exit code $exit"
  }
}

switch ($FeatureId) {
  "protocol-contract" {
    Invoke-Guard "scripts\Test-TypeDuckProtocolContract.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckProtocolContract.ps1") -RepoRoot $frontend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
  "candidate-jyutping" {
    Invoke-Guard "scripts\Test-TypeDuckCandidateData.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckCandidateData.ps1") -RepoRoot $frontend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
  "settings-persistence" {
    if (-not $backend) {
      throw "Feature 'settings-persistence' requires BACKEND_ROOT or sibling TypeDuck-Windows-backend."
    }
    Invoke-Guard "scripts\Test-TypeDuckSettingsPersistence.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckSettingsPersistence.ps1") -RepoRoot $frontend -BackendRoot $backend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
  "launcher-protocol" {
    Invoke-Guard "scripts\Test-TypeDuckLauncherProtocol.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckLauncherProtocol.ps1") -RepoRoot $frontend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
  "tsf-identity" {
    Invoke-Guard "scripts\Test-TypeDuckTsfIdentity.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckTsfIdentity.ps1") -RepoRoot $frontend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
  "typing-latency-contract" {
    Invoke-Guard "scripts\Test-TypeDuckTypingClient.ps1" {
      & (Join-Path $frontend "scripts\Test-TypeDuckTypingClient.ps1") -RepoRoot $frontend -Strict *>&1 |
        Tee-Object -FilePath $logPath
    }
  }
}

Write-Host "guard: OK ($FeatureId)"
exit 0
