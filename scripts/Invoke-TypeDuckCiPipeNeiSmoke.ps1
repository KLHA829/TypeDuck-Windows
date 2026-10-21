#Requires -Version 5.1
<#
.SYNOPSIS
  CI gate: stage debug Launcher + TypeDuckRuntime, start Launcher, run jyutping pipe-nei smoke.

.DESCRIPTION
  Builds the backend TypeDuckRuntime package when needed, stages frontend Debug binaries via
  Install-TypeDuckDebug.ps1, then runs verify-typeduck pipe-nei-smoke with launcher auto-start.
  Fails the step on any staging, start, or probe error (no skip when Launcher is absent).

.PARAMETER RepoRoot
  TypeDuck-Windows repository root.

.PARAMETER BackendRoot
  TypeDuck-Windows-backend checkout root.

.PARAMETER RimeDataSource
  Rime schema/data tree (default: RepoRoot\..\TypeDuck-HK-schema or GITHUB_WORKSPACE\TypeDuck-HK-schema).

.PARAMETER RuntimePackageDir
  Prebuilt TypeDuckRuntime directory. When omitted, builds via backend scripts\build.ps1.

.PARAMETER SkipRuntimeBuild
  Require RuntimePackageDir (or an existing backend scripts\build\TypeDuckRuntime tree).

.PARAMETER DebugRoot
  User-writable staging root (default: %LOCALAPPDATA%\TypeDuckIME-debug).
#>
param(
  [string] $RepoRoot = "",
  [string] $BackendRoot = "",
  [string] $RimeDataSource = "",
  [string] $RuntimePackageDir = "",
  [string] $DebugRoot = "",
  [switch] $SkipRuntimeBuild
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

$root = Resolve-FullPath $(if ($RepoRoot) { $RepoRoot } else { (Join-Path $PSScriptRoot "..") })
$backend = Resolve-FullPath $BackendRoot
if (-not $backend) {
  $backend = Resolve-FullPath $env:BACKEND_ROOT
}
if (-not $backend) {
  $sibling = Join-Path ([System.IO.Path]::GetDirectoryName($root)) "TypeDuck-Windows-backend"
  if (Test-Path -LiteralPath $sibling) {
    $backend = Resolve-FullPath $sibling
  }
}
if (-not $backend -or -not (Test-Path -LiteralPath (Join-Path $backend "scripts\build.ps1"))) {
  throw "Backend root required (BackendRoot / BACKEND_ROOT / sibling TypeDuck-Windows-backend)."
}

$defaultRuntime = Join-Path $backend "scripts\build\TypeDuckRuntime"
$runtimeDir = Resolve-FullPath $RuntimePackageDir
if (-not $runtimeDir -and (Test-Path -LiteralPath (Join-Path $defaultRuntime "server.exe"))) {
  $runtimeDir = $defaultRuntime
}

if (-not $runtimeDir) {
  if ($SkipRuntimeBuild) {
    throw "SkipRuntimeBuild set but TypeDuckRuntime package is missing at $defaultRuntime. Pass -RuntimePackageDir."
  }

  $rime = Resolve-FullPath $RimeDataSource
  if (-not $rime) {
    $candidates = @(
      (Join-Path $env:GITHUB_WORKSPACE "TypeDuck-HK-schema"),
      (Join-Path ([System.IO.Path]::GetDirectoryName($root)) "TypeDuck-HK-schema")
    )
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath (Join-Path $candidate "default.yaml")) {
        $rime = Resolve-FullPath $candidate
        break
      }
    }
  }
  if (-not $rime -or -not (Test-Path -LiteralPath (Join-Path $rime "default.yaml"))) {
    throw "RimeDataSource required (checkout TypeDuck-HK/schema ref desktop as TypeDuck-HK-schema)."
  }

  Write-Host ">> Building TypeDuckRuntime (backend)"
  $buildScript = Join-Path $backend "scripts\build.ps1"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $buildScript -RepoRoot $backend -RimeDataSource $rime
  if ($LASTEXITCODE -ne 0) {
    throw "Backend runtime build failed with exit $LASTEXITCODE"
  }
  $runtimeDir = $defaultRuntime
}

if (-not (Test-Path -LiteralPath (Join-Path $runtimeDir "server.exe"))) {
  throw "TypeDuckRuntime missing server.exe under $runtimeDir"
}

$debugRoot = Resolve-FullPath $DebugRoot
if (-not $debugRoot) {
  $debugRoot = Join-Path $env:LOCALAPPDATA "TypeDuckIME-debug"
}

$installScript = Join-Path $root "scripts\Install-TypeDuckDebug.ps1"
Write-Host ">> Staging debug install at $debugRoot"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript `
  -RepoRoot $root `
  -DebugRoot $debugRoot `
  -RuntimeSource $runtimeDir
if ($LASTEXITCODE -ne 0) {
  throw "Install-TypeDuckDebug failed with exit $LASTEXITCODE"
}

$existingLauncher = @(Get-Process -Name "TypeDuckLauncher" -ErrorAction SilentlyContinue)
if ($existingLauncher.Count -gt 0) {
  throw "TypeDuckLauncher already running on this runner (pid=$($existingLauncher[0].Id)). CI requires a clean session for pipe-nei."
}

$runId = $env:VERIFY_TYPEDUCK_RUN_ID
if ([string]::IsNullOrWhiteSpace($runId)) {
  if ($env:GITHUB_RUN_ID) {
    $runId = "ci-$($env:GITHUB_RUN_ID)"
  } else {
    $runId = "ci-$(Get-Date -Format yyyyMMdd-HHmmss)"
  }
}

$env:TYPEDUCK_PROGRAM_DIR = $debugRoot
$env:VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER = "1"
$env:VERIFY_TYPEDUCK_RUN_ID = $runId

$smokeScript = Join-Path $root ".cursor\skills\verify-typeduck\bin\pipe-nei-smoke.ps1"
Write-Host ">> pipe-nei-smoke (required CI gate) runId=$runId programDir=$debugRoot"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $smokeScript `
  -FrontendRoot $root `
  -BackendRoot $backend `
  -ProgramDir $debugRoot
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Invoke-TypeDuckCiPipeNeiSmoke: OK"
exit 0
