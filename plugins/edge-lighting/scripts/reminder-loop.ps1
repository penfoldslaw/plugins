param(
    [Parameter(Mandatory)][ValidateSet('idle', 'permission')][string]$Kind,
    [Parameter(Mandatory)][string]$SessionId,
    [string]$TranscriptPath = '',
    [string]$Cwd = ''
)

# Hidden background loop, one per kind and session. Repeats a reminder every N seconds until its
# marker file is deleted (reply / answered / turn ended), replaced, or the max duration passes.
#   idle       -> quiet card + popup, skipped (that round only) while Windows Terminal is in front
#   permission -> amber flash + card, never skipped
. (Join-Path $PSScriptRoot 'hook-lib.ps1')

$interval = $ReminderConfig[$Kind].Interval
$max      = $ReminderConfig[$Kind].Max
$marker   = Get-MarkerPath $Kind $SessionId
$p = [pscustomobject]@{ transcript_path = $TranscriptPath; cwd = $Cwd }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$next = $interval

function Stop-Loop([string]$Reason) {
    Write-HookLog @{ reminder = $Kind; action = 'stop'; reason = $Reason; session_id = $SessionId; pid = $PID }
    exit 0
}

while ($true) {
    Start-Sleep -Seconds 1

    if (-not (Test-Path -LiteralPath $marker)) { Stop-Loop 'marker-removed' }
    $m = Read-Marker $marker
    if ($m -and [int]$m.pid -ne 0 -and [int]$m.pid -ne $PID) { Stop-Loop 'replaced' }

    if ($sw.Elapsed.TotalSeconds -ge $max) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        Stop-Loop 'max-duration'
    }

    if ($sw.Elapsed.TotalSeconds -ge $next) {
        $next += $interval
        $fg = Get-ForegroundProcessName
        if ($Kind -eq 'idle' -and $fg -eq 'WindowsTerminal') {
            Write-HookLog @{ reminder = $Kind; action = 'skip'; reason = 'terminal-foreground'; session_id = $SessionId }
            continue
        }
        $label = Get-SessionLabel $p
        try {
            if ($Kind -eq 'idle') { Show-IdlePopup $label } else { Show-PermissionRepeat $label }
            Write-HookLog @{ reminder = $Kind; action = 'shown'; session_id = $SessionId; label = $label; foreground = $fg }
        } catch {
            Write-HookLog @{ reminder = $Kind; action = 'error'; session_id = $SessionId; error = $_.Exception.Message }
        }
    }
}
