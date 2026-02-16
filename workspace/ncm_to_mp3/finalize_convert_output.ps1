param(
  [Parameter(Mandatory = $true)]
  [string]$RuntimeOutDir,
  [Parameter(Mandatory = $true)]
  [string]$FinalOutDir,
  [Parameter(Mandatory = $true)]
  [string]$RuntimeMapFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RuntimeOutDir)) {
  exit 0
}

if (-not (Test-Path -LiteralPath $FinalOutDir)) {
  New-Item -ItemType Directory -Path $FinalOutDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $RuntimeMapFile)) {
  Copy-Item -Path (Join-Path $RuntimeOutDir '*') -Destination $FinalOutDir -Recurse -Force -ErrorAction SilentlyContinue
  exit 0
}

$raw = Get-Content -LiteralPath $RuntimeMapFile -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($raw)) {
  exit 0
}

$items = $raw | ConvertFrom-Json
$items = @($items)

foreach ($item in $items) {
  $runtimeBase = [string]$item.RuntimeBase
  $originalBase = [string]$item.OriginalBase
  if ([string]::IsNullOrWhiteSpace($runtimeBase) -or [string]::IsNullOrWhiteSpace($originalBase)) {
    continue
  }

  $src = Join-Path $RuntimeOutDir ($runtimeBase + '.mp3')
  if (-not (Test-Path -LiteralPath $src)) {
    continue
  }

  $destBase = $originalBase
  $dest = Join-Path $FinalOutDir ($destBase + '.mp3')
  $suffix = 2
  while (Test-Path -LiteralPath $dest) {
    $dest = Join-Path $FinalOutDir ("{0}_{1}.mp3" -f $destBase, $suffix)
    $suffix++
  }

  Copy-Item -LiteralPath $src -Destination $dest -Force
}
