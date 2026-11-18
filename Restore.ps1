#requires -Version 3.0
$ErrorActionPreference = 'Stop'
$primaryDataRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'WindowsNetworkRepairPro' } else { $null }
$fallbackDataRoot = Join-Path $PSScriptRoot 'Data'
$backupRoots = @()
if ($primaryDataRoot) { $backupRoots += (Join-Path $primaryDataRoot 'Backup') }
$backupRoots += (Join-Path $fallbackDataRoot 'Backup')
# Preserve access to the legacy v1 backup directory used by the original project.
$backupRoots += (Join-Path $PSScriptRoot 'Backup')
$backupRoots = @($backupRoots | Select-Object -Unique)
$DataRoot = $fallbackDataRoot
if ($primaryDataRoot -and (Test-Path -LiteralPath (Join-Path $primaryDataRoot 'Backup'))) { $DataRoot = $primaryDataRoot }

function Write-Line([string]$Text,[ConsoleColor]$Color=[ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
}

function Test-Admin {
    try {
        $p = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Admin)) {
    Write-Line 'Administrator privileges are required. Run Restore.cmd as administrator.' Yellow
    exit 1
}

Import-Module (Join-Path $PSScriptRoot 'Modules\ThreeFixes.psm1') -Force

$items = @()
foreach ($backupRoot in $backupRoots) {
    if (Test-Path -LiteralPath $backupRoot) {
        $items += @(Get-ChildItem -LiteralPath $backupRoot -Filter 'Backup_*' -Directory -ErrorAction SilentlyContinue)
    }
}
$items = @($items | Sort-Object LastWriteTime -Descending)
if ($items.Count -eq 0) {
    Write-Line ('No backup snapshots were found in: ' + ($backupRoots -join '; ')) Yellow
    exit 0
}

Write-Line 'Available rollback snapshots:' Cyan
for ($i=0; $i -lt $items.Count; $i++) {
    $manifest = Join-Path $items[$i].FullName 'manifest.json'
    $created = if (Test-Path -LiteralPath $manifest) { try { (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).Created } catch { 'Unknown date' } } else { 'Invalid snapshot' }
    Write-Host ("[{0}] {1}  {2}" -f ($i+1),$items[$i].Name,$created)
}
$pick = Read-Host 'Select backup number (0 = cancel)'
if ($pick -eq '0') { exit 0 }
$idx = 0
if (-not [int]::TryParse($pick,[ref]$idx) -or $idx -lt 1 -or $idx -gt $items.Count) {
    Write-Line 'Invalid selection.' Red
    exit 1
}

$backup = $items[$idx-1]
$manifestPath = Join-Path $backup.FullName 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { Write-Line 'Backup manifest not found. Restore cancelled.' Red; exit 1 }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$hasRegistryManifest = $manifest.PSObject.Properties.Name -contains 'Registry'
Write-Line ('Selected snapshot: ' + $backup.Name) Yellow
$confirm = Read-Host 'Type RESTORE to continue'
if ($confirm -cne 'RESTORE') { Write-Line 'Restore cancelled.' DarkGray; exit 0 }

try {
    if (-not $hasRegistryManifest) {
        # Backward compatibility with the original project snapshots.
        foreach ($legacyReg in @(Get-ChildItem -LiteralPath $backup.FullName -Filter '*.reg' -File -ErrorAction SilentlyContinue)) {
            & reg.exe import $legacyReg.FullName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('Legacy registry import failed: ' + $legacyReg.Name) }
            Write-Line ('Restored legacy registry export: ' + $legacyReg.Name) Green
        }
    }
    foreach ($entry in @($manifest.Registry)) {
        $regFile = if ($entry.ExportFile) { Join-Path $backup.FullName $entry.ExportFile } else { $null }
        if ($entry.Existed) {
            if (-not $regFile -or -not (Test-Path -LiteralPath $regFile)) { throw ('The snapshot is incomplete: registry export is missing for ' + $entry.Key) }
            & reg.exe import $regFile | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('Registry import failed: ' + $entry.Key) }
            Write-Line ('Restored registry: ' + $entry.Key) Green
        } elseif (-not $entry.Existed) {
            $providerPath = $entry.Key -replace '^HKLM\\','HKLM:\'
            if (Test-Path -LiteralPath $providerPath) { Remove-Item -LiteralPath $providerPath -Recurse -Force -ErrorAction Stop }
            Write-Line ('Removed key created after snapshot: ' + $entry.Key) Green
        }
    }

    foreach ($entry in @($manifest.RegistryValues)) {
        if ($null -eq $entry.Path -or $null -eq $entry.Name) { throw 'The backup contains an invalid registry-value record.' }
        if ($entry.Existed) {
            if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
            $key = Get-Item -LiteralPath $entry.Path -ErrorAction Stop
            $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$entry.Kind)
            $restoreValue = $entry.Value
            switch ([string]$entry.Kind) {
                'DWord' { $restoreValue = [int]$entry.Value }
                'QWord' { $restoreValue = [long]$entry.Value }
                'String' { $restoreValue = [string]$entry.Value }
                'ExpandString' { $restoreValue = [string]$entry.Value }
                'MultiString' { $restoreValue = [string[]]@($entry.Value) }
                'Binary' { $restoreValue = [byte[]]@($entry.Value) }
                'None' { $restoreValue = [byte[]]@($entry.Value) }
                default { throw ('Unsupported registry value type in backup: ' + $entry.Kind) }
            }
            $key.SetValue([string]$entry.Name,$restoreValue,$kind)
        } elseif (Test-Path -LiteralPath $entry.Path) {
            $key = Get-Item -LiteralPath $entry.Path -ErrorAction Stop
            if (@($key.GetValueNames()) -contains [string]$entry.Name) { $key.DeleteValue([string]$entry.Name,$false) }
        }
        Write-Line ('Restored exact registry value: ' + $entry.Name) Green
    }

    $bindingFile = Join-Path $backup.FullName 'bindings.json'
    if (Test-Path -LiteralPath $bindingFile) {
        $bindings = @(Get-Content -LiteralPath $bindingFile -Raw | ConvertFrom-Json)
        foreach ($result in @(Enable-MsClientBindingFromSnapshot -Snapshot $bindings)) {
            if ($result.Restored) { Write-Line ('Restored binding: ' + $result.Adapter) Green }
            else { Write-Line ('Binding restore failed: ' + $result.Adapter + ' — ' + $result.Error) Yellow }
        }
    }
    Write-Line 'Restore completed. A network reconnect or Windows restart may be required.' Green
} catch {
    Write-Line ('Restore failed: ' + $_.Exception.Message) Red
    exit 1
}
