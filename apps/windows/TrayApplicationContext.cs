using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Microsoft.Win32;

namespace QuotaRing;

internal sealed class UserPrefs
{
    public string SelectedProviderId { get; set; } = "antigravity";
    public string SelectedWindow { get; set; } = "5h"; // "5h" or "weekly"
    public int RefreshSeconds { get; set; } = 30;
}

public sealed class TrayApplicationContext : ApplicationContext
{
    private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunAppName = "QuotaRing";

    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly string _prefsPath;
    private UserPrefs _prefs;
    private MultiQuotaSnapshot? _latestSnapshot;
    private Icon? _currentIcon;

    public TrayApplicationContext()
    {
        string appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "QuotaRing");
        Directory.CreateDirectory(appData);
        _prefsPath = Path.Combine(appData, "settings.json");
        _prefs = LoadPrefs();

        _currentIcon = RingIconRenderer.CreateDualRingIcon(0, 0);
        _notifyIcon = new NotifyIcon
        {
            Icon = _currentIcon,
            Text = "QuotaRing",
            Visible = true,
            ContextMenuStrip = new ContextMenuStrip()
        };

        // Open menu on left click too for effortless inspection
        _notifyIcon.MouseUp += (_, e) =>
        {
            if (e.Button == MouseButtons.Left)
            {
                var mi = typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);
                mi?.Invoke(_notifyIcon, null);
            }
        };

        _timer = new System.Windows.Forms.Timer { Interval = Math.Max(10, _prefs.RefreshSeconds) * 1000 };
        _timer.Tick += (_, _) => RefreshData();

        RefreshData();
        _timer.Start();
    }

    private UserPrefs LoadPrefs()
    {
        try
        {
            if (File.Exists(_prefsPath))
            {
                var loaded = JsonSerializer.Deserialize<UserPrefs>(File.ReadAllText(_prefsPath));
                if (loaded is not null) return loaded;
            }
        }
        catch { /* ignore */ }
        return new UserPrefs();
    }

    private void SavePrefs()
    {
        try
        {
            File.WriteAllText(_prefsPath, JsonSerializer.Serialize(_prefs, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* ignore */ }
    }

    private void RefreshData()
    {
        var snapshot = QuotaFetcher.Shared.FetchAll();
        _latestSnapshot = snapshot;
        UpdateTrayVisual(snapshot);
        RebuildMenu(snapshot);
    }

    private ProviderQuota? ResolveActiveProvider(List<ProviderQuota> providers)
    {
        return providers.FirstOrDefault(p => string.Equals(p.Id, _prefs.SelectedProviderId, StringComparison.OrdinalIgnoreCase))
            ?? providers.FirstOrDefault();
    }

    private static double RemainingTimeFraction(QuotaWindow? window)
    {
        if (window is null || !window.ResetTime.HasValue || window.WindowSeconds <= 0) return 0.0;
        double remaining = (window.ResetTime.Value - DateTimeOffset.Now).TotalSeconds;
        return Math.Clamp(remaining / window.WindowSeconds, 0.0, 1.0);
    }

    private static string FormatShortCountdown(DateTimeOffset? resetTime)
    {
        if (!resetTime.HasValue) return "";
        TimeSpan diff = resetTime.Value - DateTimeOffset.Now;
        if (diff.TotalSeconds <= 0) return "已重置";
        if (diff.TotalDays >= 1) return $"{(int)diff.TotalDays}天{diff.Hours}时";
        if (diff.TotalHours >= 1) return $"{(int)diff.TotalHours}时{diff.Minutes}分";
        return $"{Math.Max(0, diff.Minutes)}分";
    }

    private static string FormatDetailedReset(DateTimeOffset? resetTime)
    {
        if (!resetTime.HasValue) return "";
        TimeSpan diff = resetTime.Value - DateTimeOffset.Now;
        string localStr = resetTime.Value.ToLocalTime().ToString("M月d日 HH:mm");
        if (diff.TotalSeconds <= 0) return $"已到重置时间 ({localStr})";
        if (diff.TotalDays >= 1) return $"{(int)diff.TotalDays}天{diff.Hours}小时后 ({localStr})";
        if (diff.TotalHours >= 1) return $"{(int)diff.TotalHours}小时{diff.Minutes}分后 ({localStr})";
        return $"{Math.Max(0, diff.Minutes)}分钟后 ({localStr})";
    }

    private static string FormatSyncAge(DateTimeOffset? syncedAt)
    {
        if (!syncedAt.HasValue) return "未知";
        TimeSpan age = DateTimeOffset.Now - syncedAt.Value;
        if (age.TotalSeconds < 60) return "刚刚";
        if (age.TotalMinutes < 60) return $"{(int)age.TotalMinutes} 分钟前";
        if (age.TotalHours < 24) return $"{(int)age.TotalHours} 小时前";
        return $"{(int)age.TotalDays} 天前";
    }

    private static string StatusDot(int pct) => pct >= 50 ? "●" : (pct >= 20 ? "◐" : "○");

    private void UpdateTrayVisual(MultiQuotaSnapshot snapshot)
    {
        var active = ResolveActiveProvider(snapshot.Providers);
        QuotaWindow? targetWindow = _prefs.SelectedWindow == "weekly"
            ? (active?.Weekly ?? active?.FiveHour)
            : (active?.FiveHour ?? active?.Weekly);

        double outer = targetWindow is not null ? targetWindow.Percent / 100.0 : 0.0;
        double inner = RemainingTimeFraction(targetWindow);

        var nextIcon = RingIconRenderer.CreateDualRingIcon(outer, inner);
        var oldIcon = _currentIcon;
        _currentIcon = nextIcon;
        _notifyIcon.Icon = nextIcon;
        oldIcon?.Dispose();

        // NotifyIcon.Text must be <= 63 chars on Windows
        string tip;
        if (active is null)
        {
            tip = "QuotaRing: 等待本地配额快照";
        }
        else
        {
            var parts = new List<string>();
            if (active.FiveHour is not null) parts.Add($"5h:{active.FiveHour.Percent}%");
            if (active.Weekly is not null) parts.Add($"W:{active.Weekly.Percent}%");
            tip = $"{active.Name} " + string.Join(" ", parts);
        }
        _notifyIcon.Text = tip.Length > 63 ? tip[..63] : tip;
    }

    private void RebuildMenu(MultiQuotaSnapshot snapshot)
    {
        var menu = new ContextMenuStrip();

        var legend = new ToolStripMenuItem("QuotaRing · 外圈剩余用量 / 内圈重置倒计时") { Enabled = false };
        menu.Items.Add(legend);
        menu.Items.Add(new ToolStripSeparator());

        if (snapshot.Providers.Count == 0)
        {
            menu.Items.Add(new ToolStripMenuItem("尚未检测到本地配额快照") { Enabled = false });
            menu.Items.Add(new ToolStripSeparator());
        }
        else
        {
            foreach (var p in snapshot.Providers)
            {
                string tier = string.IsNullOrEmpty(p.PlanTier) ? "" : $" · {p.PlanTier}";
                var header = new ToolStripMenuItem($"{p.Name}{tier}")
                {
                    Enabled = false,
                    Font = new Font(menu.Font, FontStyle.Bold)
                };
                menu.Items.Add(header);

                menu.Items.Add(new ToolStripMenuItem($"  {p.SourceLabel} · 同步于 {FormatSyncAge(p.SyncedAt)}") { Enabled = false });

                foreach (var g in p.Groups)
                {
                    if (p.Groups.Count > 1)
                    {
                        menu.Items.Add(new ToolStripMenuItem($"  [{g.DisplayName}]") { Enabled = false });
                    }
                    foreach (var b in g.Buckets)
                    {
                        string cd = FormatShortCountdown(b.ResetTime);
                        string suffix = string.IsNullOrEmpty(cd) ? "" : $" · {cd}";
                        menu.Items.Add(new ToolStripMenuItem($"  {StatusDot(b.Percent)} {b.DisplayName}: {b.Percent}%{suffix}") { Enabled = false });

                        if (b.ResetTime.HasValue)
                        {
                            menu.Items.Add(new ToolStripMenuItem($"      重置: {FormatDetailedReset(b.ResetTime)}") { Enabled = false });
                        }
                    }
                }

                menu.Items.Add(new ToolStripSeparator());
            }
        }

        // Provider selector
        var providerMenu = new ToolStripMenuItem("托盘展示品牌");
        foreach (var p in snapshot.Providers)
        {
            var pItem = new ToolStripMenuItem($"{p.Name} ({p.ShortBadge})")
            {
                Checked = string.Equals(_prefs.SelectedProviderId, p.Id, StringComparison.OrdinalIgnoreCase)
            };
            string capturedId = p.Id;
            pItem.Click += (_, _) =>
            {
                _prefs.SelectedProviderId = capturedId;
                SavePrefs();
                RefreshData();
            };
            providerMenu.DropDownItems.Add(pItem);
        }
        if (providerMenu.DropDownItems.Count == 0)
            providerMenu.DropDownItems.Add(new ToolStripMenuItem("暂无可用品牌") { Enabled = false });
        menu.Items.Add(providerMenu);

        // Window selector
        var windowMenu = new ToolStripMenuItem("托盘双环周期");
        var w5 = new ToolStripMenuItem("5 小时额度 (5)") { Checked = _prefs.SelectedWindow == "5h" };
        w5.Click += (_, _) => { _prefs.SelectedWindow = "5h"; SavePrefs(); RefreshData(); };
        var ww = new ToolStripMenuItem("周额度 (W)") { Checked = _prefs.SelectedWindow == "weekly" };
        ww.Click += (_, _) => { _prefs.SelectedWindow = "weekly"; SavePrefs(); RefreshData(); };
        windowMenu.DropDownItems.Add(w5);
        windowMenu.DropDownItems.Add(ww);
        menu.Items.Add(windowMenu);

        // Interval selector
        var intervalMenu = new ToolStripMenuItem("检查快照频率");
        foreach (var (sec, label) in new[] { (10, "每 10 秒"), (30, "每 30 秒（默认）"), (60, "每 1 分钟") })
        {
            var iItem = new ToolStripMenuItem(label) { Checked = _prefs.RefreshSeconds == sec };
            int capturedSec = sec;
            iItem.Click += (_, _) =>
            {
                _prefs.RefreshSeconds = capturedSec;
                SavePrefs();
                _timer.Interval = capturedSec * 1000;
                RefreshData();
            };
            intervalMenu.DropDownItems.Add(iItem);
        }
        menu.Items.Add(intervalMenu);

        menu.Items.Add(new ToolStripSeparator());

        var refreshItem = new ToolStripMenuItem("立即读取全部快照");
        refreshItem.Click += (_, _) => RefreshData();
        menu.Items.Add(refreshItem);

        var openSlotsItem = new ToolStripMenuItem("打开开放插槽目录 (Cursor / GrokBot...)");
        openSlotsItem.Click += (_, _) =>
        {
            Directory.CreateDirectory(QuotaFetcher.Shared.OpenSlotsDir);
            Process.Start(new ProcessStartInfo(QuotaFetcher.Shared.OpenSlotsDir) { UseShellExecute = true });
        };
        menu.Items.Add(openSlotsItem);

        var copyAgyItem = new ToolStripMenuItem("复制 agy 同步命令");
        copyAgyItem.Click += (_, _) => Clipboard.SetText("agy");
        menu.Items.Add(copyAgyItem);

        menu.Items.Add(new ToolStripSeparator());

        var startupItem = new ToolStripMenuItem("开机自动启动") { Checked = IsStartupEnabled() };
        startupItem.Click += (_, _) =>
        {
            ToggleStartup();
            RefreshData();
        };
        menu.Items.Add(startupItem);

        var exitItem = new ToolStripMenuItem("退出 QuotaRing");
        exitItem.Click += (_, _) => ExitThread();
        menu.Items.Add(exitItem);

        var oldMenu = _notifyIcon.ContextMenuStrip;
        _notifyIcon.ContextMenuStrip = menu;
        oldMenu?.Dispose();
    }

    private static bool IsStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, false);
        return key?.GetValue(RunAppName) is string s && !string.IsNullOrEmpty(s);
    }

    private static void ToggleStartup()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
        if (key is null) return;
        if (IsStartupEnabled())
        {
            key.DeleteValue(RunAppName, false);
        }
        else
        {
            string? exe = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exe))
            {
                key.SetValue(RunAppName, $"\"{exe}\"");
            }
        }
    }

    protected override void ExitThreadCore()
    {
        _timer.Stop();
        _timer.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _currentIcon?.Dispose();
        base.ExitThreadCore();
    }
}
