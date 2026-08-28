$script:LogFile = $null
function Initialize-RepairLog {
    param([string]$Path)
    $script:LogFile = $Path
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Add-Content -Path $Path -Value ('=' * 90)
    Add-Content -Path $Path -Value ('Windows Network Repair log - ' + (Get-Date))
    Add-Content -Path $Path -Value ('=' * 90)
}
function Write-RepairLog {
    param([string]$Level='INFO',[string]$Message)
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message)
    }
}
Export-ModuleMember -Function Initialize-RepairLog,Write-RepairLog
