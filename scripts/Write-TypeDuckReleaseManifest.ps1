#Requires -Version 5.1
param(
  [string] $RepoRoot = ".",
  [string] $BackendRoot = "",
  [string] $FrontendSha = "",
  [string] $BackendSha = "",
  [string] $BackendRef = "",
  [string] $SchemaRef = "desktop",
  [string] $OutputPath = ""
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repo "installer/dist/typeduck-release-manifest.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $repo $OutputPath
}

if ([string]::IsNullOrWhiteSpace($FrontendSha)) {
  Push-Location $repo
  try {
    $FrontendSha = (git rev-parse HEAD).Trim()
  }
  finally {
    Pop-Location
  }
}

if ([string]::IsNullOrWhiteSpace($BackendSha)) {
  if ([string]::IsNullOrWhiteSpace($BackendRoot)) {
    throw "BackendSha or BackendRoot is required."
  }
  $backendPath = (Resolve-Path $BackendRoot).Path
  Push-Location $backendPath
  try {
    $BackendSha = (git rev-parse HEAD).Trim()
  }
  finally {
    Pop-Location
  }
}

$manifestDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $manifestDir)) {
  New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}

$payload = [ordered]@{
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [Globalization.CultureInfo]::InvariantCulture)
  product = "TypeDuck Windows IME v1"
  frontend = @{
    repository = "TypeDuck-Windows"
    sha = $FrontendSha
  }
  backend = @{
    repository = "TypeDuck-Windows-backend"
    ref = $BackendRef
    sha = $BackendSha
  }
  schema = @{
    repository = "TypeDuck-HK/schema"
    ref = $SchemaRef
  }
}

($payload | ConvertTo-Json -Depth 4) + "`n" | Set-Content -Encoding UTF8 -LiteralPath $OutputPath
Write-Host "Wrote TypeDuck release manifest: $OutputPath"
