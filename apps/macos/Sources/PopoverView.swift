import SwiftUI
import AppKit

// MARK: - Reactive ViewModel

final class QuotaViewModel: ObservableObject {
    @Published var snapshot: MultiQuotaSnapshot?
    @Published var selectedProviderId: String = "antigravity"
    @Published var displayFormat: DisplayFormat = .dualRingPair
    @Published var refreshInterval: TimeInterval = 30.0
    @Published var launchAtLogin: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var copiedToast: Bool = false

    var onRefresh: (() -> Void)?
    var onProviderChanged: ((String) -> Void)?
    var onFormatChanged: ((DisplayFormat) -> Void)?
    var onIntervalChanged: ((TimeInterval) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenSlotsFolder: (() -> Void)?
    var onCopyAgyCommand: (() -> Void)?
    var onQuit: (() -> Void)?
}

// MARK: - Mini Colored Dual Ring (for Popover Cards)

struct ColoredDualRingView: View {
    let outerFraction: Double
    let innerFraction: Double
    let size: CGFloat

    private var quotaColor: Color {
        if outerFraction >= 0.5 { return Color(nsColor: .systemGreen) }
        if outerFraction >= 0.2 { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemRed)
    }

    private var timerColor: Color {
        Color(nsColor: .systemBlue)
    }

    var body: some View {
        ZStack {
            // Outer track & arc (remaining quota)
            Circle()
                .stroke(quotaColor.opacity(0.18), lineWidth: 3.4)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.0, min(1.0, outerFraction))))
                .stroke(
                    quotaColor,
                    style: StrokeStyle(lineWidth: 3.4, lineCap: outerFraction > 0.88 && outerFraction < 0.995 ? .butt : .round)
                )
                .rotationEffect(.degrees(-90))

            // Inner track & arc (reset countdown)
            Circle()
                .stroke(timerColor.opacity(0.18), lineWidth: 2.8)
                .padding(5.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.0, min(1.0, innerFraction))))
                .stroke(
                    timerColor,
                    style: StrokeStyle(lineWidth: 2.8, lineCap: innerFraction > 0.88 && innerFraction < 0.995 ? .butt : .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Main Popover View

struct PopoverView: View {
    @ObservedObject var vm: QuotaViewModel
    @State private var showSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let now = context.date
            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.5)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if showSettings {
                            settingsPanel
                        }

                        let providers = vm.snapshot?.providers ?? []
                        if providers.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(providers, id: \.id) { provider in
                                providerCard(provider, now: now)
                            }
                        }

                        if !providers.contains(where: { $0.id != "antigravity" && $0.id != "codex" }) {
                            openSlotHintCard
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 440)

                Divider().opacity(0.5)
                footerBar
            }
            .frame(width: 340)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("QuotaRing")
                        .font(.system(size: 14, weight: .semibold))
                    Text("纯本地")
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    legendDot(color: Color(nsColor: .systemGreen), text: "外圈 剩余用量")
                    legendDot(color: Color(nsColor: .systemBlue), text: "内圈 重置倒计时")
                }
            }

            Spacer()

            Button(action: { vm.onRefresh?() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("立即读取全部快照")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showSettings.toggle()
                }
            }) {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showSettings ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(showSettings ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("显示样式与设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Provider Card

    private func providerCard(_ provider: ProviderQuota, now: Date) -> some View {
        let isPinned = (vm.selectedProviderId == provider.id)
        return VStack(alignment: .leading, spacing: 9) {
            // Card top bar
            HStack(spacing: 7) {
                Image(systemName: provider.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(provider.name)
                            .font(.system(size: 12.5, weight: .semibold))
                        if let tier = provider.planTier, !tier.isEmpty {
                            Text(tier)
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.07))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(provider.sourceLabel) · 同步于 \(liveRelativeAge(from: provider.syncedAt, now: now))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: {
                    let next = isPinned ? "all" : provider.id
                    vm.onProviderChanged?(next)
                }) {
                    Text(isPinned ? "顶栏中" : "固定顶栏")
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isPinned ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(isPinned ? "点击切换为全部品牌并排" : "将此品牌固定显示在顶部菜单栏")
            }

            // Groups & buckets
            ForEach(Array(provider.groups.enumerated()), id: \.offset) { gIdx, group in
                VStack(alignment: .leading, spacing: 6) {
                    if provider.groups.count > 1 {
                        Text(group.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, gIdx == 0 ? 0 : 2)
                    }

                    ForEach(group.buckets, id: \.id) { bucket in
                        bucketRow(bucket, now: now)
                    }
                }
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func defaultWindowSeconds(for window: String) -> TimeInterval {
        switch window {
        case "5h": return 5.0 * 3600.0
        case "monthly": return 30.0 * 24.0 * 3600.0
        default: return 7.0 * 24.0 * 3600.0
        }
    }

    private func bucketRow(_ bucket: ModelBucketInfo, now: Date) -> some View {
        let winSecs: TimeInterval = bucket.windowSeconds > 0
            ? bucket.windowSeconds
            : defaultWindowSeconds(for: bucket.window)
        let outerFrac = Double(bucket.percent) / 100.0
        let innerFrac = liveRemainingFraction(resetIso: bucket.resetTime, windowSeconds: winSecs, now: now)
        let cd = liveCountdownText(resetIso: bucket.resetTime, now: now)
        let resetAbs = formatResetAbsolute(bucket.resetTime)

        return HStack(spacing: 10) {
            ColoredDualRingView(outerFraction: outerFrac, innerFraction: innerFrac, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Text("\(bucket.percent)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(percentColor(bucket.percent))
                }

                HStack {
                    Text(cd.isEmpty ? "重置时间未知" : "剩余 \(cd)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !resetAbs.isEmpty {
                        Text(resetAbs)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func percentColor(_ pct: Int) -> Color {
        if pct >= 50 { return Color(nsColor: .systemGreen) }
        if pct >= 20 { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemRed)
    }

    // MARK: Empty & Open Slot Cards

    private var emptyStateCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("尚未检测到本地配额快照")
                .font(.system(size: 12.5, weight: .semibold))
            Text("运行 agy CLI 同步 Antigravity，或使用 Codex / 开放插槽后将自动显示。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var openSlotHintCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("开放插槽（Cursor / GrokBot 等）")
                    .font(.system(size: 11, weight: .medium))
                Text("放入 ~/.config/quota-bar/providers/*.json 自动接入")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("打开目录") {
                vm.onOpenSlotsFolder?()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(0.12))
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Collapsible Settings Panel

    private var settingsPanel: some View {
        let providers = vm.snapshot?.providers ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Text("菜单栏设置")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            // Brand picker
            HStack {
                Text("顶栏品牌")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.selectedProviderId },
                    set: { vm.onProviderChanged?($0) }
                )) {
                    Text("全部并排").tag("all")
                    ForEach(providers, id: \.id) { p in
                        Text("\(p.name) (\(p.shortBadge))").tag(p.id)
                    }
                }
                .labelsHidden()
                .frame(width: 155)
                .controlSize(.small)
            }

            // Style picker
            HStack {
                Text("顶栏样式")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.displayFormat },
                    set: { vm.onFormatChanged?($0) }
                )) {
                    Text("5 / W / M 双环 [推荐]").tag(DisplayFormat.dualRingPair)
                    Text("仅 5 小时双环 (5)").tag(DisplayFormat.dualRingFiveHour)
                    Text("仅周额度双环 (W)").tag(DisplayFormat.dualRingWeekly)
                    Text("仅月额度双环 (M)").tag(DisplayFormat.dualRingMonthly)
                    Text("双环 + 主百分比").tag(DisplayFormat.ringWithWeeklyPct)
                    Text("双环 + 全部百分比").tag(DisplayFormat.ringWithBothPct)
                    Text("双环 + 文字").tag(DisplayFormat.fullText)
                }
                .labelsHidden()
                .frame(width: 155)
                .controlSize(.small)
            }

            // Refresh interval
            HStack {
                Text("检查频率")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.refreshInterval },
                    set: { vm.onIntervalChanged?($0) }
                )) {
                    Text("10秒").tag(10.0)
                    Text("30秒").tag(30.0)
                    Text("1分钟").tag(60.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 155)
                .controlSize(.small)
            }

            // Launch at login
            Toggle(isOn: Binding(
                get: { vm.launchAtLogin },
                set: { _ in vm.onToggleLaunchAtLogin?() }
            )) {
                Text("开机自动启动")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(11)
        .background(Color.accentColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button(action: { vm.onOpenSlotsFolder?() }) {
                Label("插槽目录", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("·").foregroundStyle(.quaternary)

            Button(action: { vm.onCopyAgyCommand?() }) {
                Label(vm.copiedToast ? "已复制 agy" : "复制 agy", systemImage: vm.copiedToast ? "checkmark" : "terminal")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(vm.copiedToast ? Color(nsColor: .systemGreen) : Color.secondary)

            Spacer()

            Button(action: { vm.onQuit?() }) {
                Text("退出")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Live Time Formatters

    private func liveRemainingFraction(resetIso: String, windowSeconds: TimeInterval, now: Date) -> Double {
        guard windowSeconds > 0, let target = parseISO8601Date(resetIso) else { return 0.0 }
        return max(0.0, min(1.0, target.timeIntervalSince(now) / windowSeconds))
    }

    private func liveCountdownText(resetIso: String, now: Date) -> String {
        guard let target = parseISO8601Date(resetIso) else { return "" }
        let diff = Int(target.timeIntervalSince(now))
        if diff <= 0 { return "已到重置时间" }
        let d = diff / 86400
        let h = (diff % 86400) / 3600
        let m = (diff % 3600) / 60
        let s = diff % 60
        if d > 0 { return "\(d)天 \(h)时 \(m)分" }
        if h > 0 { return String(format: "%d时 %02d分 %02d秒", h, m, s) }
        return String(format: "%d分 %02d秒", m, s)
    }

    private func formatResetAbsolute(_ resetIso: String) -> String {
        guard let target = parseISO8601Date(resetIso) else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 EEE HH:mm"
        return fmt.string(from: target)
    }

    private func liveRelativeAge(from date: Date?, now: Date) -> String {
        guard let date = date else { return "未知" }
        let sec = max(0, Int(now.timeIntervalSince(date)))
        if sec < 60 { return "刚刚" }
        if sec < 3600 { return "\(sec / 60) 分钟前" }
        if sec < 86400 { return "\(sec / 3600) 小时前" }
        return "\(sec / 86400) 天前"
    }
}
