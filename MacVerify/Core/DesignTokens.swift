// Core/DesignTokens.swift
//
// 界面令牌：字号、间距、圆角、表面、状态色。
//
// 这一版的原则是「密度优先」：验机是快速扫读，不是阅读文档。
// 改造前每页都是单列长条、行高 27、值被推到窗口最右侧，屏幕右侧一片空白，
// 所以看起来既松散又不专业。现在：
// - 字号仍只有 5 档（22 / 20 / 13 / 13 / 11），但标题从 26 bold 收到 22 semibold，
//   层级靠字重与颜色拉开，而不是靠不断加大字号；
// - 行高 26、卡片内边距 14、页面间距 12，信息密度接近 macOS 系统信息;
// - 所有卡片的区块标题一律左对齐（改造前因为 VStack 默认居中，标题飘在卡片中间）。
import SwiftUI
import AppKit

// MARK: - 字体

enum Typo {
    /// 页面主标题
    static let display = Font.system(size: 22, weight: .semibold)
    /// 指标数字（仪表盘、统计块）
    static let metric = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    /// 卡片标题、区块标题
    static let title = Font.system(size: 13, weight: .semibold)
    /// 正文
    static let body = Font.system(size: 13)
    /// 正文强调（行标题）
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// 数值列：等宽数字，纵向对齐时不跳动
    static let value = Font.system(size: 13, weight: .medium).monospacedDigit()
    /// 次要说明
    static let caption = Font.system(size: 11)
    /// 次要说明强调（徽章文字、分组标题）
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    /// 序列号、ID、指纹、路径
    static let mono = Font.system(size: 11, design: .monospaced)
    /// 图标（与文字大小解耦，仅用于 SF Symbol）
    static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }
}

// MARK: - 间距、圆角、密度

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
}

enum Radius {
    static let card: CGFloat = 8
    static let control: CGFloat = 6
    static let badge: CGFloat = 5
    static let tile: CGFloat = 6
}

enum Metrics {
    /// 页面内容最大宽度。窗口拉很宽时不让文字行横跨整个屏幕
    static let pageMaxWidth: CGFloat = 1020
    /// 页面外边距
    static let pagePadding: CGFloat = 20
    /// 页面内卡片之间
    static let pageGap: CGFloat = 12
    /// 卡片内边距
    static let cardPadding: CGFloat = 14
    /// 键值行高度（含上下留白）
    static let row: CGFloat = 26
}

// MARK: - 状态色

/// 状态色。语义单一：只表达「核对通过 / 需确认 / 不一致 / 不可用」，绝不用于装饰。
/// 浅色模式刻意不用系统 .green（小字对比度不足），改用加深过的值。
enum StatusPalette {
    static let ok = dynamic(light: 0x1B7F3B, dark: 0x4ADE80)
    static let warning = dynamic(light: 0xA85B00, dark: 0xFBBF24)
    static let critical = dynamic(light: 0xB42318, dark: 0xF87171)
    static let neutral = dynamic(light: 0x6B7280, dark: 0x9CA3AF)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color(isDark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

// MARK: - 表面

enum Surface {
    /// 窗口底色：比卡片略深，卡片才「浮」得起来
    static let page = Color(NSColor.windowBackgroundColor)
    /// 卡片底色
    static let fill = Color(NSColor.controlBackgroundColor)

    /// 内嵌块（指标块、代码块）：比卡片再沉一档
    static var well: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.025)
        })
    }

    /// 浅色模式用淡描边，深色模式下描边几乎看不见，改为轻微提亮
    static var border: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.08)
        })
    }

    /// 卡片内的分隔线
    static var hairline: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.06)
        })
    }
}

// MARK: - 业务状态 → 视觉状态的唯一映射
//
// 改造前 AuditState / FindingStatus 各自在视图里写了一遍 color(for:)，
// 同一个「不一致」在三个文件里各有一种写法。现在只在这里映射一次。

extension AuditState {
    var badgeLevel: BadgeLevel {
        switch self {
        case .consistent: return .ok
        case .notice: return .warning
        case .inconsistent: return .critical
        case .unavailable: return .neutral
        }
    }

    var color: Color { badgeLevel.color }
}

extension FindingStatus {
    var badgeLevel: BadgeLevel {
        switch self {
        case .passed: return .ok
        case .warning: return .warning
        case .failed: return .critical
        case .info: return .neutral
        }
    }

    var color: Color { badgeLevel.color }
}

/// 评分 / 健康度阈值配色。两个页面原本各写了一份一模一样的 scoreColor，合并到这里。
enum ScorePalette {
    static func color(_ score: Int) -> Color {
        if score >= 85 { return StatusPalette.ok }
        if score >= 70 { return StatusPalette.warning }
        return StatusPalette.critical
    }
}

/// 分类色（图表系列、指标块）。只用于区分「不同系列」，不表达好坏——
/// 表达好坏一律用 StatusPalette。
enum SeriesPalette {
    static let cpuSingle = Color.accentColor
    static let cpuMulti = Color.purple
    static let gpuLive = Color.cyan
    static let gpuPeak = Color.teal
}
