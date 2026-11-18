function New-RepairBackup {
    param([Parameter(Mandatory=$true)][string]$Root,[object]$BindingSnapshot)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $dir = Join-Path $Root ('Backup\Backup_' + $stamp)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $keys = @(
        'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    )
    $registryState = @()
    foreach ($key in $keys) {
        $safe = $key -replace '[\\:]','_'
        $probe = & reg.exe query $key 2>$null
        $exists = ($LASTEXITCODE -eq 0)
        $exported = $false
        $file = Join-Path $dir ($safe + '.reg')
        if ($exists) {
            & reg.exe export $key $file /y 2>$null | Out-Null
            $exported = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file))
            if (-not $exported) { throw ("Registry backup failed for {0}. No change was applied." -f $key) }
        }
        $registryState += [pscustomobject]@{ Key=$key; Existed=$exists; ExportFile=if ($exported) { [IO.Path]::GetFileName($file) } else { $null } }
    }

    if ($null -ne $BindingSnapshot) {
        ConvertTo-Json -InputObject @($BindingSnapshot) -Depth 6 | Set-Content -LiteralPath (Join-Path $dir 'bindings.json') -Encoding UTF8
    }

    # Record exact presence, data and registry type for every value touched by the repair.
    # A .reg import alone cannot remove a value that did not exist in the original snapshot.
    $valueTargets = @(
        @{ Path='HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name='AllowInsecureGuestAuth' },
        @{ Path='HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name='RequireSecuritySignature' },
        @{ Path='HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name='EnableSecuritySignature' },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'; Name='AllowInsecureGuestAuth' },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'; Name='RequireSecuritySignature' }
    )
    $registryValues = @()
    foreach ($target in $valueTargets) {
        $exists = $false
        $value = $null
        $kind = $null
        if (Test-Path -LiteralPath $target.Path) {
            $key = Get-Item -LiteralPath $target.Path -ErrorAction Stop
            $exists = @($key.GetValueNames()) -contains $target.Name
            if ($exists) {
                $value = $key.GetValue($target.Name)
                $kind = [string]$key.GetValueKind($target.Name)
            }
        }
        $registryValues += [pscustomobject]@{ Path=$target.Path; Name=$target.Name; Existed=$exists; Value=$value; Kind=$kind }
    }

    $manifest = [pscustomobject]@{
        SchemaVersion = 3
        Created = (Get-Date).ToString('o')
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        PowerShell = $PSVersionTable.PSVersion.ToString()
        BackupDirectory = $dir
        Registry = $registryState
        RegistryValues = $registryValues
        BindingCount = @($BindingSnapshot).Count
        Note = 'Restore registry key snapshots, exact repair-value presence/data/types and saved Client for Microsoft Networks adapter binding states.'
    }
    ConvertTo-Json -InputObject $manifest -Depth 8 | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8
    return $dir
}

Export-ModuleMember -Function New-RepairBackup
