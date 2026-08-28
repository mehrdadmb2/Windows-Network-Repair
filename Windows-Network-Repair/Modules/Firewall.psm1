function Enable-NRNetworkDiscoveryFirewall {
    $rules = @(Get-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction SilentlyContinue)
    if (-not $rules) { throw 'Network Discovery firewall rule group was not found.' }
    Set-NetFirewallRule -DisplayGroup 'Network Discovery' -Enabled True -ErrorAction Stop
}
function Enable-NRFileSharingFirewall {
    $rules = @(Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue)
    if (-not $rules) { throw 'File and Printer Sharing firewall rule group was not found.' }
    Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -ErrorAction Stop
}
Export-ModuleMember -Function Enable-NRNetworkDiscoveryFirewall,Enable-NRFileSharingFirewall
