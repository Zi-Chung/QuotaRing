import Cocoa
import SwiftUI

enum DisplayFormat: Int {
    case dualRingPair = 0        // 5 [◎]  W [◎]  M [◎]（按实际周期自动组合）
    case dualRingFiveHour = 1    // 5 [◎]
    case dualRingWeekly = 2      // W [◎]
    case ringWithWeeklyPct = 3   // [◎] 97%
    case ringWithBothPct = 4     // [◎] 93% | 97%
    case fullText = 5            // [◎] 5h 93% · 周 97% · 月 80%
    case dualRingMonthly = 6     // M [◎]
}

// MARK: - Shared Time Helpers

func parseISO8601Date(_ isoString: String) -> Date? {
    guard !isoString.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatter.date(from: isoString) { return d }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: isoString)
}

func remainingTimeFraction(resetIso: String, windowSeconds: TimeInterval) -> Double {
    guard windowSeconds > 0, let target = parseISO8601Date(resetIso) else { return 0.0 }
    let remaining = target.timeIntervalSince(Date())
    return max(0.0, min(1.0, remaining / windowSeconds))
}

func formatShortCountdown(from isoString: String) -> String {
    guard let targetDate = parseISO8601Date(isoString) else { return "" }
    let diff = targetDate.timeIntervalSince(Date())
    if diff <= 0 { return "已重置" }

    let totalMinutes = Int(diff) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 { return "\(days)天\(hours)时" }
    if hours > 0 { return "\(hours)时\(minutes)分" }
    return "\(minutes)分"
}

// MARK: - Concentric Dual-Ring Menu Bar Icon Rendering

struct RingSlotItem {
    let label: String
    let outerFraction: Double   // remaining quota (0..1)
    let innerFraction: Double   // remaining countdown until reset (0..1)
}

func drawConcentricRings(at center: NSPoint, outerFraction: Double, innerFraction: Double) {
    let outerRadius: CGFloat = 7.4
    let outerWidth: CGFloat = 2.1
    let innerRadius: CGFloat = 4.0
    let innerWidth: CGFloat = 1.9

    NSColor.black.withAlphaComponent(0.22).setStroke()
    let outerTrack = NSBezierPath()
    outerTrack.lineWidth = outerWidth
    outerTrack.appendArc(withCenter: center, radius: outerRadius, startAngle: 0, endAngle: 360, clockwise: false)
    outerTrack.stroke()

    let outerClamped = max(0.0, min(1.0, outerFraction))
    if outerClamped > 0.005 {
        NSColor.black.setStroke()
        let outerArc = NSBezierPath()
        outerArc.lineWidth = outerWidth
        outerArc.lineCapStyle = (outerClamped > 0.85 && outerClamped < 0.995) ? .butt : .round
        let sweep = CGFloat(outerClamped) * 360.0
        outerArc.appendArc(withCenter: center, radius: outerRadius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
        outerArc.stroke()
    }

    NSColor.black.withAlphaComponent(0.22).setStroke()
    let innerTrack = NSBezierPath()
    innerTrack.lineWidth = innerWidth
    innerTrack.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360, clockwise: false)
    innerTrack.stroke()

    let innerClamped = max(0.0, min(1.0, innerFraction))
    if innerClamped > 0.005 {
        NSColor.black.withAlphaComponent(0.85).setStroke()
        let innerArc = NSBezierPath()
        innerArc.lineWidth = innerWidth
        innerArc.lineCapStyle = (innerClamped > 0.85 && innerClamped < 0.995) ? .butt : .round
        let sweep = CGFloat(innerClamped) * 360.0
        innerArc.appendArc(withCenter: center, radius: innerRadius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
        innerArc.stroke()
    }
}

func makeDualRingStripImage(groups: [(prefix: String?, items: [RingSlotItem])]) -> NSImage {
    let labelFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    let prefixFont = NSFont.systemFont(ofSize: 10.0, weight: .bold)
    let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black]
    let prefixAttrs: [NSAttributedString.Key: Any] = [.font: prefixFont, .foregroundColor: NSColor.black.withAlphaComponent(0.75)]

    let ringExtent: CGFloat = 8.45
    let labelToRingGap: CGFloat = 2.5
    let itemGap: CGFloat = 5.5
    let groupGap: CGFloat = 8.0
    let padX: CGFloat = 1.0

    struct DrawOp {
        let text: NSAttributedString?
        let textOrigin: NSPoint
        let ringCenter: NSPoint?
        let outer: Double
        let inner: Double
        let dividerX: CGFloat?
    }

    var ops: [DrawOp] = []
    var cursorX: CGFloat = padX
    let height: CGFloat = 18.0
    let midY: CGFloat = height / 2.0

    for (gIdx, group) in groups.enumerated() {
        if gIdx > 0 {
            let divX = cursorX + groupGap / 2.0
            ops.append(DrawOp(text: nil, textOrigin: .zero, ringCenter: nil, outer: 0, inner: 0, dividerX: divX))
            cursorX += groupGap
        }

        if let prefix = group.prefix, !prefix.isEmpty {
            let attr = NSAttributedString(string: prefix, attributes: prefixAttrs)
            let sz = attr.size()
            ops.append(DrawOp(
                text: attr,
                textOrigin: NSPoint(x: cursorX, y: (height - sz.height) / 2.0 + 0.2),
                ringCenter: nil,
                outer: 0,
                inner: 0,
                dividerX: nil
            ))
            cursorX += sz.width + 3.0
        }

        for (iIdx, item) in group.items.enumerated() {
            if iIdx > 0 { cursorX += itemGap }
            if !item.label.isEmpty {
                let attr = NSAttributedString(string: item.label, attributes: labelAttrs)
                let sz = attr.size()
                ops.append(DrawOp(
                    text: attr,
                    textOrigin: NSPoint(x: cursorX, y: (height - sz.height) / 2.0 + 0.2),
                    ringCenter: nil,
                    outer: 0,
                    inner: 0,
                    dividerX: nil
                ))
                cursorX += sz.width + labelToRingGap
            }
            let cx = cursorX + ringExtent
            ops.append(DrawOp(
                text: nil,
                textOrigin: .zero,
                ringCenter: NSPoint(x: cx, y: midY),
                outer: item.outerFraction,
                inner: item.innerFraction,
                dividerX: nil
            ))
            cursorX = cx + ringExtent
        }
    }

    let totalWidth = max(18.0, ceil(cursorX + padX))
    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
        for op in ops {
            if let divX = op.dividerX {
                NSColor.black.withAlphaComponent(0.28).setFill()
                NSBezierPath(ovalIn: NSRect(x: divX - 1.0, y: midY - 1.0, width: 2.0, height: 2.0)).fill()
            }
            if let attr = op.text {
                attr.draw(at: op.textOrigin)
            }
            if let center = op.ringCenter {
                drawConcentricRings(at: center, outerFraction: op.outer, innerFraction: op.inner)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let viewModel = QuotaViewModel()
    var timer: Timer?
    var eventMonitor: Any?
    var isFetching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let savedFormat = UserDefaults.standard.value(forKey: "QuotaRing.DisplayFormat") as? Int,
           let format = DisplayFormat(rawValue: savedFormat) {
            viewModel.displayFormat = format
        }
        if let savedProvider = UserDefaults.standard.string(forKey: "QuotaRing.SelectedProvider"), !savedProvider.isEmpty {
            viewModel.selectedProviderId = savedProvider
        }
        if let savedInterval = UserDefaults.standard.value(forKey: "QuotaRing.RefreshInterval") as? Double,
           savedInterval >= 10.0 {
            viewModel.refreshInterval = savedInterval
        }
        viewModel.launchAtLogin = isLaunchAtLoginEnabled()

        bindViewModelCallbacks()

        // Configure native glass Popover hosting SwiftUI PopoverView
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(rootView: PopoverView(vm: viewModel))
        popover.contentViewController = hostingController

        // Configure status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.image = makeDualRingStripImage(groups: [(prefix: nil, items: [RingSlotItem(label: "", outerFraction: 0, innerFraction: 0)])])
            button.title = ""
            button.toolTip = "QuotaRing — 点击展开配额面板"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Dismiss popover when clicking outside even when another app is active
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let pop = self?.popover, pop.isShown {
                pop.performClose(nil)
            }
        }

        fetchData()
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func bindViewModelCallbacks() {
        viewModel.onRefresh = { [weak self] in
            self?.fetchData()
        }
        viewModel.onProviderChanged = { [weak self] pid in
            guard let self = self else { return }
            self.viewModel.selectedProviderId = pid
            UserDefaults.standard.setValue(pid, forKey: "QuotaRing.SelectedProvider")
            if let snap = self.viewModel.snapshot {
                self.updateStatusBar(snapshot: snap)
            }
        }
        viewModel.onFormatChanged = { [weak self] fmt in
            guard let self = self else { return }
            self.viewModel.displayFormat = fmt
            UserDefaults.standard.setValue(fmt.rawValue, forKey: "QuotaRing.DisplayFormat")
            if let snap = self.viewModel.snapshot {
                self.updateStatusBar(snapshot: snap)
            }
        }
        viewModel.onIntervalChanged = { [weak self] sec in
            guard let self = self else { return }
            self.viewModel.refreshInterval = sec
            UserDefaults.standard.setValue(sec, forKey: "QuotaRing.RefreshInterval")
            self.startTimer()
        }
        viewModel.onToggleLaunchAtLogin = { [weak self] in
            self?.toggleLaunchAtLogin()
        }
        viewModel.onOpenSlotsFolder = { [weak self] in
            self?.openSlotsFolder()
        }
        viewModel.onCopyAgyCommand = { [weak self] in
            self?.copyAgyCommand()
        }
        viewModel.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            fetchData()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: viewModel.refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
    }

    func fetchData() {
        guard !isFetching else { return }
        isFetching = true
        viewModel.isRefreshing = true

        QuotaFetcher.shared.fetchAll { [weak self] snapshot in
            guard let self = self else { return }
            self.isFetching = false
            self.viewModel.isRefreshing = false
            self.viewModel.snapshot = snapshot
            self.updateStatusBar(snapshot: snapshot)
        }
    }

    private func ringItem(for window: QuotaWindow, showLabel: Bool) -> RingSlotItem {
        RingSlotItem(
            label: showLabel ? window.shortTag : "",
            outerFraction: Double(window.percent) / 100.0,
            innerFraction: remainingTimeFraction(resetIso: window.resetTime, windowSeconds: window.windowSeconds)
        )
    }

    private func activeProvider(in providers: [ProviderQuota]) -> ProviderQuota? {
        providers.first(where: { $0.id == viewModel.selectedProviderId }) ?? providers.first
    }

    func updateStatusBar(snapshot: MultiQuotaSnapshot) {
        guard let button = statusItem.button else { return }
        let providers = snapshot.providers

        guard !providers.isEmpty else {
            button.image = makeDualRingStripImage(groups: [(prefix: nil, items: [RingSlotItem(label: "", outerFraction: 0, innerFraction: 0)])])
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "QuotaRing — 尚未检测到本地配额快照"
            statusItem.length = NSStatusItem.variableLength
            return
        }

        if viewModel.selectedProviderId == "all" {
            var groups: [(prefix: String?, items: [RingSlotItem])] = []
            for p in providers {
                var items: [RingSlotItem] = []
                if let fh = p.fiveHour { items.append(ringItem(for: fh, showLabel: true)) }
                if let wk = p.weekly { items.append(ringItem(for: wk, showLabel: true)) }
                if let mo = p.monthly { items.append(ringItem(for: mo, showLabel: true)) }
                if !items.isEmpty {
                    groups.append((prefix: providers.count > 1 ? p.shortBadge : nil, items: items))
                }
            }
            if groups.isEmpty {
                groups = [(prefix: nil, items: [RingSlotItem(label: "", outerFraction: 0, innerFraction: 0)])]
            }
            button.image = makeDualRingStripImage(groups: groups)
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.variableLength
        } else if let provider = activeProvider(in: providers) {
            var groups: [(prefix: String?, items: [RingSlotItem])] = []
            var title = ""

            let fallbackPrimary = provider.weekly ?? provider.monthly ?? provider.fiveHour
            switch viewModel.displayFormat {
            case .dualRingPair:
                var items: [RingSlotItem] = []
                if let fh = provider.fiveHour { items.append(ringItem(for: fh, showLabel: true)) }
                if let wk = provider.weekly { items.append(ringItem(for: wk, showLabel: true)) }
                if let mo = provider.monthly { items.append(ringItem(for: mo, showLabel: true)) }
                if items.isEmpty {
                    items.append(RingSlotItem(label: "", outerFraction: 0, innerFraction: 0))
                }
                groups = [(prefix: nil, items: items)]
            case .dualRingFiveHour:
                if let w = provider.fiveHour ?? fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: true)])]
                }
            case .dualRingWeekly:
                if let w = provider.weekly ?? fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: true)])]
                }
            case .dualRingMonthly:
                if let w = provider.monthly ?? fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: true)])]
                }
            case .ringWithWeeklyPct:
                if let w = fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: false)])]
                    title = " \(w.percent)%"
                }
            case .ringWithBothPct:
                if let w = fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: false)])]
                }
                let pcts = [provider.fiveHour, provider.weekly, provider.monthly].compactMap { $0 }.map { "\($0.percent)%" }
                title = pcts.isEmpty ? "" : " " + pcts.joined(separator: " | ")
            case .fullText:
                if let w = fallbackPrimary {
                    groups = [(prefix: nil, items: [ringItem(for: w, showLabel: false)])]
                }
                var parts: [String] = []
                if let fh = provider.fiveHour { parts.append("5h \(fh.percent)%") }
                if let wk = provider.weekly { parts.append("周 \(wk.percent)%") }
                if let mo = provider.monthly { parts.append("月 \(mo.percent)%") }
                title = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
            }

            if groups.isEmpty {
                groups = [(prefix: nil, items: [RingSlotItem(label: "", outerFraction: 0, innerFraction: 0)])]
            }
            button.image = makeDualRingStripImage(groups: groups)
            button.title = title
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            statusItem.length = NSStatusItem.variableLength
        }

        var tipLines: [String] = []
        for p in providers {
            var segs: [String] = []
            if let fh = p.fiveHour {
                let cd = formatShortCountdown(from: fh.resetTime)
                segs.append("5h \(fh.percent)%" + (cd.isEmpty ? "" : "(\(cd))"))
            }
            if let wk = p.weekly {
                let cd = formatShortCountdown(from: wk.resetTime)
                segs.append("周 \(wk.percent)%" + (cd.isEmpty ? "" : "(\(cd))"))
            }
            if let mo = p.monthly {
                let cd = formatShortCountdown(from: mo.resetTime)
                segs.append("月 \(mo.percent)%" + (cd.isEmpty ? "" : "(\(cd))"))
            }
            if !segs.isEmpty {
                tipLines.append("\(p.name)：" + segs.joined(separator: " · "))
            }
        }
        tipLines.append("外圈：剩余用量 · 内圈：重置倒计时")
        button.toolTip = tipLines.joined(separator: "\n")
    }

    private func openSlotsFolder() {
        let dir = QuotaFetcher.shared.openSlotsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        popover.performClose(nil)
        NSWorkspace.shared.open(dir)
    }

    private func copyAgyCommand() {
        let localAgy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/bin/agy").path
        let cmd = FileManager.default.fileExists(atPath: localAgy) ? localAgy : "agy"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
        viewModel.copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.viewModel.copiedToast = false
        }
    }

    // MARK: - Launch at Login Helper

    private var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.quotaring.app.plist")
    }

    func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    private func toggleLaunchAtLogin() {
        let fm = FileManager.default
        if isLaunchAtLoginEnabled() {
            try? fm.removeItem(at: launchAgentPlistURL)
        } else {
            let execPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/MacOS/QuotaRing")
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.quotaring.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            try? fm.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
        }
        viewModel.launchAtLogin = isLaunchAtLoginEnabled()
    }
}
