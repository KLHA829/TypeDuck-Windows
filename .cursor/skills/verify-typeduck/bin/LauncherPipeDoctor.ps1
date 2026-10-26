#Requires -Version 5.1
<#
.SYNOPSIS
  Helpers for verify-typeduck doctor: ensure the live Launcher pipe matches $env:USERNAME.
#>

function Test-TypeDuckLauncherPipePresent {
  param(
    [Parameter(Mandatory = $true)]
    [string] $UserSegment
  )

  if ([string]::IsNullOrWhiteSpace($UserSegment)) {
    return $false
  }

  $pipePath = "\\.\pipe\$UserSegment\TypeDuckIME\Launcher"
  if (Test-Path -LiteralPath $pipePath) {
    return $true
  }

  try {
    $stream = New-Object System.IO.FileStream(
      $pipePath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
    $stream.Close()
    return $true
  } catch [System.UnauthorizedAccessException] {
    return $true
  } catch {
    return $false
  }
}

function Get-TypeDuckLiveLauncherPipeUserSegments {
  param(
    [string] $InteractiveUser = $env:USERNAME
  )

  $segments = @()
  if (-not [string]::IsNullOrWhiteSpace($InteractiveUser)) {
    $segments += $InteractiveUser
  }
  if ($segments -notcontains "SYSTEM") {
    $segments += "SYSTEM"
  }

  $live = @()
  foreach ($seg in $segments) {
    if (Test-TypeDuckLauncherPipePresent -UserSegment $seg) {
      $live += $seg
    }
  }
  return ,$live
}

function Test-TypeDuckLauncherPipeUserSegmentRule {
  param(
    [string] $LiveSegment,
    [string] $InteractiveUser
  )

  if ([string]::IsNullOrWhiteSpace($LiveSegment)) {
    return $true
  }
  if ([string]::IsNullOrWhiteSpace($InteractiveUser)) {
    return $true
  }
  return ($LiveSegment -ieq $InteractiveUser)
}

function Assert-TypeDuckLauncherPipeMatchesInteractiveUser {
  param(
    [string] $InteractiveUser = $env:USERNAME
  )

  if ([string]::IsNullOrWhiteSpace($InteractiveUser)) {
    return
  }

  $liveSegments = Get-TypeDuckLiveLauncherPipeUserSegments -InteractiveUser $InteractiveUser
  if ($liveSegments.Count -eq 0) {
    return
  }

  foreach ($live in $liveSegments) {
    if (-not (Test-TypeDuckLauncherPipeUserSegmentRule -LiveSegment $live -InteractiveUser $InteractiveUser)) {
      throw ("doctor: launcher pipe is '\\.\pipe\{0}\TypeDuckIME\Launcher' but interactive user is '{1}'. " +
        "End the wrong launcher (often SYSTEM/Administrator) and restart as your normal user.") -f $live, $InteractiveUser
    }
  }
}
