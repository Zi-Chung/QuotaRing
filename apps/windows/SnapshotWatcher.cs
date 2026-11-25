namespace QuotaRing;

/// Watches local quota snapshot directories with FileSystemWatcher (debounced 250ms)
/// so updates from `agy`, Codex JSONL logs, or Open Slot JSON files refresh immediately.
internal sealed class SnapshotWatcher : IDisposable
{
    private readonly List<FileSystemWatcher> _watchers = new();
    private readonly SynchronizationContext? _uiContext;
    private readonly Action _onChanged;
    private readonly System.Threading.Timer _debounceTimer;
    private bool _disposed;

    public SnapshotWatcher(Action onChanged)
    {
        _onChanged = onChanged;
        _uiContext = SynchronizationContext.Current;
        _debounceTimer = new System.Threading.Timer(_ => DispatchChange(), null, Timeout.Infinite, Timeout.Infinite);
    }

    public void Start()
    {
        Stop();
        string agyDir = Path.GetDirectoryName(QuotaFetcher.Shared.AgySnapshotPath) ?? "";
        AddWatcher(agyDir, "*.json", includeSubdirs: false);
        AddWatcher(QuotaFetcher.Shared.OpenSlotsDir, "*.json", includeSubdirs: false);
        AddWatcher(QuotaFetcher.Shared.CodexSessionsDir, "*.jsonl", includeSubdirs: true);
    }

    public void Stop()
    {
        foreach (var w in _watchers)
        {
            w.EnableRaisingEvents = false;
            w.Dispose();
        }
        _watchers.Clear();
    }

    private void AddWatcher(string dir, string filter, bool includeSubdirs)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir)) return;
        try
        {
            var watcher = new FileSystemWatcher(dir, filter)
            {
                IncludeSubdirectories = includeSubdirs,
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime | NotifyFilters.Size
            };
            watcher.Changed += OnFsEvent;
            watcher.Created += OnFsEvent;
            watcher.Renamed += OnFsEvent;
            watcher.Deleted += OnFsEvent;
            watcher.EnableRaisingEvents = true;
            _watchers.Add(watcher);
        }
        catch
        {
            // Ignore unwatched paths
        }
    }

    private void OnFsEvent(object sender, FileSystemEventArgs e)
    {
        if (_disposed) return;
        _debounceTimer.Change(250, Timeout.Infinite);
    }

    private void DispatchChange()
    {
        if (_disposed) return;
        if (_uiContext is not null)
        {
            _uiContext.Post(_ =>
            {
                if (!_disposed) _onChanged();
            }, null);
        }
        else
        {
            _onChanged();
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Stop();
        _debounceTimer.Dispose();
    }
}
