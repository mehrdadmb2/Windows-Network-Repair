function Get-BindingSnapshot {
    if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) {
        try {
            return @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction Stop | Select-Object Name,Enabled,Status,DisplayName,ComponentID)
        } catch {}
    }
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        try {
            return @(Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -ErrorAction Stop | Where-Object { $_.ComponentID -eq 'ms_msclient' } | Select-Object Name,Enabled,Status,DisplayName,ComponentID)
        } catch {}
    }
    return @()
}

function Get-RegistryDword {
    param([string]$Path,[string]$Name)
    try {
        $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return [int]$p.$Name
    } catch { return $null }
}

function Ensure-Dword {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
}

function Get-SmbClientConfigSafe {
    if (Get-Command Get-SmbClientConfiguration -ErrorAction SilentlyContinue) {
        try { return Get-SmbClientConfiguration -ErrorAction Stop } catch {}
    }
    return $null
}

function Get-ThreeMainSettings {
    $wk = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    $smb = Get-SmbClientConfigSafe
    [pscustomobject]@{
        AllowInsecureGuestAuth_Runtime = Get-RegistryDword $wk 'AllowInsecureGuestAuth'
        AllowInsecureGuestAuth_Policy = Get-RegistryDword $pol 'AllowInsecureGuestAuth'
        RequireSecuritySignature = Get-RegistryDword $wk 'RequireSecuritySignature'
        EnableSecuritySignature = Get-RegistryDword $wk 'EnableSecuritySignature'
        PolicyRequireSecuritySignature = Get-RegistryDword $pol 'RequireSecuritySignature'
        GuestLogonsCmdlet = if ($smb -and ($smb.PSObject.Properties.Name -contains 'EnableInsecureGuestLogons')) { [bool]$smb.EnableInsecureGuestLogons } else { $null }
        RequireSigningCmdlet = if ($smb -and ($smb.PSObject.Properties.Name -contains 'RequireSecuritySignature')) { [bool]$smb.RequireSecuritySignature } else { $null }
        Binding = @(Get-BindingSnapshot)
    }
}

function Set-InsecureGuest {
    $runtime = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    $policyValue = Get-RegistryDword $policyPath 'AllowInsecureGuestAuth'
    if ($null -ne $policyValue -and $policyValue -eq 0) {
        throw 'A policy explicitly blocks insecure guest logons. The tool will not override an existing security policy; review the relevant Group Policy with your administrator.'
    }

    Ensure-Dword $runtime 'AllowInsecureGuestAuth' 1
    $cmd = Get-Command Set-SmbClientConfiguration -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('EnableInsecureGuestLogons')) {
        Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop | Out-Null
    }
}

function Disable-SmbClientSigning {
    $runtime = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    $policyRequire = Get-RegistryDword $policyPath 'RequireSecuritySignature'
    if ($null -ne $policyRequire -and $policyRequire -eq 1) {
        throw 'A policy explicitly requires SMB client signing. The tool will not override that policy.'
    }

    Ensure-Dword $runtime 'RequireSecuritySignature' 0
    Ensure-Dword $runtime 'EnableSecuritySignature' 0
    $cmd = Get-Command Set-SmbClientConfiguration -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('RequireSecuritySignature')) {
        Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop | Out-Null
    }
}

function Disable-MsClientBinding {
    $results = @()
    if ((Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) -and (Get-Command Disable-NetAdapterBinding -ErrorAction SilentlyContinue)) {
        $bindings = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction Stop)
        foreach ($b in $bindings) {
            if ($b.Enabled) {
                Disable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null
                $results += [pscustomobject]@{ Adapter=$b.Name; Method='NetAdapter'; Result='Disabled' }
            } else {
                $results += [pscustomobject]@{ Adapter=$b.Name; Method='NetAdapter'; Result='AlreadyDisabled' }
            }
        }
        return @($results)
    }

    if ((Get-Command Get-CimInstance -ErrorAction SilentlyContinue) -and (Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue)) {
        try {
            $bindings = @(Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -ErrorAction Stop | Where-Object { $_.ComponentID -eq 'ms_msclient' })
            foreach ($b in $bindings) {
                if ($b.Enabled) {
                    Invoke-CimMethod -InputObject $b -MethodName Disable -ErrorAction Stop | Out-Null
                    $results += [pscustomobject]@{ Adapter=$b.Name; Method='CIM'; Result='Disabled' }
                } else {
                    $results += [pscustomobject]@{ Adapter=$b.Name; Method='CIM'; Result='AlreadyDisabled' }
                }
            }
            return @($results)
        } catch { throw ('Adapter binding API failed: ' + $_.Exception.Message) }
    }
    throw 'UNSUPPORTED_API: The native adapter-binding API is unavailable on this Windows/PowerShell environment. No unsafe component uninstallation was attempted.'
}

function Enable-MsClientBindingFromSnapshot {
    param([object[]]$Snapshot)
    $results = @()
    $hasNetAdapterApi = [bool](Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Enable-NetAdapterBinding -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Disable-NetAdapterBinding -ErrorAction SilentlyContinue)
    $hasCimApi = [bool](Get-Command Get-CimInstance -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue)

    foreach ($b in $Snapshot) {
        try {
            $restored = $false
            $errors = @()
            if ($hasNetAdapterApi) {
                try {
                    if ([bool]$b.Enabled) {
                        Enable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null
                    } else {
                        Disable-NetAdapterBinding -Name $b.Name -ComponentID 'ms_msclient' -Confirm:$false -ErrorAction Stop | Out-Null
                    }
                    $restored = $true
                } catch { $errors += ('NetAdapter: ' + $_.Exception.Message) }
            }

            # Use the CIM provider when the NetAdapter cmdlets are absent or fail.
            if (-not $restored -and $hasCimApi) {
                try {
                    $allBindings = @(Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterBindingSettingData -ErrorAction Stop)
                    $matches = @($allBindings | Where-Object { $_.ComponentID -eq 'ms_msclient' -and $_.Name -eq ([string]$b.Name) })
                    if ($matches.Count -eq 0) { throw 'The saved adapter binding was not found by the CIM provider.' }
                    foreach ($item in $matches) {
                        $method = if ([bool]$b.Enabled) { 'Enable' } else { 'Disable' }
                        $result = Invoke-CimMethod -InputObject $item -MethodName $method -ErrorAction Stop
                        if ($result -and $result.ReturnValue -ne 0) { throw ("CIM {0} returned code {1}." -f $method,$result.ReturnValue) }
                    }
                    $restored = $true
                } catch { $errors += ('CIM: ' + $_.Exception.Message) }
            }

            if (-not $restored) {
                if ($errors.Count -gt 0) { throw ($errors -join ' | ') }
                throw 'No supported adapter-binding restore API is available.'
            }
            $results += [pscustomobject]@{ Adapter=$b.Name; Restored=$true }
        } catch {
            $results += [pscustomobject]@{ Adapter=$b.Name; Restored=$false; Error=$_.Exception.Message }
        }
    }
    return @($results)
}

Export-ModuleMember -Function Get-BindingSnapshot,Get-ThreeMainSettings,Set-InsecureGuest,Disable-SmbClientSigning,Disable-MsClientBinding,Enable-MsClientBindingFromSnapshot,Get-RegistryDword
