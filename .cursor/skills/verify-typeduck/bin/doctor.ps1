#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only health check for TypeDuck Windows IME verification runs.

.DESCRIPTION
  Answers whether the environment is worth driving: repo layout, sibling backend,
  optional installed IME processes on Windows, and a fast static guard subset.

.PARAMETER FrontendRoot
  TypeDuck-Windows repository root (defaults to three levels above this script).

.PARAMETER BackendRoot
  TypeDuck-Windows-backend root. Uses BACKEND_ROOT env, then sibling checkout.

.PARAMETER SkipGuards
  Skip static Test-TypeDuck guard scripts (process/registry checks still run).
#>
param(
  [string] $FrontendRoot = "",
  [string] $BackendRoot = "",
  [switch] $SkipGuards
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Resolve-DefaultFrontendRoot {
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
}

function Resolve-DefaultBackendRoot([string] $FrontendRootFull) {
  if (-not [string]::IsNullOrWhiteSpace($env:BACKEND_ROOT)) {
    return Resolve-FullPath $env:BACKEND_ROOT
  }
  $parent = [System.IO.Path]::GetDirectoryName($FrontendRootFull)
  $sibling = Join-Path $parent "TypeDuck-Windows-backend"
  if (Test-Path -LiteralPath $sibling) {
    return [System.IO.Path]::GetFullPath($sibling)
  }
  return $null
}

function Test-FrontendLayout([string] $Root) {
  $required = @(
    "AGENTS.md",
    "scripts\build.ps1",
    "scripts\Test-TypeDuckProtocolContract.ps1",
    "MoqiTextService\TypeDuckProfile.cpp",
    "MoqLauncher\PipeServer.cpp"
  )
  foreach ($rel in $required) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Frontend layout check failed: missing $rel under $Root"
    }
  }
}

function Test-BackendLayout([string] $Root) {
  $required = @(
    "server.go",
    "proto\moqi.proto",
    "input_methods\rime\rime.go",
    "scripts\Test-TypeDuckSettingsCustomization.ps1"
  )
  foreach ($rel in $required) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Backend layout check failed: missing $rel under $Root"
    }
  }
}

function Get-InstalledTypeDuckSummary {
  if (-not $IsWindows) {
    return @{
      platform = "non-windows"
      installDir = $null
      launcherRunning = $false
      runtimeRunning = $false
    }
  }

  $installDir = $null
  try {
    $keyPath = "HKLM:\Software\TypeDuckIME"
    if (Test-Path -LiteralPath $keyPath) {
      $installDir = (Get-ItemProperty -LiteralPath $keyPath -Name InstallDir -ErrorAction SilentlyContinue).InstallDir
    }
  } catch {
    $installDir = $null
  }

  $launcher = Get-Process -Name "TypeDuckLauncher" -ErrorAction SilentlyContinue
  $runtime = Get-Process -Name "server" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -match "TypeDuckRuntime" }

  return @{
    platform = "windows"
    installDir = $installDir
    launcherRunning = [bool]$launcher
    runtimeRunning = [bool]$runtime
  }
}

$frontend = Resolve-FullPath $(if ($FrontendRoot) { $FrontendRoot } else { Resolve-DefaultFrontendRoot })
if (-not $frontend) {
  throw "Could not resolve TypeDuck-Windows root."
}

$backend = Resolve-FullPath $(if ($BackendRoot) { $BackendRoot } else { Resolve-DefaultBackendRoot $frontend })

Write-Host "verify-typeduck doctor"
Write-Host "  frontend: $frontend"
Write-Host "  backend:  $(if ($backend) { $backend } else { '(not found — set BACKEND_ROOT or clone TypeDuck-Windows-backend)' })"
Write-Host "  os:       $($IsWindows ? 'Windows' : 'non-Windows (static guards only; live TSF requires Windows 10/11)')"

Test-FrontendLayout $frontend
Write-Host "  layout:   frontend OK"

if ($backend) {
  Test-BackendLayout $backend
  Write-Host "  layout:   backend OK"
} else {
  Write-Warning "Backend root missing; settings-persistence and backend go test features will be unreachable."
}

$install = Get-InstalledTypeDuckSummary
Write-Host "  install:  platform=$($install.platform) installDir=$($install.installDir) launcher=$($install.launcherRunning) runtime=$($install.runtimeRunning)"

if ($IsWindows -and $install.launcherRunning) {
  Write-Warning "TypeDuckLauncher is already running. Do not start a second launcher instance (single-instance mutex). Prefer static guards or stop only processes you started for verification."
}

if (-not $SkipGuards) {
  $strict = @{ RepoRoot = $frontend; Strict = $true }
  Write-Host ">> static guard: Test-TypeDuckProtocolContract.ps1"
  & (Join-Path $frontend "scripts\Test-TypeDuckProtocolContract.ps1") @strict
  Write-Host ">> static guard: Test-TypeDuckTsfIdentity.ps1"
  & (Join-Path $frontend "scripts\Test-TypeDuckTsfIdentity.ps1") @strict
  if ($backend) {
    Write-Host ">> static guard: Test-TypeDuckSettingsPersistence.ps1"
    & (Join-Path $frontend "scripts\Test-TypeDuckSettingsPersistence.ps1") -RepoRoot $frontend -BackendRoot $backend -Strict
  }
}

Write-Host "doctor: OK"
exit 0
