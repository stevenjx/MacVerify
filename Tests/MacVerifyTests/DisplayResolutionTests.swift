// Tests/MacVerifyTests/DisplayResolutionTests.swift
import XCTest
@testable import MacVerifyCore

/// 原生分辨率判定。Intel 机器把缩放帧缓冲当成原生值，是这一版要修的报错来源。
final class DisplayResolutionTests: XCTestCase {

    private func mode(_ w: Int, _ h: Int, native: Bool = false) -> DisplayResolution.Mode {
        DisplayResolution.Mode(pixelWidth: w, pixelHeight: h, isNative: native)
    }

    /// 真实场景：15" Intel（面板 2880×1800）选了「更多空间」，帧缓冲是 3360×2100，
    /// 体积更大但并不是原生模式
    func testIgnoresScaledFramebufferEvenWhenLarger() {
        let modes = [
            mode(3360, 2100),
            mode(2880, 1800, native: true),
            mode(1920, 1200),
            mode(1680, 1050)
        ]
        let native = DisplayResolution.native(from: modes)
        XCTAssertEqual(native?.width, 2880)
        XCTAssertEqual(native?.height, 1800)
    }

    /// 同一面板会有多个刷新率的原生模式，尺寸相同，随便取一个都对
    func testMultipleNativeRefreshRates() {
        let modes = [
            mode(3024, 1964, native: true),
            mode(3024, 1964, native: true),
            mode(3024, 1964, native: true),
            mode(1512, 982)
        ]
        XCTAssertEqual(DisplayResolution.native(from: modes)?.width, 3024)
        XCTAssertEqual(DisplayResolution.native(from: modes)?.height, 1964)
    }

    /// 没有原生标志的显示器（虚拟屏、部分外接屏）退回按面积取最大
    func testFallsBackToLargestWhenNoNativeFlag() {
        let modes = [mode(1920, 1080), mode(2560, 1440), mode(3840, 2160), mode(1280, 720)]
        XCTAssertEqual(DisplayResolution.native(from: modes)?.width, 3840)
        XCTAssertEqual(DisplayResolution.native(from: modes)?.height, 2160)
    }

    /// 原生标志只在原生集合里比较，不会被更大的非原生模式带走
    func testPicksLargestNativeWhenSeveralDiffer() {
        let modes = [mode(1280, 800, native: true), mode(2560, 1600, native: true), mode(3840, 2400)]
        XCTAssertEqual(DisplayResolution.native(from: modes)?.width, 2560)
    }

    func testEmptyOrInvalidInput() {
        XCTAssertNil(DisplayResolution.native(from: []))
        XCTAssertNil(DisplayResolution.native(from: [mode(0, 0), mode(0, 1080)]))
    }
}
