function Get-WmiOrCim {
    param([string]$Class, [string]$Namespace='root/cimv2')
    try {
        $cmd = Get-Command Get-CimInstance -ErrorAction SilentlyContinue
        if ($cmd) { return Get-CimInstance -ClassName $Class -Namespace $Namespace -ErrorAction Stop }
        return Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction Stop
    } catch { return $null }
}

function Get-WindowsEnvironment {
    $os = Get-WmiOrCim -Class 'Win32_OperatingSystem'
    $cs = Get-WmiOrCim -Class 'Win32_ComputerSystem'
    $bios = Get-WmiOrCim -Class 'Win32_BIOS'
    $cpu = Get-WmiOrCim -Class 'Win32_Processor' | Select-Object -First 1
    $ram = 0
    if ($cs -and $cs.TotalPhysicalMemory) { $ram = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 2) }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $psver = $PSVersionTable.PSVersion.ToString()
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        CPU = $cpu.Name
        RAMGB = $ram
        WindowsCaption = $os.Caption
        WindowsVersion = $os.Version
        Build = $os.BuildNumber
        InstallDate = $os.InstallDate
        OSArchitecture = $os.OSArchitecture
        ProcessArchitecture = $arch
        PowerShell = $psver
        BiosVersion = if ($bios) { ($bios.SMBIOSBIOSVersion -join ', ') } else { '' }
        IsWindows10Plus = ([int]$os.BuildNumber -ge 10240)
        IsWindows11Likely = ([int]$os.BuildNumber -ge 22000)
    }
}

function Get-NetworkAdaptersSafe {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        return @(Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name,InterfaceDescription,Status,MacAddress,LinkSpeed,ifIndex)
    }
    $configs = @(Get-WmiOrCim -Class 'Win32_NetworkAdapterConfiguration' | Where-Object { $_.IPEnabled -eq $true })
    $out = @()
    foreach ($c in $configs) {
        $out += [pscustomobject]@{
            Name = $c.Description
            InterfaceDescription = $c.Description
            Status = 'Up'
            MacAddress = $c.MACAddress
            LinkSpeed = $null
            ifIndex = $c.Index
        }
    }
    return $out
}

function Get-PowerShellEditionInfo {
    $edition = $null
    try { $edition = $PSVersionTable.PSEdition } catch {}
    if (-not $edition) { $edition = 'Desktop' }
    return $edition
}

Export-ModuleMember -Function Get-WindowsEnvironment,Get-NetworkAdaptersSafe,Get-PowerShellEditionInfo
