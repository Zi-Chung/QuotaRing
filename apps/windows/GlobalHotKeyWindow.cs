using System.Runtime.InteropServices;

namespace QuotaRing;

internal sealed class GlobalHotKeyWindow : NativeWindow, IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModNoRepeat = 0x4000;
    private const int HotKeyId = 1;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    private readonly Action _onTrigger;
    private bool _registered;

    public GlobalHotKeyWindow(Action onTrigger)
    {
        _onTrigger = onTrigger;
        CreateHandle(new CreateParams());
    }

    public void RegisterPreset(string preset)
    {
        Unregister();
        uint? vk = preset switch
        {
            "alt-q" => (uint)Keys.Q,
            "alt-r" => (uint)Keys.R,
            "alt-1" => (uint)Keys.D1,
            _ => null
        };
        if (vk.HasValue)
        {
            _registered = RegisterHotKey(Handle, HotKeyId, ModAlt | ModNoRepeat, vk.Value);
        }
    }

    public void Unregister()
    {
        if (_registered && Handle != IntPtr.Zero)
        {
            UnregisterHotKey(Handle, HotKeyId);
            _registered = false;
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotKey && m.WParam.ToInt32() == HotKeyId)
        {
            _onTrigger();
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        Unregister();
        if (Handle != IntPtr.Zero)
        {
            DestroyHandle();
        }
    }
}
