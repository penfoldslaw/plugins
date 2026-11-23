param(
    [string]$Color = '#22C55E',
    [int]$Pulses = 3,
    [int]$DurationMs = 0
)

# Edge lighting: a glowing, click-through border pulsed on every monitor.
if ($Pulses -lt 1) { $Pulses = 1 }
if ($DurationMs -le 0) { $DurationMs = [int]($Pulses * 667) }   # 3 pulses ~ 2s

$ErrorActionPreference = 'Stop'

# --- DPI awareness (must happen before any window exists) -------------------
Add-Type -Namespace Native -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
try {
    if (-not [Native.Dpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))) {   # per-monitor v2
        if ([Native.Dpi]::SetProcessDpiAwareness(2) -ne 0) { [void][Native.Dpi]::SetProcessDPIAware() }
    }
} catch {
    try { [void][Native.Dpi]::SetProcessDPIAware() } catch {}
}

# --- Overlay window ----------------------------------------------------------
$src = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class EdgeOverlay : Form
{
    const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_NOACTIVATE = 0x08000000,
              WS_EX_TOOLWINDOW = 0x80, WS_EX_TOPMOST = 0x8;
    const int WM_NCHITTEST = 0x84, WM_MOUSEACTIVATE = 0x21, MA_NOACTIVATE = 3, HTTRANSPARENT = -1;

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
        IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);

    readonly Rectangle area;
    IntPtr hBmp = IntPtr.Zero, memDc = IntPtr.Zero, oldBmp = IntPtr.Zero;

    public EdgeOverlay(Rectangle area, Color color)
    {
        this.area = area;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Bounds = area;
        using (Bitmap bmp = Render(area.Width, area.Height, color))
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
            return cp;
        }
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_NCHITTEST) { m.Result = (IntPtr)HTTRANSPARENT; return; }
        if (m.Msg == WM_MOUSEACTIVATE) { m.Result = (IntPtr)MA_NOACTIVATE; return; }
        base.WndProc(ref m);
    }

    public void SetAlpha(byte alpha)
    {
        if (!IsHandleCreated || hBmp == IntPtr.Zero) return;
        IntPtr screenDc = GetDC(IntPtr.Zero);
        try
        {
            if (memDc == IntPtr.Zero)
            {
                memDc = CreateCompatibleDC(screenDc);
                oldBmp = SelectObject(memDc, hBmp);
            }
            POINT dst = new POINT(); dst.x = area.X; dst.y = area.Y;
            SIZE size = new SIZE(); size.cx = area.Width; size.cy = area.Height;
            POINT src = new POINT();
            BLENDFUNCTION bf = new BLENDFUNCTION();
            bf.BlendOp = 0; bf.BlendFlags = 0; bf.SourceConstantAlpha = alpha; bf.AlphaFormat = 1;   // AC_SRC_OVER, AC_SRC_ALPHA
            UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref bf, 2);   // ULW_ALPHA
        }
        finally { ReleaseDC(IntPtr.Zero, screenDc); }
    }

    protected override void Dispose(bool disposing)
    {
        if (memDc != IntPtr.Zero) { SelectObject(memDc, oldBmp); DeleteDC(memDc); memDc = IntPtr.Zero; }
        if (hBmp != IntPtr.Zero) { DeleteObject(hBmp); hBmp = IntPtr.Zero; }
        base.Dispose(disposing);
    }

    // Pre-multiplied ARGB glow: ~8px bright core, soft falloff, rounded corners, hotter corners.
    static Bitmap Render(int w, int h, Color color)
    {
        const float Core = 8f, Radius = 28f, GlowMax = 64f, CornerReach = 90f;
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        int[] px = new int[w * h];
        float hw = w / 2f, hh = h / 2f;
        float[,] corners = { { 0, 0 }, { w, 0 }, { 0, h }, { w, h } };
        int band = (int)GlowMax + 1;

        for (int y = 0; y < h; y++)
        {
            int dy = Math.Min(y, h - 1 - y);
            for (int x = 0; x < w; x++)
            {
                if (dy > band && x == band && w - band > band) x = w - band;   // skip empty interior
                float fx = x + 0.5f - hw, fy = y + 0.5f - hh;
                float qx = Math.Abs(fx) - (hw - Radius), qy = Math.Abs(fy) - (hh - Radius);
                float ox = Math.Max(qx, 0f), oy = Math.Max(qy, 0f);
                float d = -((float)Math.Sqrt(ox * ox + oy * oy) + Math.Min(Math.Max(qx, qy), 0f) - Radius);
                if (d <= -0.5f || d > GlowMax) continue;

                float cover = Math.Min(1f, d + 0.5f);
                float i = d <= Core ? 1f - 0.15f * Math.Max(d, 0f) / Core
                                    : 0.85f * (float)Math.Exp(-(d - Core) / 8f);
                if (i < 0.01f) continue;

                float cd = float.MaxValue;
                for (int c = 0; c < 4; c++)
                {
                    float cx = x - corners[c, 0], cy = y - corners[c, 1];
                    cd = Math.Min(cd, (float)Math.Sqrt(cx * cx + cy * cy));
                }
                float prox = cd < CornerReach * 2 ? (float)Math.Exp(-cd / (CornerReach * 0.75f)) : 0f;
                i = Math.Min(1f, i * (1f + 0.4f * prox));
                float white = 0.4f * prox;

                float a = i * cover;
                float r = color.R + (255 - color.R) * white;
                float g = color.G + (255 - color.G) * white;
                float b = color.B + (255 - color.B) * white;
                uint A = (uint)Math.Round(a * 255f);
                uint R = (uint)Math.Round(r * a), G = (uint)Math.Round(g * a), B = (uint)Math.Round(b * a);
                px[y * w + x] = unchecked((int)((A << 24) | (R << 16) | (G << 8) | B));
            }
        }

        BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        return bmp;
    }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Windows.Forms, System.Drawing

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$hex = $Color.TrimStart('#')
if ($hex.Length -ne 6) { throw "Color must be a 6-digit hex value, got '$Color'" }
$rgb = [System.Drawing.Color]::FromArgb(
    [Convert]::ToInt32($hex.Substring(0, 2), 16),
    [Convert]::ToInt32($hex.Substring(2, 2), 16),
    [Convert]::ToInt32($hex.Substring(4, 2), 16))

$forms = @()
try {
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $f = New-Object EdgeOverlay -ArgumentList $screen.Bounds, $rgb
        $f.Show()
        $f.SetAlpha(0)
        $forms += $f
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $DurationMs) {
        $t = $sw.ElapsedMilliseconds / $DurationMs * $Pulses
        $phase = $t - [math]::Floor($t)
        $alpha = [byte][math]::Round(255 * (0.5 - 0.5 * [math]::Cos(2 * [math]::PI * $phase)))   # smooth in/out
        foreach ($f in $forms) { $f.SetAlpha($alpha) }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 8
    }
} finally {
    foreach ($f in $forms) { $f.Close(); $f.Dispose() }
}
