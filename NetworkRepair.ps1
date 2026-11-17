#requires -Version 3.0
# Windows Network Repair Pro 2.0.0
# Native PowerShell source entry point. Build/Build-Executable.ps1 bundles all modules into one EXE.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-AppRoot {
    if ($env:WNR_BUNDLED_EXE -eq '1') {
        return [AppDomain]::CurrentDomain.BaseDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar)
    }
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return Split-Path -Parent $PSCommandPath
    }
    return [AppDomain]::CurrentDomain.BaseDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar)
}

$Root = Get-AppRoot
$DataRoot = if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
    Join-Path $env:ProgramData 'WindowsNetworkRepairPro'
} else {
    Join-Path $Root 'Data'
}
try {
    foreach ($folder in @($DataRoot,(Join-Path $DataRoot 'Backup'),(Join-Path $DataRoot 'Logs'),(Join-Path $DataRoot 'Reports'))) {
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    }
} catch {
    $DataRoot = Join-Path $Root 'Data'
    foreach ($folder in @($DataRoot,(Join-Path $DataRoot 'Backup'),(Join-Path $DataRoot 'Logs'),(Join-Path $DataRoot 'Reports'))) {
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    }
}

# Source mode imports the maintainable modules. The build script replaces these lines with bundled module source.
Import-Module (Join-Path $Root 'Modules\Console.psm1') -Force
Import-Module (Join-Path $Root 'Modules\System.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Logging.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Backup.psm1') -Force
Import-Module (Join-Path $Root 'Modules\ThreeFixes.psm1') -Force
Import-Module (Join-Path $Root 'Modules\Diagnostics.psm1') -Force

$LogFile = Join-Path $DataRoot ('Logs\NetworkRepair_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Initialize-RepairLog -Path $LogFile

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-OsName {
    $e = Get-WindowsEnvironment
    $version = [version]$e.WindowsVersion
    if ($version.Major -eq 6 -and $version.Minor -eq 1) { return 'Windows 7' }
    if ($version.Major -eq 6 -and $version.Minor -eq 2) { return 'Windows 8' }
    if ($version.Major -eq 6 -and $version.Minor -eq 3) { return 'Windows 8.1' }
    if ($e.IsWindows11Likely) { return 'Windows 11' }
    if ($e.IsWindows10Plus) { return 'Windows 10 / newer build' }
    return $e.WindowsCaption
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
    Write-Host '      WINDOWS NETWORK REPAIR PRO  |  SMB COMPATIBILITY + LIVE AUDIT' -ForegroundColor DarkCyan
    Write-Host ('      Version 2.0.0  |  Log: ' + $LogFile) -ForegroundColor DarkGray
    Write-Host ('      Data: ' + $DataRoot) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-EnvironmentSummary {
    $e = Get-WindowsEnvironment
    Write-Title 'System / hardware detection'
    $rows = @(
        @('Computer', $e.ComputerName),
        @('Manufacturer', $e.Manufacturer),
        @('Model', $e.Model),
        @('CPU', $e.CPU),
        @('Logical processors', $e.LogicalProcessors),
        @('RAM', ($e.RAMGB.ToString() + ' GB')),
        @('Windows', (Get-OsName)),
        @('Version / build', ($e.WindowsVersion + ' / ' + $e.Build)),
        @('OS architecture', $e.OSArchitecture),
        @('Process architecture', $e.ProcessArchitecture),
        @('PowerShell', ($e.PowerShell + ' / ' + $e.PowerShellEdition)),
        @('BIOS', $e.BiosVersion)
    )
    foreach ($r in $rows) { Write-Host ("  {0,-23}: {1}" -f $r[0],$r[1]) -ForegroundColor White }
    $environmentSummary = (($rows | ForEach-Object { $_ -join '=' }) -join '; ')
    Write-RepairLog 'INFO' ('Environment detected: ' + $environmentSummary)
}

function Show-Adapters {
    Write-Title 'Network adapters'
    $adapters = @(Get-NetworkAdaptersSafe)
    if ($adapters.Count -eq 0) { Write-Status WARN 'No network adapters were detected by the available APIs.'; return }
    foreach ($a in $adapters) {
        Write-Host ("  {0,-22} {1,-14} {2,-18} {3}" -f $a.Name,$a.Status,$a.MacAddress,$a.LinkSpeed) -ForegroundColor White
        if ($a.IPv4Address) { Write-Host ('      IPv4: ' + $a.IPv4Address + '    Gateway: ' + $a.Gateway) -ForegroundColor DarkGray }
    }
}

function Get-GuestEffectiveValue {
    param([object]$Settings)
    if ($null -ne $Settings.AllowInsecureGuestAuth_Policy) { return [int]$Settings.AllowInsecureGuestAuth_Policy }
    if ($null -ne $Settings.GuestLogonsCmdlet) { return [int][bool]$Settings.GuestLogonsCmdlet }
    if ($null -ne $Settings.AllowInsecureGuestAuth_Runtime) { return [int]$Settings.AllowInsecureGuestAuth_Runtime }
    return $null
}

function Show-MainSettings {
    $s = Get-ThreeMainSettings
    Write-Title 'Three primary SMB compatibility settings'

    # Keep the display order identical to the primary option 3 execution order.
    if ($s.PolicyRequireSecuritySignature -eq 1) { Write-Status WARN '1/3  SMB client signing: REQUIRED BY POLICY' }
    elseif ($s.RequireSigningCmdlet -eq $true -or ($null -ne $s.RequireSecuritySignature -and $s.RequireSecuritySignature -eq 1)) { Write-Status WARN '1/3  SMB client signing: REQUIRED' }
    elseif ($s.RequireSigningCmdlet -eq $false -or ($null -ne $s.RequireSecuritySignature -and $s.RequireSecuritySignature -eq 0)) { Write-Status OK '1/3  SMB client signing: NOT REQUIRED' }
    else { Write-Status INFO '1/3  SMB client signing: NOT CONFIGURED / unavailable' }
    Write-Host ('       Registry RequireSecuritySignature: ' + $s.RequireSecuritySignature) -ForegroundColor DarkGray
    Write-Host ('       EnableSecuritySignature: ' + $s.EnableSecuritySignature + ' (negotiated/optional signing flag)') -ForegroundColor DarkGray

    $guest = Get-GuestEffectiveValue -Settings $s
    if ($guest -eq 1) { Write-Status OK '2/3  Insecure guest logons: ALLOWED (compatibility enabled)' }
    elseif ($guest -eq 0) { Write-Status WARN '2/3  Insecure guest logons: BLOCKED' }
    else { Write-Status INFO '2/3  Insecure guest logons: NOT CONFIGURED / unavailable' }
    if ($null -ne $s.AllowInsecureGuestAuth_Policy) { Write-Host ('       Policy value: ' + $s.AllowInsecureGuestAuth_Policy) -ForegroundColor DarkGray }
    if ($null -ne $s.AllowInsecureGuestAuth_Runtime) { Write-Host ('       Runtime value: ' + $s.AllowInsecureGuestAuth_Runtime) -ForegroundColor DarkGray }

    $bindings = @($s.Binding)
    if ($bindings.Count -eq 0) { Write-Status SKIP '3/3  Client for Microsoft Networks binding: API unavailable or no binding detected' }
    else {
        $enabledCount = @($bindings | Where-Object { $_.Enabled }).Count
        if ($enabledCount -eq 0) { Write-Status OK '3/3  Client for Microsoft Networks binding: DISABLED on all detected adapters' }
        else { Write-Status WARN ("3/3  Client for Microsoft Networks binding: ENABLED on {0} adapter(s)" -f $enabledCount) }
        foreach ($b in $bindings) {
            $state = if ($b.Enabled) { 'ENABLED' } else { 'DISABLED' }
            Write-Host ("       {0}: {1}" -f $b.Name,$state) -ForegroundColor DarkGray
        }
    }
}

function Get-NetworkStateSnapshot {
    $envInfo = Get-WindowsEnvironment
    $settings = Get-ThreeMainSettings
    $diagnostics = Get-NetworkDiagnostics
    $adapters = @(Get-NetworkAdaptersSafe)
    $connectivity = Get-NetworkConnectivity
    [pscustomobject]@{
        SchemaVersion = 2
        CapturedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        Environment = $envInfo
        MainSettings = $settings
        Adapters = $adapters
        Services = @($diagnostics.Services)
        Firewall = @($diagnostics.Firewall)
        Connectivity = $connectivity
    }
}

function Convert-SnapshotToMap {
    param([Parameter(Mandatory=$true)][object]$Snapshot)
    $map = [ordered]@{}
    if ($Snapshot.Environment) {
        $map['System.Windows'] = [string]$Snapshot.Environment.WindowsCaption
        $map['System.Build'] = [string]$Snapshot.Environment.Build
        $map['System.Architecture'] = [string]$Snapshot.Environment.OSArchitecture
        $map['System.RAM_GB'] = [string]$Snapshot.Environment.RAMGB
        $map['System.CPU'] = [string]$Snapshot.Environment.CPU
    }
    if ($Snapshot.MainSettings) {
        foreach ($key in @('AllowInsecureGuestAuth_Runtime','AllowInsecureGuestAuth_Policy','GuestLogonsCmdlet','RequireSecuritySignature','EnableSecuritySignature','PolicyRequireSecuritySignature','RequireSigningCmdlet')) {
            $value = $Snapshot.MainSettings.$key
            $map['SMB.' + $key] = if ($null -eq $value) { '<not configured>' } else { [string]$value }
        }
        foreach ($b in @($Snapshot.MainSettings.Binding)) {
            $map['Binding.' + $b.Name] = [string][bool]$b.Enabled
        }
    }
    foreach ($a in @($Snapshot.Adapters)) {
        $prefix = 'Adapter.' + $a.Name + '.'
        $map[$prefix + 'Status'] = [string]$a.Status
        $map[$prefix + 'IPv4'] = [string]$a.IPv4Address
        $map[$prefix + 'Gateway'] = [string]$a.Gateway
    }
    foreach ($s in @($Snapshot.Services)) {
        $map['Service.' + $s.Name] = [string]$s.Status + ' / ' + [string]$s.StartType
    }
    foreach ($f in @($Snapshot.Firewall)) {
        $map['Firewall.' + $f.Group] = if ($null -eq $f.EnabledRules) { '<unavailable>' } else { [string]$f.EnabledRules + ' enabled rule(s)' }
    }
    if ($Snapshot.Connectivity) {
        $map['Network.DefaultGateways'] = (@($Snapshot.Connectivity.DefaultGateways) -join ', ')
        $map['Network.DnsServers'] = (@($Snapshot.Connectivity.DnsServers) -join ', ')
        $map['Network.GatewayICMPReply'] = if ($null -eq $Snapshot.Connectivity.GatewayReachable) { '<not detected>' } else { [string]$Snapshot.Connectivity.GatewayReachable }
        $map['Network.ConfiguredDnsResolution'] = if ($null -eq $Snapshot.Connectivity.PublicDnsResolution) { '<not tested>' } else { [string]$Snapshot.Connectivity.PublicDnsResolution }
    }
    return ,$map
}

function Compare-NetworkSnapshots {
    param([Parameter(Mandatory=$true)][object]$Before,[Parameter(Mandatory=$true)][object]$After)
    $left = Convert-SnapshotToMap -Snapshot $Before
    $right = Convert-SnapshotToMap -Snapshot $After
    $keys = @($left.Keys + $right.Keys | Sort-Object -Unique)
    $changes = @()
    foreach ($key in $keys) {
        $leftHas = $left.Contains($key)
        $rightHas = $right.Contains($key)
        $oldValue = if ($leftHas) { [string]$left[$key] } else { '<not present>' }
        $newValue = if ($rightHas) { [string]$right[$key] } else { '<not present>' }
        $state = if (-not $leftHas) { 'Added' } elseif (-not $rightHas) { 'Removed' } elseif ($oldValue -ne $newValue) { 'Changed' } else { 'Unchanged' }
        $changes += [pscustomobject]@{ Key=$key; Before=$oldValue; After=$newValue; State=$state }
    }
    return @($changes)
}

function Show-SnapshotChanges {
    param([object[]]$Changes,[switch]$OnlyChanged)
    $selected = if ($OnlyChanged) { @($Changes | Where-Object { $_.State -ne 'Unchanged' }) } else { @($Changes) }
    if ($selected.Count -eq 0) { Write-Status INFO 'No differences detected in the captured fields.'; return }
    foreach ($c in $selected) {
        $color = if ($c.State -eq 'Changed' -or $c.State -eq 'Added' -or $c.State -eq 'Removed') { 'Yellow' } else { 'DarkGray' }
        Write-Host ("  {0,-10} {1}" -f ('[' + $c.State + ']'),$c.Key) -ForegroundColor $color
        if ($c.State -ne 'Unchanged') {
            Write-Host ('       Before: ' + $c.Before) -ForegroundColor DarkGray
            Write-Host ('       After : ' + $c.After) -ForegroundColor Gray
        }
    }
}

function Save-JsonReport {
    param([Parameter(Mandatory=$true)][object]$Object,[Parameter(Mandatory=$true)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    ConvertTo-Json -InputObject $Object -Depth 14 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Backup-BeforeChange {
    try {
        $bindings = @(Get-BindingSnapshot)
        $dir = New-RepairBackup -Root $DataRoot -BindingSnapshot $bindings
        Write-Status OK ('Verified rollback snapshot created: ' + $dir)
        Write-RepairLog 'INFO' ('Backup created: ' + $dir)
        return $dir
    } catch {
        Write-Status FAIL ('Backup failed: ' + $_.Exception.Message)
        Write-RepairLog 'ERROR' ('Backup failed: ' + $_.Exception.ToString())
        return $null
    }
}

function Start-LiveMonitor {
    param([int]$DurationSeconds=10,[int]$IntervalSeconds=2,[switch]$Quiet)
    $samples = @()
    $started = Get-Date
    $end = $started.AddSeconds($DurationSeconds)
    $nextSampleAt = $started
    $index = 0
    while ((Get-Date) -lt $end) {
        $now = Get-Date
        if ($now -lt $nextSampleAt) {
            $wait = ($nextSampleAt - $now).TotalMilliseconds
            if ($wait -gt 0) { Start-Sleep -Milliseconds ([int][math]::Min($wait,1000)) }
            continue
        }
        $index++
        try {
            $sample = Get-NetworkStateSnapshot
            $samples += $sample
            if (-not $Quiet) {
                $guest = Get-GuestEffectiveValue -Settings $sample.MainSettings
                $guestText = if ($null -eq $guest) { 'n/a' } else { [string]$guest }
                $signText = if ($null -eq $sample.MainSettings.RequireSecuritySignature) { 'n/a' } else { [string]$sample.MainSettings.RequireSecuritySignature }
                $enabledBindings = @($sample.MainSettings.Binding | Where-Object { $_.Enabled }).Count
                $gatewayText = if ($null -eq $sample.Connectivity.GatewayReachable) { 'n/a' } elseif ($sample.Connectivity.GatewayReachable) { 'ICMP reply' } else { 'no ICMP reply' }
                $dnsText = if ($null -eq $sample.Connectivity.PublicDnsResolution) { 'n/a' } elseif ($sample.Connectivity.PublicDnsResolution) { 'resolved' } else { 'failed' }
                Write-Status LIVE ("Sample {0}: guest={1} | signing-required={2} | enabled bindings={3} | gateway ICMP={4} | DNS={5} | {6}" -f $index,$guestText,$signText,$enabledBindings,$gatewayText,$dnsText,(Get-Date -Format 'HH:mm:ss'))
            }
        } catch {
            Write-Status WARN ('Monitor sample failed: ' + $_.Exception.Message)
            Write-RepairLog 'WARN' ('Monitor sample failed: ' + $_.Exception.Message)
        }
        $nextSampleAt = $nextSampleAt.AddSeconds($IntervalSeconds)
        # If a network probe took longer than the interval, start the next sample immediately;
        # do not create a backlog of delayed samples.
        if ($nextSampleAt -lt (Get-Date)) { $nextSampleAt = Get-Date }
    }
    try { $samples += (Get-NetworkStateSnapshot) } catch { Write-Status WARN ('Final monitor sample failed: ' + $_.Exception.Message) }
    return $samples
}

function Get-ActionVerification {
    param([ValidateSet('Guest','Signing','Binding')][string]$Kind)
    $s = Get-ThreeMainSettings
    switch ($Kind) {
        'Guest' {
            $effective = Get-GuestEffectiveValue -Settings $s
            if ($effective -eq 1) { return [pscustomobject]@{ Verified=$true; State='OK'; Details='Insecure guest logons are allowed by the effective value.' } }
            return [pscustomobject]@{ Verified=$false; State='FAIL'; Details=('Effective guest value is ' + $effective + '.') }
        }
        'Signing' {
            if ($s.PolicyRequireSecuritySignature -eq 1) { return [pscustomobject]@{ Verified=$false; State='FAIL'; Details='An explicit policy still requires SMB signing.' } }
            if ($s.RequireSigningCmdlet -eq $true) { return [pscustomobject]@{ Verified=$false; State='FAIL'; Details='The Windows SMB client configuration still requires signing.' } }
            if ($null -ne $s.RequireSecuritySignature -and $s.RequireSecuritySignature -ne 0) { return [pscustomobject]@{ Verified=$false; State='FAIL'; Details='The registry still requires SMB client signing.' } }
            if ($null -ne $s.EnableSecuritySignature -and $s.EnableSecuritySignature -ne 0) { return [pscustomobject]@{ Verified=$false; State='FAIL'; Details='The optional SMB client signing registry flag is still enabled.' } }
            if ($s.RequireSigningCmdlet -eq $false -or $s.RequireSecuritySignature -eq 0) {
                return [pscustomobject]@{ Verified=$true; State='OK'; Details='SMB client signing requirement is disabled and the available registry flags were checked.' }
            }
            return [pscustomobject]@{ Verified=$false; State='FAIL'; Details='The SMB signing state could not be verified through either the Windows cmdlet or registry.' }
        }
        'Binding' {
            $bindings = @(Get-BindingSnapshot)
            if ($bindings.Count -eq 0) { return [pscustomobject]@{ Verified=$null; State='SKIP'; Details='No supported adapter binding was detected.' } }
            $enabled = @($bindings | Where-Object { $_.Enabled })
            if ($enabled.Count -eq 0) { return [pscustomobject]@{ Verified=$true; State='OK'; Details=('All ' + $bindings.Count + ' detected binding(s) are disabled.') } }
            return [pscustomobject]@{ Verified=$false; State='FAIL'; Details=($enabled.Count.ToString() + ' adapter binding(s) remain enabled.') }
        }
    }
}

function Invoke-OneMainFix {
    param([string]$Name,[ValidateSet('Guest','Signing','Binding')][string]$Kind,[scriptblock]$Action)
    $startedAt = (Get-Date).ToString('o')
    $result = 'FAIL'
    $details = ''
    try {
        & $Action
        $verification = Get-ActionVerification -Kind $Kind
        $result = $verification.State
        $details = $verification.Details
        if ($verification.Verified -eq $false) { throw $verification.Details }
    } catch {
        $details = $_.Exception.Message
        if ($Kind -eq 'Binding' -and $details -like 'UNSUPPORTED_API:*') {
            $result = 'SKIP'
            $details = $details -replace '^UNSUPPORTED_API:\s*',''
        } else {
            $result = 'FAIL'
        }
    }
    $completedAt = (Get-Date).ToString('o')
    if ($result -eq 'OK') { Write-Status OK ($Name + ' — verified: ' + $details); Write-RepairLog 'OK' ($Name + ': ' + $details) }
    elseif ($result -eq 'SKIP') { Write-Status SKIP ($Name + ' — ' + $details); Write-RepairLog 'SKIP' ($Name + ': ' + $details) }
    else { Write-Status FAIL ($Name + ' — ' + $details); Write-RepairLog 'ERROR' ($Name + ': ' + $details) }
    return [pscustomobject]@{ Name=$Name; Kind=$Kind; Result=$result; Details=$details; StartedAt=$startedAt; CompletedAt=$completedAt }
}

function Apply-MainFixes {
    Write-Title 'Option 3 — primary SMB compatibility workflow'
    Write-Host 'This workflow performs a real pre-check, a rollback backup, three controlled changes,' -ForegroundColor White
    Write-Host 'post-change verification, live sampling and a before/after JSON report.' -ForegroundColor White
    Write-Host ''
    Write-Status WARN 'Security impact: guest authentication is unauthenticated; SMB signing is reduced; disabling the client binding can interrupt access to network shares.'
    Write-Host 'Use only for a trusted legacy device/network. Do not apply on public or untrusted networks.' -ForegroundColor Yellow
    Write-Host 'A restart or reconnect may be required before every application observes the new state.' -ForegroundColor Yellow
    Write-Host ''

    $before = Get-NetworkStateSnapshot
    Write-Status INFO ('Pre-change snapshot captured: ' + $before.CapturedAt)
    Write-Host 'Current state:' -ForegroundColor Cyan
    Show-MainSettings
    Write-Host ''

    $blockers = @()
    if ($before.MainSettings.AllowInsecureGuestAuth_Policy -eq 0) {
        $blockers += 'A policy explicitly blocks insecure SMB guest logons.'
    }
    if ($before.MainSettings.PolicyRequireSecuritySignature -eq 1) {
        $blockers += 'A policy explicitly requires SMB client signing.'
    }
    if ($blockers.Count -gt 0) {
        foreach ($blocker in $blockers) { Write-Status FAIL $blocker }
        Write-Status WARN 'No registry values or adapter bindings were changed. Review the Group Policy with the system administrator, then run diagnostics again.'
        Write-RepairLog 'WARN' ('Option 3 preflight blocked: ' + ($blockers -join ' | '))
        return
    }

    $ack = Read-Host 'Type APPLY to create a backup and run option 3 (anything else cancels)'
    if ($ack -cne 'APPLY') { Write-Status INFO 'Operation cancelled. No changes were made.'; return }

    $backup = Backup-BeforeChange
    if (-not $backup) { Write-Status FAIL 'Stopped safely because a complete rollback snapshot could not be created.'; return }

    $actions = @()
    # Disable required signing first: insecure guest sessions do not support SMB signing.
    $signingAction = Invoke-OneMainFix -Name '1/3 Disable required SMB client signing (guest compatibility prerequisite)' -Kind Signing -Action { Disable-SmbClientSigning }
    $actions += $signingAction
    if ($signingAction.Result -ne 'OK') {
        $skipTime = (Get-Date).ToString('o')
        $actions += [pscustomobject]@{ Name='2/3 Enable insecure guest authentication'; Kind='Guest'; Result='SKIP'; Details='Skipped because the SMB signing prerequisite was not verified.'; StartedAt=$skipTime; CompletedAt=$skipTime }
        $actions += [pscustomobject]@{ Name='3/3 Disable Client for Microsoft Networks binding'; Kind='Binding'; Result='SKIP'; Details='Skipped because an earlier prerequisite failed; no adapter bindings were changed.'; StartedAt=$skipTime; CompletedAt=$skipTime }
        Write-Status WARN 'Remaining changes were skipped because the signing prerequisite failed.'
    } else {
        $guestAction = Invoke-OneMainFix -Name '2/3 Enable insecure guest authentication' -Kind Guest -Action { Set-InsecureGuest }
        $actions += $guestAction
        if ($guestAction.Result -ne 'OK') {
            $skipTime = (Get-Date).ToString('o')
            $actions += [pscustomobject]@{ Name='3/3 Disable Client for Microsoft Networks binding'; Kind='Binding'; Result='SKIP'; Details='Skipped because guest authentication could not be verified; no adapter bindings were changed.'; StartedAt=$skipTime; CompletedAt=$skipTime }
            Write-Status WARN 'Adapter binding change was skipped because guest authentication did not verify successfully.'
        } else {
            $actions += Invoke-OneMainFix -Name '3/3 Disable Client for Microsoft Networks binding' -Kind Binding -Action { [void](Disable-MsClientBinding) }
        }
    }

    Write-Title 'Live post-change monitoring'
    Write-Host 'Sampling the actual Windows configuration on a 2-second cadence...' -ForegroundColor DarkGray
    $samples = @(Start-LiveMonitor -DurationSeconds 10 -IntervalSeconds 2)
    $after = Get-NetworkStateSnapshot
    $changes = @(Compare-NetworkSnapshots -Before $before -After $after)
    $changed = @($changes | Where-Object { $_.State -ne 'Unchanged' })
    $reportStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $reportPath = Join-Path $DataRoot ('Reports\ApplyReport_' + $reportStamp + '.json')
    $report = [pscustomobject]@{
        ReportType = 'ApplyReport'
        SchemaVersion = 2
        Application = 'Windows Network Repair Pro'
        Version = '2.0.0'
        GeneratedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        BackupPath = $backup
        Before = $before
        After = $after
        Changes = $changes
        Actions = $actions
        MonitorSamples = $samples
        Summary = [pscustomobject]@{
            ChangedFields = $changed.Count
            VerifiedActions = @($actions | Where-Object { $_.Result -eq 'OK' }).Count
            FailedActions = @($actions | Where-Object { $_.Result -eq 'FAIL' }).Count
            SkippedActions = @($actions | Where-Object { $_.Result -eq 'SKIP' }).Count
            MonitorSampleCount = $samples.Count
        }
        SecurityNotice = 'Compatibility changes may reduce SMB security. Apply only when required for a trusted legacy endpoint.'
    }
    Save-JsonReport -Object $report -Path $reportPath | Out-Null
    Write-RepairLog 'INFO' ('Option 3 report saved: ' + $reportPath)

    Write-Title 'Before / after verification'
    Show-SnapshotChanges -Changes $changes -OnlyChanged
    Write-Host ''
    Write-Status INFO ("Actions verified: {0} | failed: {1} | skipped: {2}" -f $report.Summary.VerifiedActions,$report.Summary.FailedActions,$report.Summary.SkippedActions)
    Write-Status OK ('Real monitoring report saved: ' + $reportPath)
    Write-Status INFO ('Rollback backup: ' + $backup)
    Write-Host 'Import this JSON report into the GitHub Pages dashboard to explore the before/after timeline.' -ForegroundColor Cyan
    if ($report.Summary.FailedActions -gt 0) { Write-Status WARN 'One or more settings could not be applied. Review the action details and log before troubleshooting further.' }
    elseif ($report.Summary.SkippedActions -gt 0) { Write-Status WARN 'The workflow completed with one or more skipped steps. Review the API availability and action details.' }
    else { Write-Status OK 'All three option 3 actions were verified. Review the final state before reconnecting to a network share.' }
    Write-Status WARN 'A Windows restart or network adapter reconnect may be necessary.'
}

function Restore-BackupFolder {
    param([Parameter(Mandatory=$true)][string]$BackupPath)
    $manifestPath = Join-Path $BackupPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Backup manifest is missing. This folder is not a recognized snapshot.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $restored = 0
    $hasRegistryManifest = $manifest.PSObject.Properties.Name -contains 'Registry'
    if (-not $hasRegistryManifest) {
        # Backward compatibility with v1 snapshots: the old manifest only listed metadata
        # and the snapshot consisted of one or more exported .reg files.
        foreach ($legacyReg in @(Get-ChildItem -LiteralPath $BackupPath -Filter '*.reg' -File -ErrorAction SilentlyContinue)) {
            & reg.exe import $legacyReg.FullName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('Legacy registry import failed: ' + $legacyReg.Name) }
            $restored++
        }
    }
    foreach ($entry in @($manifest.Registry)) {
        $regFile = if ($entry.ExportFile) { Join-Path $BackupPath $entry.ExportFile } else { $null }
        if ($entry.Existed) {
            if (-not $regFile -or -not (Test-Path -LiteralPath $regFile)) { throw ('The snapshot is incomplete: registry export is missing for ' + $entry.Key) }
            & reg.exe import $regFile | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('Registry import failed: ' + $entry.Key) }
            $restored++
        } elseif (-not $entry.Existed) {
            $providerPath = $entry.Key -replace '^HKLM\\','HKLM:\'
            if (Test-Path -LiteralPath $providerPath) { Remove-Item -LiteralPath $providerPath -Recurse -Force -ErrorAction Stop }
            $restored++
        }
    }
    foreach ($entry in @($manifest.RegistryValues)) {
        if ($null -eq $entry.Path -or $null -eq $entry.Name) { throw 'The backup contains an invalid registry-value record.' }
        if ($entry.Existed) {
            if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
            $key = Get-Item -LiteralPath $entry.Path -ErrorAction Stop
            $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$entry.Kind)
            $restoreValue = $entry.Value
            switch ([string]$entry.Kind) {
                'DWord' { $restoreValue = [int]$entry.Value }
                'QWord' { $restoreValue = [long]$entry.Value }
                'String' { $restoreValue = [string]$entry.Value }
                'ExpandString' { $restoreValue = [string]$entry.Value }
                'MultiString' { $restoreValue = [string[]]@($entry.Value) }
                'Binary' { $restoreValue = [byte[]]@($entry.Value) }
                'None' { $restoreValue = [byte[]]@($entry.Value) }
                default { throw ('Unsupported registry value type in backup: ' + $entry.Kind) }
            }
            $key.SetValue([string]$entry.Name,$restoreValue,$kind)
        } elseif (Test-Path -LiteralPath $entry.Path) {
            $key = Get-Item -LiteralPath $entry.Path -ErrorAction Stop
            if (@($key.GetValueNames()) -contains [string]$entry.Name) { $key.DeleteValue([string]$entry.Name,$false) }
        }
        $restored++
    }
    $bindingFile = Join-Path $BackupPath 'bindings.json'
    $bindingResults = @()
    if (Test-Path -LiteralPath $bindingFile) {
        $bindings = @(Get-Content -LiteralPath $bindingFile -Raw | ConvertFrom-Json)
        $bindingResults = @(Enable-MsClientBindingFromSnapshot -Snapshot $bindings)
    }
    [pscustomobject]@{ RegistryItemsRestored=$restored; Bindings=$bindingResults }
}

function Restore-Latest {
    $backupRoots = @((Join-Path $DataRoot 'Backup'),(Join-Path $Root 'Backup')) | Select-Object -Unique
    $dirs = @()
    foreach ($backupRoot in $backupRoots) {
        if (Test-Path -LiteralPath $backupRoot) {
            $dirs += @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'Backup_*' -ErrorAction SilentlyContinue)
        }
    }
    $dirs = @($dirs | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -eq 0) { Write-Status WARN 'No backup snapshots were found.'; return }
    Write-Title 'Restore a backup snapshot'
    for ($i=0; $i -lt $dirs.Count; $i++) {
        $manifest = Join-Path $dirs[$i].FullName 'manifest.json'
        $created = if (Test-Path -LiteralPath $manifest) { try { (Get-Content $manifest -Raw | ConvertFrom-Json).Created } catch { 'Unknown date' } } else { 'Unknown date' }
        Write-Host ("  [{0}] {1}   {2}" -f ($i+1),$dirs[$i].Name,$created) -ForegroundColor White
    }
    $pick = Read-Host 'Select backup number (0 = cancel)'
    if ($pick -eq '0') { return }
    $index = 0
    if (-not [int]::TryParse($pick,[ref]$index) -or $index -lt 1 -or $index -gt $dirs.Count) { Write-Status WARN 'Invalid backup selection.'; return }
    $selected = $dirs[$index-1]
    Write-Status WARN ('This will restore the selected snapshot: ' + $selected.Name)
    if (-not (Read-YesNo 'Continue with restore?' $false)) { return }
    try {
        $result = Restore-BackupFolder -BackupPath $selected.FullName
        Write-Status OK ('Registry items restored: ' + $result.RegistryItemsRestored)
        foreach ($b in @($result.Bindings)) {
            if ($b.Restored) { Write-Status OK ('Binding restored: ' + $b.Adapter) }
            else { Write-Status WARN ('Binding restore failed: ' + $b.Adapter + ' — ' + $b.Error) }
        }
        Write-Status INFO 'Reconnect the network adapter or restart Windows if settings do not take effect immediately.'
    } catch { Write-Status FAIL ('Restore failed: ' + $_.Exception.Message); Write-RepairLog 'ERROR' ('Restore failed: ' + $_.Exception.ToString()) }
}

function Enable-Smb1Optional {
    Write-Title 'SMB 1.0 / CIFS optional feature'
    Write-Status WARN 'SMB1 is obsolete and vulnerable. Enable it only when a legacy device explicitly requires it.'
    if (-not (Read-YesNo 'Enable the Windows SMB1 optional feature?' $false)) { return }
    $cmd = Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Status SKIP 'Enable-WindowsOptionalFeature is unavailable on this Windows edition.'; return }
    try {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -All -NoRestart -ErrorAction Stop
        Write-Status OK ('SMB1 feature state: ' + $result.State)
        Write-Status WARN 'Restart may be required. Disable SMB1 again after the compatibility need ends.'
        Write-RepairLog 'WARN' 'SMB1 optional feature enable requested.'
    } catch { Write-Status FAIL $_.Exception.Message; Write-RepairLog 'ERROR' $_.Exception.ToString() }
}

function Network-RepairExtras {
    Write-Title 'Optional network repair tools'
    Write-Host '[1] Flush DNS resolver cache' -ForegroundColor White
    Write-Host '[2] Reset Winsock catalog (restart required)' -ForegroundColor White
    Write-Host '[3] Reset TCP/IP stack (restart required)' -ForegroundColor White
    Write-Host '[4] Enable Network Discovery + File and Printer Sharing firewall rules' -ForegroundColor White
    Write-Host '[5] Start common discovery / sharing services' -ForegroundColor White
    Write-Host '[0] Back' -ForegroundColor White
    $c = Read-Host 'Select a tool'
    switch ($c) {
        '1' {
            & ipconfig.exe /flushdns
            if ($LASTEXITCODE -eq 0) { Write-Status OK 'DNS cache flushed.' } else { Write-Status WARN 'ipconfig returned a non-zero exit code.' }
        }
        '2' {
            if (Read-YesNo 'Winsock reset changes the network catalog and requires a restart. Continue?' $false) {
                & netsh.exe winsock reset
                if ($LASTEXITCODE -eq 0) { Write-Status OK 'Winsock reset requested. Restart Windows.' } else { Write-Status FAIL 'Winsock reset failed.' }
            }
        }
        '3' {
            if (Read-YesNo 'TCP/IP reset can affect static network settings and requires a restart. Continue?' $false) {
                & netsh.exe int ip reset
                if ($LASTEXITCODE -eq 0) { Write-Status OK 'TCP/IP reset requested. Restart Windows and re-check static IP settings.' } else { Write-Status FAIL 'TCP/IP reset failed.' }
            }
        }
        '4' {
            if (Get-Command Set-NetFirewallRule -ErrorAction SilentlyContinue) {
                if (Read-YesNo 'Enable the two Windows firewall rule groups?' $false) {
                    try {
                        Set-NetFirewallRule -DisplayGroup 'Network Discovery' -Enabled True -ErrorAction Stop
                        Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -ErrorAction Stop
                        Write-Status OK 'Network Discovery and File/Printer Sharing firewall rules enabled.'
                    } catch { Write-Status WARN ('Firewall rules could not all be enabled. On localized Windows, rule group names may differ. ' + $_.Exception.Message) }
                }
            } else { Write-Status SKIP 'NetSecurity firewall cmdlets are unavailable.' }
        }
        '5' {
            foreach ($name in @('FDResPub','FDPHost','SSDPSRV','upnphost','LanmanWorkstation','LanmanServer')) {
                try {
                    $service = Get-Service -Name $name -ErrorAction Stop
                    if ($service.Status -ne 'Running') { Start-Service -Name $name -ErrorAction Stop }
                    Write-Status OK ($name + ' is running.')
                } catch { Write-Status WARN ($name + ': ' + $_.Exception.Message) }
            }
        }
        '0' { return }
        default { Write-Status WARN 'Unknown tool selection.' }
    }
}

function Invoke-StandaloneMonitor {
    Write-Title 'Live system / network monitor'
    $duration = Read-ValidatedInt -Prompt 'Monitor duration in seconds (10-300)' -Default 30 -Minimum 10 -Maximum 300
    $interval = Read-ValidatedInt -Prompt 'Sampling interval in seconds (1-10)' -Default 2 -Minimum 1 -Maximum 10
    $before = Get-NetworkStateSnapshot
    Write-Status LIVE ('Monitoring started at ' + $before.CapturedAt)
    $samples = @(Start-LiveMonitor -DurationSeconds $duration -IntervalSeconds $interval)
    $after = Get-NetworkStateSnapshot
    $changes = @(Compare-NetworkSnapshots -Before $before -After $after)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $path = Join-Path $DataRoot ('Reports\MonitorReport_' + $stamp + '.json')
    $report = [pscustomobject]@{
        ReportType='MonitorReport'; SchemaVersion=2; Application='Windows Network Repair Pro'; Version='2.0.0'
        GeneratedAt=(Get-Date).ToString('o'); ComputerName=$env:COMPUTERNAME
        DurationSeconds=$duration; IntervalSeconds=$interval
        Before=$before; After=$after; Changes=$changes; MonitorSamples=$samples
        Summary=[pscustomobject]@{ SampleCount=$samples.Count; ChangedFields=@($changes | Where-Object { $_.State -ne 'Unchanged' }).Count }
    }
    Save-JsonReport -Object $report -Path $path | Out-Null
    Write-Status OK ('Monitor report saved: ' + $path)
    Show-SnapshotChanges -Changes $changes -OnlyChanged
}

function Generate-Report {
    $snapshot = Get-NetworkStateSnapshot
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $json = Join-Path $DataRoot ('Reports\DiagnosticReport_' + $stamp + '.json')
    $txt = Join-Path $DataRoot ('Reports\DiagnosticReport_' + $stamp + '.txt')
    Save-JsonReport -Object ([pscustomobject]@{ ReportType='DiagnosticReport'; SchemaVersion=2; Application='Windows Network Repair Pro'; Version='2.0.0'; GeneratedAt=(Get-Date).ToString('o'); Snapshot=$snapshot }) -Path $json | Out-Null
    $lines = @(
        'Windows Network Repair Pro — Diagnostic Report'
        ('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
        ('Computer: ' + $snapshot.Environment.ComputerName)
        ('Windows: ' + $snapshot.Environment.WindowsCaption + ' / ' + $snapshot.Environment.WindowsVersion + ' / Build ' + $snapshot.Environment.Build)
        ('CPU: ' + $snapshot.Environment.CPU)
        ('RAM: ' + $snapshot.Environment.RAMGB + ' GB')
        ('Architecture: ' + $snapshot.Environment.OSArchitecture)
        ''
        'SMB SETTINGS'
        ($snapshot.MainSettings | Format-List | Out-String)
        'ADAPTERS'
        ($snapshot.Adapters | Format-Table -AutoSize | Out-String)
        'SERVICES'
        ($snapshot.Services | Format-Table -AutoSize | Out-String)
        'FIREWALL'
        ($snapshot.Firewall | Format-Table -AutoSize | Out-String)
        'CONNECTIVITY'
        ($snapshot.Connectivity | Format-List | Out-String)
    )
    $lines | Set-Content -LiteralPath $txt -Encoding UTF8
    Write-Status OK ('JSON report: ' + $json)
    Write-Status OK ('TXT report : ' + $txt)
}

function Show-MainMenu {
    Write-Title 'Main menu'
    Write-Host '  [3]  >>> PRIMARY WORKFLOW: Apply all 3 SMB settings + backup + live verification' -ForegroundColor Green
    Write-Host '       Pre-check  >  Snapshot  >  Apply  >  Monitor  >  Before/after report' -ForegroundColor DarkGreen
    Write-Host ''
    Write-Host '  [1]  Full system + network diagnostics' -ForegroundColor White
    Write-Host '  [2]  Show the three main SMB settings' -ForegroundColor White
    Write-Host '  [4]  SMB 1.0 / CIFS optional feature (legacy / risky)' -ForegroundColor White
    Write-Host '  [5]  Optional network repair tools' -ForegroundColor White
    Write-Host '  [6]  Create a backup snapshot' -ForegroundColor White
    Write-Host '  [7]  Restore a backup snapshot' -ForegroundColor White
    Write-Host '  [8]  Generate diagnostic JSON + TXT report' -ForegroundColor White
    Write-Host '  [9]  Show network adapters' -ForegroundColor White
    Write-Host ' [10]  Live system / network monitor' -ForegroundColor Magenta
    Write-Host '  [0]  Exit' -ForegroundColor DarkGray
    Write-Host ''
}

if (-not (Test-Administrator)) {
    Write-Host ''
    Write-Status FAIL 'Administrator privileges are required for system changes.'
    Write-Host 'Right-click NetworkRepair.cmd or WindowsNetworkRepair.exe and select Run as administrator.' -ForegroundColor Yellow
    exit 1
}

try { Show-Banner; Show-EnvironmentSummary } catch { Write-Status WARN ('Initial environment detection issue: ' + $_.Exception.Message) }

while ($true) {
    Show-MainMenu
    $choice = Read-Host 'Select an option [default: 3]'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '3' }
    if ($choice -eq '0') { Write-Status INFO 'Exiting Windows Network Repair Pro.'; break }
    try {
        switch ($choice) {
            '1' {
                Show-EnvironmentSummary
                Show-Adapters
                Show-MainSettings
                $d = Get-NetworkDiagnostics
                Write-Title 'Services'
                $d.Services | Format-Table -AutoSize
                Write-Title 'Firewall rule groups'
                $d.Firewall | Format-Table -AutoSize
                Write-Title 'Connectivity'
                Get-NetworkConnectivity | Format-List
            }
            '2' { Show-MainSettings }
            '3' { Apply-MainFixes }
            '4' { Enable-Smb1Optional }
            '5' { Network-RepairExtras }
            '6' { [void](Backup-BeforeChange) }
            '7' { Restore-Latest }
            '8' { Generate-Report }
            '9' { Show-Adapters }
            '10' { Invoke-StandaloneMonitor }
            default { Write-Status WARN 'Invalid selection. Choose one of the listed menu numbers.' }
        }
    } catch {
        Write-Status FAIL ('Unhandled operation error: ' + $_.Exception.Message)
        Write-RepairLog 'ERROR' $_.Exception.ToString()
    }
    Write-Host ''
    Read-Host 'Press Enter to return to the main menu' | Out-Null
    Show-Banner
}
