# UserPromptSubmit hook: the user replied, so stop this session's idle and permission reminder loops.
. (Join-Path $PSScriptRoot 'hook-lib.ps1')

$payload = Read-HookPayload
if ($payload -and $payload.session_id) {
    foreach ($kind in $ReminderKinds) { Remove-ReminderMarker $kind ([string]$payload.session_id) 'user-replied' }
}
Clear-StaleMarkers
