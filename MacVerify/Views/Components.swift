// Views/Components.swift
import SwiftUI
import AppKit

// MARK: - 容器

struct Card<Content: View>: View {
    var padding: CGFloat = Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Surface.border, lineWidth: 1)
            )
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.display)
                if let subtitle = subtitle {
                    Text(subtitle).font(Typo.body).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let trailing = trailing { trailing }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: Space.xs + 1) {
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

// MARK: - 行 / 徽标

/// 数值的三种「没有值」情形，必须区分开：
/// - normal：有值
/// - unavailable：本机不提供（读不到），配减号，提示这是系统限制
/// - absent：确实不存在（如没插 USB 设备、没有电池），配斜杠，提示这是事实
/// 两者都不该显示成 0 或用空白糊过去。
enum ValueState {
    case normal, unavailable, absent
}

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var valueColor: Color = .primary
    var isLast: Bool = false
    var state: ValueState = .normal

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Text(label).font(Typo.body).foregroundColor(.secondary)
                Spacer(minLength: Space.md)
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
            // 13pt 正文 + 上下各 7，行高约 27；改造前是 9pt/13pt 混排，行高压到 22
            .padding(.vertical, 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label)：\(value)")
            if !isLast { Divider().opacity(Surface.dividerOpacity) }
        }
    }
}

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

struct StatusBadge: View {
    let text: String
    var level: BadgeLevel = .neutral

    var body: some View {
        HStack(spacing: Space.xs + 1) {
            Image(systemName: level.symbol).font(Typo.icon(10, weight: .bold))
            Text(text).font(Typo.captionStrong)
        }
        .foregroundColor(level.color)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(level.color.opacity(0.12))
        .cornerRadius(Radius.badge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.spoken)：\(text)")
    }
}

// MARK: - 指标

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var color: Color = .accentColor
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs + 2) {
                if let icon = icon {
                    Image(systemName: icon).font(Typo.icon(11, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(Typo.caption).foregroundColor(.secondary)
            }
            Text(value)
                .font(Typo.metric)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail = detail {
                Text(detail).font(Typo.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Surface.border, lineWidth: 1))
    }
}

struct RingGauge: View {
    let title: String
    let value: Double
    var total: Double = 100
    var unit: String = "%"
    var color: Color = .accentColor
    var caption: String? = nil

    private var ratio: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(ratio))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(unit == "%" ? String(format: "%.0f", value) : String(format: "%.1f", value))
                        .font(Typo.metric)
                    Text(unit).font(Typo.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            Text(title).font(Typo.body).foregroundColor(.secondary)
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
                // 网格
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
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
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
            Image(systemName: level.symbol).font(Typo.icon(11, weight: .semibold)).foregroundColor(level.color)
            // 提示条承载的是「不可用/无对照」这类关键说明，用正文号而不是小字，避免被跳过
            Text(text).font(Typo.body).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .background(level.color.opacity(0.08))
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
            HStack(spacing: Space.xs + 2) {
                if let icon = icon { Image(systemName: icon).font(Typo.icon(11, weight: .semibold)) }
                Text(title).font(Typo.bodyStrong)
            }
            .padding(.horizontal, Space.md + 2)
            .padding(.vertical, 7)
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
            HStack(spacing: Space.xs + 2) {
                if let icon = icon { Image(systemName: icon).font(Typo.icon(11, weight: .semibold)) }
                Text(title).font(Typo.body)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(Radius.control)
        }
        .buttonStyle(.plain)
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
