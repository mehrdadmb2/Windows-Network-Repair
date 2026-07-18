function Disable-SMBSigning {
    Write-Log "Disabling SMB Signing..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "RequireSecuritySignature" -Value 0 -Type DWord
    Write-Host "[OK] SMB Signing disabled." -ForegroundColor Green
}

function Enable-InsecureGuest {
    Write-Log "Enabling Insecure Guest Auth..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord
    Write-Host "[OK] Insecure Guest Auth enabled." -ForegroundColor Green
}