#Requires -Version 5.1
param(
  [string] $RepoRoot = ".",
  [string] $ProtobufRoot = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ProtocExe {
  param([string] $Root)
  if (-not [string]::IsNullOrWhiteSpace($Root)) {
    $candidate = Join-Path $Root "bin/protoc.exe"
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  $fromPath = Get-Command protoc -ErrorAction SilentlyContinue
  if ($fromPath) {
    return $fromPath.Source
  }
  throw "protoc not found. Set -ProtobufRoot to a protoc install root."
}

$repo = (Resolve-Path $RepoRoot).Path
$schema = Join-Path $repo "proto/moqi.proto"
$checkedInCc = Join-Path $repo "proto/moqi.pb.cc"
$checkedInH = Join-Path $repo "proto/moqi.pb.h"
foreach ($path in @($schema, $checkedInCc, $checkedInH)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required path: $path"
  }
}

$protoc = Resolve-ProtocExe -Root $ProtobufRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("typeduck-proto-verify-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
  & $protoc --proto_path=$repo "--cpp_out=$tempRoot" $schema
  if ($LASTEXITCODE -ne 0) {
    throw "protoc exited with code $LASTEXITCODE"
  }

  $generatedCc = Join-Path $tempRoot "proto/moqi.pb.cc"
  $generatedH = Join-Path $tempRoot "proto/moqi.pb.h"
  foreach ($path in @($generatedCc, $generatedH)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "protoc did not emit expected file: $path"
    }
  }

  $pairs = @(
    @{ Expected = $checkedInCc; Actual = $generatedCc; Label = "moqi.pb.cc" },
    @{ Expected = $checkedInH; Actual = $generatedH; Label = "moqi.pb.h" }
  )
  function Get-NormalizedTextHash {
    param([string] $Path)
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $normalized = $raw -replace "`r`n", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
      $sha.Dispose()
    }
  }

  foreach ($pair in $pairs) {
    $expectedHash = Get-NormalizedTextHash -Path $pair.Expected
    $actualHash = Get-NormalizedTextHash -Path $pair.Actual
    if ($expectedHash -ne $actualHash) {
      throw "Checked-in $($pair.Label) does not match protoc output from proto/moqi.proto. Regenerate with protoc 33.5 on Windows and commit proto/moqi.pb.*"
    }
  }

  $checkedInText = Get-Content -Raw -LiteralPath $checkedInH
  if ($checkedInText -match 'cloud_clipboard_text') {
    throw "Reserved field cloud_clipboard_text must not appear in checked-in moqi.pb.h"
  }

  Write-Host "TypeDuck protobuf codegen verification passed."
}
finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
