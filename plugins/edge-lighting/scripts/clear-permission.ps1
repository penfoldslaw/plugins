# PostToolUse hook (called by clear-permission.cmd): a tool ran, so this session's pending permission
# prompt was answered. Deleting the marker stops its permission reminder loop.
. (Join-Path $PSScriptRoot 'hook-lib.ps1')

$payload = Read-HookPayload
if ($payload -and $payload.session_id) {
    Remove-ReminderMarker 'permission' ([string]$payload.session_id) 'tool-ran'
}
