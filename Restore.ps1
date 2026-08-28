$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupRoot = Join-Path $Root 'Backup'

function Write-Line([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Line 'ERROR: Administrator privileges are required.' Red
    exit 1
}

$items = @(Get-ChildItem -Path $BackupRoot -Filter 'Backup_*' -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($items.Count -eq 0) {
    Write-Line 'No backup snapshots were found.' Yellow
    exit 0
}

Write-Line 'Available backups:' Cyan
for ($i=0; $i -lt $items.Count; $i++) {
    Write-Host ("[{0}] {1}" -f ($i+1), $items[$i].Name)
}
$pick = Read-Host 'Select backup number (0 = cancel)'
if ($pick -eq '0') { exit 0 }
$idx = 0
if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 1 -or $idx -gt $items.Count) {
    Write-Line 'Invalid selection.' Red
    exit 1
}

$backup = $items[$idx-1]
$regFiles = Get-ChildItem -Path $backup.FullName -Filter '*.reg' -File -ErrorAction SilentlyContinue
foreach ($reg in $regFiles) {
    Write-Line ("Importing {0}" -f $reg.Name) DarkCyan
    & reg.exe import $reg.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Line ("Failed to import {0}" -f $reg.Name) Red }
}

$bindingFile = Join-Path $backup.FullName 'bindings.json'
if (Test-Path $bindingFile) {
    try {
        $bindings = @(Get-Content $bindingFile -Raw | ConvertFrom-Json)
        if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) {
            foreach ($b in $bindings) {
                try {
                    if ([bool]$b.Enabled) {
                        Enable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -ErrorAction Stop | Out-Null
                    } else {
                        Disable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -ErrorAction Stop | Out-Null
                    }
                } catch { Write-Line ("Binding restore failed for {0}: {1}" -f $b.Name, $_.Exception.Message) Yellow }
            }
        }
    } catch { Write-Line ('Binding restore skipped: ' + $_.Exception.Message) Yellow }
}

Write-Line 'Restore completed. A Windows restart may be required.' Green
