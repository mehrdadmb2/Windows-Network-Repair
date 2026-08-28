function Get-BindingSnapshot {
    $result = @()
    if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) {
        return @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction SilentlyContinue | Select-Object Name,Enabled,Status,DisplayName,ComponentID)
    }
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        try {
            return @(Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -ErrorAction Stop | Where-Object { $_.ComponentID -eq 'ms_msclient' } | Select-Object Name,Enabled,Status,DisplayName,ComponentID)
        } catch {}
    }
    return $result
}

function Get-RegistryDword {
    param([string]$Path,[string]$Name)
    try {
        $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [int]$p.$Name
    } catch { return $null }
}

function Ensure-Dword {
    param([string]$Path,[string]$Name,[int]$Value)
    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Get-ThreeMainSettings {
    $wk = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    [pscustomobject]@{
        AllowInsecureGuestAuth_Runtime = Get-RegistryDword $wk 'AllowInsecureGuestAuth'
        AllowInsecureGuestAuth_Policy = Get-RegistryDword $pol 'AllowInsecureGuestAuth'
        RequireSecuritySignature = Get-RegistryDword $wk 'RequireSecuritySignature'
        EnableSecuritySignature = Get-RegistryDword $wk 'EnableSecuritySignature'
        PolicyRequireSecuritySignature = Get-RegistryDword $pol 'RequireSecuritySignature'
        Binding = @(Get-BindingSnapshot)
    }
}

function Set-InsecureGuest {
    param([switch]$ModernPolicyKey)
    $runtime = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    Ensure-Dword $runtime 'AllowInsecureGuestAuth' 1
    if ($ModernPolicyKey) {
        $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
        Ensure-Dword $policy 'AllowInsecureGuestAuth' 1
    }
}

function Disable-SmbClientSigning {
    $runtime = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    Ensure-Dword $runtime 'RequireSecuritySignature' 0
    Ensure-Dword $runtime 'EnableSecuritySignature' 0
    if (Get-Command Set-SmbClientConfiguration -ErrorAction SilentlyContinue) {
        Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
    }
}

function Disable-MsClientBinding {
    $results = @()
    if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue -and Get-Command Disable-NetAdapterBinding -ErrorAction SilentlyContinue) {
        $bindings = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction Stop)
        foreach ($b in $bindings) {
            if ($b.Enabled) {
                Disable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null
                $results += [pscustomobject]@{Adapter=$b.Name;Method='NetAdapter';Result='Disabled'}
            } else {
                $results += [pscustomobject]@{Adapter=$b.Name;Method='NetAdapter';Result='AlreadyDisabled'}
            }
        }
        return $results
    }
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue -and Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue) {
        $bindings = @(Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -ErrorAction Stop | Where-Object { $_.ComponentID -eq 'ms_msclient' })
        foreach ($b in $bindings) {
            if ($b.Enabled) {
                Invoke-CimMethod -InputObject $b -MethodName Disable -ErrorAction Stop | Out-Null
                $results += [pscustomobject]@{Adapter=$b.Name;Method='CIM';Result='Disabled'}
            } else {
                $results += [pscustomobject]@{Adapter=$b.Name;Method='CIM';Result='AlreadyDisabled'}
            }
        }
        return $results
    }
    throw 'Native adapter-binding API is not available on this Windows/PowerShell environment. No unsafe netcfg uninstallation was attempted.'
}

function Enable-MsClientBindingFromSnapshot {
    param([object[]]$Snapshot)
    foreach ($b in $Snapshot) {
        try {
            if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) {
                if ([bool]$b.Enabled) { Enable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null }
                else { Disable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null }
            } elseif (Get-Command Get-CimInstance -ErrorAction SilentlyContinue -and Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue) {
                $q = Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -Filter ("Name='{0}' AND ComponentID='ms_msclient'" -f $b.Name.Replace("'","''")) -ErrorAction Stop
                if ([bool]$b.Enabled) { Invoke-CimMethod -InputObject $q -MethodName Enable -ErrorAction Stop | Out-Null } else { Invoke-CimMethod -InputObject $q -MethodName Disable -ErrorAction Stop | Out-Null }
            }
        } catch {}
    }
}

Export-ModuleMember -Function Get-BindingSnapshot,Get-ThreeMainSettings,Set-InsecureGuest,Disable-SmbClientSigning,Disable-MsClientBinding,Enable-MsClientBindingFromSnapshot
