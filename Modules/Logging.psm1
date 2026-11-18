$script:LogFile = $null

function Initialize-RepairLog {
    param([Parameter(Mandatory=$true)][string]$Path)
    $script:LogFile = $Path
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value ('=' * 92)
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value ('Windows Network Repair Pro | ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value ('=' * 92)
}

function Write-RepairLog {
    param([string]$Level='INFO',[string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Message
        Add-Content -LiteralPath $script:LogFile -Encoding UTF8 -Value $line
    }
}

Export-ModuleMember -Function Initialize-RepairLog,Write-RepairLog
