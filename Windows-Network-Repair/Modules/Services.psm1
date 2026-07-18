function Enable-SMB1 {
    Write-Log "Enabling SMB 1.0 / CIFS support..."
    Enable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart
    Write-Host "[OK] SMB1 enabled (may require restart)." -ForegroundColor Green
}