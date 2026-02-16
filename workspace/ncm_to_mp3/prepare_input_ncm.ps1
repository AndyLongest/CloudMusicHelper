param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,
  [Parameter(Mandatory = $true)]
  [string]$InputDir,
  [string]$CountFile = ""
)

$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourceDir).Path

New-Item -ItemType Directory -Path $InputDir -Force | Out-Null

$files = Get-ChildItem -LiteralPath $resolvedSource -Recurse -File -Filter *.ncm -Force
$index = 0
$total = $files.Count
$expectedNames = New-Object 'System.Collections.Generic.HashSet[string]'

if (-not [string]::IsNullOrWhiteSpace($CountFile)) {
  Set-Content -LiteralPath $CountFile -Value 0 -Encoding ASCII
}

Write-Output "[[COLLECT_TOTAL]] $total"

foreach ($file in $files) {
  $index++
  Write-Output ("[[COLLECT]] {0}/{1}|{2}" -f $index, $total, $file.Name)
  $targetName = ('{0:D6}_{1}' -f $index, $file.Name)
  [void]$expectedNames.Add($targetName)
  $targetPath = Join-Path $InputDir $targetName
  if (-not (Test-Path -LiteralPath $targetPath)) {
    Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
  }
  if (-not [string]::IsNullOrWhiteSpace($CountFile)) {
    Set-Content -LiteralPath $CountFile -Value $index -Encoding ASCII
  }
}

$staleFiles = Get-ChildItem -LiteralPath $InputDir -File -Filter *.ncm -Force -ErrorAction SilentlyContinue
foreach ($stale in $staleFiles) {
  if (-not $expectedNames.Contains($stale.Name)) {
    Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction SilentlyContinue
  }
}

if (-not [string]::IsNullOrWhiteSpace($CountFile)) {
  Set-Content -LiteralPath $CountFile -Value $index -Encoding ASCII
}

Write-Output $index
