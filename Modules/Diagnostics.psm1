function Get-ServiceStateSafe {
    param([Parameter(Mandatory=$true)][string]$Name)
    try {
        $s = Get-Service -Name $Name -ErrorAction Stop
        $startType = 'Unknown'
        try { $startType = [string]$s.StartType } catch {
            try { $startType = [string](Get-WmiObject Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction Stop).StartMode } catch {}
        }
        return [pscustomobject]@{ Name=$Name; DisplayName=[string]$s.DisplayName; Status=[string]$s.Status; StartType=$startType }
    } catch {
        return [pscustomobject]@{ Name=$Name; DisplayName=$Name; Status='NotInstalled'; StartType='Unknown' }
    }
}

function Get-NetworkDiagnostics {
    $serviceNames = @('LanmanWorkstation','LanmanServer','FDResPub','FDPHost','SSDPSRV','upnphost','lmhosts','Dnscache','NlaSvc')
    $services = @($serviceNames | ForEach-Object { Get-ServiceStateSafe $_ })
    $firewall = @()
    if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        foreach ($group in @('Network Discovery','File and Printer Sharing')) {
            try {
                $rules = @(Get-NetFirewallRule -DisplayGroup $group -Enabled True -ErrorAction Stop)
                $firewall += [pscustomobject]@{ Group=$group; EnabledRules=$rules.Count; Supported=$true }
            } catch {
                $firewall += [pscustomobject]@{ Group=$group; EnabledRules=$null; Supported=$false; Note=$_.Exception.Message }
            }
        }
    } else {
        $firewall += [pscustomobject]@{ Group='Windows Defender Firewall'; EnabledRules=$null; Supported=$false; Note='NetSecurity firewall cmdlets are unavailable.' }
    }
    [pscustomobject]@{ Services=$services; Firewall=$firewall }
}

Export-ModuleMember -Function Get-NetworkDiagnostics,Get-ServiceStateSafe
