using System.Globalization;
using System.Text.Json;

namespace QuotaRing;

public sealed record QuotaWindow(
    string Label,
    string ShortTag,
    int Percent,
    DateTimeOffset? ResetTime,
    double WindowSeconds
);

public sealed record ModelBucketInfo(
    string Id,
    string DisplayName,
    string Window,
    int Percent,
    DateTimeOffset? ResetTime
);

public sealed record ModelGroupInfo(
    string DisplayName,
    string Description,
    List<ModelBucketInfo> Buckets
);

public sealed record ProviderQuota(
    string Id,
    string Name,
    string ShortBadge,
    string SourceLabel,
    string? PlanTier,
    DateTimeOffset? SyncedAt,
    QuotaWindow? FiveHour,
    QuotaWindow? Weekly,
    List<ModelGroupInfo> Groups
);

public sealed record MultiQuotaSnapshot(
    List<ProviderQuota> Providers,
    string OpenSlotsDir,
    DateTimeOffset FetchedAt
);

public sealed class QuotaFetcher
{
    public static QuotaFetcher Shared { get; } = new();

    private readonly string _userHome = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public string AgySnapshotPath =>
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("AGY_QUOTA_SNAPSHOT"))
            ? Environment.GetEnvironmentVariable("AGY_QUOTA_SNAPSHOT")!
            : Path.Combine(_userHome, ".gemini", "antigravity-cli", "quota-snapshot.json");

    public string CodexSessionsDir => Path.Combine(_userHome, ".codex", "sessions");

    public string OpenSlotsDir => Path.Combine(_userHome, ".config", "quota-bar", "providers");

    public MultiQuotaSnapshot FetchAll()
    {
        try { Directory.CreateDirectory(OpenSlotsDir); } catch { /* ignore */ }

        var providers = new List<ProviderQuota>();

        var agy = LoadAntigravity();
        if (agy is not null) providers.Add(agy);

        var codex = LoadCodex();
        if (codex is not null) providers.Add(codex);

        foreach (var slot in LoadOpenSlots())
        {
            int idx = providers.FindIndex(p => string.Equals(p.Id, slot.Id, StringComparison.OrdinalIgnoreCase));
            if (idx >= 0) providers[idx] = slot;
            else providers.Add(slot);
        }

        return new MultiQuotaSnapshot(providers, OpenSlotsDir, DateTimeOffset.Now);
    }

    private static DateTimeOffset? ParseIso(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return DateTimeOffset.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind,
            out var dto)
            ? dto
            : null;
    }

    private static DateTimeOffset? ResolveReset(JsonElement el)
    {
        if (el.TryGetProperty("resetTime", out var rt) && rt.ValueKind == JsonValueKind.String)
        {
            var parsed = ParseIso(rt.GetString());
            if (parsed.HasValue) return parsed;
        }
        if (el.TryGetProperty("resetsAt", out var ra) && ra.ValueKind == JsonValueKind.Number && ra.TryGetDouble(out double ts) && ts > 0)
        {
            long seconds = ts > 1_000_000_000_000 ? (long)(ts / 1000.0) : (long)ts;
            return DateTimeOffset.FromUnixTimeSeconds(seconds);
        }
        return null;
    }

    private static int? ResolvePercent(JsonElement el)
    {
        if (el.TryGetProperty("remainingPercent", out var rp) && rp.ValueKind == JsonValueKind.Number && rp.TryGetDouble(out double rpv))
            return (int)Math.Round(Math.Clamp(rpv, 0.0, 100.0));
        if (el.TryGetProperty("remainingFraction", out var rf) && rf.ValueKind == JsonValueKind.Number && rf.TryGetDouble(out double rfv))
            return (int)Math.Round(Math.Clamp(rfv, 0.0, 1.0) * 100.0);
        if (el.TryGetProperty("usedPercent", out var up) && up.ValueKind == JsonValueKind.Number && up.TryGetDouble(out double upv))
            return (int)Math.Round(Math.Clamp(100.0 - upv, 0.0, 100.0));
        return null;
    }

    private static string? GetStringOrNull(JsonElement el, string prop)
    {
        return el.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    }

    private static double? GetDoubleOrNull(JsonElement el, string prop)
    {
        return el.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out double d) ? d : null;
    }

    // 1. Antigravity official agy CLI statusLine snapshot
    private ProviderQuota? LoadAntigravity()
    {
        if (!File.Exists(AgySnapshotPath)) return null;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(AgySnapshotPath));
            var root = doc.RootElement;
            if (!root.TryGetProperty("buckets", out var bucketsEl) || bucketsEl.ValueKind != JsonValueKind.Array)
                return null;

            QuotaWindow? fiveHour = null;
            QuotaWindow? weekly = null;
            var geminiBuckets = new List<ModelBucketInfo>();
            var thirdPartyBuckets = new List<ModelBucketInfo>();
            var otherBuckets = new List<ModelBucketInfo>();

            foreach (var b in bucketsEl.EnumerateArray())
            {
                string id = GetStringOrNull(b, "id") ?? "";
                if (string.IsNullOrEmpty(id)) continue;

                double frac = Math.Clamp(GetDoubleOrNull(b, "remainingFraction") ?? 1.0, 0.0, 1.0);
                int pct = (int)Math.Round(frac * 100.0);
                DateTimeOffset? reset = ParseIso(GetStringOrNull(b, "resetTime"));
                string lower = id.ToLowerInvariant();
                bool isWeekly = lower.Contains("weekly");
                bool is5h = lower.Contains("5h");
                string win = isWeekly ? "weekly" : (is5h ? "5h" : "other");
                string label = isWeekly ? "周额度" : (is5h ? "5 小时额度" : id);

                var info = new ModelBucketInfo(id, label, win, pct, reset);
                if (lower.StartsWith("gemini"))
                {
                    geminiBuckets.Add(info);
                    if (is5h) fiveHour = new QuotaWindow("5 小时额度", "5", pct, reset, 5 * 3600);
                    else if (isWeekly) weekly = new QuotaWindow("周额度", "W", pct, reset, 7 * 24 * 3600);
                }
                else if (lower.StartsWith("3p") || lower.Contains("claude") || lower.Contains("gpt"))
                {
                    thirdPartyBuckets.Add(info);
                }
                else
                {
                    otherBuckets.Add(info);
                }
            }

            if (geminiBuckets.Count == 0 && thirdPartyBuckets.Count == 0 && otherBuckets.Count == 0)
                return null;

            static int Rank(string w) => w == "5h" ? 0 : (w == "weekly" ? 1 : 2);
            var groups = new List<ModelGroupInfo>();
            if (geminiBuckets.Count > 0)
                groups.Add(new ModelGroupInfo("Google Gemini", "Gemini 系列模型配额池", geminiBuckets.OrderBy(x => Rank(x.Window)).ToList()));
            if (thirdPartyBuckets.Count > 0)
                groups.Add(new ModelGroupInfo("第三方模型 (3P)", "Claude / GPT 等第三方模型", thirdPartyBuckets.OrderBy(x => Rank(x.Window)).ToList()));
            if (otherBuckets.Count > 0)
                groups.Add(new ModelGroupInfo("其他配额", "", otherBuckets.OrderBy(x => Rank(x.Window)).ToList()));

            return new ProviderQuota(
                "antigravity",
                "Antigravity",
                "A",
                "官方 agy CLI 快照",
                GetStringOrNull(root, "planTier"),
                ParseIso(GetStringOrNull(root, "updatedAt")),
                fiveHour,
                weekly,
                groups
            );
        }
        catch
        {
            return null;
        }
    }

    // 2. OpenAI Codex local JSONL session logs (~/.codex/sessions/**/*.jsonl)
    private ProviderQuota? LoadCodex()
    {
        if (!Directory.Exists(CodexSessionsDir)) return null;
        try
        {
            var files = Directory.EnumerateFiles(CodexSessionsDir, "*.jsonl", SearchOption.AllDirectories)
                .Select(path => new FileInfo(path))
                .OrderByDescending(fi => fi.LastWriteTimeUtc)
                .Take(12)
                .ToList();

            foreach (var fi in files)
            {
                var parsed = ParseCodexFile(fi);
                if (parsed is not null) return parsed;
            }
        }
        catch { /* ignore */ }
        return null;
    }

    private static ProviderQuota? ParseCodexFile(FileInfo file)
    {
        try
        {
            var lines = File.ReadAllLines(file.FullName);
            for (int i = lines.Length - 1; i >= 0; i--)
            {
                string line = lines[i];
                if (!line.Contains("\"rate_limits\"", StringComparison.Ordinal)) continue;

                using var doc = JsonDocument.Parse(line);
                var root = doc.RootElement;
                if (!root.TryGetProperty("payload", out var payload)) continue;
                if (!payload.TryGetProperty("rate_limits", out var rl) || rl.ValueKind != JsonValueKind.Object) continue;

                var rawWindows = new List<JsonElement>();
                if (rl.TryGetProperty("primary", out var p1) && p1.ValueKind == JsonValueKind.Object) rawWindows.Add(p1);
                if (rl.TryGetProperty("secondary", out var p2) && p2.ValueKind == JsonValueKind.Object) rawWindows.Add(p2);
                if (rawWindows.Count == 0) continue;

                DateTimeOffset synced = ParseIso(GetStringOrNull(root, "timestamp")) ?? new DateTimeOffset(file.LastWriteTimeUtc, TimeSpan.Zero);
                string? planRaw = GetStringOrNull(rl, "plan_type");

                QuotaWindow? fiveHour = null;
                QuotaWindow? weekly = null;
                var buckets = new List<ModelBucketInfo>();

                foreach (var w in rawWindows)
                {
                    double? used = GetDoubleOrNull(w, "used_percent");
                    if (!used.HasValue) continue;

                    int remPct = (int)Math.Round(Math.Clamp(100.0 - used.Value, 0.0, 100.0));
                    double winMins = GetDoubleOrNull(w, "window_minutes") ?? 0;
                    double resetEpoch = GetDoubleOrNull(w, "resets_at") ?? 0;
                    DateTimeOffset? resetTime = resetEpoch > 0 ? DateTimeOffset.FromUnixTimeSeconds((long)resetEpoch) : null;

                    if (winMins > 0 && winMins <= 360)
                    {
                        int hrs = (int)Math.Round(winMins / 60.0);
                        string label = $"{hrs} 小时额度";
                        fiveHour = new QuotaWindow(label, hrs.ToString(CultureInfo.InvariantCulture), remPct, resetTime, winMins * 60.0);
                        buckets.Add(new ModelBucketInfo("codex-5h", label, "5h", remPct, resetTime));
                    }
                    else
                    {
                        double secs = winMins > 0 ? winMins * 60.0 : 7 * 24 * 3600;
                        string label = (winMins == 10080 || winMins == 0) ? "周额度" : $"{(int)Math.Round(winMins / 1440.0)} 天额度";
                        weekly = new QuotaWindow(label, "W", remPct, resetTime, secs);
                        buckets.Add(new ModelBucketInfo("codex-weekly", label, "weekly", remPct, resetTime));
                    }
                }

                if (buckets.Count == 0) continue;

                string? planLabel = planRaw?.ToLowerInvariant() switch
                {
                    "prolite" => "Pro Lite",
                    "pro" => "Pro",
                    "plus" => "Plus",
                    "team" => "Team",
                    _ => planRaw
                };

                return new ProviderQuota(
                    "codex",
                    "Codex",
                    "C",
                    "本地 ~/.codex 会话日志",
                    planLabel,
                    synced,
                    fiveHour,
                    weekly,
                    new List<ModelGroupInfo>
                    {
                        new("OpenAI Codex", "来自本地会话日志 rate_limits", buckets.OrderBy(x => x.Window == "5h" ? 0 : 1).ToList())
                    }
                );
            }
        }
        catch { /* ignore */ }
        return null;
    }

    // 3. Open Provider Slots (~/.config/quota-bar/providers/*.json)
    private List<ProviderQuota> LoadOpenSlots()
    {
        var list = new List<ProviderQuota>();
        if (!Directory.Exists(OpenSlotsDir)) return list;

        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(OpenSlotsDir, "*.json").OrderBy(p => p, StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            return list;
        }

        foreach (var path in files)
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                var root = doc.RootElement;
                string stem = Path.GetFileNameWithoutExtension(path);
                string id = (GetStringOrNull(root, "id") ?? stem).ToLowerInvariant();
                string name = GetStringOrNull(root, "name") ?? CultureInfo.InvariantCulture.TextInfo.ToTitleCase(stem);
                string badgeRaw = GetStringOrNull(root, "shortBadge") ?? GetStringOrNull(root, "shortName") ?? name;
                string badge = badgeRaw[..Math.Min(2, badgeRaw.Length)].ToUpperInvariant();
                DateTimeOffset? synced = ParseIso(GetStringOrNull(root, "updatedAt"))
                    ?? new DateTimeOffset(File.GetLastWriteTimeUtc(path), TimeSpan.Zero);

                QuotaWindow? fiveHour = null;
                if (root.TryGetProperty("fiveHour", out var fhEl) && fhEl.ValueKind == JsonValueKind.Object)
                {
                    int? pct = ResolvePercent(fhEl);
                    if (pct.HasValue)
                    {
                        double mins = GetDoubleOrNull(fhEl, "windowMinutes") ?? 300.0;
                        fiveHour = new QuotaWindow(GetStringOrNull(fhEl, "label") ?? "5 小时额度", "5", pct.Value, ResolveReset(fhEl), mins * 60.0);
                    }
                }

                QuotaWindow? weekly = null;
                if (root.TryGetProperty("weekly", out var wkEl) && wkEl.ValueKind == JsonValueKind.Object)
                {
                    int? pct = ResolvePercent(wkEl);
                    if (pct.HasValue)
                    {
                        double mins = GetDoubleOrNull(wkEl, "windowMinutes") ?? 10080.0;
                        weekly = new QuotaWindow(GetStringOrNull(wkEl, "label") ?? "周额度", "W", pct.Value, ResolveReset(wkEl), mins * 60.0);
                    }
                }

                var groups = new List<ModelGroupInfo>();
                if (root.TryGetProperty("groups", out var groupsEl) && groupsEl.ValueKind == JsonValueKind.Array)
                {
                    foreach (var g in groupsEl.EnumerateArray())
                    {
                        string? gName = GetStringOrNull(g, "displayName");
                        if (string.IsNullOrEmpty(gName)) continue;
                        var bs = new List<ModelBucketInfo>();
                        if (g.TryGetProperty("buckets", out var bArr) && bArr.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var b in bArr.EnumerateArray())
                            {
                                int? pct = ResolvePercent(b);
                                if (!pct.HasValue) continue;
                                bs.Add(new ModelBucketInfo(
                                    GetStringOrNull(b, "id") ?? Guid.NewGuid().ToString("N"),
                                    GetStringOrNull(b, "displayName") ?? "额度",
                                    GetStringOrNull(b, "window") ?? "other",
                                    pct.Value,
                                    ResolveReset(b)
                                ));
                            }
                        }
                        if (bs.Count > 0)
                            groups.Add(new ModelGroupInfo(gName, GetStringOrNull(g, "description") ?? "", bs));
                    }
                }
                else
                {
                    var autoBuckets = new List<ModelBucketInfo>();
                    if (fiveHour is not null)
                        autoBuckets.Add(new ModelBucketInfo($"{id}-5h", fiveHour.Label, "5h", fiveHour.Percent, fiveHour.ResetTime));
                    if (weekly is not null)
                        autoBuckets.Add(new ModelBucketInfo($"{id}-weekly", weekly.Label, "weekly", weekly.Percent, weekly.ResetTime));
                    if (autoBuckets.Count > 0)
                        groups.Add(new ModelGroupInfo(name, $"来自开放插槽 {Path.GetFileName(path)}", autoBuckets));
                }

                if (fiveHour is null && weekly is null && groups.Count == 0) continue;

                list.Add(new ProviderQuota(
                    id,
                    name,
                    badge,
                    $"开放插槽 ({Path.GetFileName(path)})",
                    GetStringOrNull(root, "planTier"),
                    synced,
                    fiveHour,
                    weekly,
                    groups
                ));
            }
            catch { /* ignore invalid slot file */ }
        }

        return list;
    }
}
