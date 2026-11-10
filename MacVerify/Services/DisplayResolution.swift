// Services/DisplayResolution.swift
//
// 面板原生分辨率的判定。
//
// 为什么需要单独一段逻辑：Intel Mac 在「显示器 › 更多空间」这类缩放下，系统会渲染一个
// 比面板更大的帧缓冲（2880×1800 的面板会渲染 3360×2100 再缩回去）。此时按「所有模式里
// 像素面积最大的那个」取原生值，会取到缩放后的 3360×2100，和系统信息里的 2880×1800 对不上。
//
// 正确做法是认 kDisplayModeNativeFlag（CGDisplayMode 的 0x02000000）：带这个标志的
// 是面板自己的模式，缩放出来的模式不带。没有该标志的显示器（部分虚拟/外接屏）才退回按面积取最大。
import Foundation

enum DisplayResolution {

    struct Mode {
        let pixelWidth: Int
        let pixelHeight: Int
        let isNative: Bool

        init(pixelWidth: Int, pixelHeight: Int, isNative: Bool) {
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.isNative = isNative
        }
    }

    /// kDisplayModeNativeFlag，见 CGDisplayMode.h
    static let nativeFlag: UInt32 = 0x0200_0000

    static func native(from modes: [Mode]) -> (width: Int, height: Int)? {
        let usable = modes.filter { $0.pixelWidth > 0 && $0.pixelHeight > 0 }
        // 有原生模式就只在原生模式里挑；一个都没有（虚拟屏、部分外接屏）才退回全部模式
        let candidates = usable.contains(where: { $0.isNative })
            ? usable.filter { $0.isNative }
            : usable

        guard let best = candidates.max(by: { area($0) < area($1) }) else { return nil }
        return (best.pixelWidth, best.pixelHeight)
    }

    private static func area(_ mode: Mode) -> Int {
        mode.pixelWidth * mode.pixelHeight
    }

}
