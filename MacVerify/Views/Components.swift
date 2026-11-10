// Views/Components.swift
//
// 展示层基础件。改造的重点不是「好看」，而是让一屏能读到更多事实：
// - 卡片的标题不再居中，统一左对齐 + 图标 + 右侧操作；
// - 键值不再「标签在左、值飘到窗口最右」，改为标签定宽、值紧跟在后面，
//   并且支持两列并排，屏幕宽度真正被用上；
// - 状态用 7pt 圆点 + 文字表达，不再给每一行都套一个彩色胶囊。
import SwiftUI
import AppKit

// MARK: - 容器

/// 卡片。标题可选：给了标题就渲染一条带分隔线的卡头。
struct Card<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var trailing: AnyView? = nil
    var padding: CGFloat = Metrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                HStack(spacing: Space.xs + 2) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(Typo.icon(11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(title).font(Typo.title)
                    Spacer(minLength: Space.sm)
                    if let trailing = trailing { trailing }
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 9)

                Rectangle()
                    .fill(Surface.hairline)
                    .frame(height: 1)
            }

            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
    }
}

/// 页面标题区：标题 + 说明 + 右侧操作。
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.display)
                if let subtitle = subtitle {
                    Text(subtitle).font(Typo.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: Space.md)
            if let trailing = trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

/// 卡片内的分组标签（小号、大写、左对齐）。
struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon = icon {
                Image(systemName: icon).font(Typo.icon(10, weight: .semibold))
            }
            Text(title)
                .font(Typo.captionStrong)
                .textCase(.uppercase)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - 状态

enum BadgeLevel {
    case ok, warning, critical, neutral

    /// 全 App 唯一的状态色来源。其他文件不要再写 .green / .orange / .red。
    var color: Color {
        switch self {
        case .ok: return StatusPalette.ok
        case .warning: return StatusPalette.warning
        case .critical: return StatusPalette.critical
        case .neutral: return StatusPalette.neutral
        }
    }

    /// 供 VoiceOver 朗读的状态词，避免只念出一串字符
    var spoken: String {
        switch self {
        case .ok: return T("通过", "pass")
        case .warning: return T("需确认", "needs confirmation")
        case .critical: return T("不一致", "mismatch")
        case .neutral: return T("不可用", "unavailable")
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .neutral: return "minus.circle"
        }
    }
}

/// 7pt 状态点。行内表达状态用它，比给每行套胶囊安静得多。
struct StatusDot: View {
    var level: BadgeLevel = .neutral
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: size, height: size)
    }
}

struct StatusBadge: View {
    let text: String
    var level: BadgeLevel = .neutral

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: level.symbol).font(Typo.icon(9, weight: .bold))
            Text(text).font(Typo.captionStrong)
        }
        .foregroundColor(level.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(level.color.opacity(0.10))
        .cornerRadius(Radius.badge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.spoken)：\(text)")
    }
}

// MARK: - 键值

/// 数值的三种「没有值」情形，必须区分开：
/// - normal：有值
/// - unavailable：本机不提供（读不到），配减号，提示这是系统限制
/// - absent：确实不存在（如没插 USB 设备、没有电池），配斜杠，提示这是事实
/// 两者都不该显示成 0 或用空白糊过去。
enum ValueState {
    case normal, unavailable, absent
}

/// 一条事实：标签 + 值。值紧跟标签，不再被推到窗口右侧。
struct Fact {
    let label: String
    let value: String
    var mono: Bool = false
    var color: Color = .primary
    var state: ValueState = .normal

    init(_ label: String, _ value: String, mono: Bool = false,
         color: Color = .primary, state: ValueState = .normal) {
        self.label = label
        self.value = value
        self.mono = mono
        self.color = color
        self.state = state
    }
}

/// 多列事实表。列数根据内容长度选 2 列（默认）或 1 列。
struct FactGrid: View {
    let facts: [Fact]
    var columns: Int = 2
    var labelWidth: CGFloat = 104

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 160), spacing: Space.xl, alignment: .leading),
              count: max(columns, 1))
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 1) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(fact.label)
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        // 标签定宽是为了让值成列对齐；遇到 "Marketing name" 这种长标签
                        // 宁可轻微缩字，也不要截成 "Marketing na…"
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .frame(width: labelWidth, alignment: .leading)
                    valueText(fact)
                    Spacer(minLength: 0)
                }
                .frame(height: Metrics.row)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fact.label)：\(fact.value)")
            }
        }
    }

    @ViewBuilder
    private func valueText(_ fact: Fact) -> some View {
        if fact.state == .normal {
            Text(fact.value)
                .font(fact.mono ? Typo.mono : Typo.value)
                .foregroundColor(fact.color)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .textSelection(.enabled)
        } else {
            HStack(spacing: 3) {
                Image(systemName: fact.state == .unavailable ? "minus.circle" : "slash.circle")
                    .font(Typo.icon(9))
                Text(fact.value).font(Typo.body)
            }
            .foregroundColor(StatusPalette.neutral)
            .lineLimit(1)
        }
    }
}

/// 单列键值行（带分隔线）。用于细节表、需要逐行阅读的地方。
struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var valueColor: Color = .primary
    var isLast: Bool = false
    var state: ValueState = .normal

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Text(label).font(Typo.body).foregroundColor(.secondary)
                Spacer(minLength: Space.sm)
                if state == .normal {
                    Text(value)
                        .font(monospaced ? Typo.mono : Typo.value)
                        .foregroundColor(valueColor)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                } else {
                    HStack(spacing: Space.xs) {
                        Image(systemName: state == .unavailable ? "minus.circle" : "slash.circle")
                            .font(Typo.icon(10))
                        Text(value).font(Typo.body)
                    }
                    .foregroundColor(StatusPalette.neutral)
                }
            }
            .padding(.vertical, 5)
            .frame(minHeight: Metrics.row)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label)：\(value)")
            if !isLast {
                Rectangle().fill(Surface.hairline).frame(height: 1)
            }
        }
    }
}

// MARK: - 指标块

/// 紧凑指标块：标题一行、数值一行，高约 62。改造前是 110 高的空白块。
struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    /// 还没有数据（如未开始测试）。此时不用 20pt 显示一个破折号——
    /// 那个字符在大字号下会变成一条粗黑杠，看着像加载失败。
    var placeholder: Bool = false
    var detail: String? = nil
    var color: Color = .secondary
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon).font(Typo.icon(9, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(Typo.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            if placeholder {
                Text(value)
                    .font(Typo.title)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(height: 24, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(Typo.metric)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = unit {
                        Text(unit).font(Typo.caption).foregroundColor(.secondary)
                    }
                }
                .frame(height: 24, alignment: .leading)
            }
            if let detail = detail {
                Text(detail).font(Typo.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Surface.well))
    }
}

struct RingGauge: View {
    let title: String
    let value: Double
    var total: Double = 100
    var unit: String = "%"
    var color: Color = .accentColor
    var caption: String? = nil
    var size: CGFloat = 96
    /// 环心的自定义文案。用于「157 次」「—」（读数不可用）这类不适合按单位格式化的值。
    /// 给了它就不再渲染 unit 后缀。
    var centerText: String? = nil

    private var ratio: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }

    var body: some View {
        VStack(spacing: Space.xs + 2) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(ratio))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    if let centerText = centerText {
                        Text(centerText).font(Typo.metric)
                    } else {
                        Text(unit == "%" ? String(format: "%.0f", value) : String(format: "%.1f", value))
                            .font(Typo.metric)
                        Text(unit).font(Typo.caption).foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: size, height: size)

            Text(title).font(Typo.caption).foregroundColor(.secondary)
            if let caption = caption {
                Text(caption).font(Typo.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 折线图（Canvas，兼容 macOS 12）

struct LineChart: View {
    let values: [Double]
    var color: Color = .accentColor
    var unit: String = ""

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let span = max(maxValue - minValue, 0.001)
            let padding = span * 0.15
            let lower = minValue - padding
            let upper = maxValue + padding

            ZStack {
                Path { path in
                    for index in 0...3 {
                        let y = size.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)

                if values.count > 1 {
                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = (value - lower) / (upper - lower)
                            let y = size.height - size.height * CGFloat(ratio)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = (value - lower) / (upper - lower)
                            let y = size.height - size.height * CGFloat(ratio)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: size.height))
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.01)],
                                         startPoint: .top, endPoint: .bottom))
                } else {
                    Text(T("采样中…", "Sampling…"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - 提示条

struct NoticeBar: View {
    let text: String
    var level: BadgeLevel = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: level.symbol).font(Typo.icon(10, weight: .semibold)).foregroundColor(level.color)
                .padding(.top, 1)
            Text(text).font(Typo.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(level.color.opacity(0.07))
        .cornerRadius(Radius.control)
    }
}

// MARK: - 按钮

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = .accentColor
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs + 1) {
                if let icon = icon { Image(systemName: icon).font(Typo.icon(10, weight: .semibold)) }
                Text(title).font(Typo.bodyStrong)
            }
            .padding(.horizontal, Space.md + 2)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(color.opacity(enabled ? 1 : 0.4))
            .cornerRadius(Radius.control)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs + 1) {
                if let icon = icon { Image(systemName: icon).font(Typo.icon(10, weight: .semibold)) }
                Text(title).font(Typo.body)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(Radius.control)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// 分段选择（测试时长、文件大小这类少量互斥选项）。
struct SegmentedPicker<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button(action: { selection = option }) {
                    Text(title(option))
                        .font(Typo.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(isSelected ? Surface.fill : Color.clear)
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(Radius.badge)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - 格式化

enum Format {
    /// 使用十进制单位（1 GB = 10^9 字节），与磁盘厂商标称、finder/diskutil 一致。
    /// 原先的 .binary 会把 738GB 显示成 687GB，与系统其它位置对不上。
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useTB]
        return formatter.string(fromByteCount: Int64(value))
    }

    static func gb(_ value: Int) -> String { "\(value) GB" }

    /// 大整数计数（如写入命令数），按本地化千分位
    static func count(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Localization.shared.locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func speed(_ value: Double) -> String {
        // 与磁盘容量统一使用十进制（1 GB/s = 1000 MB/s）
        value >= 1000 ? String(format: "%.2f GB/s", value / 1000) : String(format: "%.0f MB/s", value)
    }

    /// 按应用内语言格式化日期，避免与界面语言不一致
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
