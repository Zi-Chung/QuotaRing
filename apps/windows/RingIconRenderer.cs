using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace QuotaRing;

public static class RingIconRenderer
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static bool IsLightTaskbar()
    {
        try
        {
            object? val = Registry.GetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "SystemUsesLightTheme",
                0);
            return val is int i && i == 1;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Creates a high-DPI 32x32 concentric dual-ring Icon:
    /// - Outer ring: remaining quota (0..1)
    /// - Inner ring: remaining countdown until reset (0..1)
    /// Caller owns the returned Icon and must Dispose() it.
    /// </summary>
    public static Icon CreateDualRingIcon(double outerFraction, double innerFraction)
    {
        const int size = 32;
        bool lightTaskbar = IsLightTaskbar();
        Color baseColor = lightTaskbar ? Color.FromArgb(255, 24, 24, 27) : Color.White;
        Color trackColor = Color.FromArgb(62, baseColor);
        Color innerColor = Color.FromArgb(215, baseColor);

        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);

            DrawRing(g, size, inset: 3.5f, width: 3.8f, fraction: outerFraction, activeColor: baseColor, trackColor: trackColor);
            DrawRing(g, size, inset: 9.8f, width: 3.4f, fraction: innerFraction, activeColor: innerColor, trackColor: trackColor);
        }

        IntPtr hIcon = bmp.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(hIcon);
            return (Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    private static void DrawRing(
        Graphics g,
        int canvasSize,
        float inset,
        float width,
        double fraction,
        Color activeColor,
        Color trackColor)
    {
        var rect = new RectangleF(inset, inset, canvasSize - inset * 2f, canvasSize - inset * 2f);

        using (var trackPen = new Pen(trackColor, width))
        {
            g.DrawEllipse(trackPen, rect);
        }

        double clamped = Math.Clamp(fraction, 0.0, 1.0);
        if (clamped <= 0.005) return;

        using var activePen = new Pen(activeColor, width);
        bool useFlatCap = clamped > 0.85 && clamped < 0.995;
        activePen.StartCap = useFlatCap ? LineCap.Flat : LineCap.Round;
        activePen.EndCap = useFlatCap ? LineCap.Flat : LineCap.Round;

        float sweep = (float)(clamped * 360.0);
        g.DrawArc(activePen, rect, -90f, sweep);
    }
}
