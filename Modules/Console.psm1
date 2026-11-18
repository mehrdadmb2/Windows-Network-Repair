function Write-Title {
    param([Parameter(Mandatory=$true)][string]$Text)
    $width = 78
    $line = ('-' * $width)
    Write-Host ''
    Write-Host ('+' + ('=' * ($width - 2)) + '+') -ForegroundColor DarkCyan
    Write-Host ('| ' + $Text.ToUpper().PadRight($width - 4).Substring(0, $width - 4) + ' |') -ForegroundColor Cyan
    Write-Host ('+' + ('=' * ($width - 2)) + '+') -ForegroundColor DarkCyan
}

function Write-Status {
    param(
        [ValidateSet('OK','WARN','FAIL','INFO','SKIP','LIVE')][string]$State,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $colors = @{ OK='Green'; WARN='Yellow'; FAIL='Red'; INFO='Cyan'; SKIP='DarkYellow'; LIVE='Magenta' }
    $symbols = @{ OK='[ OK ]'; WARN='[WARN]'; FAIL='[FAIL]'; INFO='[INFO]'; SKIP='[SKIP]'; LIVE='[LIVE]' }
    Write-Host ("{0} {1}" -f $symbols[$State], $Text) -ForegroundColor $colors[$State]
}

function Write-Step {
    param([int]$Index,[int]$Total,[string]$Text)
    $pct = if ($Total -gt 0) { [int](($Index / $Total) * 100) } else { 0 }
    Write-Progress -Activity 'Windows Network Repair Pro' -Status ("Step {0}/{1}: {2}" -f $Index,$Total,$Text) -PercentComplete $pct
    Write-Host ("  {0}/{1}  {2}" -f $Index,$Total,$Text) -ForegroundColor Cyan
}

function Read-YesNo {
    param([string]$Question,[bool]$DefaultYes=$false)
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host ("{0} {1}" -f $Question,$suffix)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return ($answer.Trim() -match '^(?i:y|yes)$')
}

function Read-ValidatedInt {
    param([string]$Prompt,[int]$Default,[int]$Minimum,[int]$Maximum)
    while ($true) {
        $raw = Read-Host ("{0} [{1}]" -f $Prompt,$Default)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $value = 0
        if ([int]::TryParse($raw,[ref]$value) -and $value -ge $Minimum -and $value -le $Maximum) { return $value }
        Write-Status WARN ("Enter a number from {0} to {1}." -f $Minimum,$Maximum)
    }
}

Export-ModuleMember -Function Write-Title,Write-Status,Write-Step,Read-YesNo,Read-ValidatedInt
