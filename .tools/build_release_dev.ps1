param(
    [string]$Version = '',
    [string]$Ref = 'HEAD',
    [ValidateSet('beta', 'stable')]
    [string]$Channel = 'beta',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$UseExisting
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ArchiveSha256([string]$FilePath) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($FilePath)
    try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}

function Get-VersionFromToc {
    param([string]$TocPath)
    if (-not (Test-Path $TocPath)) {
        throw "Primary TOC not found at '$TocPath'."
    }
    $match = Select-String -Path $TocPath -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
    if (-not $match) {
        throw "Missing ## Version tag in '$TocPath'."
    }
    return $match.Matches[0].Groups[1].Value.Trim()
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-VersionFromToc -TocPath (Join-Path $RepoRoot 'ULO\ULO.toc')
}
$Version = $Version.TrimStart('v', 'V')
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    throw 'A semantic release version is required.'
}

$commitSha = (& git -C $RepoRoot rev-parse --verify "$Ref^{commit}" 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commitSha)) {
    throw "Unable to resolve git commit for Ref='$Ref'."
}
$commitSha = $commitSha.Trim()

$versionsDir = Join-Path $RepoRoot ".versions\$Version"
New-Item -ItemType Directory -Path $versionsDir -Force | Out-Null

$zipName = "ULO-v$Version.zip"
$zipPath = Join-Path $versionsDir $zipName
if ((Test-Path $zipPath) -and -not $UseExisting) {
    throw "Release archive already exists at '$zipPath'; do not replace immutable candidates."
}

if ($UseExisting) {
    if (-not (Test-Path $zipPath)) { throw 'Existing release ZIP is missing.' }
    $checksumPath = "$zipPath.sha256"
    if (-not (Test-Path $checksumPath)) { throw 'Existing release checksum is missing.' }
    $checksum = (Get-Content -Raw -LiteralPath $checksumPath).Trim() -split '\s+'
    if ((Get-ArchiveSha256 $zipPath) -ne $checksum[0]) { throw 'Existing release ZIP checksum mismatch.' }
} else {
    # Archive the commit with a pathspec so commit timestamps are retained.
    & git -C $RepoRoot -c core.autocrlf=false -c core.eol=lf archive --format=zip --output="$zipPath" $commitSha ULO
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipPath)) { throw "git archive failed for $commitSha." }
}

$treeLines = & git -C $RepoRoot ls-tree -r --full-tree "$($commitSha):ULO"
if ($LASTEXITCODE -ne 0) {
    throw "git ls-tree failed for $commitSha:ULO."
}

$expectedEntries = New-Object System.Collections.Generic.List[string]
$expectedBlobs = @{}
foreach ($line in $treeLines) {
    if ($line -match '^\d+\s+blob\s+([0-9a-f]+)\s+(.+)$') {
        $blobHash = $Matches[1]
        $rel = $Matches[2].Replace('\', '/')
        $expectedEntries.Add("ULO/$rel")
        $expectedBlobs["ULO/$rel"] = $blobHash
    }
}

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$fileHashes = New-Object System.Collections.Generic.List[string]
$archiveEntries = New-Object System.Collections.Generic.List[string]

$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $archiveEntries.Add($entry.FullName)
        $contentStream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try { $contentStream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $contentStream.Dispose(); $memory.Dispose() }
        $header = [Text.Encoding]::UTF8.GetBytes("blob $($bytes.Length)`0")
        $objectBytes = New-Object byte[] ($header.Length + $bytes.Length)
        [Array]::Copy($header, 0, $objectBytes, 0, $header.Length)
        [Array]::Copy($bytes, 0, $objectBytes, $header.Length, $bytes.Length)
        $gitHasher = [Security.Cryptography.SHA1]::Create()
        try { $blob = ([BitConverter]::ToString($gitHasher.ComputeHash($objectBytes))).Replace('-', '').ToLowerInvariant() } finally { $gitHasher.Dispose() }
        if ($expectedBlobs[$entry.FullName] -ne $blob) { throw "Archive content differs from tagged source: $($entry.FullName)" }
        $stream = $entry.Open()
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            $hashHex = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
            $fileHashes.Add("$hashHex  $($entry.FullName)")
        }
        finally {
            $stream.Dispose()
        }
    }
}
finally {
    $zip.Dispose()
}

$sortedExpected = ($expectedEntries | Sort-Object) -join "`n"
$sortedActual = ($archiveEntries | Sort-Object) -join "`n"
if ($sortedExpected -ne $sortedActual) {
    throw "Archive entry mismatch against git ls-tree for $commitSha:ULO."
}
if (-not ($archiveEntries -contains 'ULO/ULO.toc')) {
    throw 'Archive verification failed: ULO/ULO.toc missing at archive root.'
}

$verifyZip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($name in @('ULO.toc', 'ULO_Camelot.toc', 'ULO_Vanilla.toc', 'ULO_TBC.toc', 'ULO_Mists.toc', 'ULO_Mainline.toc')) {
        $entry = $verifyZip.GetEntry("ULO/$name")
        if (-not $entry) { throw "Missing release manifest: $name" }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $toc = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($toc -notmatch '(?m)^##\s*Version:\s*(.+)$' -or $Matches[1].Trim() -ne $Version) { throw "Release version mismatch in $name" }
        if ($name -eq 'ULO_Camelot.toc' -and $toc -notmatch '(?m)^## Interface: 16001\r?$') { throw 'Forever interface changed' }
        if ($name -eq 'ULO_Vanilla.toc' -and $toc -notmatch '(?m)^## Interface: 11509\r?$') { throw 'Vanilla interface changed' }
    }
    foreach ($name in @('ULOIcon.tga', 'ULOMinimap.tga', 'ULOHudBg.tga')) {
        $entry = $verifyZip.GetEntry("ULO/Media/$name")
        if (-not $entry -or $entry.Length -le 18) { throw "Required release asset is missing/empty: $name" }
    }
} finally { $verifyZip.Dispose() }

$zipHashHex = Get-ArchiveSha256 $zipPath

Set-Content -Path (Join-Path $versionsDir 'SOURCE_COMMIT.txt') -Value $commitSha -Encoding UTF8
Set-Content -Path (Join-Path $versionsDir 'SOURCE_TREE.txt') -Value ($treeLines -join "`n") -Encoding UTF8
Set-Content -Path (Join-Path $versionsDir 'SOURCE_FILES.sha256') -Value (($fileHashes | Sort-Object) -join "`n") -Encoding UTF8
Set-Content -Path "$zipPath.sha256" -Value "$zipHashHex  $zipName" -Encoding UTF8

Write-Output "Built verified release archive ($Channel):"
Write-Output "  Commit : $commitSha"
Write-Output "  Archive: $zipPath"
Write-Output "  SHA256 : $zipHashHex"
Write-Output "  Files  : $($archiveEntries.Count)"
