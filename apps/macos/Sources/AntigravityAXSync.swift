import ApplicationServices
import Cocoa
import Foundation

struct AXSyncResult {
    let success: Bool
    let message: String
    let bucketCount: Int
    let syncedAt: Date?
    let diagnosticSummary: String
}

/// Optional, opt-in macOS Accessibility reader for Antigravity's official
/// "Settings -> Model Quota & Usage" page.
/// - Never reads credentials, Keychain, cookies, or internal ports.
/// - Never activates or steals foreground focus from the user's active app.
/// - Only clicks the refresh button inside a verified Quota window.
/// - Preserves real 0% values and never turns missing values into 0% or 100%.
final class AntigravityAXSync {
    static let shared = AntigravityAXSync()

    let axSnapshotURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quota-bar/antigravity-ax-snapshot.json")
    }()

    private let workQueue = DispatchQueue(label: "com.quotaring.axsync", qos: .utility)
    private var timer: Timer?
    private var isSyncing = false
    private var isSystemAsleep = false
    private var enabled = false
    private var intervalSeconds: TimeInterval = 300.0 // 5 min minimum default
    private var onResult: ((AXSyncResult) -> Void)?

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func handleSleep() {
        isSystemAsleep = true
    }

    @objc private func handleWake() {
        isSystemAsleep = false
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        _ = isAccessibilityTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func configure(enabled: Bool, intervalSeconds: TimeInterval, onResult: @escaping (AXSyncResult) -> Void) {
        self.enabled = enabled
        self.intervalSeconds = max(300.0, intervalSeconds) // Enforce >= 5 min
        self.onResult = onResult
        timer?.invalidate()
        timer = nil

        guard enabled else { return }

        timer = Timer.scheduledTimer(withTimeInterval: self.intervalSeconds, repeats: true) { [weak self] _ in
            self?.syncNow(manual: false)
        }

        // Run an initial check shortly after enabling
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.enabled else { return }
            self.syncNow(manual: false)
        }
    }

    func syncNow(manual: Bool) {
        guard !isSyncing else { return }
        if !manual && (!enabled || isSystemAsleep) { return }

        guard Self.isAccessibilityTrusted(prompt: false) else {
            deliver(AXSyncResult(
                success: false,
                message: "未授予「辅助功能」权限（保留上次读数）",
                bucketCount: 0,
                syncedAt: nil,
                diagnosticSummary: "AXIsProcessTrusted() == false"
            ))
            return
        }

        isSyncing = true
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.performSync()
            self.isSyncing = false
            self.deliver(result)
        }
    }

    private func deliver(_ result: AXSyncResult) {
        DispatchQueue.main.async { [weak self] in
            self?.onResult?(result)
        }
    }

    // MARK: - Core AX Discovery, Refresh, and Parsing

    private struct AXButtonCandidate {
        let element: AXUIElement
        let label: String
    }

    private struct AXWindowDump {
        let window: AXUIElement
        let windowTitle: String
        let nodesVisited: Int
        let texts: [String]
        let buttons: [AXButtonCandidate]
        let hasBusyIndicator: Bool
    }

    private func findAntigravityApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            if app.isTerminated { return false }
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").lowercased()
            if bid == "com.quotaring.app" { return false }
            return bid.contains("antigravity") || name.contains("antigravity")
        }
    }

    private func performSync() -> AXSyncResult {
        let apps = findAntigravityApps()
        guard !apps.isEmpty else {
            return AXSyncResult(
                success: false,
                message: "未检测到运行中的 Antigravity（保留上次读数）",
                bucketCount: 0,
                syncedAt: nil,
                diagnosticSummary: "No running Antigravity process found"
            )
        }

        // Scan ALL non-minimized Antigravity windows and pick the highest-scoring real Quota Settings window
        // (avoids accidentally matching a chat window that merely discusses quota strings in prose).
        var bestCandidate: (dump: AXWindowDump, score: Int)?
        var scannedWindows = 0
        var minimizedWindows = 0
        var windowDiagParts: [String] = []

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for win in windows {
                if isMinimized(win) {
                    minimizedWindows += 1
                    continue
                }
                scannedWindows += 1
                var dump = dumpWindow(win)
                if dump.texts.count < 8 {
                    Thread.sleep(forTimeInterval: 0.35)
                    dump = dumpWindow(win)
                }
                let score = scoreQuotaWindow(dump)
                let parsedPreview = parseQuotaBuckets(from: dump.texts)
                windowDiagParts.append("win(title=\(dump.windowTitle), score=\(score), parsed=\(parsedPreview.count), nodes=\(dump.nodesVisited), btns=\(dump.buttons.count))")

                if score > 0 && parsedPreview.count >= 2 {
                    if bestCandidate == nil || score > bestCandidate!.score {
                        bestCandidate = (dump, score)
                    }
                }
            }
        }

        guard let initialDump = bestCandidate?.dump else {
            let minHint = minimizedWindows > 0 ? "（检测到 \(minimizedWindows) 个最小化窗口，请取消最小化）" : "（请单独打开「设置 → 模型配额与用量」窗口并保持未最小化）"
            return AXSyncResult(
                success: false,
                message: "未找到「模型配额与用量」窗口\(minHint)",
                bucketCount: 0,
                syncedAt: nil,
                diagnosticSummary: "scanned=\(scannedWindows), minimized=\(minimizedWindows); " + windowDiagParts.joined(separator: " ; ")
            )
        }

        // Click the Refresh button in the background without bringing Antigravity to front
        var clickedRefresh = false
        if let refreshBtn = findRefreshButton(in: initialDump.buttons) {
            let pressErr = AXUIElementPerformAction(refreshBtn.element, kAXPressAction as CFString)
            clickedRefresh = (pressErr == .success)
        }

        // Wait for reload completion (up to 7.0s) instead of blind fixed sleep
        var finalDump = initialDump
        if clickedRefresh {
            Thread.sleep(forTimeInterval: 0.6)
            let deadline = Date().addingTimeInterval(6.4)
            var lastTextHash = initialDump.texts.hashValue
            var stablePolls = 0

            while Date() < deadline {
                let current = dumpWindow(initialDump.window)
                if !looksLikeQuotaPage(current.texts) {
                    // User navigated away mid-refresh -> abort safely without overwriting
                    return AXSyncResult(
                        success: false,
                        message: "额度页已切走或关闭（保留上次读数）",
                        bucketCount: 0,
                        syncedAt: nil,
                        diagnosticSummary: "Window navigated away from quota page during refresh."
                    )
                }

                finalDump = current
                let curHash = current.texts.hashValue
                let parsedNow = parseQuotaBuckets(from: current.texts)
                if !current.hasBusyIndicator && !parsedNow.isEmpty {
                    if curHash != initialDump.texts.hashValue || stablePolls >= 2 {
                        break
                    }
                    if curHash == lastTextHash {
                        stablePolls += 1
                    } else {
                        stablePolls = 0
                    }
                }
                lastTextHash = curHash
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        let parsed = parseQuotaBuckets(from: finalDump.texts)
        let diagLines = finalDump.texts.prefix(80).joined(separator: " | ")

        // Require at least both Gemini weekly and Gemini 5h (or >= 2 parsed buckets) so partial reads never wipe existing rings
        guard parsed.count >= 2 else {
            return AXSyncResult(
                success: false,
                message: "额度页解析不完整（保留上次读数）",
                bucketCount: 0,
                syncedAt: nil,
                diagnosticSummary: "clickedRefresh=\(clickedRefresh), parsedCount=\(parsed.count)\ntexts=\(diagLines)"
            )
        }

        let now = Date()
        let savedCount = writeSnapshot(parsedBuckets: parsed, syncedAt: now)
        let btnSummary = finalDump.buttons.prefix(25).map { $0.label }.joined(separator: ", ")
        return AXSyncResult(
            success: true,
            message: "已同步 \(savedCount) 项配额" + (clickedRefresh ? "" : "（读取当前页面）"),
            bucketCount: savedCount,
            syncedAt: now,
            diagnosticSummary: "clickedRefresh=\(clickedRefresh), parsed=\(parsed.map { "\($0.id):\($0.percent)%(\($0.resetTime ?? "no-reset"))" }.joined(separator: ", ")), btns=[\(btnSummary)]"
        )
    }

    // MARK: - AX Tree Traversal

    private func isMinimized(_ win: AXUIElement) -> Bool {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &val) == .success,
           let num = val as? NSNumber {
            return num.boolValue
        }
        return false
    }

    private func getStringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &val) == .success else { return nil }
        if let s = val as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    private func dumpWindow(_ window: AXUIElement) -> AXWindowDump {
        var texts: [String] = []
        var buttons: [AXButtonCandidate] = []
        var hasBusy = false
        var visited = 0
        let maxNodes = 15000
        let maxDepth = 50
        let winTitle = getStringAttr(window, kAXTitleAttribute) ?? "(untitled)"

        func walk(_ el: AXUIElement, depth: Int) {
            if depth > maxDepth || visited >= maxNodes { return }
            visited += 1

            let role = getStringAttr(el, kAXRoleAttribute) ?? ""
            if role == "AXBusyIndicator" {
                hasBusy = true
            }

            let title = getStringAttr(el, kAXTitleAttribute)
            let desc = getStringAttr(el, kAXDescriptionAttribute)
            let help = getStringAttr(el, kAXHelpAttribute)
            let valueStr = getStringAttr(el, kAXValueAttribute)

            if role == "AXButton" {
                let btnLabel = title ?? desc ?? help ?? collectDirectChildText(el)
                if let lbl = btnLabel, !lbl.isEmpty {
                    buttons.append(AXButtonCandidate(element: el, label: lbl))
                }
            }

            for candidate in [title, valueStr, desc].compactMap({ $0 }) {
                if candidate.count <= 240 {
                    if texts.last != candidate {
                        texts.append(candidate)
                    }
                    let lower = candidate.lowercased()
                    if lower == "加载中" || lower == "刷新中" || lower == "loading..." || lower == "refreshing..." {
                        hasBusy = true
                    }
                }
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    walk(child, depth: depth + 1)
                    if visited >= maxNodes { break }
                }
            }
        }

        walk(window, depth: 0)
        return AXWindowDump(window: window, windowTitle: winTitle, nodesVisited: visited, texts: texts, buttons: buttons, hasBusyIndicator: hasBusy)
    }

    private func collectDirectChildText(_ el: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let v = getStringAttr(child, kAXValueAttribute) ?? getStringAttr(child, kAXTitleAttribute) {
                return v
            }
        }
        return nil
    }

    private func scoreQuotaWindow(_ dump: AXWindowDump) -> Int {
        var score = 0
        let shortLines = dump.texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 32 }
        let shortLower = Set(shortLines.map { $0.lowercased() })

        // Strong exact standalone UI labels from Antigravity Settings -> Model Quota
        if shortLower.contains("gemini 模型") || shortLower.contains("gemini models") { score += 40 }
        if shortLower.contains("claude 与 gpt 模型") || shortLower.contains("claude and gpt models") || shortLower.contains("claude & gpt models") { score += 40 }
        if shortLower.contains("每周限额剩余") || shortLower.contains("weekly limit remaining") { score += 35 }
        if shortLower.contains("5 小时限额剩余") || shortLower.contains("5小时限额剩余") || shortLower.contains("5-hour limit remaining") { score += 35 }
        if shortLower.contains("模型配额与用量") || shortLower.contains("model quota") || shortLower.contains("models & quota") { score += 25 }

        // Standalone percentage tokens like "65%", "85%", "100%"
        let exactPctCount = shortLines.filter { $0.range(of: #"^(?:100|[1-9]?\d)%$"#, options: .regularExpression) != nil }.count
        if exactPctCount >= 2 { score += 20 }
        if exactPctCount >= 4 { score += 20 }

        if findRefreshButton(in: dump.buttons) != nil { score += 25 }

        let titleLower = dump.windowTitle.lowercased()
        if titleLower.contains("setting") || titleLower.contains("设置") { score += 20 }

        // Must look genuinely like the quota page (at least 2 strong structural signals)
        return score >= 70 ? score : 0
    }

    private func looksLikeQuotaPage(_ texts: [String]) -> Bool {
        let shortLower = Set(texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { $0.count <= 32 })
        if shortLower.contains("每周限额剩余") || shortLower.contains("5 小时限额剩余") || shortLower.contains("weekly limit remaining") || shortLower.contains("5-hour limit remaining") {
            return true
        }
        return shortLower.contains("模型配额与用量") || shortLower.contains("model quota") || shortLower.contains("models & quota")
    }

    private func findRefreshButton(in buttons: [AXButtonCandidate]) -> AXButtonCandidate? {
        let exactNames = ["刷新", "刷新配额", "重新加载", "更新", "refresh", "refresh quota", "reload"]
        if let exact = buttons.first(where: { btn in
            let l = btn.label.lowercased()
            return exactNames.contains(l)
        }) {
            return exact
        }
        return buttons.first(where: { btn in
            let l = btn.label.lowercased()
            return l.contains("刷新") || l.contains("refresh") || l.contains("reload")
        })
    }

    // MARK: - Strict Quota Parser (Distinguishes Real 0% from Missing Data)

    private struct ParsedBucket {
        let id: String              // "gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"
        let percent: Double         // 0.0 ... 100.0 (real parsed value)
        let resetTime: String?      // ISO8601 if parsed
    }

    private func parseQuotaBuckets(from texts: [String]) -> [ParsedBucket] {
        enum Pool { case none, gemini, thirdParty }
        enum WindowKind { case none, fiveHour, weekly }

        var currentPool: Pool = .none
        var currentWindow: WindowKind = .none
        var pendingReset: String?
        var expectingResetDuration = false
        var found: [String: ParsedBucket] = [:]

        let exactPctRegex = try? NSRegularExpression(pattern: #"^\s*(100(?:\.0+)?|[1-9]?\d(?:\.\d+)?)\s*%\s*$"#)

        func bucketId(pool: Pool, window: WindowKind) -> String? {
            switch (pool, window) {
            case (.gemini, .fiveHour): return "gemini-5h"
            case (.gemini, .weekly): return "gemini-weekly"
            case (.thirdParty, .fiveHour): return "3p-5h"
            case (.thirdParty, .weekly): return "3p-weekly"
            default: return nil
            }
        }

        for raw in texts {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let lower = line.lowercased()

            // Detect model pool headers ONLY on concise standalone header nodes (<= 32 chars)
            // so conversational prose in other UI regions can never hijack state.
            if line.count <= 32 {
                let isThirdPartyHeader =
                    lower == "claude 与 gpt 模型" ||
                    lower == "claude and gpt models" ||
                    lower == "claude & gpt models" ||
                    ((lower.contains("claude") || lower.contains("gpt") || lower.contains("第三方") || lower.contains("third-party") || lower.contains("other models")) && !lower.contains("%"))
                let isGeminiHeader =
                    (lower == "gemini 模型" || lower == "gemini models" || (lower.contains("gemini") && (lower.contains("模型") || lower.contains("model")))) && !isThirdPartyHeader

                if isThirdPartyHeader {
                    currentPool = .thirdParty
                    currentWindow = .none
                    pendingReset = nil
                    expectingResetDuration = false
                    continue
                } else if isGeminiHeader {
                    currentPool = .gemini
                    currentWindow = .none
                    pendingReset = nil
                    expectingResetDuration = false
                    continue
                }

                let is5hHeader =
                    lower == "5 小时限额剩余" ||
                    lower == "5小时限额剩余" ||
                    lower == "5-hour limit remaining" ||
                    lower == "5 hour limit remaining" ||
                    lower == "5 小时额度"
                let isWeeklyHeader =
                    lower == "每周限额剩余" ||
                    lower == "本周限额剩余" ||
                    lower == "weekly limit remaining" ||
                    lower == "周额度"

                if is5hHeader {
                    if currentPool == .gemini && found["gemini-5h"] != nil {
                        currentPool = .thirdParty
                    } else if currentPool == .none {
                        currentPool = .gemini
                    }
                    currentWindow = .fiveHour
                    pendingReset = nil
                    expectingResetDuration = false
                    continue
                } else if isWeeklyHeader {
                    if currentPool == .gemini && found["gemini-weekly"] != nil {
                        currentPool = .thirdParty
                    } else if currentPool == .none {
                        currentPool = .gemini
                    }
                    currentWindow = .weekly
                    pendingReset = nil
                    expectingResetDuration = false
                    continue
                }
            }

            guard let bId = bucketId(pool: currentPool, window: currentWindow) else { continue }

            // Extract reset duration / timestamp cleanly from the description sentence (<= 110 chars)
            // or from the immediately following duration node when Chromium splits after the colon.
            if line.count <= 110, let afterMarker = extractTextAfterResetMarker(from: line) {
                if let resetIso = parseDurationOrTimestampISO(from: afterMarker) {
                    applyReset(resetIso, to: bId, found: &found, pendingReset: &pendingReset)
                    expectingResetDuration = false
                } else {
                    expectingResetDuration = true
                }
                continue
            } else if expectingResetDuration && line.count <= 32 {
                if let resetIso = parseDurationOrTimestampISO(from: line) {
                    applyReset(resetIso, to: bId, found: &found, pendingReset: &pendingReset)
                    expectingResetDuration = false
                    continue
                } else if line.contains("%") {
                    expectingResetDuration = false
                }
            }

            // Extract ONLY standalone percentage tokens (e.g. "65%", "85%", "100%", "0%") — never prose numbers!
            if line.count <= 12, let regex = exactPctRegex {
                let ns = line as NSString
                if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges > 1 {
                    let numStr = ns.substring(with: match.range(at: 1))
                    if let val = Double(numStr), val >= 0.0 && val <= 100.0 {
                        let resetIso = pendingReset ?? found[bId]?.resetTime
                        if found[bId] == nil {
                            found[bId] = ParsedBucket(id: bId, percent: val, resetTime: resetIso)
                        }
                        pendingReset = nil
                        expectingResetDuration = false
                    }
                }
            }
        }

        let order = ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"]
        return order.compactMap { found[$0] }
    }

    private func applyReset(_ resetIso: String, to bId: String, found: inout [String: ParsedBucket], pendingReset: inout String?) {
        if let existing = found[bId], existing.resetTime == nil {
            found[bId] = ParsedBucket(id: bId, percent: existing.percent, resetTime: resetIso)
        } else {
            pendingReset = resetIso
        }
    }

    /// Returns the substring strictly AFTER a reset/refresh phrase (e.g., "完全刷新：" or "resets in").
    /// Returns "" if the marker is present at the end of the line (so the next AX node carries the duration).
    /// Returns nil if the line does not contain a reset/refresh marker.
    private func extractTextAfterResetMarker(from text: String) -> String? {
        let markers = [
            "完全刷新：", "完全刷新:",
            "完全重置：", "完全重置:",
            "刷新时间：", "刷新时间:",
            "重置时间：", "重置时间:",
            "刷新：", "刷新:",
            "重置：", "重置:",
            "refreshes in ", "will refresh in ", "refresh in ",
            "resets in ", "reset in ",
            "resets at ", "refreshes at "
        ]
        for m in markers {
            if let range = text.range(of: m, options: [.caseInsensitive]) {
                let tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return tail
            }
        }
        return nil
    }

    private func parseDurationOrTimestampISO(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Relative duration e.g. "6 天，4 小时", "2 小时，34 分钟", "45 分钟", "2d 4h", "1h 20m"
        var totalSeconds: TimeInterval = 0
        var matchedDuration = false

        let patterns: [(String, TimeInterval)] = [
            (#"(\d+)\s*(?:天|d\b|days?)"#, 86400),
            (#"(\d+)\s*(?:小时|时|h\b|hrs?|hours?)"#, 3600),
            (#"(\d+)\s*(?:分钟|分|m\b|mins?|minutes?)"#, 60)
        ]

        for (pat, mult) in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let ns = trimmed as NSString
                if let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges > 1,
                   let v = Double(ns.substring(with: m.range(at: 1))) {
                    totalSeconds += v * mult
                    matchedDuration = true
                }
            }
        }

        if matchedDuration && totalSeconds > 0 {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            return fmt.string(from: Date().addingTimeInterval(totalSeconds))
        }

        // 2. ISO-like YYYY-MM-DD HH:mm
        if let regex = try? NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})[T\s](\d{2}:\d{2})"#) {
            let ns = trimmed as NSString
            if let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges > 2 {
                let str = "\(ns.substring(with: m.range(at: 1))) \(ns.substring(with: m.range(at: 2)))"
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd HH:mm"
                if let dt = df.date(from: str) {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime]
                    return iso.string(from: dt)
                }
            }
        }

        return nil
    }

    // MARK: - Atomic Snapshot Persistence

    private func loadPreviousResetTimes() -> [String: String] {
        var map: [String: String] = [:]
        let candidates = [axSnapshotURL, QuotaFetcher.shared.agySnapshotURL]
        let now = Date()
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let buckets = json["buckets"] as? [[String: Any]] else { continue }
            for b in buckets {
                if let id = b["id"] as? String,
                   let rt = b["resetTime"] as? String,
                   map[id] == nil,
                   let dt = parseISO8601Date(rt),
                   dt > now {
                    map[id] = rt
                }
            }
        }
        return map
    }

    private func writeSnapshot(parsedBuckets: [ParsedBucket], syncedAt: Date) -> Int {
        let prevResets = loadPreviousResetTimes()
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]

        let bucketObjects: [[String: Any]] = parsedBuckets.map { b in
            var obj: [String: Any] = [
                "id": b.id,
                "remainingFraction": round((b.percent / 100.0) * 10000.0) / 10000.0,
                "disabled": false
            ]
            if let rt = b.resetTime ?? prevResets[b.id] {
                obj["resetTime"] = rt
            }
            return obj
        }

        let payload: [String: Any] = [
            "version": 1,
            "source": "antigravity-ax",
            "updatedAt": isoFmt.string(from: syncedAt),
            "buckets": bucketObjects
        ]

        do {
            try FileManager.default.createDirectory(at: axSnapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let tmp = axSnapshotURL.deletingLastPathComponent().appendingPathComponent(".antigravity-ax-snapshot.json.tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: axSnapshotURL.path) {
                try FileManager.default.removeItem(at: axSnapshotURL)
            }
            try FileManager.default.moveItem(at: tmp, to: axSnapshotURL)
        } catch {
            return 0
        }

        return bucketObjects.count
    }
}
