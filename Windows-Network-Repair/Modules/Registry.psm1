$Workstation = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
$Server = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'

function Set-DwordValue {
    param([string]$Path,[string]$Name,[int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}
function Remove-ValueIfPresent {
    param([string]$Path,[string]$Name)
    if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    }
}
function Get-DwordValue {
    param([string]$Path,[string]$Name)
    $v = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $null }
    return [int]$v.$Name
}
function Get-SmbWorkstationState {
    [pscustomobject]@{
        RequireSecuritySignature = Get-DwordValue $Workstation 'RequireSecuritySignature'
        EnableSecuritySignature  = Get-DwordValue $Workstation 'EnableSecuritySignature'
        AllowInsecureGuestAuth   = Get-DwordValue $Workstation 'AllowInsecureGuestAuth'
    }
}
function Set-NRGuestAuth {
    param([Parameter(Mandatory)][bool]$Enabled)
    Set-DwordValue $Workstation 'AllowInsecureGuestAuth' ([int]$Enabled)
    $check = Get-DwordValue $Workstation 'AllowInsecureGuestAuth'
    if ($check -ne [int]$Enabled) { throw 'Guest authentication registry value was not applied.' }
}
function Set-NRClientSigning {
    param([Parameter(Mandatory)][bool]$Enabled)
    $v = [int]$Enabled
    Set-DwordValue $Workstation 'RequireSecuritySignature' $v
    Set-DwordValue $Workstation 'EnableSecuritySignature' $v
    $a = Get-SmbWorkstationState
    if ($a.RequireSecuritySignature -ne $v -or $a.EnableSecuritySignature -ne $v) {
        throw 'SMB client signing registry values were not applied.'
    }
}
Export-ModuleMember -Function Get-SmbWorkstationState,Set-NRGuestAuth,Set-NRClientSigning
