#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$CommitSha = 'local-build'
)

$ErrorActionPreference = 'Stop'

function Get-RelativeFilePath {
    param([string]$Root, [string]$FullName)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fileFull = [System.IO.Path]::GetFullPath($FullName)
    if (-not $fileFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "File is outside the source root: $FullName"
    }
    return $fileFull.Substring($rootFull.Length + 1).Replace('\', '/')
}

function Test-PortablePeExecutable {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing EXE: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 50000) { throw "EXE file size is unexpectedly small: $($item.Length) bytes" }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $reader = New-Object System.IO.BinaryReader($stream)
        $mz = [string]::Concat([char]$reader.ReadByte(), [char]$reader.ReadByte())
        if ($mz -ne 'MZ') { throw 'EXE is missing the MZ signature.' }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 4)) { throw 'Invalid PE header offset.' }
        $stream.Position = $offset
        $pe = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($pe -ne "PE`0`0") { throw 'EXE is missing the PE signature.' }
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
    return $item
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw "Source root does not exist: $SourceRoot" }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$exePath = Join-Path $OutputPath 'WindowsNetworkRepair.exe'
$sidecarPath = $exePath + '.config'
if (Test-Path -LiteralPath $sidecarPath) {
    throw 'WindowsNetworkRepair.exe.config exists. This is not a single-file build; rebuild without PS2EXE -longPaths before packaging.'
}
$exeInfo = Test-PortablePeExecutable -Path $exePath

$sourceArchive = Join-Path $OutputPath 'WindowsNetworkRepair-source.zip'
$manifestPath = Join-Path $OutputPath 'release-manifest.json'
$checksumsPath = Join-Path $OutputPath 'SHA256SUMS.txt'
foreach ($stale in @($sourceArchive, $manifestPath, $checksumsPath)) {
    if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force -ErrorAction Stop }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = $null
$archiveFileCount = 0
try {
    $archive = [System.IO.Compression.ZipFile]::Open($sourceArchive, [System.IO.Compression.ZipArchiveMode]::Create)
    $excludedRootDirectories = @('.git', 'dist', 'Data', 'Backup', 'Logs', 'Reports', '.vscode', '.idea', 'node_modules')
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force)

    foreach ($file in $files) {
        $relative = Get-RelativeFilePath -Root $SourceRoot -FullName $file.FullName
        $segments = $relative -split '/'
        if ($segments.Count -gt 0 -and $excludedRootDirectories -contains $segments[0]) { continue }
        if ($file.Extension -in @('.zip', '.exe', '.log', '.tmp')) { continue }
        if ($relative -match '(^|/)photo_[^/]+$') { continue }
        if ($relative -match '(^|/)(Thumbs\.db|\.DS_Store)$') { continue }

        $entryName = $relative.Replace('\', '/')
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $inputStream = $null
        $entryStream = $null
        try {
            $inputStream = [System.IO.File]::OpenRead($file.FullName)
            $entryStream = $entry.Open()
            $inputStream.CopyTo($entryStream)
        }
        finally {
            if ($entryStream) { $entryStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
        }
        $archiveFileCount++
    }
}
finally {
    if ($archive) { $archive.Dispose() }
}

if ($archiveFileCount -lt 10) { throw "Source archive contains too few files ($archiveFileCount). Refusing to publish an incomplete source package." }

# Re-open the ZIP and verify important source entries before it can be released.
$checkArchive = [System.IO.Compression.ZipFile]::OpenRead($sourceArchive)
try {
    $entryNames = @($checkArchive.Entries | ForEach-Object { $_.FullName })
    foreach ($requiredEntry in @('NetworkRepair.ps1', 'README.md', 'Build/Build-Executable.ps1', 'Modules/ThreeFixes.psm1', '.github/workflows/build-release.yml')) {
        if ($requiredEntry -notin $entryNames) { throw "Source ZIP is missing required entry: $requiredEntry" }
    }
}
finally {
    $checkArchive.Dispose()
}

$sourceInfo = Get-Item -LiteralPath $sourceArchive
$exeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
$sourceHash = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant()

$manifest = [ordered]@{
    application = 'Windows Network Repair Pro'
    version = $Version
    tag = $Tag
    commit = $CommitSha
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    executable = [ordered]@{
        file = 'WindowsNetworkRepair.exe'
        sizeBytes = [long]$exeInfo.Length
        sha256 = $exeHash
        architecture = 'AnyCPU'
        projectModulesBundled = $true
        externalConfigRequired = $false
    }
    sourceArchive = [ordered]@{
        file = 'WindowsNetworkRepair-source.zip'
        sizeBytes = [long]$sourceInfo.Length
        sha256 = $sourceHash
        includedFiles = $archiveFileCount
    }
}
$manifestJson = ConvertTo-Json -InputObject $manifest -Depth 8
$utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($manifestPath, $manifestJson + [Environment]::NewLine, $utf8NoBom)

$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumLines = @(
    "$exeHash  WindowsNetworkRepair.exe",
    "$sourceHash  WindowsNetworkRepair-source.zip",
    "$manifestHash  release-manifest.json"
)
[System.IO.File]::WriteAllLines($checksumsPath, $checksumLines, $utf8NoBom)

Write-Host ''
Write-Host 'Release payload prepared and validated:' -ForegroundColor Green
Get-ChildItem -LiteralPath $OutputPath -File | Where-Object { $_.Name -in @('WindowsNetworkRepair.exe', 'WindowsNetworkRepair-source.zip', 'release-manifest.json', 'SHA256SUMS.txt') } | Format-Table Name,Length -AutoSize
Write-Host ("Source archive entries: {0}" -f $archiveFileCount) -ForegroundColor Green
Write-Host 'EXE validation: MZ + PE signatures valid; no .exe.config sidecar.' -ForegroundColor Green
