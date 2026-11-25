import SwiftUI
import AppKit

// MARK: - Reactive ViewModel

final class QuotaViewModel: ObservableObject {
    @Published var snapshot: MultiQuotaSnapshot?
    @Published var selectedProviderId: String = "antigravity"
    @Published var displayFormat: DisplayFormat = .dualRingPair
    @Published var refreshInterval: TimeInterval = 30.0
    @Published var hotKeyPreset: HotKeyPreset = .optionQ
    @Published var launchAtLogin: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var copiedToast: Bool = false

    // Optional macOS Accessibility background sync for Antigravity Quota page (opt-in, default off)
    @Published var axSyncEnabled: Bool = false
    @Published var axSyncInterval: TimeInterval = 300.0
    @Published var axTrusted: Bool = false
    @Published var axIsSyncing: Bool = false
    @Published var axStatusMessage: String = ""
    @Published var axLastDiagnostic: String = ""

    var onRefresh: (() -> Void)?
    var onProviderChanged: ((String) -> Void)?
    var onFormatChanged: ((DisplayFormat) -> Void)?
    var onIntervalChanged: ((TimeInterval) -> Void)?
    var onHotKeyChanged: ((HotKeyPreset) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenSlotsFolder: (() -> Void)?
    var onCopyAgyCommand: (() -> Void)?
    var onLaunchAgySync: (() -> Void)?
    var onAXSyncEnabledChanged: ((Bool) -> Void)?
    var onAXSyncIntervalChanged: ((TimeInterval) -> Void)?
    var onAXSyncNow: (() -> Void)?
    var onRequestAXPermission: (() -> Void)?
    var onCopyAXDiagnostic: (() -> Void)?
    var onSaveSlot: ((EditableSlotDraft) -> Void)?
    var onDeleteSlot: ((String) -> Void)?
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
    @State private var showSlotEditor = false
    @State private var editingExistingSlot = false
    @State private var slotDraft = EditableSlotDraft()

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

                        if showSlotEditor {
                            slotEditorPanel
                        }

                        let providers = vm.snapshot?.providers ?? []
                        if providers.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(providers, id: \.id) { provider in
                                providerCard(provider, now: now)
                            }
                        }

                        openSlotHintCard
                    }
                    .padding(12)
                }
                .frame(maxHeight: 460)

                Divider().opacity(0.5)
                footerBar
            }
            .frame(width: 344)
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
                    if !vm.hotKeyPreset.shortBadge.isEmpty {
                        Text(vm.hotKeyPreset.shortBadge)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.07))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
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

                if provider.isOpenSlot {
                    Button(action: {
                        startEditing(provider)
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 21, height: 21)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑此开放插槽")
                }

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
                        bucketRow(bucket, providerId: provider.id, now: now)
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

    private func bucketRow(_ bucket: ModelBucketInfo, providerId: String, now: Date) -> some View {
        let winSecs: TimeInterval = bucket.windowSeconds > 0
            ? bucket.windowSeconds
            : defaultWindowSeconds(for: bucket.window)
        let expired = isResetExpired(resetIso: bucket.resetTime, now: now)
        let outerFrac = expired ? 0.0 : (Double(bucket.percent) / 100.0)
        let innerFrac = expired ? 0.0 : liveRemainingFraction(resetIso: bucket.resetTime, windowSeconds: winSecs, now: now)
        let cd = liveCountdownText(resetIso: bucket.resetTime, now: now)
        let resetAbs = formatResetAbsolute(bucket.resetTime)

        return HStack(spacing: 10) {
            ColoredDualRingView(outerFraction: outerFrac, innerFraction: innerFrac, size: 28)
                .opacity(expired ? 0.45 : 1.0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(bucket.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    if expired {
                        if providerId == "antigravity" {
                            Button(action: { vm.onLaunchAgySync?() }) {
                                Label("同步", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(Color.accentColor.opacity(0.16))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("打开终端运行 agy 刷新新一轮配额")
                        } else {
                            Text("已重置")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(bucket.percent)%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(percentColor(bucket.percent))
                    }
                }

                HStack {
                    if expired {
                        Text("已重置 · 上轮 \(bucket.percent)%")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(cd.isEmpty ? "重置时间未知" : "剩余 \(cd)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
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
        .background(Color.primary.opacity(expired ? 0.02 : 0.035))
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
                Text("可视化添加或放入 providers/*.json 自动监听")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(showSlotEditor ? "收起" : "+ 添加") {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if !showSlotEditor {
                        editingExistingSlot = false
                        slotDraft = EditableSlotDraft()
                    }
                    showSlotEditor.toggle()
                }
            }
            .buttonStyle(.borderedProminent)
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

    // MARK: Visual Open-Slot Editor

    private func startEditing(_ provider: ProviderQuota) {
        let winKind: String
        let pct: Double
        let resetDate: Date
        if let mo = provider.monthly {
            winKind = "monthly"
            pct = Double(mo.percent)
            resetDate = parseISO8601Date(mo.resetTime) ?? Date().addingTimeInterval(30 * 24 * 3600)
        } else if let wk = provider.weekly {
            winKind = "weekly"
            pct = Double(wk.percent)
            resetDate = parseISO8601Date(wk.resetTime) ?? Date().addingTimeInterval(7 * 24 * 3600)
        } else if let fh = provider.fiveHour {
            winKind = "5h"
            pct = Double(fh.percent)
            resetDate = parseISO8601Date(fh.resetTime) ?? Date().addingTimeInterval(5 * 3600)
        } else {
            winKind = "monthly"
            pct = 80
            resetDate = Date().addingTimeInterval(30 * 24 * 3600)
        }

        slotDraft = EditableSlotDraft(
            id: provider.id,
            name: provider.name,
            shortBadge: provider.shortBadge,
            planTier: provider.planTier ?? "",
            windowKind: winKind,
            remainingPercent: pct,
            resetDate: resetDate
        )
        editingExistingSlot = true
        withAnimation(.easeInOut(duration: 0.16)) {
            showSlotEditor = true
        }
    }

    private func applySlotPreset(id: String, name: String, badge: String, tier: String, kind: String, offsetSeconds: TimeInterval) {
        slotDraft.id = id
        slotDraft.name = name
        slotDraft.shortBadge = badge
        slotDraft.planTier = tier
        slotDraft.windowKind = kind
        slotDraft.resetDate = Date().addingTimeInterval(offsetSeconds)
    }

    private var slotEditorPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(editingExistingSlot ? "编辑开放插槽" : "添加开放插槽")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !editingExistingSlot {
                    HStack(spacing: 4) {
                        presetChip("Cursor") {
                            applySlotPreset(id: "cursor", name: "Cursor", badge: "Cu", tier: "Pro", kind: "monthly", offsetSeconds: 30 * 24 * 3600)
                        }
                        presetChip("GrokBot") {
                            applySlotPreset(id: "grokbot", name: "GrokBot", badge: "G", tier: "SuperGrok", kind: "5h", offsetSeconds: 5 * 3600)
                        }
                        presetChip("Claude") {
                            applySlotPreset(id: "claude", name: "Claude", badge: "Cl", tier: "Pro", kind: "weekly", offsetSeconds: 7 * 24 * 3600)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("品牌名 (如 Cursor)", text: $slotDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onChange(of: slotDraft.name) { newVal in
                        if !editingExistingSlot {
                            let clean = newVal.lowercased().replacingOccurrences(of: "[^a-z0-9_-]", with: "", options: .regularExpression)
                            if !clean.isEmpty { slotDraft.id = clean }
                        }
                    }
                TextField("缩写", text: $slotDraft.shortBadge)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 46)
                TextField("套餐", text: $slotDraft.planTier)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 72)
            }

            HStack {
                Text("周期")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $slotDraft.windowKind) {
                    Text("5 小时").tag("5h")
                    Text("周 (7天)").tag("weekly")
                    Text("月 (30天)").tag("monthly")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("剩余比例")
                        .font(.system(size: 11))
                    Spacer()
                    Text("\(Int(round(slotDraft.remainingPercent)))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(percentColor(Int(round(slotDraft.remainingPercent))))
                }
                Slider(value: $slotDraft.remainingPercent, in: 0...100, step: 1)
                    .controlSize(.small)
            }

            HStack {
                Text("重置时间")
                    .font(.system(size: 11))
                Spacer()
                DatePicker("", selection: $slotDraft.resetDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                if editingExistingSlot {
                    Button("删除", role: .destructive) {
                        vm.onDeleteSlot?(slotDraft.id)
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showSlotEditor = false
                        }
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button("取消") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showSlotEditor = false
                    }
                }
                .controlSize(.small)

                Button("保存") {
                    vm.onSaveSlot?(slotDraft)
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showSlotEditor = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(Color.accentColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func presetChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
            .buttonStyle(.plain)
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

            // Global hotkey picker (2-key summon even when menu bar is crowded)
            HStack {
                Text("全局唤起")
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.hotKeyPreset },
                    set: { vm.onHotKeyChanged?($0) }
                )) {
                    ForEach(HotKeyPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
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

            Divider().opacity(0.45)

            // Optional Antigravity Background Page Sync (Accessibility, Opt-in)
            VStack(alignment: .leading, spacing: 7) {
                Toggle(isOn: Binding(
                    get: { vm.axSyncEnabled },
                    set: { vm.onAXSyncEnabledChanged?($0) }
                )) {
                    HStack(spacing: 4) {
                        Text("Antigravity 页面自动同步")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("实验性")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.16))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if vm.axSyncEnabled {
                    HStack(spacing: 6) {
                        Text(vm.axTrusted ? "辅助功能：已授权 ✓" : "辅助功能：未授权")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(vm.axTrusted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                        Spacer()
                        if !vm.axTrusted {
                            Button("前往授权") {
                                vm.onRequestAXPermission?()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        } else {
                            Button(vm.axIsSyncing ? "读取中..." : "立即同步") {
                                vm.onAXSyncNow?()
                            }
                            .disabled(vm.axIsSyncing)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }

                    HStack {
                        Text("自动间隔")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.axSyncInterval },
                            set: { vm.onAXSyncIntervalChanged?($0) }
                        )) {
                            Text("5分钟").tag(300.0)
                            Text("10分钟").tag(600.0)
                            Text("15分钟").tag(900.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 165)
                        .controlSize(.small)
                    }

                    if !vm.axStatusMessage.isEmpty {
                        HStack(spacing: 6) {
                            Text(vm.axStatusMessage)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            if !vm.axLastDiagnostic.isEmpty {
                                Button("诊断") {
                                    vm.onCopyAXDiagnostic?()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.accentColor)
                                .help("复制 AX 解析诊断信息到剪贴板")
                            }
                        }
                    }

                    Text("需保持一个 Antigravity 窗口停在「设置 → 模型配额与用量」且未最小化；登录凭证始终留在官方应用内。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
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

            Button(action: { vm.onLaunchAgySync?() }) {
                Label("终端同步", systemImage: "terminal")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("在系统终端打开 agy CLI 刷新官方配额快照")

            Text("·").foregroundStyle(.quaternary)

            Button(action: { vm.onCopyAgyCommand?() }) {
                Label(vm.copiedToast ? "已复制" : "复制 agy", systemImage: vm.copiedToast ? "checkmark" : "doc.on.doc")
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

    private func isResetExpired(resetIso: String, now: Date) -> Bool {
        guard let target = parseISO8601Date(resetIso) else { return false }
        return target.timeIntervalSince(now) <= 0
    }

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
