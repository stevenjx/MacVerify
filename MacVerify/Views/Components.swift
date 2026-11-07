// Views/Components.swift
import SwiftUI
import AppKit

// MARK: - 容器

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold))
                if let subtitle = subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let trailing = trailing { trailing }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - 行 / 徽标

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var valueColor: Color = .primary
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 13)).foregroundColor(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(monospaced ? .system(size: 13, design: .monospaced) : .system(size: 13, weight: .medium))
                    .foregroundColor(valueColor)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 9)
            if !isLast { Divider().opacity(0.5) }
        }
    }
}

enum BadgeLevel {
    case ok, warning, critical, neutral

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .secondary
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
        HStack(spacing: 5) {
            Image(systemName: level.symbol).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(level.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.color.opacity(0.12))
        .cornerRadius(6)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail = detail {
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 1))
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(unit).font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            if let caption = caption {
                Text(caption).font(.system(size: 10)).foregroundColor(.secondary)
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
                        .font(.system(size: 11))
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: level.symbol).font(.system(size: 11, weight: .semibold)).foregroundColor(level.color)
            Text(text).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(level.color.opacity(0.08))
        .cornerRadius(8)
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
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundColor(.white)
            .background(color.opacity(enabled ? 1 : 0.4))
            .cornerRadius(7)
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
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(7)
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
