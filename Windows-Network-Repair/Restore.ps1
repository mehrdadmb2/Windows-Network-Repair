#requires -version 5.1
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Definition
$BackupDir=Join-Path $Root 'Backup'
$backups=Get-ChildItem $BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if(-not $backups){ Write-Host 'No backups found.' -ForegroundColor Red; exit 1 }
Write-Host 'Available backups:' -ForegroundColor Cyan
$i=1
foreach($b in $backups){ Write-Host ("[{0}] {1}" -f $i,$b.Name); $i++ }
$sel=Read-Host 'Select backup number or press ENTER for latest'
if([string]::IsNullOrWhiteSpace($sel)){ $target=$backups[0] }
elseif($sel -as [int] -and [int]$sel -ge 1 -and [int]$sel -le $backups.Count){ $target=$backups[[int]$sel-1] }
else { Write-Host 'Invalid selection.' -ForegroundColor Red; exit 1 }
Write-Host "Restoring $($target.FullName)" -ForegroundColor Yellow
foreach($reg in Get-ChildItem $target.FullName -Filter '*.reg' -File){
    & reg.exe import $reg.FullName | Out-Null
    if($LASTEXITCODE -ne 0){ throw "Failed to import $($reg.Name)" }
}
$adapter=Join-Path $target.FullName 'NetworkAdapters.json'
if(Test-Path $adapter){
    foreach($item in @(Get-Content $adapter -Raw | ConvertFrom-Json)){
        try{
            if($item.Enabled){ Enable-NetAdapterBinding -Name $item.Name -ComponentID $item.ComponentID -ErrorAction Stop | Out-Null }
            else{ Disable-NetAdapterBinding -Name $item.Name -ComponentID $item.ComponentID -ErrorAction Stop | Out-Null }
        }catch{ Write-Warning "Adapter restore failed for $($item.Name): $($_.Exception.Message)" }
    }
}
Write-Host 'Restore completed. Restart Windows to ensure all changes take effect.' -ForegroundColor Green
