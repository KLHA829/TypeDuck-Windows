#Requires -Version 5.1
<#
.SYNOPSIS
  Static checks for Launcher pipe doctor rules and launcher identity guard sources.

.PARAMETER RepoRoot
  TypeDuck-Windows repository root.
#>
param(
  [string] $RepoRoot = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  param([string] $RequestedRoot)
  if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  }
  return [System.IO.Path]::GetFullPath($RequestedRoot)
}

$root = Resolve-RepoRoot $RepoRoot
$doctorHelpers = Join-Path $root ".cursor\skills\verify-typeduck\bin\LauncherPipeDoctor.ps1"
if (-not (Test-Path -LiteralPath $doctorHelpers)) {
  throw "Missing LauncherPipeDoctor.ps1 under $root"
}
. $doctorHelpers

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string] $Message) {
  $failures.Add($Message) | Out-Null
}

# Pure rule: SYSTEM pipe segment must FAIL when interactive user is Aidan.
if (Test-TypeDuckLauncherPipeUserSegmentRule -LiveSegment "SYSTEM" -InteractiveUser "Aidan") {
  Add-Failure "Pipe user rule should FAIL when live segment is SYSTEM and interactive user is Aidan."
}
if (-not (Test-TypeDuckLauncherPipeUserSegmentRule -LiveSegment "Aidan" -InteractiveUser "Aidan")) {
  Add-Failure "Pipe user rule should PASS when live segment matches interactive user (case-sensitive name)."
}
if (-not (Test-TypeDuckLauncherPipeUserSegmentRule -LiveSegment "aidan" -InteractiveUser "Aidan")) {
  Add-Failure "Pipe user rule should PASS case-insensitively."
}

$pipeServer = Join-Path $root "MoqLauncher\PipeServer.cpp"
$identityCpp = Join-Path $root "MoqLauncher\LauncherProcessIdentity.cpp"
if (-not (Test-Path -LiteralPath $pipeServer)) {
  Add-Failure "Missing MoqLauncher\PipeServer.cpp"
}
if (-not (Test-Path -LiteralPath $identityCpp)) {
  Add-Failure "Missing MoqLauncher\LauncherProcessIdentity.cpp"
}

if ($failures.Count -eq 0) {
  $pipeText = [System.IO.File]::ReadAllText($pipeServer)
  $identityText = [System.IO.File]::ReadAllText($identityCpp)
  if ($pipeText -notmatch "isLauncherProcessIdentityAllowed") {
    Add-Failure "PipeServer.cpp must refuse wrong identity via isLauncherProcessIdentityAllowed."
  }
  if ($pipeText -notmatch "exitCodeForExistingLauncherMutexConflict") {
    Add-Failure "PipeServer.cpp must surface mutex conflicts via exitCodeForExistingLauncherMutexConflict."
  }
  if ($identityText -notmatch "TokenElevation") {
    Add-Failure "LauncherProcessIdentity.cpp must check TokenElevation."
  }
  if ($identityText -notmatch "WinLocalSystemSid") {
    Add-Failure "LauncherProcessIdentity.cpp must reject LocalSystem SID."
  }
  if ($identityText -notmatch "SECURITY_MANDATORY_MEDIUM_RID") {
    Add-Failure "LauncherProcessIdentity.cpp must reject integrity above Medium."
  }
  # Ensure identity check runs before CreateMutex in exec().
  $mutexPos = $pipeText.IndexOf("initSingleInstance")
  $identityPos = $pipeText.IndexOf("isLauncherProcessIdentityAllowed")
  if ($identityPos -lt 0 -or $mutexPos -lt 0 -or $identityPos -gt $mutexPos) {
    Add-Failure "isLauncherProcessIdentityAllowed must be called before initSingleInstance in PipeServer::exec."
  }
}

$doctorPath = Join-Path $root ".cursor\skills\verify-typeduck\bin\doctor.ps1"
$doctorText = [System.IO.File]::ReadAllText($doctorPath)
if ($doctorText -notmatch "Assert-TypeDuckLauncherPipeMatchesInteractiveUser") {
  Add-Failure "doctor.ps1 must call Assert-TypeDuckLauncherPipeMatchesInteractiveUser."
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Host "Test-TypeDuckLauncherPipeDoctor: OK"
exit 0
