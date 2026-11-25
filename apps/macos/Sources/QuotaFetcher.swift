import Foundation

// MARK: - Unified Multi-Provider Models

struct QuotaWindow {
    let label: String          // e.g. "5 小时额度", "周额度"
    let shortTag: String       // e.g. "5", "W"
    let percent: Int           // remaining percent 0..100
    let resetTime: String      // ISO8601 string
    let windowSeconds: TimeInterval
}

struct ModelBucketInfo {
    let id: String
    let displayName: String
    let window: String
    let percent: Int
    let resetTime: String
    let description: String
    let windowSeconds: TimeInterval
}

struct ModelGroupInfo {
    let displayName: String
    let description: String
    var buckets: [ModelBucketInfo]
}

struct ProviderQuota {
    let id: String             // "antigravity", "codex", "cursor", "grokbot", ...
    let name: String           // "Antigravity", "Codex", "Cursor", ...
    let shortBadge: String     // "A", "C", "Cu", "G", ...
    let symbolName: String     // SF Symbol name for menu header
    let sourceLabel: String    // "官方 agy CLI 快照", "本地 ~/.codex 会话日志", "开放插槽"
    let isOpenSlot: Bool
    var planTier: String?
    var syncedAt: Date?
    var fiveHour: QuotaWindow?
    var weekly: QuotaWindow?
    var monthly: QuotaWindow?
    var groups: [ModelGroupInfo]
}

struct EditableSlotDraft {
    var id: String = "cursor"
    var name: String = "Cursor"
    var shortBadge: String = "Cu"
    var planTier: String = "Pro"
    var windowKind: String = "monthly" // "5h", "weekly", "monthly"
    var remainingPercent: Double = 80
    var resetDate: Date = Date().addingTimeInterval(30 * 24 * 3600)
}

struct MultiQuotaSnapshot {
    let providers: [ProviderQuota]
    let providersDirPath: String
    let fetchedAt: Date
}

// MARK: - Antigravity Snapshot Decoding

private struct AgySnapshotModel: Decodable {
    let id: String?
    let display_name: String?
}

private struct AgySnapshotBucket: Decodable {
    let id: String
    let remainingFraction: Double?
    let remainingAmount: Double?
    let resetTime: String?
    let resetInSeconds: Int?
    let disabled: Bool?
}

private struct AgySnapshotFile: Decodable {
    let version: Int?
    let source: String?
    let updatedAt: String?
    let planTier: String?
    let model: AgySnapshotModel?
    let buckets: [AgySnapshotBucket]?
}

// MARK: - Open Slot Provider JSON Decoding

private struct SlotWindowInput: Decodable {
    let label: String?
    let shortTag: String?
    let remainingPercent: Double?
    let usedPercent: Double?
    let remainingFraction: Double?
    let resetTime: String?
    let resetsAt: Double?
    let windowMinutes: Double?
}

private struct SlotBucketInput: Decodable {
    let id: String?
    let displayName: String?
    let window: String?
    let remainingPercent: Double?
    let usedPercent: Double?
    let remainingFraction: Double?
    let resetTime: String?
    let resetsAt: Double?
    let windowMinutes: Double?
    let description: String?
}

private struct SlotGroupInput: Decodable {
    let displayName: String
    let description: String?
    let buckets: [SlotBucketInput]?
}

private struct SlotProviderFile: Decodable {
    let id: String?
    let name: String?
    let shortBadge: String?
    let shortName: String?
    let planTier: String?
    let updatedAt: String?
    let fiveHour: SlotWindowInput?
    let weekly: SlotWindowInput?
    let monthly: SlotWindowInput?
    let groups: [SlotGroupInput]?
}

// MARK: - Local Read-Only Multi-Provider Fetcher

class QuotaFetcher {
    static let shared = QuotaFetcher()

    let agySnapshotURL: URL = {
        if let envPath = ProcessInfo.processInfo.environment["AGY_QUOTA_SNAPSHOT"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/quota-snapshot.json")
    }()

    let agyAXSnapshotURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quota-bar/antigravity-ax-snapshot.json")
    }()

    let codexSessionsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }()

    let openSlotsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quota-bar/providers")
    }()

    private func parseISO8601(_ str: String?) -> Date? {
        guard let str = str, !str.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: str) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: str)
    }

    private func toISO8601(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }

    private func resolvePercent(remainingPercent: Double?, usedPercent: Double?, remainingFraction: Double?) -> Int? {
        if let rp = remainingPercent {
            return Int(round(max(0.0, min(100.0, rp))))
        }
        if let rf = remainingFraction {
            return Int(round(max(0.0, min(1.0, rf)) * 100.0))
        }
        if let up = usedPercent {
            return Int(round(max(0.0, min(100.0, 100.0 - up))))
        }
        return nil
    }

    private func resolveResetISO(resetTime: String?, resetsAt: Double?) -> String {
        if let rt = resetTime, !rt.isEmpty { return rt }
        if let ts = resetsAt, ts > 0 {
            let seconds = ts > 1_000_000_000_000 ? ts / 1000.0 : ts
            return toISO8601(Date(timeIntervalSince1970: seconds))
        }
        return ""
    }

    func fetchAll(completion: @escaping (MultiQuotaSnapshot) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.createDirectory(at: self.openSlotsDir, withIntermediateDirectories: true)

            var providers: [ProviderQuota] = []
            if let agy = self.loadAntigravity() {
                providers.append(agy)
            }
            if let codex = self.loadCodex() {
                providers.append(codex)
            }
            for sp in self.loadOpenSlots() {
                if let idx = providers.firstIndex(where: { $0.id == sp.id }) {
                    providers[idx] = sp
                } else {
                    providers.append(sp)
                }
            }

            let snapshot = MultiQuotaSnapshot(
                providers: providers,
                providersDirPath: self.openSlotsDir.path,
                fetchedAt: Date()
            )
            DispatchQueue.main.async {
                completion(snapshot)
            }
        }
    }

    // MARK: 1. Antigravity Official CLI Snapshot & Optional AX UI Snapshot (Newest Wins)

    private func decodeAgySnapshot(at url: URL) -> (snap: AgySnapshotFile, updatedAt: Date)? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(AgySnapshotFile.self, from: data),
              let buckets = snap.buckets, !buckets.isEmpty else {
            return nil
        }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let dt = parseISO8601(snap.updatedAt) ?? mtime
        return (snap, dt)
    }

    private func loadAntigravity() -> ProviderQuota? {
        let cliLoaded = decodeAgySnapshot(at: agySnapshotURL)
        let axLoaded = decodeAgySnapshot(at: agyAXSnapshotURL)

        let chosen: (snap: AgySnapshotFile, updatedAt: Date, sourceLabel: String)?
        switch (cliLoaded, axLoaded) {
        case let (c?, a?):
            if a.updatedAt > c.updatedAt {
                chosen = (a.snap, a.updatedAt, "后台额度页自动同步")
            } else {
                chosen = (c.snap, c.updatedAt, "官方 agy CLI 快照")
            }
        case let (c?, nil):
            chosen = (c.snap, c.updatedAt, "官方 agy CLI 快照")
        case let (nil, a?):
            chosen = (a.snap, a.updatedAt, "后台额度页自动同步")
        case (nil, nil):
            chosen = nil
        }

        guard let selected = chosen, let buckets = selected.snap.buckets, !buckets.isEmpty else {
            return nil
        }
        let snap = selected.snap
        let fallbackPlanTier = snap.planTier ?? cliLoaded?.snap.planTier

        var fiveHour: QuotaWindow?
        var weekly: QuotaWindow?
        var geminiBuckets: [ModelBucketInfo] = []
        var thirdPartyBuckets: [ModelBucketInfo] = []
        var otherBuckets: [ModelBucketInfo] = []

        for b in buckets {
            let fraction = max(0.0, min(1.0, b.remainingFraction ?? 1.0))
            let percent = Int(round(fraction * 100.0))
            let reset = b.resetTime ?? ""
            let lowerId = b.id.lowercased()
            let isMonthly = lowerId.contains("monthly")
            let isWeekly = lowerId.contains("weekly")
            let is5h = lowerId.contains("5h")
            let window = isMonthly ? "monthly" : (isWeekly ? "weekly" : (is5h ? "5h" : "other"))
            let label = isMonthly ? "月额度" : (isWeekly ? "周额度" : (is5h ? "5 小时额度" : b.id))
            let winSecs: TimeInterval = isMonthly ? (30 * 24 * 3600) : (isWeekly ? (7 * 24 * 3600) : (5 * 3600))

            let info = ModelBucketInfo(
                id: b.id,
                displayName: label,
                window: window,
                percent: percent,
                resetTime: reset,
                description: b.id,
                windowSeconds: winSecs
            )

            if lowerId.hasPrefix("gemini") {
                geminiBuckets.append(info)
                if is5h {
                    fiveHour = QuotaWindow(label: "5 小时额度", shortTag: "5", percent: percent, resetTime: reset, windowSeconds: 5 * 3600)
                } else if isWeekly {
                    weekly = QuotaWindow(label: "周额度", shortTag: "W", percent: percent, resetTime: reset, windowSeconds: 7 * 24 * 3600)
                }
            } else if lowerId.hasPrefix("3p") || lowerId.contains("claude") || lowerId.contains("gpt") {
                thirdPartyBuckets.append(info)
            } else {
                otherBuckets.append(info)
            }
        }

        let sortOrder: (ModelBucketInfo, ModelBucketInfo) -> Bool = { a, b in
            let rank: (String) -> Int = { $0 == "5h" ? 0 : ($0 == "weekly" ? 1 : 2) }
            if rank(a.window) != rank(b.window) { return rank(a.window) < rank(b.window) }
            return a.id < b.id
        }

        var groups: [ModelGroupInfo] = []
        if !geminiBuckets.isEmpty {
            groups.append(ModelGroupInfo(displayName: "Google Gemini", description: "Gemini 系列模型配额池", buckets: geminiBuckets.sorted(by: sortOrder)))
        }
        if !thirdPartyBuckets.isEmpty {
            groups.append(ModelGroupInfo(displayName: "第三方模型 (3P)", description: "Claude / GPT 等第三方模型", buckets: thirdPartyBuckets.sorted(by: sortOrder)))
        }
        if !otherBuckets.isEmpty {
            groups.append(ModelGroupInfo(displayName: "其他配额", description: "", buckets: otherBuckets.sorted(by: sortOrder)))
        }

        return ProviderQuota(
            id: "antigravity",
            name: "Antigravity",
            shortBadge: "A",
            symbolName: "sparkles",
            sourceLabel: selected.sourceLabel,
            isOpenSlot: false,
            planTier: fallbackPlanTier,
            syncedAt: selected.updatedAt,
            fiveHour: fiveHour,
            weekly: weekly,
            monthly: nil,
            groups: groups
        )
    }

    // MARK: 2. Codex Local Session Log Reader

    private func loadCodex() -> ProviderQuota? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: codexSessionsDir.path) else { return nil }

        var candidates: [(url: URL, mtime: Date)] = []
        if let enumerator = fm.enumerator(
            at: codexSessionsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                   vals.isRegularFile == true {
                    candidates.append((url: fileURL, mtime: vals.contentModificationDate ?? .distantPast))
                }
            }
        }

        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.mtime > $1.mtime }

        for item in candidates.prefix(12) {
            if let parsed = parseCodexRateLimits(from: item.url, fallbackDate: item.mtime) {
                return parsed
            }
        }
        return nil
    }

    private func parseCodexRateLimits(from fileURL: URL, fallbackDate: Date) -> ProviderQuota? {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        for lineSub in lines.reversed() {
            guard lineSub.contains("\"rate_limits\"") else { continue }
            guard let lineData = lineSub.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any] else {
                continue
            }

            let primary = rateLimits["primary"] as? [String: Any]
            let secondary = rateLimits["secondary"] as? [String: Any]
            guard primary != nil || secondary != nil else { continue }

            let eventTime = parseISO8601(json["timestamp"] as? String) ?? fallbackDate
            let planType = rateLimits["plan_type"] as? String

            var fiveHour: QuotaWindow?
            var weekly: QuotaWindow?
            var monthly: QuotaWindow?
            var buckets: [ModelBucketInfo] = []

            for w in [primary, secondary].compactMap({ $0 }) {
                guard let usedPct = w["used_percent"] as? Double else { continue }
                let remainingPct = Int(round(max(0.0, min(100.0, 100.0 - usedPct))))
                let windowMinutes = (w["window_minutes"] as? Double) ?? Double(w["window_minutes"] as? Int ?? 0)
                let resetEpoch = (w["resets_at"] as? Double) ?? Double(w["resets_at"] as? Int ?? 0)
                let resetIso = resetEpoch > 0 ? toISO8601(Date(timeIntervalSince1970: resetEpoch)) : ""

                if windowMinutes > 0 && windowMinutes <= 360 {
                    let secs = windowMinutes * 60.0
                    let hours = Int(round(windowMinutes / 60.0))
                    let label = "\(hours) 小时额度"
                    fiveHour = QuotaWindow(label: label, shortTag: "\(hours)", percent: remainingPct, resetTime: resetIso, windowSeconds: secs)
                    buckets.append(ModelBucketInfo(id: "codex-5h", displayName: label, window: "5h", percent: remainingPct, resetTime: resetIso, description: "", windowSeconds: secs))
                } else if windowMinutes >= 20000 {
                    let secs = windowMinutes * 60.0
                    let label = "月额度"
                    monthly = QuotaWindow(label: label, shortTag: "M", percent: remainingPct, resetTime: resetIso, windowSeconds: secs)
                    buckets.append(ModelBucketInfo(id: "codex-monthly", displayName: label, window: "monthly", percent: remainingPct, resetTime: resetIso, description: "", windowSeconds: secs))
                } else {
                    let secs = windowMinutes > 0 ? windowMinutes * 60.0 : 7 * 24 * 3600
                    let label = windowMinutes == 10080 || windowMinutes == 0 ? "周额度" : "\(Int(round(windowMinutes / 1440.0))) 天额度"
                    weekly = QuotaWindow(label: label, shortTag: "W", percent: remainingPct, resetTime: resetIso, windowSeconds: secs)
                    buckets.append(ModelBucketInfo(id: "codex-weekly", displayName: label, window: "weekly", percent: remainingPct, resetTime: resetIso, description: "", windowSeconds: secs))
                }
            }

            guard !buckets.isEmpty else { continue }

            let tierLabel: String? = planType.map { raw in
                switch raw.lowercased() {
                case "prolite": return "Pro Lite"
                case "pro": return "Pro"
                case "plus": return "Plus"
                case "team": return "Team"
                default: return raw
                }
            }

            let rank: (String) -> Int = { $0 == "5h" ? 0 : ($0 == "weekly" ? 1 : 2) }
            return ProviderQuota(
                id: "codex",
                name: "Codex",
                shortBadge: "C",
                symbolName: "terminal",
                sourceLabel: "本地 ~/.codex 会话日志",
                isOpenSlot: false,
                planTier: tierLabel,
                syncedAt: eventTime,
                fiveHour: fiveHour,
                weekly: weekly,
                monthly: monthly,
                groups: [
                    ModelGroupInfo(
                        displayName: "OpenAI Codex",
                        description: "来自本地会话日志 rate_limits",
                        buckets: buckets.sorted { rank($0.window) < rank($1.window) }
                    )
                ]
            )
        }
        return nil
    }

    // MARK: 3. Open Provider Slots

    private func loadOpenSlots() -> [ProviderQuota] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: openSlotsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        let jsonFiles = items
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var results: [ProviderQuota] = []
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let slot = try? JSONDecoder().decode(SlotProviderFile.self, from: data) else {
                continue
            }

            let stem = fileURL.deletingPathExtension().lastPathComponent
            let id = (slot.id?.isEmpty == false ? slot.id! : stem).lowercased()
            let name = (slot.name?.isEmpty == false) ? slot.name! : stem.capitalized
            let rawBadge = slot.shortBadge ?? slot.shortName ?? String(name.prefix(2))
            let badge = String(rawBadge.prefix(2)).uppercased()

            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let syncedAt = parseISO8601(slot.updatedAt) ?? mtime

            var fiveHour: QuotaWindow?
            if let fh = slot.fiveHour,
               let pct = resolvePercent(remainingPercent: fh.remainingPercent, usedPercent: fh.usedPercent, remainingFraction: fh.remainingFraction) {
                let mins = fh.windowMinutes ?? 300.0
                fiveHour = QuotaWindow(
                    label: fh.label ?? "5 小时额度",
                    shortTag: (fh.shortTag?.isEmpty == false ? fh.shortTag! : "5"),
                    percent: pct,
                    resetTime: resolveResetISO(resetTime: fh.resetTime, resetsAt: fh.resetsAt),
                    windowSeconds: mins * 60.0
                )
            }

            var weekly: QuotaWindow?
            if let wk = slot.weekly,
               let pct = resolvePercent(remainingPercent: wk.remainingPercent, usedPercent: wk.usedPercent, remainingFraction: wk.remainingFraction) {
                let mins = wk.windowMinutes ?? 10080.0
                weekly = QuotaWindow(
                    label: wk.label ?? "周额度",
                    shortTag: (wk.shortTag?.isEmpty == false ? wk.shortTag! : "W"),
                    percent: pct,
                    resetTime: resolveResetISO(resetTime: wk.resetTime, resetsAt: wk.resetsAt),
                    windowSeconds: mins * 60.0
                )
            }

            var monthly: QuotaWindow?
            if let mo = slot.monthly,
               let pct = resolvePercent(remainingPercent: mo.remainingPercent, usedPercent: mo.usedPercent, remainingFraction: mo.remainingFraction) {
                let mins = mo.windowMinutes ?? 43200.0
                monthly = QuotaWindow(
                    label: mo.label ?? "月额度",
                    shortTag: (mo.shortTag?.isEmpty == false ? mo.shortTag! : "M"),
                    percent: pct,
                    resetTime: resolveResetISO(resetTime: mo.resetTime, resetsAt: mo.resetsAt),
                    windowSeconds: mins * 60.0
                )
            }

            var groups: [ModelGroupInfo] = []
            if let customGroups = slot.groups, !customGroups.isEmpty {
                for g in customGroups {
                    let bs: [ModelBucketInfo] = (g.buckets ?? []).compactMap { b in
                        guard let pct = resolvePercent(remainingPercent: b.remainingPercent, usedPercent: b.usedPercent, remainingFraction: b.remainingFraction) else {
                            return nil
                        }
                        let win = b.window ?? "other"
                        let defaultSecs: TimeInterval = (win == "5h") ? (5 * 3600) : (win == "monthly" ? (30 * 24 * 3600) : (7 * 24 * 3600))
                        let winSecs: TimeInterval = b.windowMinutes.map { $0 * 60.0 } ?? defaultSecs
                        return ModelBucketInfo(
                            id: b.id ?? UUID().uuidString,
                            displayName: b.displayName ?? "额度",
                            window: win,
                            percent: pct,
                            resetTime: resolveResetISO(resetTime: b.resetTime, resetsAt: b.resetsAt),
                            description: b.description ?? "",
                            windowSeconds: winSecs
                        )
                    }
                    if !bs.isEmpty {
                        groups.append(ModelGroupInfo(displayName: g.displayName, description: g.description ?? "", buckets: bs))
                    }
                }
            } else {
                var autoBuckets: [ModelBucketInfo] = []
                if let fh = fiveHour {
                    autoBuckets.append(ModelBucketInfo(id: "\(id)-5h", displayName: fh.label, window: "5h", percent: fh.percent, resetTime: fh.resetTime, description: "", windowSeconds: fh.windowSeconds))
                }
                if let wk = weekly {
                    autoBuckets.append(ModelBucketInfo(id: "\(id)-weekly", displayName: wk.label, window: "weekly", percent: wk.percent, resetTime: wk.resetTime, description: "", windowSeconds: wk.windowSeconds))
                }
                if let mo = monthly {
                    autoBuckets.append(ModelBucketInfo(id: "\(id)-monthly", displayName: mo.label, window: "monthly", percent: mo.percent, resetTime: mo.resetTime, description: "", windowSeconds: mo.windowSeconds))
                }
                if !autoBuckets.isEmpty {
                    groups.append(ModelGroupInfo(displayName: name, description: "来自开放插槽 \(fileURL.lastPathComponent)", buckets: autoBuckets))
                }
            }

            guard fiveHour != nil || weekly != nil || monthly != nil || !groups.isEmpty else { continue }

            let symbol: String
            switch id {
            case "cursor": symbol = "cube"
            case "grokbot", "grok": symbol = "bolt.circle"
            case "claude", "claudecode": symbol = "bubble.left.and.bubble.right"
            default: symbol = "puzzlepiece.extension"
            }

            results.append(ProviderQuota(
                id: id,
                name: name,
                shortBadge: badge,
                symbolName: symbol,
                sourceLabel: "开放插槽 (\(fileURL.lastPathComponent))",
                isOpenSlot: true,
                planTier: slot.planTier,
                syncedAt: syncedAt,
                fiveHour: fiveHour,
                weekly: weekly,
                monthly: monthly,
                groups: groups
            ))
        }

        return results
    }

    // MARK: 4. Watch Directories & Open Slot Persistence

    func directoriesToWatch() -> [URL] {
        var dirs: [URL] = [
            agySnapshotURL.deletingLastPathComponent(),
            agyAXSnapshotURL.deletingLastPathComponent(),
            openSlotsDir
        ]

        let fm = FileManager.default
        if fm.fileExists(atPath: codexSessionsDir.path) {
            dirs.append(codexSessionsDir)
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: Date())
            if let y = comps.year, let m = comps.month, let d = comps.day {
                let todayDir = codexSessionsDir
                    .appendingPathComponent(String(format: "%04d", y))
                    .appendingPathComponent(String(format: "%02d", m))
                    .appendingPathComponent(String(format: "%02d", d))
                let monthDir = todayDir.deletingLastPathComponent()
                if fm.fileExists(atPath: monthDir.path) { dirs.append(monthDir) }
                if fm.fileExists(atPath: todayDir.path) { dirs.append(todayDir) }
            }
        }
        return dirs
    }

    func saveOpenSlot(_ draft: EditableSlotDraft) {
        let cleanedId = draft.id
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "-", options: .regularExpression)
        let finalId = cleanedId.isEmpty ? "custom" : cleanedId
        let finalName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalId.capitalized : draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBadge = String((draft.shortBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(finalName.prefix(2)) : draft.shortBadge).prefix(2))

        let windowKey: String
        let windowLabel: String
        let windowMinutes: Int
        switch draft.windowKind {
        case "5h":
            windowKey = "fiveHour"
            windowLabel = "5 小时额度"
            windowMinutes = 300
        case "weekly":
            windowKey = "weekly"
            windowLabel = "周额度"
            windowMinutes = 10080
        default:
            windowKey = "monthly"
            windowLabel = "月额度"
            windowMinutes = 43200
        }

        var payload: [String: Any] = [
            "id": finalId,
            "name": finalName,
            "shortBadge": finalBadge,
            "updatedAt": toISO8601(Date()),
            windowKey: [
                "label": windowLabel,
                "remainingPercent": round(max(0.0, min(100.0, draft.remainingPercent)) * 10.0) / 10.0,
                "resetTime": toISO8601(draft.resetDate),
                "windowMinutes": windowMinutes
            ]
        ]
        let tier = draft.planTier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tier.isEmpty {
            payload["planTier"] = tier
        }

        do {
            try FileManager.default.createDirectory(at: openSlotsDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let dest = openSlotsDir.appendingPathComponent("\(finalId).json")
            let tmp = openSlotsDir.appendingPathComponent(".\(finalId).json.tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            // Ignore write errors
        }
    }

    func deleteOpenSlot(id: String) {
        let dest = openSlotsDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: dest)
    }
}
