function Write-Title {
    param([string]$Text)
    $line = ('=' * 76)
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
}

function Write-Status {
    param([ValidateSet('OK','WARN','FAIL','INFO','SKIP')][string]$State, [string]$Text)
    $colors = @{ OK='Green'; WARN='Yellow'; FAIL='Red'; INFO='Cyan'; SKIP='DarkYellow' }
    $symbols = @{ OK='[OK]'; WARN='[!!]'; FAIL='[XX]'; INFO='[i ]'; SKIP='[- ]' }
    Write-Host ("{0} {1}" -f $symbols[$State], $Text) -ForegroundColor $colors[$State]
}

function Write-Step {
    param([int]$Index, [int]$Total, [string]$Text)
    Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $Text) -ForegroundColor Cyan
}

function Read-YesNo {
    param([string]$Question, [bool]$DefaultYes = $false)
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host ("{0} {1}" -f $Question, $suffix)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return ($answer -match '^(y|yes)$')
}

Export-ModuleMember -Function Write-Title,Write-Status,Write-Step,Read-YesNo
