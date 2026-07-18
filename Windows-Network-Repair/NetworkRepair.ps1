# NetworkRepair.ps1
# Windows Network / SMB Repair Utility

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

# بارگذاری ماژول‌ها
Import-Module "$scriptPath\Modules\Logger.psm1" -Force
Import-Module "$scriptPath\Modules\Registry.psm1" -Force
Import-Module "$scriptPath\Modules\Services.psm1" -Force
Import-Module "$scriptPath\Modules\SMB.psm1" -Force
Import-Module "$scriptPath\Modules\Firewall.psm1" -Force

# تنظیمات اولیه
$BackupDir = "$scriptPath\Backup"
$LogDir = "$scriptPath\Logs"
$LogFile = "$LogDir\NetworkRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Initialize-Logger -LogFile $LogFile

# چک ادمین
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator." -ForegroundColor Red
    exit 1
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "        Windows Network / SMB Repair Utility v2.0" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[1] Check Current Configuration"
    Write-Host "[2] Apply Recommended Fixes (Step by Step)"
    Write-Host "[3] Enable SMB 1.0 / CIFS File Sharing Support"
    Write-Host "[4] Disable SMB Signing"
    Write-Host "[5] Enable Insecure Guest Logons"
    Write-Host "[6] Disable Client for Microsoft Networks (on all NICs)"
    Write-Host "[7] Backup Current Settings"
    Write-Host "[8] Restore Previous Settings"
    Write-Host "[9] Undo All Changes"
    Write-Host "[10] Generate Report"
    Write-Host "[0] Exit"
    Write-Host ""
}

function Check-Configuration {
    Write-Host "`n=== Current Configuration ===" -ForegroundColor Yellow
    # Network Discovery
    $discovery = Get-NetFirewallRule -DisplayGroup "Network Discovery" -Enabled True -ErrorAction SilentlyContinue
    if ($discovery) { Write-Host "[OK] Network Discovery Firewall Rules are enabled" -ForegroundColor Green }
    else { Write-Host "[FAIL] Network Discovery Firewall Rules are disabled" -ForegroundColor Red }

    # File Sharing
    $sharing = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True -ErrorAction SilentlyContinue
    if ($sharing) { Write-Host "[OK] File and Printer Sharing Firewall Rules are enabled" -ForegroundColor Green }
    else { Write-Host "[FAIL] File and Printer Sharing Firewall Rules are disabled" -ForegroundColor Red }

    # Services
    $svc = @("FDResPub", "FDPHost", "SSDPSRV", "upnphost", "LanmanServer", "LanmanWorkstation")
    foreach ($s in $svc) {
        $status = (Get-Service -Name $s -ErrorAction SilentlyContinue).Status
        if ($status -eq 'Running') { Write-Host "[OK] Service $s is running" -ForegroundColor Green }
        elseif ($status) { Write-Host "[WARN] Service $s is $status" -ForegroundColor Yellow }
        else { Write-Host "[FAIL] Service $s not found" -ForegroundColor Red }
    }

    # SMB signing
    $signAlways = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "RequireSecuritySignature" -ErrorAction SilentlyContinue).RequireSecuritySignature
    if ($signAlways -eq 0) { Write-Host "[OK] SMB Signing (always) is Disabled" -ForegroundColor Green }
    else { Write-Host "[WARN] SMB Signing (always) is Enabled" -ForegroundColor Yellow }

    # Guest auth
    $guest = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -ErrorAction SilentlyContinue).AllowInsecureGuestAuth
    if ($guest -eq 1) { Write-Host "[OK] Insecure Guest Auth is Enabled" -ForegroundColor Green }
    else { Write-Host "[WARN] Insecure Guest Auth is Disabled" -ForegroundColor Yellow }

    # Client for MS Networks
    Get-NetAdapter | ForEach-Object {
        $name = $_.Name
        $client = Get-NetAdapterBinding -Name $name -ComponentID "ms_msclient" -ErrorAction SilentlyContinue
        if ($client.Enabled) { Write-Host "[WARN] Client for Microsoft Networks is ENABLED on $name" -ForegroundColor Yellow }
        else { Write-Host "[OK] Client for Microsoft Networks is DISABLED on $name" -ForegroundColor Green }
    }
}

function Apply-RecommendedFixes {
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Enable", "Enable Network Discovery and File Sharing"),
        [System.Management.Automation.Host.ChoiceDescription]::new("&Disable", "Disable SMB Signing"),
        [System.Management.Automation.Host.ChoiceDescription]::new("&Guest", "Enable Insecure Guest Logons"),
        [System.Management.Automation.Host.ChoiceDescription]::new("&Client", "Disable Client for Microsoft Networks"),
        [System.Management.Automation.Host.ChoiceDescription]::new("&Cancel", "Cancel")
    )
    $result = $Host.UI.PromptForChoice("Select fixes to apply", "What would you like to fix?", $choices, 4)
    switch ($result) {
        0 { Enable-NetworkDiscoveryAndSharing }
        1 { Disable-SMBSigning }
        2 { Enable-InsecureGuest }
        3 { Disable-ClientForMSNetworks }
    }
}

function Backup-Settings {
    Write-Log "Creating backup..."
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = "$BackupDir\RegistryBackup_$timestamp.reg"
    reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" $backupFile /y
    Write-Host "[OK] Registry backup saved to $backupFile" -ForegroundColor Green
}

function Restore-Settings {
    $backups = Get-ChildItem "$BackupDir\*.reg" | Sort-Object LastWriteTime -Descending
    if (-not $backups) { Write-Host "No backups found." -ForegroundColor Red; return }
    $latest = $backups[0].FullName
    Write-Host "Restoring from: $latest" -ForegroundColor Yellow
    reg import $latest
    Write-Host "[OK] Registry restored. Restart recommended." -ForegroundColor Green
}

function Undo-All {
    Write-Host "Undoing all changes: enabling SMB signing, disabling guest auth, enabling Client for MS Networks..." -ForegroundColor Yellow
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "RequireSecuritySignature" -Value 1
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 0
    Get-NetAdapter | ForEach-Object { Enable-NetAdapterBinding -Name $_.Name -ComponentID "ms_msclient" }
    Write-Host "[OK] Undone. Restart to apply." -ForegroundColor Green
}

function Generate-Report {
    $report = "$LogDir\Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    "Windows Network Configuration Report - $(Get-Date)" | Out-File $report
    Get-Service -Name @("FDResPub","FDPhost","SSDPSRV","upnphost","LanmanServer","LanmanWorkstation") | Select Name,Status | Out-File $report -Append
    "`nSMB Signing:" | Out-File $report -Append
    Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" | Select RequireSecuritySignature,AllowInsecureGuestAuth | Out-File $report -Append
    Write-Host "[OK] Report saved to $report" -ForegroundColor Green
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        '1' { Check-Configuration }
        '2' { Apply-RecommendedFixes }
        '3' { Enable-SMB1 }
        '4' { Disable-SMBSigning }
        '5' { Enable-InsecureGuest }
        '6' { Disable-ClientForMSNetworks }
        '7' { Backup-Settings }
        '8' { Restore-Settings }
        '9' { Undo-All }
        '10' { Generate-Report }
        '0' { return }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }
    if ($choice -ne '0') { Read-Host "`nPress Enter to continue" }
} while ($choice -ne '0')