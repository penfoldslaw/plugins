# Shared helpers for the edge-lighting hook scripts (dot-sourced; keep this file ASCII).

# --- Where user data lives ---------------------------------------------------
# config.json, state\ (reminder markers, card slots) and the optional hook-log.jsonl live outside the
# plugin folder so they survive plugin updates. Override with CLAUDE_EDGE_LIGHTING_HOME.
$HomeDir = $env:CLAUDE_EDGE_LIGHTING_HOME
if (-not $HomeDir) { $HomeDir = Join-Path $env:USERPROFILE '.claude\edge-lighting' }
$StateDir   = Join-Path $HomeDir 'state'
$LogPath    = Join-Path $HomeDir 'hook-log.jsonl'
$ConfigPath = Join-Path $HomeDir 'config.json'

# --- Settings (defaults, overridden by config.json) --------------------------
$Config = @{
    log        = $false      # write every hook payload and reminder event to hook-log.jsonl
    edgeFlash  = $true       # glowing border on every monitor
    cornerCard = $true       # dark card in the bottom-right of every monitor
    toast      = $true       # Windows notification (needs the BurntToast module); silent
    colors     = @{ done = '#22C55E'; permission = '#F59E0B'; idle = '#9CA3AF' }
    idle       = @{ mode = 'popup'; intervalMinutes = 30; maxHours = 4 }       # mode: popup | none
    permission = @{ intervalMinutes = 2; maxHours = 1; repeatPulses = 2 }
    card       = @{ holdSeconds = 6 }
}

function Merge-Config($Target, $Source) {
    if ($null -eq $Source) { return }
    foreach ($prop in $Source.PSObject.Properties) {
        $key = $prop.Name
        if (-not $Target.ContainsKey($key)) { continue }   # ignore unknown keys
        if ($Target[$key] -is [hashtable] -and $prop.Value -is [pscustomobject]) {
            Merge-Config $Target[$key] $prop.Value
        } elseif ($null -ne $prop.Value -and -not ($Target[$key] -is [hashtable])) {
            $Target[$key] = $prop.Value
        }
    }
}
try {
    if (Test-Path -LiteralPath $ConfigPath) {
        Merge-Config $Config (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
} catch {}   # a broken config.json falls back to the defaults

$Green    = $Config.colors.done
$Amber    = $Config.colors.permission
$IdleGray = $Config.colors.idle

function Get-EnvSeconds([string]$Name, [int]$Default) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v -match '^\d+$' -and [int]$v -gt 0) { return [int]$v }
    return $Default
}
# Env overrides (seconds) exist for testing.
$ReminderConfig = @{
    idle       = @{ Interval = (Get-EnvSeconds 'CLAUDE_IDLE_INTERVAL_SECONDS' ([int]([double]$Config.idle.intervalMinutes * 60)))
                    Max      = (Get-EnvSeconds 'CLAUDE_IDLE_MAX_SECONDS' ([int]([double]$Config.idle.maxHours * 3600))) }
    permission = @{ Interval = (Get-EnvSeconds 'CLAUDE_PERM_INTERVAL_SECONDS' ([int]([double]$Config.permission.intervalMinutes * 60)))
                    Max      = (Get-EnvSeconds 'CLAUDE_PERM_MAX_SECONDS' ([int]([double]$Config.permission.maxHours * 3600))) }
}
$ReminderKinds = 'idle', 'permission'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-HookLog($Fields) {
    if (-not $Config.log) { return }
    try {
        if (-not (Test-Path -LiteralPath $HomeDir)) { New-Item -ItemType Directory -Path $HomeDir -Force | Out-Null }
        $entry = [ordered]@{ timestamp = (Get-Date).ToString('o') }
        foreach ($k in $Fields.Keys) { $entry[$k] = $Fields[$k] }
        [System.IO.File]::AppendAllText($LogPath, ($entry | ConvertTo-Json -Compress -Depth 20) + "`n", $Utf8NoBom)
    } catch {}
}

# Read the hook JSON from stdin and log it. Returns the parsed payload, or $null if empty/invalid.
function Read-HookPayload {
    $raw = ''
    try {
        if ([Console]::IsInputRedirected) {
            [Console]::InputEncoding = [System.Text.Encoding]::UTF8
            $raw = [Console]::In.ReadToEnd()
        }
    } catch {}
    $payload = $null
    if ($raw -and $raw.Trim()) {
        try { $payload = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop } catch { $payload = $null }
    }
    if ($payload) { Write-HookLog @{ payload = $payload } } else { Write-HookLog @{ raw = $raw } }
    return $payload
}

# --- Session label -----------------------------------------------------------
# /rename stores {"type":"custom-title","customTitle":"..."}; Claude Code's own title is
# {"type":"ai-title","aiTitle":"..."} (what the terminal tab shows). Both are re-appended over time,
# so the last one wins. Check the tail first, then the whole file.
function Get-TranscriptTitle([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            foreach ($tail in 262144, $fs.Length) {
                $start = [math]::Max(0, $fs.Length - $tail)
                $fs.Position = $start
                $buf = New-Object byte[] ($fs.Length - $start)
                [void]$fs.Read($buf, 0, $buf.Length)
                $custom = ''; $auto = ''
                foreach ($l in $Utf8NoBom.GetString($buf).Split("`n")) {
                    if ($l.StartsWith('{"type":"custom-title"')) {
                        try { $t = [string]($l | ConvertFrom-Json).customTitle; if ($t) { $custom = $t } } catch {}
                    } elseif ($l.StartsWith('{"type":"ai-title"')) {
                        try { $t = [string]($l | ConvertFrom-Json).aiTitle; if ($t) { $auto = $t } } catch {}
                    }
                }
                # /rename title wins; otherwise the auto-generated title
                $title = if ($custom) { $custom } else { $auto }
                if ($title -or $start -eq 0) { return $title }
            }
        } finally { $fs.Dispose() }
    } catch {}
    return ''
}

function Get-SessionName($p) {
    foreach ($field in 'session_name', 'session_title') {
        if ($p.$field) { return [string]$p.$field }
    }
    return Get-TranscriptTitle ([string]$p.transcript_path)
}

# Session name, else cwd folder, else 'Claude Code'.
function Get-SessionLabel($p) {
    $label = Get-SessionName $p
    if (-not $label -and $p.cwd) { $label = Split-Path -Leaf ([string]$p.cwd).TrimEnd('\', '/') }
    if (-not $label) { $label = 'Claude Code' }
    return $label
}

# --- Reminder markers --------------------------------------------------------
# One marker file per kind and session; deleting it tells that session's loop to stop.
function Get-MarkerPath([string]$Kind, [string]$SessionId) {
    $safe = ($SessionId -replace '[^A-Za-z0-9_-]', '_')
    if (-not $safe) { $safe = 'unknown' }
    return Join-Path $StateDir "$Kind-$safe.json"
}

function Test-ProcessAlive([int]$ProcId) {
    if ($ProcId -le 0) { return $false }
    return [bool](Get-Process -Id $ProcId -ErrorAction SilentlyContinue)
}

# Opened with FileShare.Delete so reading a marker never blocks another hook from deleting it.
function Read-Marker([string]$Path) {
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite, Delete')
        try { $sr = New-Object System.IO.StreamReader($fs); return ($sr.ReadToEnd() | ConvertFrom-Json) }
        finally { $fs.Dispose() }
    } catch { return $null }
}

function Remove-ReminderMarker([string]$Kind, [string]$SessionId, [string]$Reason) {
    $path = Get-MarkerPath $Kind $SessionId
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        Write-HookLog @{ reminder = $Kind; action = 'stop-requested'; reason = $Reason; session_id = $SessionId }
    }
}

# Drop markers whose loop is gone or that outlived their max duration.
function Clear-StaleMarkers {
    if (-not (Test-Path -LiteralPath $StateDir)) { return }
    foreach ($kind in $ReminderKinds) {
        foreach ($f in Get-ChildItem -LiteralPath $StateDir -Filter "$kind-*.json" -ErrorAction SilentlyContinue) {
            $m = Read-Marker $f.FullName
            $age = ((Get-Date) - $f.CreationTime).TotalSeconds
            $dead = ($m -and [int]$m.pid -gt 0 -and -not (Test-ProcessAlive ([int]$m.pid)))
            if ($dead -or $age -gt ($ReminderConfig[$kind].Max + 600)) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                Write-HookLog @{ reminder = $kind; action = 'cleanup-stale'; marker = $f.Name }
            }
        }
    }
}

# Start the hidden loop for this kind/session. -Restart replaces a live loop (fresh timer).
function Start-Reminder([string]$Kind, $p, [switch]$Restart) {
    $sid = [string]$p.session_id
    $marker = Get-MarkerPath $Kind $sid
    if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

    if ($Restart -and (Test-Path -LiteralPath $marker)) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue   # old loop sees this and exits
        Write-HookLog @{ reminder = $Kind; action = 'restart'; session_id = $sid }
    }

    $created = $false
    for ($try = 0; $try -lt 2 -and -not $created; $try++) {
        try {
            $fs = [System.IO.File]::Open($marker, 'CreateNew', 'Write', 'None')
            $fs.Dispose()
            $created = $true
        } catch [System.IO.IOException] {
            $m = Read-Marker $marker
            $age = ((Get-Date) - (Get-Item -LiteralPath $marker -ErrorAction SilentlyContinue).CreationTime).TotalSeconds
            $loopPid = if ($m) { [int]$m.pid } else { 0 }
            # pid 0 = another hook is still launching the loop
            if ((Test-ProcessAlive $loopPid) -or ($loopPid -eq 0 -and $age -lt 30)) {
                Write-HookLog @{ reminder = $Kind; action = 'reuse'; session_id = $sid; pid = $loopPid }
                return
            }
            Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $created) { return }

    $script = Join-Path $PSScriptRoot 'reminder-loop.ps1'
    $proc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Kind', $Kind,
        '-SessionId', "`"$sid`"", '-TranscriptPath', "`"$([string]$p.transcript_path)`"", '-Cwd', "`"$([string]$p.cwd)`""
    )
    $json = [ordered]@{ pid = $proc.Id; session_id = $sid; started = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($marker, $json, $Utf8NoBom)
    Write-HookLog @{ reminder = $Kind; action = 'start'; session_id = $sid; pid = $proc.Id
                     interval_seconds = $ReminderConfig[$Kind].Interval; max_seconds = $ReminderConfig[$Kind].Max }
}

# --- Foreground window -------------------------------------------------------
function Get-ForegroundProcessName {
    if (-not ('Native.Fg' -as [type])) {
        Add-Type -Namespace Native -Name Fg -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
'@
    }
    $h = [Native.Fg]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return '' }
    [uint32]$procId = 0
    [void][Native.Fg]::GetWindowThreadProcessId($h, [ref]$procId)
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName }
    return ''
}

# --- Visuals (all detached and hidden so the caller never waits) -------------
function Start-EdgeFlash([string]$Color, [int]$Pulses = 3) {
    if (-not $Config.edgeFlash) { return }
    $flash = Join-Path $PSScriptRoot 'edge-flash.ps1'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$flash`"", '-Color', "`"$Color`"", '-Pulses', "$Pulses"
    )
}

# Custom corner card on every monitor.
function Start-CornerCard([string]$Title, [string]$Message, [string]$Color) {
    if (-not $Config.cornerCard) { return }
    $card = Join-Path $PSScriptRoot 'corner-card.ps1'
    $t = ($Title -replace '"', "'").TrimEnd('\')
    $m = ($Message -replace '"', "'").TrimEnd('\')
    try {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$card`"",
            '-Title', "`"$t`"", '-Message', "`"$m`"", '-Color', "`"$Color`"", '-HoldSeconds', ([string][int]$Config.card.holdSeconds)
        )
    } catch { Write-HookLog @{ card = 'error'; error = $_.Exception.Message } }
}

# Silent Windows notification for Notification Center history. Skipped if BurntToast isn't installed.
function Show-Toast([string]$Title, [string]$Message) {
    if (-not $Config.toast) { return }
    try {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text $Title, $Message -Silent
    } catch {
        Write-HookLog @{ toast = 'skipped'; reason = 'BurntToast not available'; error = $_.Exception.Message }
    }
}

function Show-IdlePopup([string]$Label) {
    Start-CornerCard $Label 'Waiting for your input' $IdleGray
    Show-Toast "$([char]::ConvertFromUtf32(0x1F4AC)) $Label" 'Waiting for your input'
}

# Repeat nudge for an unanswered permission prompt: flash + card only.
function Show-PermissionRepeat([string]$Label) {
    Start-EdgeFlash $Amber ([int]$Config.permission.repeatPulses)
    Start-CornerCard $Label 'Still waiting for your permission' $Amber
}
