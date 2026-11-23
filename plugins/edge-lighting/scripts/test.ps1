param(
    [ValidateSet('all', 'done', 'permission', 'idle')][string]$Case = 'all'
)

# Fires the same visuals the real hooks do, so you can see them on every monitor.
#   powershell -File test.ps1                 # all three, one after another
#   powershell -File test.ps1 -Case permission
. (Join-Path $PSScriptRoot 'hook-lib.ps1')

function Show-Case([string]$Name, [string]$Color, [string]$Message, [bool]$Flash) {
    Write-Output "Showing: $Name"
    if ($Flash) { Start-EdgeFlash $Color 3 }
    Start-CornerCard 'edge-lighting test' $Message $Color
    Show-Toast "edge-lighting test ($Name)" $Message
    Start-Sleep -Seconds 8
}

if ($Case -in 'all', 'done')       { Show-Case 'done (green)'            $Green    'Task done'                        $true }
if ($Case -in 'all', 'permission') { Show-Case 'permission (amber)'      $Amber    'Claude needs your permission'     $true }
if ($Case -in 'all', 'idle')       { Show-Case 'idle (gray, no flash)'   $IdleGray 'Waiting for your input'            $false }
