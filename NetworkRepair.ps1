# Windows Network Repair Pro
# Focus: robust, capability-aware automation for the user's three main legacy SMB compatibility settings.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Import-Module (Join-Path $Root 'Modules\Console.psm1') -Force
Import-Module (Join-Path $Root 'Modules\System.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Logging.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Backup.psm1') -Force
Import-Module (Join-Path $Root 'Modules\ThreeFixes.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Diagnostics.psm1') -Force

$LogFile = Join-Path $Root ('Logs\NetworkRepair_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Initialize-RepairLog $LogFile

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OsCode {
    $envInfo = Get-WindowsEnvironment
    $v = [version]$envInfo.WindowsVersion
    if ($v.Major -eq 6 -and $v.Minor -eq 1) { return 'Windows 7' }
    if ($v.Major -eq 6 -and $v.Minor -eq 2) { return 'Windows 8' }
    if ($v.Major -eq 6 -and $v.Minor -eq 3) { return 'Windows 8.1' }
    if ($v.Major -eq 10 -and $envInfo.IsWindows11Likely) { return 'Windows 11' }
    if ($v.Major -eq 10) { return 'Windows 10' }
    return 'Unknown Windows'
}

function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host ' __        ___           _                 _   _      _                  ' -ForegroundColor Cyan
    Write-Host ' \ \      / (_)_ __   __| | _____      _| \ | | ___| |_ _      __        ' -ForegroundColor Cyan
    Write-Host '  \ \ /\ / /| | \_ \ / _` |/ _ \ \ /\ / /  \| |/ _ \ __| | /\ / /' -ForegroundColor Cyan
    Write-Host '   \ V  V / | | | | | (_| | (_) \ V  V /| |\  |  __/ |_| |/  V / ' -ForegroundColor Cyan
    Write-Host '    \_/\_/  |_|_| |_|\__,_|\___/ \_/\_/ |_| \_|\___|\__|_/\_/  ' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '        WINDOWS NETWORK REPAIR PRO  |  SMB / SHARING TOOL' -ForegroundColor DarkCyan
    Write-Host ('        Log: ' + $LogFile) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-EnvironmentSummary {
    $e = Get-WindowsEnvironment
    Write-Title 'SYSTEM / HARDWARE DETECTION'
    $rows = @(
        @('Computer', $e.ComputerName),
        @('Manufacturer', $e.Manufacturer),
        @('Model', $e.Model),
        @('CPU', $e.CPU),
        @('RAM', ($e.RAMGB.ToString() + ' GB')),
        @('Windows', (Get-OsCode + '  ' + $e.WindowsVersion + '  Build ' + $e.Build)),
        @('OS Architecture', $e.OSArchitecture),
        @('Process Architecture', $e.ProcessArchitecture),
        @('PowerShell', $e.PowerShell),
        @('BIOS', $e.BiosVersion)
    )
    foreach ($r in $rows) { Write-Host ("{0,-22}: {1}" -f $r[0],$r[1]) -ForegroundColor White }
    Write-RepairLog 'INFO' ('Environment: ' + ($rows | ForEach-Object { $_ -join '=' } -join '; '))
}

function Show-Adapters {
    Write-Title 'NETWORK ADAPTERS'
    $adapters = @(Get-NetworkAdaptersSafe)
    if ($adapters.Count -eq 0) { Write-Status FAIL 'No network adapters were detected.'; return }
    foreach ($a in $adapters) {
        Write-Host ("{0,-24} {1,-10} {2,-18} {3}" -f $a.Name,$a.Status,$a.MacAddress,$a.LinkSpeed) -ForegroundColor White
    }
}

function Show-MainSettings {
    $s = Get-ThreeMainSettings
    Write-Title 'THREE MAIN SETTINGS'
    $guest = if ($null -eq $s.AllowInsecureGuestAuth_Policy) { $s.AllowInsecureGuestAuth_Runtime } else { $s.AllowInsecureGuestAuth_Policy }
    if ($guest -eq 1) { Write-Status OK 'Guest authentication: ALLOWED (insecure guest logons permitted)' } else { Write-Status WARN 'Guest authentication: BLOCKED / not enabled' }
    if ($s.RequireSecuritySignature -eq 0) { Write-Status OK 'SMB client RequireSecuritySignature: 0 (not required)' } else { Write-Status WARN ('SMB client RequireSecuritySignature: ' + $s.RequireSecuritySignature) }
    if ($s.EnableSecuritySignature -eq 0) { Write-Status OK 'SMB1 EnableSecuritySignature: 0' } elseif ($null -eq $s.EnableSecuritySignature) { Write-Status INFO 'SMB1 EnableSecuritySignature: not configured' } else { Write-Status WARN ('SMB1 EnableSecuritySignature: ' + $s.EnableSecuritySignature) }
    $b = @($s.Binding)
    if ($b.Count -eq 0) { Write-Status SKIP 'Client for Microsoft Networks binding: native binding API unavailable / not detected' }
    else {
        foreach ($x in $b) {
            if ($x.Enabled) { Write-Status WARN ($x.Name + ': Client for Microsoft Networks ENABLED') }
            else { Write-Status OK ($x.Name + ': Client for Microsoft Networks DISABLED') }
        }
    }
    if ($s.PolicyRequireSecuritySignature -eq 1) { Write-Status WARN 'A policy key explicitly requires SMB signing; local changes may be overridden.' }
}

function Backup-BeforeChange {
    $bindings = @(Get-BindingSnapshot)
    try {
        $dir = New-RepairBackup -Root $Root -BindingSnapshot $bindings
        Write-Status OK ('Backup created: ' + $dir)
        Write-RepairLog 'INFO' ('Backup created: ' + $dir)
        return $dir
    } catch {
        Write-Status FAIL ('Backup failed: ' + $_.Exception.Message)
        Write-RepairLog 'ERROR' ('Backup failed: ' + $_.Exception.Message)
        return $null
    }
}

function Apply-MainFixes {
    Write-Title 'APPLY THREE MAIN SETTINGS'
    Write-Host 'These changes can reduce SMB security. They are intended for controlled/legacy-device scenarios.' -ForegroundColor Yellow
    Write-Host 'The tool will create a rollback snapshot before changing anything.' -ForegroundColor Yellow
    if (-not (Read-YesNo 'Continue?' $false)) { Write-Status INFO 'Operation cancelled.'; return }

    $backup = Backup-BeforeChange
    if (-not $backup) { Write-Status FAIL 'No changes were made because backup creation failed.'; return }

    $envInfo = Get-WindowsEnvironment
    $modernPolicy = $envInfo.IsWindows10Plus
    $total = 3
    $step = 0

    $step++; Write-Step $step $total 'Enable insecure guest authentication'
    try {
        Set-InsecureGuest -ModernPolicyKey:$modernPolicy
        $v = Get-ThreeMainSettings
        $effective = if ($null -ne $v.AllowInsecureGuestAuth_Policy) { $v.AllowInsecureGuestAuth_Policy } else { $v.AllowInsecureGuestAuth_Runtime }
        if ($effective -eq 1) { Write-Status OK 'AllowInsecureGuestAuth = 1 verified.'; Write-RepairLog 'OK' 'Guest authentication enabled.' }
        else { throw 'Verification failed: AllowInsecureGuestAuth is not 1.' }
    } catch {
        Write-Status FAIL $_.Exception.Message; Write-RepairLog 'ERROR' $_.Exception.Message
    }

    $step++; Write-Step $step $total 'Disable required SMB client signing'
    try {
        Disable-SmbClientSigning
        $v = Get-ThreeMainSettings
        if ($v.RequireSecuritySignature -eq 0) { Write-Status OK 'SMB client signing requirement = 0 verified.'; Write-RepairLog 'OK' 'SMB client signing requirement disabled.' }
        else { throw 'Verification failed: RequireSecuritySignature is not 0.' }
    } catch {
        Write-Status FAIL $_.Exception.Message; Write-RepairLog 'ERROR' $_.Exception.Message
    }

    $step++; Write-Step $step $total 'Disable Client for Microsoft Networks binding'
    try {
        $result = @(Disable-MsClientBinding)
        if ($result.Count -eq 0) { Write-Status SKIP 'No eligible binding was found.' }
        else { foreach ($r in $result) { Write-Status OK ($r.Adapter + ': ' + $r.Result) } }
        Write-RepairLog 'OK' ('Client binding result count: ' + $result.Count)
    } catch {
        Write-Status FAIL $_.Exception.Message; Write-RepairLog 'ERROR' $_.Exception.Message
        Write-Host 'On older Windows versions the native binding API may be unavailable; the tool deliberately avoids unsafe component uninstallation.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Status INFO 'Final verification:'
    Show-MainSettings
    Write-Status INFO 'A restart is recommended after registry/SMB configuration changes.'
}

function Restore-Latest {
    $dirs = @(Get-ChildItem (Join-Path $Root 'Backup') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -eq 0) { Write-Status FAIL 'No backup snapshots found.'; return }
    $latest = $dirs[0]
    Write-Title 'RESTORE LATEST SNAPSHOT'
    Write-Host ('Backup: ' + $latest.FullName) -ForegroundColor Yellow
    if (-not (Read-YesNo 'Restore this snapshot?' $false)) { return }
    foreach ($reg in @(Get-ChildItem $latest.FullName -Filter '*.reg' -File)) {
        & reg.exe import $reg.FullName | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Status OK ('Restored ' + $reg.Name) } else { Write-Status FAIL ('Failed ' + $reg.Name) }
    }
    $bf = Join-Path $latest.FullName 'bindings.json'
    if (Test-Path $bf) {
        try { Enable-MsClientBindingFromSnapshot @(Get-Content $bf -Raw | ConvertFrom-Json); Write-Status OK 'Adapter binding state restored.' } catch { Write-Status WARN ('Binding restore: ' + $_.Exception.Message) }
    }
    Write-Status INFO 'Restart Windows if the networking stack does not reflect the restored state immediately.'
}

function Enable-Smb1Optional {
    Write-Title 'SMB 1.0 / CIFS OPTIONAL FEATURE'
    Write-Host 'SMB1 is legacy and should only be enabled when a target device actually requires it.' -ForegroundColor Yellow
    if (-not (Read-YesNo 'Enable SMB1?' $false)) { return }
    $cmd = Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -All -NoRestart -ErrorAction Stop | Out-Null
            Write-Status OK 'SMB1 optional feature enabled. A restart may be required.'
        } catch { Write-Status FAIL $_.Exception.Message }
    } else {
        Write-Status SKIP 'Enable-WindowsOptionalFeature is unavailable on this system.'
    }
}

function Network-RepairExtras {
    Write-Title 'OPTIONAL NETWORK REPAIR'
    Write-Host '[1] Flush DNS cache' -ForegroundColor White
    Write-Host '[2] Reset Winsock' -ForegroundColor White
    Write-Host '[3] Reset TCP/IP stack' -ForegroundColor White
    Write-Host '[4] Enable Network Discovery + File Sharing firewall rules' -ForegroundColor White
    Write-Host '[5] Restart common discovery/sharing services' -ForegroundColor White
    Write-Host '[0] Back' -ForegroundColor White
    $c = Read-Host 'Select'
    switch ($c) {
        '1' { ipconfig.exe /flushdns | Out-Null; Write-Status OK 'DNS cache flushed.' }
        '2' { if (Read-YesNo 'Winsock reset will require a restart. Continue?' $false) { netsh.exe winsock reset; Write-Status OK 'Winsock reset requested.' } }
        '3' { if (Read-YesNo 'TCP/IP reset will require a restart. Continue?' $false) { netsh.exe int ip reset; Write-Status OK 'TCP/IP reset requested.' } }
        '4' {
            if (Get-Command Set-NetFirewallRule -ErrorAction SilentlyContinue) {
                try { Set-NetFirewallRule -DisplayGroup 'Network Discovery' -Enabled True -ErrorAction Stop; Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -ErrorAction Stop; Write-Status OK 'Firewall sharing/discovery rules enabled.' } catch { Write-Status FAIL $_.Exception.Message }
            } else { Write-Status SKIP 'NetSecurity firewall cmdlets are unavailable.' }
        }
        '5' {
            foreach ($name in @('FDResPub','FDPHost','SSDPSRV','upnphost','LanmanWorkstation','LanmanServer')) {
                try { $s = Get-Service -Name $name -ErrorAction Stop; if ($s.Status -ne 'Running') { Start-Service -Name $name -ErrorAction Stop }; Write-Status OK ($name + ' is running.') } catch { Write-Status WARN ($name + ': ' + $_.Exception.Message) }
            }
        }
    }
}

function Generate-Report {
    $reportDir = Join-Path $Root 'Logs'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $json = Join-Path $reportDir ('Report_' + $stamp + '.json')
    $txt = Join-Path $reportDir ('Report_' + $stamp + '.txt')
    $envInfo = Get-WindowsEnvironment
    $settings = Get-ThreeMainSettings
    $diag = Get-NetworkDiagnostics
    $adapters = @(Get-NetworkAdaptersSafe)
    [pscustomobject]@{Environment=$envInfo; MainSettings=$settings; Adapters=$adapters; Diagnostics=$diag; Generated=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content $json -Encoding UTF8
    @(
        'Windows Network Repair Pro - Diagnostic Report'
        ('Generated: ' + (Get-Date))
        ''
        'SYSTEM'
        ('Computer: ' + $envInfo.ComputerName)
        ('Manufacturer/Model: ' + $envInfo.Manufacturer + ' / ' + $envInfo.Model)
        ('CPU: ' + $envInfo.CPU)
        ('RAM: ' + $envInfo.RAMGB + ' GB')
        ('Windows: ' + (Get-OsCode) + ' ' + $envInfo.WindowsVersion + ' Build ' + $envInfo.Build)
        ('Architecture: ' + $envInfo.OSArchitecture)
        ('PowerShell: ' + $envInfo.PowerShell)
        ''
        'MAIN SETTINGS'
        ('AllowInsecureGuestAuth runtime: ' + $settings.AllowInsecureGuestAuth_Runtime)
        ('AllowInsecureGuestAuth policy: ' + $settings.AllowInsecureGuestAuth_Policy)
        ('RequireSecuritySignature: ' + $settings.RequireSecuritySignature)
        ('EnableSecuritySignature: ' + $settings.EnableSecuritySignature)
        ''
        'SERVICES'
    ) | Set-Content $txt -Encoding UTF8
    $diag.Services | Format-Table -AutoSize | Out-String | Add-Content $txt
    Write-Status OK ('JSON report: ' + $json)
    Write-Status OK ('TXT report : ' + $txt)
}

if (-not (Test-Administrator)) {
    Write-Status FAIL 'Administrator privileges are required.'
    Write-Host 'Run NetworkRepair.cmd as Administrator.' -ForegroundColor Yellow
    exit 1
}

Show-Banner
try {
    Show-EnvironmentSummary
} catch { Write-Status WARN ('Environment detection issue: ' + $_.Exception.Message) }

while ($true) {
    Write-Title 'MAIN MENU'
    Write-Host '[1] Full system + network diagnostics' -ForegroundColor White
    Write-Host '[2] Show the three main settings' -ForegroundColor White
    Write-Host '[3] Apply the three main settings (recommended workflow)' -ForegroundColor White
    Write-Host '[4] Enable SMB 1.0 / CIFS' -ForegroundColor White
    Write-Host '[5] Optional network repair tools' -ForegroundColor White
    Write-Host '[6] Backup current configuration' -ForegroundColor White
    Write-Host '[7] Restore latest backup' -ForegroundColor White
    Write-Host '[8] Generate diagnostic report' -ForegroundColor White
    Write-Host '[9] Show network adapters' -ForegroundColor White
    Write-Host '[0] Exit' -ForegroundColor White
    Write-Host ''
    $choice = Read-Host 'Select an option'
    try {
        switch ($choice) {
            '1' { Show-EnvironmentSummary; Show-Adapters; Show-MainSettings; $d=Get-NetworkDiagnostics; Write-Title 'SERVICES'; $d.Services | Format-Table -AutoSize }
            '2' { Show-MainSettings }
            '3' { Apply-MainFixes }
            '4' { Enable-Smb1Optional }
            '5' { Network-RepairExtras }
            '6' { [void](Backup-BeforeChange) }
            '7' { Restore-Latest }
            '8' { Generate-Report }
            '9' { Show-Adapters }
            '0' { Write-Status INFO 'Exiting.'; break }
            default { Write-Status WARN 'Invalid selection.' }
        }
    } catch { Write-Status FAIL ('Unhandled operation error: ' + $_.Exception.Message); Write-RepairLog 'ERROR' $_.Exception.ToString() }
    if ($choice -ne '0') { Read-Host 'Press Enter to continue' | Out-Null; Show-Banner }
}
