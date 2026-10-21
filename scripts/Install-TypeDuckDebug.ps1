#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy TypeDuck Windows binaries to a user-writable debug root (no Program Files / UAC for copy).

.DESCRIPTION
  Copies Launcher, settings/about apps, and TypeDuckRuntime from local CMake build outputs into
  %LOCALAPPDATA%\TypeDuckIME-debug (or -DebugRoot). Does not replace the official installer path.

  Point iterative development at the debug tree with:
    setx TYPEDUCK_PROGRAM_DIR "%LOCALAPPDATA%\TypeDuckIME-debug"
  Then restart TypeDuckLauncher from that directory (or add it to PATH for manual runs).

  TSF registration still requires elevation once (regsvr32 for TypeDuckTextService.dll). This script
  can stage TSF DLLs under the debug root for convenience but does not copy into System32.

.PARAMETER RepoRoot
  TypeDuck-Windows repository root.

.PARAMETER Win32BuildDir
  CMake Win32 output directory (default: RepoRoot\build-vs32).

.PARAMETER X64BuildDir
  CMake x64 output directory (default: RepoRoot\build-vs64).

.PARAMETER DebugRoot
  User-writable install root (default: %LOCALAPPDATA%\TypeDuckIME-debug).

.PARAMETER RuntimeSource
  Path to a staged TypeDuckRuntime tree. When omitted, uses Win32BuildDir\..\runtime or sibling backend output if present.

.PARAMETER SkipRuntime
  Skip copying TypeDuckRuntime (launcher-only refresh).
#>
param(
  [string] $RepoRoot = "",
  [string] $Win32BuildDir = "",
  [string] $X64BuildDir = "",
  [string] $DebugRoot = "",
  [string] $RuntimeSource = "",
  [switch] $SkipRuntime
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

$root = Resolve-FullPath $(if ($RepoRoot) { $RepoRoot } else { (Join-Path $PSScriptRoot "..") })
$win32 = Resolve-FullPath $(if ($Win32BuildDir) { $Win32BuildDir } else { (Join-Path $root "build-vs32") })
$x64 = Resolve-FullPath $(if ($X64BuildDir) { $X64BuildDir } else { (Join-Path $root "build-vs64") })
$debugRoot = Resolve-FullPath $(if ($DebugRoot) { $DebugRoot } else { Join-Path $env:LOCALAPPDATA "TypeDuckIME-debug" })

function Copy-IfExists {
  param(
    [string] $Source,
    [string] $Destination
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Required artifact missing: $Source"
  }
  $destDir = Split-Path -Parent $Destination
  if ($destDir) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Find-ConfigArtifact {
  param(
    [string] $BuildDir,
    [string] $RelativePath,
    [string[]] $Configs = @("Debug", "Release")
  )
  foreach ($config in $Configs) {
    $candidate = Join-Path $BuildDir ($RelativePath -replace "{config}", $config)
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  throw "Artifact not found under $BuildDir for $RelativePath"
}

Write-Host "TypeDuck debug deploy root: $debugRoot"
New-Item -ItemType Directory -Path $debugRoot -Force | Out-Null

$launcher = Find-ConfigArtifact $win32 "MoqLauncher\{config}\TypeDuckLauncher.exe"
Copy-IfExists $launcher (Join-Path $debugRoot "TypeDuckLauncher.exe")

$settings = Find-ConfigArtifact $win32 "TypeDuckSettings\{config}\TypeDuckSettings.exe"
Copy-IfExists $settings (Join-Path $debugRoot "TypeDuckSettings.exe")

$about = $null
foreach ($config in @("Debug", "Release")) {
  $aboutCandidate = Join-Path $win32 "TypeDuckAbout\$config\TypeDuckAbout.exe"
  if (Test-Path -LiteralPath $aboutCandidate) {
    $about = $aboutCandidate
    break
  }
}
if ($about) {
  Copy-IfExists $about (Join-Path $debugRoot "TypeDuckAbout.exe")
} else {
  Write-Host "Note: TypeDuckAbout.exe not built; skipping optional About staging."
}

$tsf32 = Find-ConfigArtifact $win32 "MoqiTextService\{config}\TypeDuckTextService.dll"
Copy-IfExists $tsf32 (Join-Path $debugRoot "win32\TypeDuckTextService.dll")

if (Test-Path -LiteralPath $x64) {
  try {
    $tsf64 = Find-ConfigArtifact $x64 "MoqiTextService\{config}\TypeDuckTextService.dll"
    Copy-IfExists $tsf64 (Join-Path $debugRoot "x64\TypeDuckTextService.dll")
  }
  catch {
    Write-Host "Note: x64 TypeDuckTextService.dll not found; win32-only debug staging."
  }
}

if (-not $SkipRuntime) {
  $runtimeSource = Resolve-FullPath $RuntimeSource
  if (-not $runtimeSource) {
    $backendRoot = Join-Path ([System.IO.Path]::GetDirectoryName($root)) "TypeDuck-Windows-backend"
    $candidates = @(
      (Join-Path $root "runtime\TypeDuckRuntime"),
      (Join-Path $root "installer\stage\win32\TypeDuckIME\TypeDuckRuntime"),
      (Join-Path $backendRoot "scripts\build\TypeDuckRuntime"),
      (Join-Path $backendRoot "build\TypeDuckRuntime")
    )
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath (Join-Path $candidate "server.exe")) {
        $runtimeSource = $candidate
        break
      }
    }
  }
  if (-not $runtimeSource -or -not (Test-Path -LiteralPath (Join-Path $runtimeSource "server.exe"))) {
    throw "TypeDuckRuntime source not found. Pass -RuntimeSource or build/package backend runtime."
  }
  $runtimeDest = Join-Path $debugRoot "TypeDuckRuntime"
  if (Test-Path -LiteralPath $runtimeDest) {
    Remove-Item -LiteralPath $runtimeDest -Recurse -Force
  }
  Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDest -Recurse -Force
}

$readme = @"
TypeDuck debug install (user-writable)
=====================================

Root: $debugRoot

Launcher / settings:
  Start TypeDuckLauncher.exe from this folder after setting:
    TYPEDUCK_PROGRAM_DIR=$debugRoot

Official Program Files install is unchanged. Use scripts/install.ps1 for release installers.

Limits:
  - TSF DLL registration (regsvr32) still needs elevation once per machine/bitness.
  - Windows may keep using system32-copied TSF DLLs until SetupHelper reinstalls them.
  - Only one TypeDuckLauncher per user (TypeDuckLauncherMutex); stop the tray app before swapping trees.

Logs: %LOCALAPPDATA%\TypeDuckIME\Log\TypeDuckLauncher.log
"@
Set-Content -LiteralPath (Join-Path $debugRoot "DEBUG-INSTALL.txt") -Value $readme -Encoding UTF8

Write-Host "Debug install staged. Set TYPEDUCK_PROGRAM_DIR to: $debugRoot"
Write-Host "詳情請見 DEBUG-INSTALL.txt / See DEBUG-INSTALL.txt in the debug root."
