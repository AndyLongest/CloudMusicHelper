param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,
  [Parameter(Mandatory = $true)]
  [string]$OutputDir,
  [Parameter(Mandatory = $true)]
  [string]$RuntimeInputDir,
  [string]$CountFile = "",
  [string]$RuntimeMapFile = ""
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $RuntimeInputDir -Force | Out-Null
Get-ChildItem -LiteralPath $RuntimeInputDir -File -Filter *.ncm -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$files = Get-ChildItem -LiteralPath $InputDir -Recurse -File -Filter *.ncm -Force
$total = $files.Count
$existing = 0
$pending = 0
$mapItems = @()

foreach ($file in $files) {
  $targetMp3 = Join-Path $OutputDir ($file.BaseName + '.mp3')
  if (Test-Path -LiteralPath $targetMp3) {
    $existing++
    continue
  }

  $pending++
  $runtimeBase = ('pending_{0:D6}' -f $pending)
  $runtimeName = $runtimeBase + '.ncm'
  Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $RuntimeInputDir $runtimeName) -Force

  $mapItems += [PSCustomObject]@{
    RuntimeBase = $runtimeBase
    OriginalBase = $file.BaseName
  }
}

Write-Output "[[CONVERT_EXISTING]] $existing"
Write-Output "[[CONVERT_PENDING]] $pending"

if (-not [string]::IsNullOrWhiteSpace($CountFile)) {
  Set-Content -LiteralPath $CountFile -Value ("{0}|{1}|{2}" -f $total, $existing, $pending) -Encoding ASCII
}

if (-not [string]::IsNullOrWhiteSpace($RuntimeMapFile)) {
  $mapItems | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $RuntimeMapFile -Encoding UTF8
}
