function Get-WmiOrCim {
    param([Parameter(Mandatory=$true)][string]$Class,[string]$Namespace='root/cimv2')
    # Try CIM first, but do not let a class/provider error block the legacy WMI fallback.
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        try {
            return Get-CimInstance -ClassName $Class -Namespace $Namespace -ErrorAction Stop
        } catch {}
    }
    if (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
        try {
            return Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction Stop
        } catch {}
    }
    return $null
}

function Get-WindowsEnvironment {
    $os = Get-WmiOrCim -Class 'Win32_OperatingSystem'
    $cs = Get-WmiOrCim -Class 'Win32_ComputerSystem'
    $bios = Get-WmiOrCim -Class 'Win32_BIOS'
    $cpu = Get-WmiOrCim -Class 'Win32_Processor' | Select-Object -First 1
    $ram = 0
    if ($cs -and $cs.TotalPhysicalMemory) { $ram = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB),2) }

    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $versionText = if ($os -and $os.Version) { [string]$os.Version } else { [Environment]::OSVersion.Version.ToString() }
    $build = if ($os -and $os.BuildNumber) { [string]$os.BuildNumber } else { [string][Environment]::OSVersion.Version.Build }
    $caption = if ($os -and $os.Caption) { [string]$os.Caption.Trim() } else { 'Microsoft Windows' }
    $buildNumber = 0
    [void][int]::TryParse($build,[ref]$buildNumber)

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = if ($cs) { [string]$cs.Manufacturer } else { 'Unknown' }
        Model = if ($cs) { [string]$cs.Model } else { 'Unknown' }
        CPU = if ($cpu) { [string]$cpu.Name } else { 'Unknown' }
        LogicalProcessors = if ($cs) { [int]$cs.NumberOfLogicalProcessors } else { 0 }
        RAMGB = $ram
        WindowsCaption = $caption
        WindowsVersion = $versionText
        Build = $build
        InstallDate = if ($os) { [string]$os.InstallDate } else { $null }
        OSArchitecture = if ($os) { [string]$os.OSArchitecture } else { $arch }
        ProcessArchitecture = $arch
        PowerShell = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
        BiosVersion = if ($bios) { [string]($bios.SMBIOSBIOSVersion -join ', ') } else { '' }
        IsWindows10Plus = ($buildNumber -ge 10240)
        IsWindows11Likely = ($buildNumber -ge 22000)
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    }
}

function Get-NetworkAdaptersSafe {
    $adapters = @()
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        try {
            $adapters = @(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
                $ip = $null
                if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
                    try { $ip = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex -ErrorAction Stop } catch {}
                }
                [pscustomobject]@{
                    Name = [string]$_.Name
                    InterfaceDescription = [string]$_.InterfaceDescription
                    Status = [string]$_.Status
                    MacAddress = [string]$_.MacAddress
                    LinkSpeed = [string]$_.LinkSpeed
                    InterfaceIndex = [int]$_.ifIndex
                    IPv4Address = if ($ip -and $ip.IPv4Address) { [string]($ip.IPv4Address.IPAddress -join ', ') } else { '' }
                    Gateway = if ($ip -and $ip.IPv4DefaultGateway) { [string]($ip.IPv4DefaultGateway.NextHop -join ', ') } else { '' }
                    DnsServers = if ($ip -and $ip.DnsServer) { [string]($ip.DnsServer.ServerAddresses -join ', ') } else { '' }
                }
            })
            return $adapters
        } catch {}
    }

    $configs = @(Get-WmiOrCim -Class 'Win32_NetworkAdapterConfiguration' | Where-Object { $_.IPEnabled -eq $true })
    foreach ($c in $configs) {
        $status = 'Unknown'
        try {
            $na = Get-WmiOrCim -Class 'Win32_NetworkAdapter' | Where-Object { $_.Index -eq $c.Index } | Select-Object -First 1
            if ($na -and $na.NetConnectionStatus -eq 2) { $status = 'Up' } elseif ($na) { $status = 'Disconnected' }
        } catch {}
        $adapters += [pscustomobject]@{
            Name = [string]$c.Description
            InterfaceDescription = [string]$c.Description
            Status = $status
            MacAddress = [string]$c.MACAddress
            LinkSpeed = ''
            InterfaceIndex = [int]$c.Index
            IPv4Address = [string]($c.IPAddress -join ', ')
            Gateway = [string]($c.DefaultIPGateway -join ', ')
            DnsServers = [string]($c.DNSServerSearchOrder -join ', ')
        }
    }
    return @($adapters)
}

function Get-NetworkConnectivity {
    $gateways = @()
    $dnsServers = @()
    foreach ($a in @(Get-NetworkAdaptersSafe)) {
        if (-not [string]::IsNullOrWhiteSpace($a.Gateway)) { $gateways += @($a.Gateway -split ',\s*') }
        if (-not [string]::IsNullOrWhiteSpace($a.DnsServers)) { $dnsServers += @($a.DnsServers -split ',\s*') }
    }
    $gateways = @($gateways | Where-Object { $_ } | Select-Object -Unique)
    $dnsServers = @($dnsServers | Where-Object { $_ } | Select-Object -Unique)
    $gatewayReachable = $null
    if ($gateways.Count -gt 0) {
        $p = $null
        try {
            $p = New-Object System.Net.NetworkInformation.Ping
            $reply = $p.Send([string]$gateways[0],1200)
            $gatewayReachable = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
        } catch { $gatewayReachable = $false }
        finally { if ($p) { $p.Dispose() } }
    }
    $dnsResolved = $null
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses('example.com')
        $dnsResolved = ($addresses.Count -gt 0)
    } catch { $dnsResolved = $false }
    [pscustomobject]@{
        DefaultGateways = $gateways
        DnsServers = $dnsServers
        # GatewayReachable is retained as a compatibility field; it represents an ICMP echo reply,
        # not a guarantee that all traffic through the gateway is reachable.
        GatewayReachable = $gatewayReachable
        GatewayIcmpReply = $gatewayReachable
        GatewayProbeMethod = 'ICMP echo'
        PublicDnsResolution = $dnsResolved
        ConfiguredDnsResolution = $dnsResolved
        DnsResolutionTarget = 'example.com'
    }
}

function Get-PowerShellEditionInfo {
    if ($PSVersionTable.PSEdition) { return [string]$PSVersionTable.PSEdition }
    return 'Desktop'
}

Export-ModuleMember -Function Get-WindowsEnvironment,Get-NetworkAdaptersSafe,Get-NetworkConnectivity,Get-PowerShellEditionInfo,Get-WmiOrCim
