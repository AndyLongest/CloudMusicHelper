param(
  [string]$ProjectRoot = $PSScriptRoot,
  [string]$OutputRoot = "",
  [string]$SelectionFile = ""
)

$ErrorActionPreference = "Stop"
$organizerVersion = "11-album-trackno-name-match"
$script:ShellTrackColumnCache = @{}

function Normalize-Text {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $lower = $Text.ToLowerInvariant()
  return [regex]::Replace($lower, "[\s\p{P}\p{S}]+", "")
}

function Sanitize-Name {
  param([string]$Name)
  $invalid = [System.IO.Path]::GetInvalidFileNameChars()
  $result = $Name
  foreach ($char in $invalid) {
    $result = $result.Replace($char, '_')
  }
  if ([string]::IsNullOrWhiteSpace($result)) { return "unnamed" }
  return $result.Trim()
}

function Get-TrackNumberFromText {
  param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
  $text = $Raw.Trim([char]0).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }

  $m = [regex]::Match($text, '^\s*(\d+)')
  if (-not $m.Success) {
    $m = [regex]::Match($text, '\d+')
  }
  if (-not $m.Success) { return $null }

  $num = [int]$m.Groups[1].Value
  if ($num -le 0) { return $null }
  return $num
}

function Get-TrackNumberFromShell {
  param([System.IO.FileInfo]$File)

  try {
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($File.DirectoryName)
    if ($null -eq $folder) { return $null }
    $item = $folder.ParseName($File.Name)
    if ($null -eq $item) { return $null }

    $cacheKey = $File.DirectoryName
    $trackCol = $null
    if ($script:ShellTrackColumnCache.ContainsKey($cacheKey)) {
      $trackCol = $script:ShellTrackColumnCache[$cacheKey]
    } else {
      for ($i = 0; $i -lt 320; $i++) {
        $header = $folder.GetDetailsOf($null, $i)
        if ([string]::IsNullOrWhiteSpace($header)) { continue }
        $h = $header.Trim()
        if (
          $h -eq '#' -or
          $h -match '^(?i)track\s*number$' -or
          $h -match '^(?i)track$' -or
          $h -match '^(曲目|曲目号|曲目编号|音轨|音轨号|轨道号)$'
        ) {
          $trackCol = $i
          break
        }
      }
      if ($null -eq $trackCol) {
        $trackCol = 26
      }
      $script:ShellTrackColumnCache[$cacheKey] = $trackCol
    }

    $raw = $folder.GetDetailsOf($item, [int]$trackCol)
    return (Get-TrackNumberFromText -Raw $raw)
  } catch {
    return $null
  }
}

function Get-TrackNumberFromMp3 {
  param([System.IO.FileInfo]$File)

  $fs = $null
  $br = $null
  try {
    $fs = [System.IO.File]::OpenRead($File.FullName)
    $br = New-Object System.IO.BinaryReader($fs)

    if ($fs.Length -lt 10) { return $null }

    $id = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(3))
    if ($id -ne 'ID3') { return $null }

    $versionMajor = [int]$br.ReadByte()
    [void]$br.ReadByte()
    [void]$br.ReadByte()
    $sizeBytes = $br.ReadBytes(4)
    if ($sizeBytes.Length -ne 4) { return $null }

    $tagSize =
      (($sizeBytes[0] -band 0x7F) -shl 21) -bor
      (($sizeBytes[1] -band 0x7F) -shl 14) -bor
      (($sizeBytes[2] -band 0x7F) -shl 7) -bor
      ($sizeBytes[3] -band 0x7F)

    $tagEnd = 10 + $tagSize
    $pos = 10

    while (($pos + 10) -le $tagEnd -and ($pos + 10) -le $fs.Length) {
      $fs.Position = $pos
      $frameId = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
      if ([string]::IsNullOrWhiteSpace($frameId) -or $frameId -eq "`0`0`0`0") { break }

      $frameSizeBytes = $br.ReadBytes(4)
      if ($frameSizeBytes.Length -ne 4) { break }

      $frameSize = 0
      if ($versionMajor -ge 4) {
        $frameSize =
          (($frameSizeBytes[0] -band 0x7F) -shl 21) -bor
          (($frameSizeBytes[1] -band 0x7F) -shl 14) -bor
          (($frameSizeBytes[2] -band 0x7F) -shl 7) -bor
          ($frameSizeBytes[3] -band 0x7F)
      } else {
        $frameSize =
          ([int]$frameSizeBytes[0] -shl 24) -bor
          ([int]$frameSizeBytes[1] -shl 16) -bor
          ([int]$frameSizeBytes[2] -shl 8) -bor
          ([int]$frameSizeBytes[3])
      }

      [void]$br.ReadBytes(2)
      if ($frameSize -le 0) { break }
      if (($fs.Position + $frameSize) -gt $fs.Length) { break }

      if ($frameId -eq 'TRCK') {
        $payload = $br.ReadBytes($frameSize)
        if ($payload.Length -le 1) { return $null }

        $enc = [int]$payload[0]
        $textBytes = $payload[1..($payload.Length - 1)]
        $raw = ""

        switch ($enc) {
          0 { $raw = [System.Text.Encoding]::GetEncoding(28591).GetString($textBytes) }
          1 { $raw = [System.Text.Encoding]::Unicode.GetString($textBytes) }
          2 { $raw = [System.Text.Encoding]::BigEndianUnicode.GetString($textBytes) }
          3 { $raw = [System.Text.Encoding]::UTF8.GetString($textBytes) }
          default { $raw = [System.Text.Encoding]::UTF8.GetString($textBytes) }
        }
        $trackNo = Get-TrackNumberFromText -Raw $raw
        if ($null -ne $trackNo) { return $trackNo }
        break
      } else {
        $fs.Position = $fs.Position + $frameSize
      }

      $pos = $fs.Position
    }

    if ($fs.Length -ge 128) {
      $fs.Position = $fs.Length - 128
      $tag = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(3))
      if ($tag -eq 'TAG') {
        $title = $br.ReadBytes(30)
        $artist = $br.ReadBytes(30)
        $album = $br.ReadBytes(30)
        $year = $br.ReadBytes(4)
        $comment = $br.ReadBytes(30)
        $genre = $br.ReadByte()

        if ($comment.Length -ge 30 -and $comment[28] -eq 0 -and $comment[29] -gt 0) {
          return [int]$comment[29]
        }
      }
    }

    return (Get-TrackNumberFromShell -File $File)
  } catch {
    return (Get-TrackNumberFromShell -File $File)
  } finally {
    if ($null -ne $br) { $br.Close() }
    if ($null -ne $fs) { $fs.Close() }
  }
}

function Get-OrderedSongEntries {
  param([string]$FilePath)

  $entries = @()
  $lines = Get-Content -LiteralPath $FilePath -Encoding UTF8
  $lineIndex = 0

  foreach ($rawLine in $lines) {
    if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
    $line = $rawLine.Trim()
    if ($line -match '^\s*[#;]') { continue }

    $line = [regex]::Replace($line, '^\s*\d+\s*[\.\-\)\]]\s*', '')
    $line = [regex]::Replace($line, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $lineIndex++

    $candidateSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $candidateList = New-Object System.Collections.ArrayList

    if ($candidateSet.Add($line)) {
      [void]$candidateList.Add($line)
    }

    $splitters = @(' - ', ' — ', ' / ', ' | ', '_')
    foreach ($splitter in $splitters) {
      if ($line.Contains($splitter)) {
        $parts = $line.Split($splitter, [System.StringSplitOptions]::RemoveEmptyEntries)
        foreach ($part in $parts) {
          $partText = $part.Trim()
          if (-not [string]::IsNullOrWhiteSpace($partText)) {
            if ($candidateSet.Add($partText)) {
              [void]$candidateList.Add($partText)
            }
          }
        }
      }
    }

    $entries += [PSCustomObject]@{
      Index = $lineIndex
      DisplayTitle = $line
      Candidates = @($candidateList)
    }
  }

  return $entries
}

function Find-BestMatch {
  param(
    [array]$Mp3Index,
    [array]$CandidateTexts,
    [System.Collections.Generic.HashSet[string]]$UsedPaths,
    [bool]$AllowLooseMatch = $true,
    [int]$ExpectedTrack = 0,
    [bool]$PreferTrack = $false,
    [ValidateSet('any','equal','missing')]
    [string]$TrackFilter = 'any'
  )

  $best = $null
  $bestScore = [int]::MaxValue

  foreach ($candidate in $CandidateTexts) {
    $norm = Normalize-Text -Text $candidate
    if ($norm.Length -lt 2) { continue }

    foreach ($item in $Mp3Index) {
      $sourcePath = $item.File.FullName
      if ($UsedPaths.Contains($sourcePath)) { continue }

      if ($TrackFilter -eq 'equal') {
        if ($ExpectedTrack -le 0 -or $null -eq $item.TrackNo -or [int]$item.TrackNo -ne [int]$ExpectedTrack) {
          continue
        }
      } elseif ($TrackFilter -eq 'missing') {
        if ($null -ne $item.TrackNo) {
          continue
        }
      }

      $itemNorm = $item.NormCore
      if ([string]::IsNullOrWhiteSpace($itemNorm)) { continue }

      $matched = $false
      $score = 999999

      if ($itemNorm -eq $norm) {
        $matched = $true
        $score = 0
      } elseif ($AllowLooseMatch -and ($itemNorm.Contains($norm) -or $norm.Contains($itemNorm))) {
        $matched = $true
        $score = [Math]::Abs($itemNorm.Length - $norm.Length) + 10
      }

      if ($matched -and $score -lt $bestScore) {
        if ($PreferTrack -and $ExpectedTrack -gt 0 -and $null -ne $item.TrackNo) {
          if ($item.TrackNo -eq $ExpectedTrack) {
            $score -= 3
          } else {
            $score += [Math]::Min(20, [Math]::Abs($item.TrackNo - $ExpectedTrack))
          }
        }

        $best = $item
        $bestScore = $score
      }
    }
  }

  return $best
}

function Get-Mp3Snapshot {
  param([System.IO.FileInfo[]]$Mp3Files)
  if ($Mp3Files.Count -eq 0) {
    return [PSCustomObject]@{ Count = 0; MaxTicks = 0 }
  }
  $maxTicks = 0
  foreach ($mp3 in $Mp3Files) {
    $ticks = [int64]$mp3.LastWriteTimeUtc.Ticks
    if ($ticks -gt $maxTicks) {
      $maxTicks = $ticks
    }
  }
  return [PSCustomObject]@{ Count = $Mp3Files.Count; MaxTicks = $maxTicks }
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$outputRootResolved = ""
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $outputRootResolved = $projectRootResolved
} else {
  if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $outputRootResolved = $OutputRoot
  } else {
    $outputRootResolved = Join-Path $projectRootResolved $OutputRoot
  }
}
$mp3Dir = Join-Path $projectRootResolved "ncm_to_mp3\output_mp3"
$listRoot = Join-Path $projectRootResolved "get_lists\output"
$fallbackListRoot = Join-Path $projectRootResolved "output"
$targetRoot = Join-Path $outputRootResolved "organized_music"
$checkpointRoot = Join-Path $targetRoot "_checkpoints"

if (-not (Test-Path -LiteralPath $mp3Dir)) {
  Write-Error "MP3 directory not found: $mp3Dir"
}
if (-not (Test-Path -LiteralPath $listRoot)) {
  if (Test-Path -LiteralPath $fallbackListRoot) {
    $listRoot = $fallbackListRoot
  } else {
    Write-Error "List export directory not found: $listRoot"
  }
}

$mp3Files = Get-ChildItem -LiteralPath $mp3Dir -Recurse -File -Filter *.mp3
if ($mp3Files.Count -eq 0) {
  Write-Error "No mp3 files found in: $mp3Dir"
}

$mp3Snapshot = Get-Mp3Snapshot -Mp3Files $mp3Files

$mp3Index = @()
foreach ($file in $mp3Files) {
  $coreName = [regex]::Replace($file.BaseName, '^\d{6}_', '')
  $mp3Index += [PSCustomObject]@{
    File = $file
    NormCore = (Normalize-Text -Text $coreName)
    TrackNo = (Get-TrackNumberFromMp3 -File $file)
  }
}

$allListFiles = @(Get-ChildItem -LiteralPath $listRoot -Recurse -File -Filter *.txt)
if ($allListFiles.Count -eq 0) {
  Write-Error "No playlist/album txt files found in: $listRoot"
}

$selectedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
if (-not [string]::IsNullOrWhiteSpace($SelectionFile) -and (Test-Path -LiteralPath $SelectionFile)) {
  $rawLines = @(Get-Content -LiteralPath $SelectionFile -Encoding UTF8)
  foreach ($line in $rawLines) {
    $trim = ($line | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($trim)) { continue }
    [void]$selectedKeys.Add($trim.ToLowerInvariant())
  }
}

$listFiles = @()
if ($selectedKeys.Count -eq 0) {
  $listFiles = $allListFiles
} else {
  foreach ($lf in $allListFiles) {
    $typeFolder = $lf.Directory.Name
    $targetType = if ($typeFolder -ieq "playlists") { "playlists" } elseif ($typeFolder -ieq "albums") { "albums" } else { "others" }
    $key = ("{0}|{1}" -f $targetType, $lf.BaseName).ToLowerInvariant()
    if ($selectedKeys.Contains($key)) {
      $listFiles += $lf
    }
  }

  if ($listFiles.Count -eq 0) {
    Write-Error "No selected playlists/albums matched exported txt files."
  }
}

New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null
New-Item -Path $checkpointRoot -ItemType Directory -Force | Out-Null

$totalCopied = 0
$totalProcessed = 0
$totalSkipped = 0

foreach ($listFile in $listFiles) {
  $typeFolder = $listFile.Directory.Name
  $targetType = if ($typeFolder -ieq "playlists") { "playlists" } elseif ($typeFolder -ieq "albums") { "albums" } else { "others" }

  $folderName = Sanitize-Name -Name $listFile.BaseName
  $destDir = Join-Path (Join-Path $targetRoot $targetType) $folderName
  New-Item -Path $destDir -ItemType Directory -Force | Out-Null

  $listIdentity = "{0}__{1}" -f $targetType, (Sanitize-Name -Name $listFile.BaseName)
  $checkpointPath = Join-Path $checkpointRoot ($listIdentity + ".json")

  $currentSignature = [PSCustomObject]@{
    Version = $organizerVersion
    ListPath = $listFile.FullName
    ListLength = $listFile.Length
    ListWriteTicks = $listFile.LastWriteTimeUtc.Ticks
    Mp3Count = $mp3Snapshot.Count
    Mp3MaxTicks = $mp3Snapshot.MaxTicks
  }

  $needProcess = $true
  if (Test-Path -LiteralPath $checkpointPath) {
    try {
      $old = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
      if (
        $old.Version -eq $currentSignature.Version -and
        $old.ListPath -eq $currentSignature.ListPath -and
        [int64]$old.ListLength -eq [int64]$currentSignature.ListLength -and
        [int64]$old.ListWriteTicks -eq [int64]$currentSignature.ListWriteTicks -and
        [int64]$old.Mp3Count -eq [int64]$currentSignature.Mp3Count -and
        [int64]$old.Mp3MaxTicks -eq [int64]$currentSignature.Mp3MaxTicks
      ) {
        $needProcess = $false
      }
    } catch {
      $needProcess = $true
    }
  }

  if (-not $needProcess) {
    $totalSkipped++
    Write-Host "[skip] [$targetType] $folderName"
    continue
  }

  Get-ChildItem -LiteralPath $destDir -File -Filter *.mp3 -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

  $songEntries = @(Get-OrderedSongEntries -FilePath $listFile.FullName)
  if ($null -eq $songEntries -or $songEntries.Count -eq 0) {
    $currentSignature | ConvertTo-Json | Set-Content -LiteralPath $checkpointPath -Encoding UTF8
    $totalProcessed++
    Write-Host "[done] [$targetType] $folderName -> copied=0, missing=0 (empty list)"
    continue
  }

  $copiedSet = New-Object 'System.Collections.Generic.HashSet[string]'
  $missingCount = 0
  $indexWidth = [Math]::Max(2, $songEntries.Count.ToString().Length)
  $isAlbumList = ($targetType -ieq "albums")

  foreach ($entry in $songEntries) {
    Write-Host ("[[ORG]] {0}/{1}|{2}|{3}" -f $entry.Index, $songEntries.Count, $folderName, $entry.DisplayTitle)
    $match = $null
    if ($isAlbumList) {
      $match = Find-BestMatch -Mp3Index $mp3Index -CandidateTexts $entry.Candidates -UsedPaths $copiedSet -AllowLooseMatch $true -TrackFilter 'any'
    } else {
      $match = Find-BestMatch -Mp3Index $mp3Index -CandidateTexts $entry.Candidates -UsedPaths $copiedSet -AllowLooseMatch $true -TrackFilter 'any'
    }

    if ($null -eq $match) {
      $missingCount++
      Write-Host "[[ORG_MISS]] $($entry.DisplayTitle)"
      continue
    }

    $sourcePath = $match.File.FullName
    [void]$copiedSet.Add($sourcePath)

    $safeTitle = Sanitize-Name -Name $entry.DisplayTitle
    $prefixIndex = if ($isAlbumList -and $null -ne $match.TrackNo -and [int]$match.TrackNo -gt 0) { [int]$match.TrackNo } else { $entry.Index }
    $prefix = $prefixIndex.ToString("D$indexWidth")
    $destBaseName = "${prefix}_$safeTitle"
    $destPath = Join-Path $destDir ($destBaseName + ".mp3")

    $suffix = 2
    while (Test-Path -LiteralPath $destPath) {
      $destPath = Join-Path $destDir ("${destBaseName}_$suffix.mp3")
      $suffix++
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
    $totalCopied++
  }

  if ($isAlbumList -and $copiedSet.Count -eq 0) {
    Write-Host "[[ORG_EMPTY_ALBUM]] $folderName|strict-track-match-none"
    if (Test-Path -LiteralPath $destDir) {
      Remove-Item -LiteralPath $destDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  $currentSignature | ConvertTo-Json | Set-Content -LiteralPath $checkpointPath -Encoding UTF8

  $totalProcessed++
  Write-Host "[done] [$targetType] $folderName -> copied=$($copiedSet.Count), missing=$missingCount"
}

Write-Host ""

$albumsRoot = Join-Path $targetRoot "albums"
if (Test-Path -LiteralPath $albumsRoot) {
  $albumDirs = @(Get-ChildItem -LiteralPath $albumsRoot -Directory -ErrorAction SilentlyContinue)
  foreach ($albumDir in $albumDirs) {
    $mp3Inside = @(Get-ChildItem -LiteralPath $albumDir.FullName -File -Filter *.mp3 -ErrorAction SilentlyContinue)
    if ($mp3Inside.Count -eq 0) {
      Remove-Item -LiteralPath $albumDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Write-Host "organize finished:"
Write-Host "- target: $targetRoot"
Write-Host "- processed lists: $totalProcessed"
Write-Host "- skipped lists: $totalSkipped"
Write-Host "- copied files: $totalCopied"
