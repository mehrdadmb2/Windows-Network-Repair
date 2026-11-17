#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$Version = '2.0.0.0'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$mainFile = Join-Path $repoRoot 'NetworkRepair.ps1'
$moduleDir = Join-Path $repoRoot 'Modules'
$moduleOrder = @('Console.psm1','System.psm1','Logging.psm1','Backup.psm1','ThreeFixes.psm1','Diagnostics.psm1')
$ps2exeVersion = '1.0.18'

if (-not (Test-Path -LiteralPath $mainFile)) { throw "Main script not found: $mainFile" }
foreach ($name in $moduleOrder) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleDir $name))) { throw "Required module not found: $name" }
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$bundlePath = Join-Path ([IO.Path]::GetTempPath()) ('WNR_Bundle_' + [guid]::NewGuid().ToString('N') + '.ps1')
$outputFile = Join-Path $OutputPath 'WindowsNetworkRepair.exe'
$iconFile = Join-Path $repoRoot 'assets\WindowsNetworkRepair.ico'
if (-not (Test-Path -LiteralPath $iconFile)) { throw "Application icon not found: $iconFile" }

try {
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('# Windows Network Repair Pro — bundled executable source')
    $parts.Add("`$env:WNR_BUNDLED_EXE = '1'")
    foreach ($name in $moduleOrder) {
        $path = Join-Path $moduleDir $name
        $content = Get-Content -LiteralPath $path -Raw
        $content = [regex]::Replace($content,'(?m)^\s*Export-ModuleMember\b.*(?:\r?\n|$)','')
        $parts.Add("`r`n# --- Bundled module: $name ---`r`n")
        $parts.Add($content)
    }

    $main = Get-Content -LiteralPath $mainFile -Raw
    $main = [regex]::Replace($main,'(?m)^Import-Module \(Join-Path \$Root ''Modules\\[^'']+''\) -Force\s*\r?\n','')
    if ($main -match '(?m)^Import-Module \(Join-Path \$Root') {
        throw 'One or more module imports could not be removed. Refusing to build an EXE with external module dependencies.'
    }
    $parts.Add("`r`n# --- Main application ---`r`n")
    $parts.Add($main)
    [IO.File]::WriteAllText($bundlePath,($parts -join "`r`n"),(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))

    $installedPs2Exe = Get-Module -ListAvailable -Name ps2exe | Where-Object { $_.Version.ToString() -eq $ps2exeVersion } | Select-Object -First 1
    if (-not $installedPs2Exe) {
        Write-Host ("Installing pinned PS2EXE build dependency {0}..." -f $ps2exeVersion) -ForegroundColor Cyan
        Install-Module -Name ps2exe -RequiredVersion $ps2exeVersion -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
    Import-Module ps2exe -RequiredVersion $ps2exeVersion -Force
    $versionFourParts = $Version
    if ($versionFourParts -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Version must use four numeric parts, e.g. 2.0.0.0.' }

    Write-Host 'Compiling the single-file script bundle (AnyCPU console executable)...' -ForegroundColor Cyan
    Invoke-ps2exe -inputFile $bundlePath -outputFile $outputFile `
        -requireAdmin -supportOS -longPaths -iconFile $iconFile `
        -title 'Windows Network Repair Pro' `
        -description 'SMB compatibility repair, rollback and live configuration monitoring.' `
        -company 'Windows Network Repair Pro' `
        -product 'Windows Network Repair Pro' `
        -copyright 'Copyright (c) Windows Network Repair Pro contributors' `
        -version $versionFourParts

    if (-not (Test-Path -LiteralPath $outputFile)) { throw 'PS2EXE did not create the expected executable.' }
    $item = Get-Item -LiteralPath $outputFile
    Write-Host ("Build complete: {0} ({1:N2} MB)" -f $item.FullName,($item.Length / 1MB)) -ForegroundColor Green
    Write-Host 'The EXE contains the project modules; no Modules folder is required beside the EXE.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $bundlePath) { Remove-Item -LiteralPath $bundlePath -Force -ErrorAction SilentlyContinue }
}
