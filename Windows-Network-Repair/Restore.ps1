$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath
$latest = Get-ChildItem "$scriptPath\Backup\*.reg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host "Restoring from $($latest.FullName)" -ForegroundColor Yellow
    reg import $latest.FullName
    Write-Host "Restored. Please restart." -ForegroundColor Green
} else {
    Write-Host "No backup file found." -ForegroundColor Red
}