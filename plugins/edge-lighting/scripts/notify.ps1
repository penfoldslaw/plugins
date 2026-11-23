param(
    [string]$Title = 'Claude Code',
    [string]$Message = '',
    [string]$Color = '',
    [switch]$DryRun   # print what would be shown instead of showing it
)

# Stop and Notification hook. Reads the hook JSON on stdin; falls back to the arguments if it is
# empty or invalid. Settings (colours, idle mode, reminder intervals) come from config.json.
. (Join-Path $PSScriptRoot 'hook-lib.ps1')

if (-not $Color) { $Color = $Green }

# --- Read and log the hook payload (empty/invalid stdin -> $null) -----------
$payload = Read-HookPayload

# --- Decide what to show (falls back to the passed arguments) ---------------
$showFlash = $true
$showPopup = $true
$isIdle = $false
$isPermission = $false
$idleOff = ($Config.idle.mode -eq 'none')

if ($payload) {
    $event = [string]$payload.hook_event_name
    $type  = [string]$payload.notification_type
    $msg   = [string]$payload.message
    $folder = Get-SessionLabel $payload

    if ($event -eq 'Stop') {
        $Title = "$([char]0x2705) $folder"
        $Color = $Green
    } elseif ($event -eq 'Notification') {
        if ($msg) { $Message = $msg }
        $isIdle = ($type -eq 'idle_prompt') -or (-not $type -and $msg -match 'waiting for your input')
        if ($isIdle) {
            $Title = "$([char]::ConvertFromUtf32(0x1F4AC)) $folder"
            $Message = 'Waiting for your input'
            $showFlash = $false                       # idle reminders never flash
            if ($idleOff) { $showPopup = $false }
        } else {
            # permission_prompt, or anything else that needs attention
            $isPermission = $true
            $Title = "$([char]0x26A0)$([char]0xFE0F) $folder"
            $Color = $Amber
        }
    } else {
        $Title = $folder
    }
}

if ($DryRun) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Output "title=[$Title] message=[$Message] flash=$showFlash ($Color) popup=$showPopup idle_loop=$($isIdle -and -not $idleOff) permission_loop=$isPermission"
    return
}

Clear-StaleMarkers

# Reminder bookkeeping: a permission prompt ends the idle loop; a finished turn ends the permission loop.
if ($payload -and $payload.session_id) {
    $sid = [string]$payload.session_id
    if ($isPermission) { Remove-ReminderMarker 'idle' $sid 'permission-prompt' }
    if ($event -eq 'Stop') { Remove-ReminderMarker 'permission' $sid 'turn-ended' }
}

if ($showFlash) { Start-EdgeFlash $Color 3 }

if ($showPopup) {
    # Corner card on every monitor (session name only; the colour carries the status) ...
    $cardTitle = if ($payload) { $folder } else { $Title }
    $cardColor = if ($isIdle) { $IdleGray } else { $Color }
    Start-CornerCard $cardTitle $Message $cardColor
    # ... plus a silent Windows notification for Notification Center history.
    Show-Toast $Title $Message
}

# Keep nudging, one loop per kind and session.
if ($payload -and $payload.session_id) {
    if ($isIdle -and -not $idleOff) { Start-Reminder 'idle' $payload }
    if ($isPermission) { Start-Reminder 'permission' $payload -Restart }   # restart: interval counts from this prompt
}
