function Disable-ClientForMSNetworks {
    Write-Log "Disabling Client for Microsoft Networks on all adapters..."
    Get-NetAdapter | ForEach-Object {
        Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_msclient" -ErrorAction SilentlyContinue
    }
    Write-Host "[OK] Client for Microsoft Networks disabled on all adapters." -ForegroundColor Green
}