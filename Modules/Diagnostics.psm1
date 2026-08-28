function Get-ServiceStateSafe {
    param([string]$Name)
    try {
        $s = Get-Service -Name $Name -ErrorAction Stop
        return [pscustomobject]@{ Name=$Name; Status=$s.Status.ToString(); StartType=$s.StartType.ToString() }
    } catch { return [pscustomobject]@{ Name=$Name; Status='NotInstalled'; StartType='Unknown' } }
}

function Get-NetworkDiagnostics {
    $services = @('LanmanWorkstation','LanmanServer','FDResPub','FDPHost','SSDPSRV','upnphost','lmhosts') | ForEach-Object { Get-ServiceStateSafe $_ }
    $fw = @()
    if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        foreach ($group in @('Network Discovery','File and Printer Sharing')) {
            $rules = @(Get-NetFirewallRule -DisplayGroup $group -Enabled True -ErrorAction SilentlyContinue)
            $fw += [pscustomobject]@{Group=$group;EnabledRules=$rules.Count}
        }
    }
    [pscustomobject]@{ Services=$services; Firewall=$fw }
}
Export-ModuleMember -Function Get-NetworkDiagnostics
