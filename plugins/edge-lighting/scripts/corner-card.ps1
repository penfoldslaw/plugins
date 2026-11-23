param(
    [string]$Title = 'Claude Code',
    [string]$Message = '',
    [string]$Color = '#9CA3AF',
    [int]$HoldSeconds = 6
)

# Dark popup card in the bottom-right corner of every monitor. Click to dismiss.
# Several cards at once stack upward: each process claims a free slot (<home>\state\cards\slot-N.json).

$CardWidth = 340; $CardHeight = 80   # DIPs at 100% scale
$Margin = 16; $Gap = 10              # DIPs
$HoldMs = [math]::Max(1, $HoldSeconds) * 1000; $FadeInMs = 250; $FadeOutMs = 400; $ClickFadeMs = 150

$ErrorActionPreference = 'Stop'

# --- DPI awareness (before any window exists) --------------------------------
Add-Type -Namespace Native -Name Win -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
[DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr hMon, int type, out uint dpiX, out uint dpiY);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
'@
try {
    if (-not [Native.Win]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))) {   # per-monitor v2
        if ([Native.Win]::SetProcessDpiAwareness(2) -ne 0) { [void][Native.Win]::SetProcessDPIAware() }
    }
} catch { try { [void][Native.Win]::SetProcessDPIAware() } catch {} }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- Claim a stacking slot ---------------------------------------------------
$homeDir = $env:CLAUDE_EDGE_LIGHTING_HOME
if (-not $homeDir) { $homeDir = Join-Path $env:USERPROFILE '.claude\edge-lighting' }
$cardsDir = Join-Path $homeDir 'state\cards'
New-Item -ItemType Directory -Path $cardsDir -Force | Out-Null
$slot = -1
$slotFile = $null
for ($n = 0; $n -lt 12 -and $slot -lt 0; $n++) {
    $f = Join-Path $cardsDir "slot-$n.json"
    for ($try = 0; $try -lt 2 -and $slot -lt 0; $try++) {
        try {
            $fs =[System.IO.File]::Open($f, 'CreateNew', 'Write', 'None')
            $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$PID)
            $fs.Write($bytes, 0, $bytes.Length); $fs.Dispose()
            $slot = $n; $slotFile = $f
        } catch [System.IO.IOException] {
            $owner = 0
            try { $owner = [int](Get-Content -LiteralPath $f -Raw -ErrorAction Stop) } catch {}
            $age = ((Get-Date) - (Get-Item -LiteralPath $f -ErrorAction SilentlyContinue).CreationTime).TotalSeconds
            if ($owner -gt 0 -and -not (Get-Process -Id $owner -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue   # stale, retry same slot
            } elseif ($owner -eq 0 -and $age -gt 20) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            } else { break }
        }
    }
}
if ($slot -lt 0) { $slot = 0 }   # all slots busy: overlap rather than not show

function Release-Slot { if ($slotFile) { Remove-Item -LiteralPath $slotFile -Force -ErrorAction SilentlyContinue } }

# --- Build one window per monitor -------------------------------------------
try { $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color) } catch { $brush = [System.Windows.Media.Brushes]::Gray }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        ShowInTaskbar="False" Topmost="True" ShowActivated="False" Focusable="False"
        Width="340" Height="80" Opacity="0" Cursor="Hand">
  <Viewbox Stretch="Uniform">
    <Border Width="340" Height="80" CornerRadius="12" Background="#F2202124" BorderBrush="#33FFFFFF" BorderThickness="1">
      <Grid>
        <Ellipse x:Name="Dot" Width="12" Height="12" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="18,0,0,0"/>
        <StackPanel VerticalAlignment="Center" Margin="42,0,16,0">
          <TextBlock x:Name="T" FontFamily="Segoe UI" FontWeight="Bold" FontSize="15" Foreground="White" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="M" FontFamily="Segoe UI" FontSize="13" Foreground="#FFB8BCC4" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/>
        </StackPanel>
      </Grid>
    </Border>
  </Viewbox>
</Window>
'@

$windows = New-Object System.Collections.ArrayList
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
    $w = [System.Windows.Markup.XamlReader]::Parse($xaml)
    $w.FindName('T').Text = $Title
    $w.FindName('M').Text = $Message
    $w.FindName('Dot').Fill = $brush

    # Physical-pixel geometry from this monitor's own scale.
    $wa = $screen.WorkingArea
    $pt = New-Object Native.Win+POINT
    $pt.x = $wa.Left + [int]($wa.Width / 2); $pt.y = $wa.Top + [int]($wa.Height / 2)
    $hmon = [Native.Win]::MonitorFromPoint($pt, 2)
    [uint32]$dx = 96; [uint32]$dy = 96
    try { if ([Native.Win]::GetDpiForMonitor($hmon, 0, [ref]$dx, [ref]$dy) -ne 0) { $dx = 96 } } catch { $dx = 96 }
    $scale = $dx / 96.0
    $pw = [int][math]::Round($CardWidth * $scale);  $ph = [int][math]::Round($CardHeight * $scale)
    $px = $wa.Right - [int][math]::Round($Margin * $scale) - $pw
    $py = $wa.Bottom - [int][math]::Round($Margin * $scale) - $ph - $slot * [int][math]::Round(($CardHeight + $Gap) * $scale)

    $w.Tag = @{ X = $px; Y = $py; W = $pw; H = $ph }
    $w.Add_SourceInitialized({
        param($s, $e)
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($s)).Handle
        # NOACTIVATE | TOOLWINDOW: no focus steal, no taskbar / Alt+Tab
        $ex = [Native.Win]::GetWindowLong($h, -20)
        [void][Native.Win]::SetWindowLong($h, -20, ($ex -bor 0x08000000 -bor 0x80))
    })
    $w.Add_MouseLeftButtonUp({
        if ($script:dismissAt -lt 0) {   # first click on any monitor dismisses them all
            $script:dismissFrom = $windows[0].Opacity
            $script:dismissAt = $script:clock.ElapsedMilliseconds
        }
    })
    [void]$windows.Add($w)
}

# --- Show, place, animate ----------------------------------------------------
$script:dismissAt = -1
$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
$script:dismissFrom = 1.0
$script:slotFile = $slotFile

foreach ($w in $windows) {
    $w.Show()
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle
    $g = $w.Tag
    # HWND_TOPMOST = -1; SWP_NOACTIVATE = 0x10; SWP_SHOWWINDOW = 0x40
    [void][Native.Win]::SetWindowPos($h, [IntPtr]::new(-1), $g.X, $g.Y, $g.W, $g.H, 0x50)
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(15)
$timer.Add_Tick({
    $t = $script:clock.ElapsedMilliseconds
    if ($script:dismissAt -ge 0) {
        $o = $script:dismissFrom * (1 - ($t - $script:dismissAt) / $ClickFadeMs)
    } elseif ($t -lt $FadeInMs) {
        $o = $t / $FadeInMs
    } elseif ($t -lt $FadeInMs + $HoldMs) {
        $o = 1.0
    } else {
        $o = 1 - ($t - $FadeInMs - $HoldMs) / $FadeOutMs
    }
    if ($o -le 0) {
        $timer.Stop()
        foreach ($w in $windows) { $w.Close() }
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
        return
    }
    foreach ($w in $windows) { $w.Opacity = [math]::Min(1.0, $o) }
})
$timer.Start()

try { [System.Windows.Threading.Dispatcher]::Run() } finally { Release-Slot }
