param(
  [string]$ProjectRoot = $PSScriptRoot,
  [string]$OutputRoot = ""
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$outputRootResolved = ""
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $outputRootResolved = $root
} else {
  if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $outputRootResolved = $OutputRoot
  } else {
    $outputRootResolved = Join-Path $root $OutputRoot
  }
}

function Remove-PathIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$inputDir = Join-Path $root 'ncm_to_mp3\input_ncm'
$outputMp3Dir = Join-Path $root 'ncm_to_mp3\output_mp3'
$listOutDir = Join-Path $root 'get_lists\output'
$runtimeDir = Join-Path $root 'ncm_to_mp3\_convert_runtime'
$convertCheckpoint = Join-Path $root 'ncm_to_mp3\.convert_checkpoint.txt'
$organizeCheckpointDir = Join-Path $outputRootResolved 'organized_music\_checkpoints'

Remove-PathIfExists -Path $runtimeDir
Remove-PathIfExists -Path $organizeCheckpointDir
if (Test-Path -LiteralPath $convertCheckpoint) {
  Remove-Item -LiteralPath $convertCheckpoint -Force -ErrorAction SilentlyContinue
}

Remove-PathIfExists -Path $inputDir
New-Item -ItemType Directory -Path $inputDir -Force | Out-Null

Remove-PathIfExists -Path $outputMp3Dir
New-Item -ItemType Directory -Path $outputMp3Dir -Force | Out-Null

Remove-PathIfExists -Path $listOutDir
New-Item -ItemType Directory -Path (Join-Path $listOutDir 'albums') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $listOutDir 'playlists') -Force | Out-Null

Write-Output 'cleanup completed'
