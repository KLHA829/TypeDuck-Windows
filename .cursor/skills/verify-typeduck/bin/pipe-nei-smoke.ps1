#Requires -Version 5.1
<#
.SYNOPSIS
  Named-pipe RPC smoke: type fixed Jyutping "nei" via Launcher pipe; prove candidates.

.DESCRIPTION
  Primary programmatic proof that Launcher framing + backend candidates work
  (catches double-frame regressions). Does not drive TSF/Notepad.

  Requires TypeDuckLauncher already running (non-elevated), OR starts
  InstallDir\TypeDuckLauncher.exe when VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1.
  Never kills a launcher it did not start.

.PARAMETER FrontendRoot
  TypeDuck-Windows root (default: three levels above this script).

.PARAMETER BackendRoot
  TypeDuck-Windows-backend root (BACKEND_ROOT env or sibling).

.PARAMETER EvidenceDir
  Artifact directory (default: artifacts/<VERIFY_TYPEDUCK_RUN_ID>/).
#>
param(
  [string] $FrontendRoot = "",
  [string] $BackendRoot = "",
  [string] $EvidenceDir = ""
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Test-IsWindowsHost {
  if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    return [bool]$IsWindows
  }
  return ($env:OS -eq "Windows_NT")
}

function Get-GoExe {
  $candidates = @(
    (Join-Path ${env:ProgramFiles} "Go\bin\go.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Go\bin\go.exe")
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  $cmd = Get-Command go -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-InstallDir {
  $keyPath = "HKLM:\Software\TypeDuckIME"
  if (-not (Test-Path -LiteralPath $keyPath)) { return $null }
  return (Get-ItemProperty -LiteralPath $keyPath -Name InstallDir -ErrorAction SilentlyContinue).InstallDir
}

$skillRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$frontend = Resolve-FullPath $(if ($FrontendRoot) { $FrontendRoot } else { (Join-Path $skillRoot "..\..\..") })
$backend = $null
if ($BackendRoot) {
  $backend = Resolve-FullPath $BackendRoot
} elseif ($env:BACKEND_ROOT) {
  $backend = Resolve-FullPath $env:BACKEND_ROOT
} else {
  $sibling = Join-Path ([System.IO.Path]::GetDirectoryName($frontend)) "TypeDuck-Windows-backend"
  if (Test-Path -LiteralPath $sibling) {
    $backend = Resolve-FullPath $sibling
  }
}

if (-not (Test-IsWindowsHost)) {
  throw "pipe-nei-smoke requires Windows (named pipe + installed Launcher)."
}
if (-not $backend) {
  throw "Backend root required (BACKEND_ROOT or sibling TypeDuck-Windows-backend) for protobuf Go module."
}
if (-not (Test-Path -LiteralPath (Join-Path $backend "proto"))) {
  throw "Backend proto package missing under $backend"
}

$goExe = Get-GoExe
if (-not $goExe) {
  throw "Go toolchain not found. Expected under Program Files\Go\bin\go.exe"
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
$logPath = Join-Path $artifactRoot "jyutping-pipe-nei.log"
$scratch = Join-Path $artifactRoot "pipe-nei-probe-scratch"
if (Test-Path -LiteralPath $scratch) {
  Remove-Item -LiteralPath $scratch -Recurse -Force
}
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

$startedLauncher = $false
$launcherProc = $null
$existing = @(Get-Process -Name "TypeDuckLauncher" -ErrorAction SilentlyContinue)
if ($existing.Count -eq 0) {
  $allow = $env:VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER
  if ($allow -ne "1") {
    throw "TypeDuckLauncher is not running. Start it from the tray/install, or set VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1 to let this script start InstallDir\TypeDuckLauncher.exe (non-elevated)."
  }
  $installDir = Get-InstallDir
  if (-not $installDir) {
    throw "HKLM\Software\TypeDuckIME\InstallDir missing; cannot start Launcher."
  }
  $launcherPath = Join-Path $installDir "TypeDuckLauncher.exe"
  if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Launcher binary missing: $launcherPath"
  }
  Write-Host "pipe-nei-smoke: starting Launcher (VERIFY_TYPEDUCK_ALLOW_START_LAUNCHER=1): $launcherPath"
  $launcherProc = Start-Process -FilePath $launcherPath -PassThru -WindowStyle Hidden
  $startedLauncher = $true
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $pipeUser = $env:USERNAME
    $pipePathCheck = "\\.\pipe\$pipeUser\TypeDuckIME\Launcher"
    # Named pipes are not normal files; brief wait then probe dial via Go.
    if (Get-Process -Name "TypeDuckLauncher" -ErrorAction SilentlyContinue) {
      $ready = $true
      break
    }
  }
  if (-not $ready) {
    throw "Launcher process did not stay up after start."
  }
  Start-Sleep -Seconds 2
} else {
  Write-Host "pipe-nei-smoke: using existing TypeDuckLauncher (pid=$($existing[0].Id)); will not kill on cleanup"
}

$probeSrc = Join-Path $PSScriptRoot "pipe-nei-probe"
Copy-Item -LiteralPath (Join-Path $probeSrc "main.go") -Destination (Join-Path $scratch "main.go") -Force

$backendSlash = ($backend -replace '\\', '/')
$gomod = @"
module pipeprobe

go 1.22.0

require (
	github.com/Microsoft/go-winio v0.6.2
	github.com/gaboolic/moqi-ime v0.0.0
	google.golang.org/protobuf v1.36.11
)

require golang.org/x/sys v0.10.0 // indirect

replace github.com/gaboolic/moqi-ime => $backendSlash
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $scratch "go.mod"), ($gomod -replace "`r`n", "`n"), $utf8NoBom)

$pipeUser = $env:USERNAME
if ([string]::IsNullOrWhiteSpace($pipeUser)) { $pipeUser = "Aidan" }
$env:TYPEDUCK_PIPE_PATH = "\\.\pipe\$pipeUser\TypeDuckIME\Launcher"
$env:TYPEDUCK_PIPE_TARGET_RUNE = [char]0x4F60  # 你

$transcript = New-Object System.Collections.Generic.List[string]
function Write-Log([string] $Line) {
  Write-Host $Line
  $transcript.Add($Line) | Out-Null
}

Write-Log "pipe-nei-smoke: frontend=$frontend"
Write-Log "pipe-nei-smoke: backend=$backend"
Write-Log "pipe-nei-smoke: go=$goExe"
Write-Log "pipe-nei-smoke: pipe=$($env:TYPEDUCK_PIPE_PATH)"
Write-Log "pipe-nei-smoke: scratch=$scratch"
Write-Log "pipe-nei-smoke: evidence=$logPath"
Write-Log "pipe-nei-smoke: startedLauncher=$startedLauncher"

$exitCode = 1
try {
  Push-Location $scratch
  try {
    # Native go stderr must not trip $ErrorActionPreference Stop
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      Write-Log ">> go mod tidy"
      $tidyOut = & $goExe mod tidy 2>&1 | ForEach-Object { "$_" }
      $tidyExit = $LASTEXITCODE
      foreach ($line in $tidyOut) { Write-Log $line }
      if ($tidyExit -ne 0) {
        throw "go mod tidy failed with exit $tidyExit"
      }

      Write-Log ">> go run ."
      $runOut = & $goExe run . 2>&1 | ForEach-Object { "$_" }
      $exitCode = $LASTEXITCODE
      foreach ($line in $runOut) { Write-Log $line }
      if ($null -eq $exitCode) { $exitCode = 0 }
    } finally {
      $ErrorActionPreference = $prevEap
    }
  } finally {
    Pop-Location
  }
} finally {
  # Evidence must survive cleanup.
  ($transcript -join "`r`n") + "`r`n" | Set-Content -LiteralPath $logPath -Encoding UTF8

  if ($startedLauncher -and $launcherProc) {
    Write-Host "pipe-nei-smoke: stopping Launcher we started (pid=$($launcherProc.Id))"
    try {
      Stop-Process -Id $launcherProc.Id -Force -ErrorAction SilentlyContinue
    } catch {}
  }

  # Scratch is under artifacts; keep it for debugging this run (artifacts are gitignored).
}

if ($exitCode -ne 0) {
  Write-Host "pipe-nei-smoke: FAIL (exit $exitCode); see $logPath"
  exit $exitCode
}
Write-Host "pipe-nei-smoke: OK"
Write-Host "evidence: $logPath"
exit 0
