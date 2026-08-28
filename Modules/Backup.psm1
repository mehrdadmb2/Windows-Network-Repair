function New-RepairBackup {
    param([string]$Root, [object]$BindingSnapshot)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $Root ('Backup\Backup_' + $stamp)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $keys = @(
        'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    )
    foreach ($key in $keys) {
        $safe = $key -replace '[\\:]','_'
        & reg.exe export $key (Join-Path $dir ($safe + '.reg')) /y | Out-Null
    }
    if ($BindingSnapshot) { $BindingSnapshot | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dir 'bindings.json') -Encoding UTF8 }
    $manifest = [pscustomobject]@{
        Created = (Get-Date).ToString('o')
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        PowerShell = $PSVersionTable.PSVersion.ToString()
        BackupDirectory = $dir
        Note = 'Restore registry and saved Client for Microsoft Networks binding states from this snapshot.'
    }
    $manifest | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'manifest.json') -Encoding UTF8
    return $dir
}
Export-ModuleMember -Function New-RepairBackup
