#requires -version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BackupDir = Join-Path $Root 'Backup'
$LogDir = Join-Path $Root 'Logs'
$ModuleDir = Join-Path $Root 'Modules'
New-Item -ItemType Directory -Force -Path $BackupDir,$LogDir | Out-Null

Import-Module (Join-Path $ModuleDir 'Logger.psm1') -Force
Import-Module (Join-Path $ModuleDir 'Registry.psm1') -Force
Import-Module (Join-Path $ModuleDir 'SMB.psm1') -Force
Import-Module (Join-Path $ModuleDir 'Services.psm1') -Force
Import-Module (Join-Path $ModuleDir 'Firewall.psm1') -Force

$sessionId = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogDir "NetworkRepair_$sessionId.log"
Initialize-NRLogger -Path $LogFile

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host 'This tool must be run as Administrator.' -ForegroundColor Red
    exit 1
}

function Get-OSInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        [pscustomobject]@{
            Caption = $os.Caption
            Version = $os.Version
            Build = $os.BuildNumber
            Architecture = $os.OSArchitecture
            PowerShell = $PSVersionTable.PSVersion.ToString()
        }
    } catch {
        [pscustomobject]@{ Caption='Unknown'; Version='Unknown'; Build='Unknown'; Architecture='Unknown'; PowerShell=$PSVersionTable.PSVersion.ToString() }
    }
}

function Show-Header {
    Clear-Host
    $os = Get-OSInfo
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '              Windows Network Repair Utility' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ("OS: {0} | Build: {1} | PowerShell: {2}" -f $os.Caption,$os.Build,$os.PowerShell) -ForegroundColor DarkGray
    Write-Host ''
}

function Pause-NR { Read-Host 'Press ENTER to continue' | Out-Null }

function Confirm-NR($Message) {
    $a = Read-Host "$Message [Y/N]"
    return $a -match '^(y|yes)$'
}

function Invoke-Step($Name, [scriptblock]$Action) {
    Write-NRLog "START: $Name"
    try {
        & $Action
        Write-Host "[OK] $Name" -ForegroundColor Green
        Write-NRLog "SUCCESS: $Name"
        return $true
    } catch {
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
        Write-NRLog "ERROR: $Name :: $($_.Exception.ToString())"
        return $false
    }
}

function New-FullBackup {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $BackupDir $stamp
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $paths = @(
        'HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters',
        'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    )
    foreach ($p in $paths) {
        $safe = ($p -replace '[\\:]','_') + '.reg'
        $out = Join-Path $dir $safe
        & reg.exe export $p $out /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Registry export failed: $p" }
    }

    $adapterFile = Join-Path $dir 'NetworkAdapters.json'
    Get-NetAdapterBinding -ComponentID ms_msclient -ErrorAction SilentlyContinue |
        Select-Object Name,DisplayName,ComponentID,Enabled |
        ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $adapterFile

    $featuresFile = Join-Path $dir 'WindowsFeatures.json'
    try {
        Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop |
            Select-Object FeatureName,State |
            ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $featuresFile
    } catch {
        '{"FeatureName":"SMB1Protocol","State":"Unknown"}' | Set-Content -Encoding UTF8 $featuresFile
    }

    $meta = [pscustomobject]@{
        Created = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        OS = Get-OSInfo
        BackupDirectory = $dir
    }
    $meta | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $dir 'BackupInfo.json')
    Write-NRLog "Backup created: $dir"
    return $dir
}

function Get-LatestBackup {
    Get-ChildItem -Path $BackupDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Restore-Backup($Dir) {
    if (-not (Test-Path $Dir)) { throw "Backup not found: $Dir" }
    $regs = Get-ChildItem $Dir -Filter '*.reg' -File
    foreach ($reg in $regs) {
        & reg.exe import $reg.FullName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to import $($reg.Name)" }
    }

    $adapterFile = Join-Path $Dir 'NetworkAdapters.json'
    if (Test-Path $adapterFile) {
        $items = Get-Content $adapterFile -Raw | ConvertFrom-Json
        foreach ($item in @($items)) {
            try {
                if ($item.Enabled) {
                    Enable-NetAdapterBinding -Name $item.Name -ComponentID $item.ComponentID -ErrorAction Stop
                } else {
                    Disable-NetAdapterBinding -Name $item.Name -ComponentID $item.ComponentID -ErrorAction Stop
                }
            } catch {
                Write-NRLog "Adapter restore warning for $($item.Name): $($_.Exception.Message)"
            }
        }
    }
    Write-NRLog "Backup restored: $Dir"
}

function Get-StatusReport {
    $ws = Get-SmbWorkstationState
    $svcNames = @('LanmanWorkstation','LanmanServer','FDResPub','fdPHost','SSDPSRV','upnphost','lmhosts')
    $services = foreach ($n in $svcNames) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s) { [pscustomobject]@{Name=$s.Name;Status=$s.Status;StartType=$s.StartType} }
    }

    $bindings = Get-NetAdapterBinding -ComponentID ms_msclient -ErrorAction SilentlyContinue |
        Select-Object Name,Enabled

    $firewall = @(
        Get-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction SilentlyContinue |
            Group-Object Enabled | ForEach-Object { "Network Discovery / $($_.Name): $($_.Count)" }
        Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue |
            Group-Object Enabled | ForEach-Object { "File and Printer Sharing / $($_.Name): $($_.Count)" }
    )

    $smb1 = $null
    try { $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop | Select-Object FeatureName,State } catch {}

    [pscustomobject]@{
        Generated = Get-Date
        ComputerName = $env:COMPUTERNAME
        OS = Get-OSInfo
        SMB = $ws
        Services = $services
        ClientBinding = $bindings
        Firewall = $firewall
        SMB1 = $smb1
    }
}

function Show-Status {
    Write-Host '--- SMB / NETWORK STATUS ---' -ForegroundColor Yellow
    $s = Get-SmbWorkstationState
    Write-Host ("RequireSecuritySignature : {0}" -f $s.RequireSecuritySignature)
    Write-Host ("EnableSecuritySignature  : {0}" -f $s.EnableSecuritySignature)
    Write-Host ("AllowInsecureGuestAuth   : {0}" -f $s.AllowInsecureGuestAuth)
    Write-Host ''

    Write-Host '--- CLIENT FOR MICROSOFT NETWORKS ---' -ForegroundColor Yellow
    $b = Get-NetAdapterBinding -ComponentID ms_msclient -ErrorAction SilentlyContinue
    if ($b) {
        foreach ($x in $b) { Write-Host ("{0,-25} Enabled={1}" -f $x.Name,$x.Enabled) }
    } else { Write-Host 'No bindings found.' -ForegroundColor DarkGray }
    Write-Host ''

    Write-Host '--- REQUIRED SERVICES ---' -ForegroundColor Yellow
    foreach ($n in @('LanmanWorkstation','LanmanServer','FDResPub','fdPHost','SSDPSRV','upnphost','lmhosts')) {
        $svc = Get-Service $n -ErrorAction SilentlyContinue
        if ($svc) {
            $color = if ($svc.Status -eq 'Running') {'Green'} else {'Yellow'}
            Write-Host ("{0,-18} {1,-10} StartType={2}" -f $n,$svc.Status,$svc.StartType) -ForegroundColor $color
        } else { Write-Host ("{0,-18} Not installed" -f $n) -ForegroundColor DarkGray }
    }
    Write-Host ''

    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        Write-Host ("SMB1Protocol: {0}" -f $f.State)
    } catch { Write-Host 'SMB1Protocol: Unable to query' -ForegroundColor DarkGray }
}

function Apply-CoreFixes {
    Write-Host ''
    Write-Host 'This action applies the three core compatibility changes from the original checklist:' -ForegroundColor Yellow
    Write-Host '  1) Disable Client for Microsoft Networks' -ForegroundColor Yellow
    Write-Host '  2) Enable insecure SMB guest authentication' -ForegroundColor Yellow
    Write-Host '  3) Disable SMB client signing requirements' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'WARNING: These changes can reduce network security.' -ForegroundColor Red
    if (-not (Confirm-NR 'Create a backup and continue?')) { return }
    $backup = Invoke-Step 'Create full backup' { New-FullBackup }
    if (-not $backup) { return }
    Write-Host "Backup: $backup" -ForegroundColor DarkGray

    Invoke-Step 'Disable Client for Microsoft Networks' { Disable-NRClientForMicrosoftNetworks }
    Invoke-Step 'Enable SMB insecure guest authentication' { Set-NRGuestAuth -Enabled $true }
    Invoke-Step 'Disable SMB client signing requirements' { Set-NRClientSigning -Enabled $false }
    Write-Host ''
    Write-Host 'Core fixes completed. A restart is recommended.' -ForegroundColor Green
}

function Enable-SMB1Menu {
    Write-Host 'SMB 1.0 / CIFS is a legacy protocol and is not recommended unless required.' -ForegroundColor Yellow
    if (-not (Confirm-NR 'Create backup and enable SMB1?')) { return }
    Invoke-Step 'Create full backup' { New-FullBackup } | Out-Null
    Invoke-Step 'Enable SMB1Protocol' { Enable-NRSMB1 }
    Write-Host 'A restart may be required.' -ForegroundColor Yellow
}

function Configure-SigningMenu {
    Write-Host 'Current client signing configuration:' -ForegroundColor Yellow
    $s = Get-SmbWorkstationState
    Write-Host ("RequireSecuritySignature={0}, EnableSecuritySignature={1}" -f $s.RequireSecuritySignature,$s.EnableSecuritySignature)
    Write-Host ''
    Write-Host '[1] Disable client signing requirements'
    Write-Host '[2] Restore client signing requirements'
    Write-Host '[0] Cancel'
    $c = Read-Host 'Select'
    if ($c -eq '0') { return }
    if (-not (Confirm-NR 'Create backup before changing SMB signing?')) { return }
    Invoke-Step 'Create full backup' { New-FullBackup } | Out-Null
    if ($c -eq '1') { Invoke-Step 'Disable SMB client signing requirements' { Set-NRClientSigning -Enabled $false } }
    elseif ($c -eq '2') { Invoke-Step 'Restore SMB client signing requirements' { Set-NRClientSigning -Enabled $true } }
}

function Configure-GuestMenu {
    $s = Get-SmbWorkstationState
    Write-Host ("Current AllowInsecureGuestAuth={0}" -f $s.AllowInsecureGuestAuth) -ForegroundColor Yellow
    Write-Host '[1] Enable insecure guest authentication'
    Write-Host '[2] Disable insecure guest authentication'
    Write-Host '[0] Cancel'
    $c = Read-Host 'Select'
    if ($c -eq '0') { return }
    if (-not (Confirm-NR 'Create backup before changing guest authentication?')) { return }
    Invoke-Step 'Create full backup' { New-FullBackup } | Out-Null
    if ($c -eq '1') { Invoke-Step 'Enable insecure guest authentication' { Set-NRGuestAuth -Enabled $true } }
    elseif ($c -eq '2') { Invoke-Step 'Disable insecure guest authentication' { Set-NRGuestAuth -Enabled $false } }
}

function Configure-ClientMenu {
    Write-Host '[1] Disable Client for Microsoft Networks on all adapters'
    Write-Host '[2] Enable Client for Microsoft Networks on all adapters'
    Write-Host '[0] Cancel'
    $c = Read-Host 'Select'
    if ($c -eq '0') { return }
    if (-not (Confirm-NR 'Create backup before changing adapter bindings?')) { return }
    Invoke-Step 'Create full backup' { New-FullBackup } | Out-Null
    if ($c -eq '1') { Invoke-Step 'Disable Client for Microsoft Networks' { Disable-NRClientForMicrosoftNetworks } }
    elseif ($c -eq '2') { Invoke-Step 'Enable Client for Microsoft Networks' { Enable-NRClientForMicrosoftNetworks } }
}

function Repair-NetworkServices {
    if (-not (Confirm-NR 'Create backup and repair discovery/sharing services?')) { return }
    Invoke-Step 'Create full backup' { New-FullBackup } | Out-Null
    Invoke-Step 'Configure core network services' { Set-NRRequiredServices }
    Invoke-Step 'Enable Network Discovery firewall rules' { Enable-NRNetworkDiscoveryFirewall }
    Invoke-Step 'Enable File and Printer Sharing firewall rules' { Enable-NRFileSharingFirewall }
}

function Generate-ReportFile {
    $report = Get-StatusReport
    $path = Join-Path $LogDir ("Report_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $path
    $txt = Join-Path $LogDir ("Report_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    @(
        'Windows Network Repair - Diagnostic Report'
        ('Generated: ' + (Get-Date))
        ('Computer: ' + $env:COMPUTERNAME)
        ('OS: ' + $report.OS.Caption)
        ('Build: ' + $report.OS.Build)
        ''
        'SMB:'
        ($report.SMB | Format-List | Out-String)
        'Services:'
        ($report.Services | Format-Table -AutoSize | Out-String)
        'Client Binding:'
        ($report.ClientBinding | Format-Table -AutoSize | Out-String)
        'Firewall:'
        ($report.Firewall -join "`r`n")
        'SMB1:'
        ($report.SMB1 | Format-List | Out-String)
    ) | Set-Content -Encoding UTF8 $txt
    Write-Host "JSON report: $path" -ForegroundColor Green
    Write-Host "Text report: $txt" -ForegroundColor Green
}

function Restore-LatestMenu {
    $b = Get-LatestBackup
    if (-not $b) { Write-Host 'No backups found.' -ForegroundColor Red; return }
    Write-Host "Latest backup: $($b.FullName)" -ForegroundColor Yellow
    if (-not (Confirm-NR 'Restore this backup?')) { return }
    Invoke-Step 'Restore latest backup' { Restore-Backup $b.FullName }
    Write-Host 'Restart is recommended after restore.' -ForegroundColor Yellow
}

function Undo-CoreMenu {
    if (-not (Confirm-NR 'Undo the three core compatibility changes?')) { return }
    if (-not (Confirm-NR 'Create a fresh backup before undo?')) { return }
    Invoke-Step 'Create safety backup' { New-FullBackup } | Out-Null
    Invoke-Step 'Enable Client for Microsoft Networks' { Enable-NRClientForMicrosoftNetworks }
    Invoke-Step 'Disable insecure SMB guest authentication' { Set-NRGuestAuth -Enabled $false }
    Invoke-Step 'Restore SMB client signing requirements' { Set-NRClientSigning -Enabled $true }
    Write-Host 'Undo complete. Restart is recommended.' -ForegroundColor Green
}

while ($true) {
    Show-Header
    Write-Host '[1] Check current configuration'
    Write-Host '[2] Apply the 3 core fixes (backup + verify)'
    Write-Host '[3] Enable SMB 1.0 / CIFS'
    Write-Host '[4] Configure SMB client signing'
    Write-Host '[5] Configure insecure guest authentication'
    Write-Host '[6] Configure Client for Microsoft Networks'
    Write-Host '[7] Repair Network Discovery / File Sharing services'
    Write-Host '[8] Backup current settings'
    Write-Host '[9] Restore latest backup'
    Write-Host '[10] Undo the 3 core fixes'
    Write-Host '[11] Generate diagnostic report'
    Write-Host '[0] Exit'
    Write-Host ''
    $choice = Read-Host 'Select an option'
    switch ($choice) {
        '1' { Show-Status; Pause-NR }
        '2' { Apply-CoreFixes; Pause-NR }
        '3' { Enable-SMB1Menu; Pause-NR }
        '4' { Configure-SigningMenu; Pause-NR }
        '5' { Configure-GuestMenu; Pause-NR }
        '6' { Configure-ClientMenu; Pause-NR }
        '7' { Repair-NetworkServices; Pause-NR }
        '8' { Invoke-Step 'Create full backup' { $p=New-FullBackup; Write-Host "Backup: $p" -ForegroundColor Green }; Pause-NR }
        '9' { Restore-LatestMenu; Pause-NR }
        '10' { Undo-CoreMenu; Pause-NR }
        '11' { Invoke-Step 'Generate diagnostic report' { Generate-ReportFile }; Pause-NR }
        '0' { break }
        default { Write-Host 'Invalid option.' -ForegroundColor Red; Start-Sleep -Milliseconds 700 }
    }
}
