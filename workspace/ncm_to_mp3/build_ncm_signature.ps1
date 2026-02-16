param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,
  [Parameter(Mandatory = $true)]
  [string]$OutFile
)

$ErrorActionPreference = 'Stop'

$resolvedInput = (Resolve-Path -LiteralPath $InputDir).Path
$files = Get-ChildItem -LiteralPath $resolvedInput -Recurse -File -Filter *.ncm |
  Sort-Object FullName

$sb = New-Object System.Text.StringBuilder
foreach ($file in $files) {
  $relative = $file.FullName.Substring($resolvedInput.Length).TrimStart('\\')
  [void]$sb.Append($relative)
  [void]$sb.Append('|')
  [void]$sb.Append($file.Length)
  [void]$sb.Append('|')
  [void]$sb.Append($file.LastWriteTimeUtc.Ticks)
  [void]$sb.Append("`n")
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash($bytes)
$hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })

Set-Content -LiteralPath $OutFile -Value $hash -Encoding ASCII
Write-Output $hash
