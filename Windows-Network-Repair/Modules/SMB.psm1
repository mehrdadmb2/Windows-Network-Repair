function Disable-NRClientForMicrosoftNetworks {
    $items = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction SilentlyContinue)
    if (-not $items) { throw 'No Client for Microsoft Networks bindings were found.' }
    foreach ($item in $items) {
        if ($item.Enabled) {
            Disable-NetAdapterBinding -Name $item.Name -ComponentID 'ms_msclient' -ErrorAction Stop | Out-Null
        }
    }
    $bad = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction SilentlyContinue | Where-Object Enabled)
    if ($bad.Count -gt 0) { throw 'Some adapter bindings are still enabled.' }
}
function Enable-NRClientForMicrosoftNetworks {
    $items = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction SilentlyContinue)
    if (-not $items) { throw 'No Client for Microsoft Networks bindings were found.' }
    foreach ($item in $items) {
        if (-not $item.Enabled) {
            Enable-NetAdapterBinding -Name $item.Name -ComponentID 'ms_msclient' -ErrorAction Stop | Out-Null
        }
    }
    $bad = @(Get-NetAdapterBinding -ComponentID 'ms_msclient' -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
    if ($bad.Count -gt 0) { throw 'Some adapter bindings are still disabled.' }
}
function Enable-NRSMB1 {
    $r = Enable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop
    if ($r.RestartNeeded) { Write-NRLog 'SMB1 enable reports that a restart is required.' }
    $state = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
    if ($state.State -notin @('Enabled','Enable Pending')) { throw "SMB1 state is $($state.State) after enable operation." }
}
Export-ModuleMember -Function Disable-NRClientForMicrosoftNetworks,Enable-NRClientForMicrosoftNetworks,Enable-NRSMB1
