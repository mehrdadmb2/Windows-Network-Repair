$script:LogFile = $null

function Initialize-Logger {
    param($LogFile)
    $script:LogFile = $LogFile
    "=== Log started at $(Get-Date) ===" | Out-File $LogFile
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp - $Message" | Out-File $script:LogFile -Append
    Write-Host $Message
}