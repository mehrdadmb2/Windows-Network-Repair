#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$Version = '2.0.2.0'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-PortablePeExecutable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Executable was not created: $Path"
    }

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -lt 50000) {
        throw "Executable size is unexpectedly small ($($file.Length) bytes). The compiler output may be incomplete."
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 128) { throw 'Executable is too small to contain a valid PE header.' }

        $mz = [string]::Concat([char]$reader.ReadByte(), [char]$reader.ReadByte())
        if ($mz -ne 'MZ') { throw 'Output does not contain a valid DOS/PE executable signature (MZ).' }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 4)) {
            throw 'The PE header offset is outside the executable file.'
        }
        $stream.Position = $peOffset
        $signature = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($signature -ne "PE`0`0") { throw 'The output does not contain a valid PE signature.' }
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }

    return $file
}

$repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mainFile = Join-Path $repoRoot 'NetworkRepair.ps1'
$moduleDir = Join-Path $repoRoot 'Modules'
$moduleOrder = @(
    'Console.psm1',
    'System.psm1',
    'Logging.psm1',
    'Backup.psm1',
    'ThreeFixes.psm1',
    'Diagnostics.psm1'
)
$ps2exeVersion = '1.0.18'

if (-not (Test-Path -LiteralPath $mainFile -PathType Leaf)) {
    throw "Main script not found: $mainFile"
}
foreach ($name in $moduleOrder) {
    $modulePath = Join-Path $moduleDir $name
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Required module not found: $modulePath"
    }
}

if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw 'Version must use four numeric parts, for example 2.0.2.0.'
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$outputFile = Join-Path $OutputPath 'WindowsNetworkRepair.exe'
$configFile = $outputFile + '.config'
$iconFile = Join-Path $repoRoot 'assets\WindowsNetworkRepair.ico'
$bundlePath = Join-Path ([System.IO.Path]::GetTempPath()) ('WNR_Bundle_' + [guid]::NewGuid().ToString('N') + '.ps1')

if (-not (Test-Path -LiteralPath $iconFile -PathType Leaf)) {
    throw "Application icon not found: $iconFile"
}

# Remove stale outputs so a previous build cannot be mistaken for the current result.
foreach ($stalePath in @($outputFile, $configFile)) {
    if (Test-Path -LiteralPath $stalePath) {
        Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
    }
}

try {
    Write-Host 'Preparing the self-contained PowerShell source bundle...' -ForegroundColor Cyan
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('# Windows Network Repair Pro — bundled executable source')
    $parts.Add("`$env:WNR_BUNDLED_EXE = '1'")

    foreach ($name in $moduleOrder) {
        $path = Join-Path $moduleDir $name
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        # Module export declarations are not meaningful in the merged script scope.
        $content = [regex]::Replace($content, '(?m)^[ \t]*Export-ModuleMember\b[^\r\n]*(?:\r?\n|$)', '')
        $parts.Add("`r`n# --- Bundled module: $name ---`r`n")
        $parts.Add($content)
    }

    $main = Get-Content -LiteralPath $mainFile -Raw -ErrorAction Stop
    # Strip source-only directives/imports: the module bodies are already embedded above.
    $main = [regex]::Replace($main, '(?m)^[ \t]*#requires\b[^\r\n]*(?:\r?\n|$)', '')
    $main = [regex]::Replace(
        $main,
        '(?m)^[ \t]*Import-Module\s+\(Join-Path\s+\$Root\s+''Modules\\[^'']+''\)\s+-Force[ \t]*(?:\r?\n|$)',
        ''
    )
    if ($main -match '(?m)^[ \t]*Import-Module\s+\(Join-Path\s+\$Root') {
        throw 'One or more source module imports could not be removed. Refusing to build an EXE with external module dependencies.'
    }
    $parts.Add("`r`n# --- Main application ---`r`n")
    $parts.Add($main)

    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($bundlePath, ($parts -join "`r`n"), $utf8)

    # Parse the actual bundled file as well as the individual source files.
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($bundlePath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $details = @($parseErrors | ForEach-Object {
            '{0}:{1} {2}' -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
        }) -join [Environment]::NewLine
        throw "Bundled PowerShell source failed syntax validation:`r`n$details"
    }

    # Force TLS 1.2 for PowerShell Gallery downloads on older Windows/.NET defaults.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-Warning ('Could not explicitly enable TLS 1.2: ' + $_.Exception.Message)
    }

    $installedPs2Exe = Get-Module -ListAvailable -Name ps2exe |
        Where-Object { $_.Version.ToString() -eq $ps2exeVersion } |
        Select-Object -First 1

    if (-not $installedPs2Exe) {
        Write-Host ("Installing pinned PS2EXE build dependency {0}..." -f $ps2exeVersion) -ForegroundColor Cyan
        $nugetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $nugetProvider) {
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
        }
        Install-Module -Name ps2exe -RequiredVersion $ps2exeVersion -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
    }

    Import-Module -Name ps2exe -RequiredVersion $ps2exeVersion -Force -ErrorAction Stop
    if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
        throw "PS2EXE $ps2exeVersion was imported, but Invoke-ps2exe is unavailable."
    }

    Write-Host 'Compiling AnyCPU console executable (no external Modules folder)...' -ForegroundColor Cyan
    # Do NOT use -longPaths here: PS2EXE creates an adjacent .exe.config for that option,
    # which breaks the one-file distribution requirement.
    Invoke-ps2exe -inputFile $bundlePath -outputFile $outputFile `
        -requireAdmin -supportOS -iconFile $iconFile `
        -title 'Windows Network Repair Pro' `
        -description 'SMB compatibility repair, rollback and live configuration monitoring.' `
        -company 'Windows Network Repair Pro' `
        -product 'Windows Network Repair Pro' `
        -copyright 'Copyright (c) Windows Network Repair Pro contributors' `
        -version $Version

    if (Test-Path -LiteralPath $configFile) {
        throw 'PS2EXE generated an adjacent .exe.config. The build is rejected because the deliverable must be a single EXE file.'
    }

    $builtFile = Test-PortablePeExecutable -Path $outputFile
    Write-Host ''
    Write-Host ("Build complete: {0}" -f $builtFile.FullName) -ForegroundColor Green
    Write-Host ("Size: {0:N2} MB | Version: {1} | Architecture: AnyCPU" -f ($builtFile.Length / 1MB), $Version) -ForegroundColor Green
    Write-Host 'Verified: valid PE executable, bundled project modules, and no required .config sidecar.' -ForegroundColor Green
    Write-Host 'Build script completed successfully.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $bundlePath) {
        Remove-Item -LiteralPath $bundlePath -Force -ErrorAction SilentlyContinue
    }
}
