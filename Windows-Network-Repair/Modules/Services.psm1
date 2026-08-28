function Set-ServiceSafe {
    param([string]$Name,[ValidateSet('Automatic','Manual','Disabled')][string]$StartupType='Automatic',[switch]$Start)
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { Write-NRLog "Service not found: $Name"; return }
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    if ($Start -and $s.Status -ne 'Running') {
        Start-Service -Name $Name -ErrorAction Stop
    }
}
function Set-NRRequiredServices {
    Set-ServiceSafe -Name 'LanmanWorkstation' -StartupType Automatic -Start
    Set-ServiceSafe -Name 'LanmanServer' -StartupType Automatic -Start
    Set-ServiceSafe -Name 'FDResPub' -StartupType Automatic -Start
    Set-ServiceSafe -Name 'fdPHost' -StartupType Manual -Start
    Set-ServiceSafe -Name 'SSDPSRV' -StartupType Manual -Start
    Set-ServiceSafe -Name 'upnphost' -StartupType Manual -Start
    Set-ServiceSafe -Name 'lmhosts' -StartupType Manual -Start
}
Export-ModuleMember -Function Set-NRRequiredServices
