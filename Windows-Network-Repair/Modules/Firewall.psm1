function Enable-NetworkDiscoveryAndSharing {
    Write-Log "Enabling Network Discovery and File Sharing firewall rules..."
    Set-NetFirewallRule -DisplayGroup "Network Discovery" -Enabled True
    Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True
    Write-Host "[OK] Firewall rules enabled." -ForegroundColor Green
}