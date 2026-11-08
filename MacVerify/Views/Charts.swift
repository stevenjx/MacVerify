// Views/Charts.swift
//
// 轻量图表：不依赖 Swift Charts（项目最低支持 macOS 12），
// 也不引入任何外部机型基准——只做「同一台机器自己前后几次」的相对比较。
import SwiftUI

// MARK: - 横向条形图（兼容 macOS 12，不依赖 Swift Charts）

struct BarRow: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let valueText: String
    var color: Color = Color.accentColor
}

/// 以本组最大值为 100% 画条。
/// 刻意不提供"对照机型基准"参数：外部基准会过期，写错就是新的假数据。
struct HorizontalBars: View {
    let rows: [BarRow]
    var labelWidth: CGFloat = 92

    var body: some View {
        let maxValue = max(rows.map(\.value).max() ?? 0, 0.0001)
        VStack(spacing: Space.xs + 2) {
            ForEach(rows) { row in
                HStack(spacing: Space.sm) {
                    Text(row.label)
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(row.color.opacity(0.8))
                                .frame(width: max(2, geometry.size.width * CGFloat(row.value / maxValue)))
                        }
                    }
                    .frame(height: 10)

                    Text(row.valueText)
                        .font(Typo.mono)
                        .foregroundColor(.primary)
                        .frame(width: 96, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
