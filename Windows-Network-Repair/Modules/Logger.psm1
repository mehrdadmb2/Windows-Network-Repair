$script:NRLogPath = $null
function Initialize-NRLogger {
    param([Parameter(Mandatory)][string]$Path)
    $script:NRLogPath = $Path
    "===== Windows Network Repair =====" | Set-Content -Encoding UTF8 $Path
    ("Started: {0}" -f (Get-Date)) | Add-Content -Encoding UTF8 $Path
}
function Write-NRLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    if ($script:NRLogPath) { Add-Content -Encoding UTF8 -Path $script:NRLogPath -Value $line }
}
Export-ModuleMember -Function Initialize-NRLogger,Write-NRLog
