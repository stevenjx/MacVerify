// Views/PanelTest.swift
//
// 屏幕检查：参照 EIZO Monitor Test 的测试项与呈现方式重做。
// 14 个全屏测试项覆盖：综合测试图、坏点（黑/白/三原色）、均匀性（三档灰）、
// 渐变色阶（8 / 256 级）、文字锐度、可视角度、响应时间（移动方块）。
//
// 全屏用独立的无边框窗口，隐藏 Dock 与菜单栏；空格或点击下一个，← → 切换，Esc 退出。
// 不做 gamma 与「色距」两项：那两项要用户边看边调到「看不出差别」，
// 结果完全依赖主观判断，验机时写不出可复核的结论，所以宁可不做。
import SwiftUI
import AppKit

// MARK: - 测试项

enum PanelSolid {
    case black, white, red, green, blue, gray25, gray50, gray75

    var color: Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .red: return Color(red: 1, green: 0, blue: 0)
        case .green: return Color(red: 0, green: 1, blue: 0)
        case .blue: return Color(red: 0, green: 0, blue: 1)
        case .gray25: return Color(white: 0.25)
        case .gray50: return Color(white: 0.50)
        case .gray75: return Color(white: 0.75)
        }
    }
}

struct PanelStep: Identifiable {
    enum Kind {
        case pattern
        case solid(PanelSolid)
        case gradient(Int)
        case sharpness
        case viewingAngle
        case motion
    }

    let id = UUID()
    let number: Int
    let title: String
    let kind: Kind
}

enum PanelTestSuite {
    /// 页面里的清单与全屏测试共用同一份定义，避免两处文案对不上
    static func steps() -> [PanelStep] {
        var list: [PanelStep] = [
            PanelStep(number: 1, title: T("综合测试图", "Test pattern"), kind: .pattern)
        ]
        let solids: [(PanelSolid, String)] = [
            (.black, T("坏点 · 黑", "Defective pixels · black")),
            (.white, T("坏点 · 白", "Defective pixels · white")),
            (.red, T("坏点 · 红", "Defective pixels · red")),
            (.green, T("坏点 · 绿", "Defective pixels · green")),
            (.blue, T("坏点 · 蓝", "Defective pixels · blue")),
            (.gray25, T("均匀性 · 25% 灰", "Uniformity · 25% gray")),
            (.gray50, T("均匀性 · 50% 灰", "Uniformity · 50% gray")),
            (.gray75, T("均匀性 · 75% 灰", "Uniformity · 75% gray"))
        ]
        for (index, item) in solids.enumerated() {
            list.append(PanelStep(number: index + 2, title: item.1, kind: .solid(item.0)))
        }
        list.append(PanelStep(number: 10, title: T("渐变 · 8 级", "Gradient · 8 steps"), kind: .gradient(8)))
        list.append(PanelStep(number: 11, title: T("渐变 · 256 级", "Gradient · 256 steps"), kind: .gradient(256)))
        list.append(PanelStep(number: 12, title: T("文字锐度", "Sharpness"), kind: .sharpness))
        list.append(PanelStep(number: 13, title: T("可视角度", "Viewing angle"), kind: .viewingAngle))
        list.append(PanelStep(number: 14, title: T("响应时间", "Response time"), kind: .motion))
        return list
    }
}

// MARK: - 状态

final class PanelTestState: ObservableObject {
    let steps: [PanelStep]
    @Published var index = 0
    @Published var showsChrome = true

    init() {
        steps = PanelTestSuite.steps()
    }

    var current: PanelStep { steps[max(0, min(index, steps.count - 1))] }

    func next() {
        index = (index + 1) % steps.count
        showsChrome = true
    }

    func previous() {
        index = (index - 1 + steps.count) % steps.count
        showsChrome = true
    }
}

// MARK: - 全屏

struct PanelTestOverlayView: View {
    @ObservedObject var state: PanelTestState
    let onExit: () -> Void

    private var step: PanelStep { state.current }

    /// 浅底画面用深色控件，深底画面用浅色控件
    private var chromeColor: Color {
        switch step.kind {
        case .solid(let value):
            switch value {
            case .white, .gray25, .gray50, .gray75, .red, .green: return .black
            default: return .white
            }
        case .pattern, .sharpness: return .black
        case .gradient, .viewingAngle, .motion: return .white
        }
    }

    var body: some View {
        ZStack {
            PanelStepView(step: step)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .center, spacing: 10) {
                    Text(String(format: "%02d / %02d", step.number, state.steps.count))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(chromeColor.opacity(0.10))
                        .cornerRadius(4)
                    Text(step.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("Esc")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(chromeColor.opacity(0.10))
                        .cornerRadius(4)
                }
                .foregroundColor(chromeColor.opacity(0.75))
                .padding(20)

                Spacer()

                Text(T("空格 / 点击 下一个 · ← → 切换 · Esc 退出",
                       "Space or click for next · ← → to navigate · Esc to exit"))
                    .font(.system(size: 11))
                    .foregroundColor(chromeColor.opacity(0.55))
                    .padding(16)
            }
            .opacity(state.showsChrome ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: state.showsChrome)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.next() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                state.showsChrome = false
            }
        }
    }
}

private struct PanelStepView: View {
    let step: PanelStep

    var body: some View {
        switch step.kind {
        case .pattern:
            TestPatternView()
        case .solid(let value):
            value.color
        case .gradient(let count):
            GradientStepsView(steps: count)
        case .sharpness:
            SharpnessView()
        case .viewingAngle:
            ViewingAngleView()
        case .motion:
            MotionView()
        }
    }
}

// MARK: - 各项画面

/// 综合测试图：灰阶条 + 中心同心圆与十字 + 三原色条 + 单像素线栅
private struct TestPatternView: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

            // 顶部 16 级灰阶
            let bandHeight = size.height * 0.12
            for step in 0..<16 {
                let rect = CGRect(x: size.width / 16 * CGFloat(step), y: 0,
                                  width: size.width / 16 + 1, height: bandHeight)
                context.fill(Path(rect), with: .color(Color(white: Double(step) / 15)))
            }

            // 中心同心圆 + 十字线：圆要正、线要直，变形说明缩放或面板有问题
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for factor in [0.06, 0.12, 0.18, 0.26] {
                let radius = min(size.width, size.height) * factor
                let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
                context.stroke(circle, with: .color(.black), lineWidth: 1.5)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: 0, y: center.y))
            cross.addLine(to: CGPoint(x: size.width, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: bandHeight))
            cross.addLine(to: CGPoint(x: center.x, y: size.height))
            context.stroke(cross, with: .color(.black.opacity(0.7)), lineWidth: 1)

            // 底部三原色 + 二次色
            let colours: [Color] = [
                Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0),
                Color(red: 0, green: 0, blue: 1), Color(red: 0, green: 1, blue: 1),
                Color(red: 1, green: 0, blue: 1), Color(red: 1, green: 1, blue: 0)
            ]
            let colourHeight = size.height * 0.08
            for (index, colour) in colours.enumerated() {
                let rect = CGRect(x: size.width / 6 * CGFloat(index),
                                  y: size.height - colourHeight,
                                  width: size.width / 6 + 1, height: colourHeight)
                context.fill(Path(rect), with: .color(colour))
            }

            // 左上角细线栅：能看清每一根线说明没有做过缩放插值
            var lines = Path()
            var x: CGFloat = 24
            while x < size.width * 0.30 {
                lines.move(to: CGPoint(x: x, y: bandHeight + 24))
                lines.addLine(to: CGPoint(x: x, y: bandHeight + 104))
                x += 3
            }
            context.stroke(lines, with: .color(.black), lineWidth: 1)
        }
    }
}

private struct GradientStepsView: View {
    let steps: Int

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let width = size.width / CGFloat(steps)
            for index in 0..<steps {
                let rect = CGRect(x: width * CGFloat(index), y: 0,
                                  width: width + 1, height: size.height)
                context.fill(Path(rect), with: .color(Color(white: Double(index) / Double(max(steps - 1, 1)))))
            }
        }
    }
}

private struct SharpnessView: View {
    private let sample = "MacVerify 0123456789 — The quick brown fox jumps over the lazy dog."

    var body: some View {
        ZStack {
            Color.white
            VStack(alignment: .leading, spacing: 26) {
                ForEach([10, 12, 18], id: \.self) { size in
                    Text(sample)
                        .font(.system(size: CGFloat(size)))
                        .foregroundColor(.black)
                }

                // 反相：白字黑底，检查另一种极性下的边缘
                Text(sample)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)

                Text(T("每一行都应边缘清晰、没有彩色描边或重影；发虚说明缩放不是整数倍或面板有问题。",
                       "Every line should have crisp edges with no colour fringing or ghosting. Blur means non-integer scaling or a panel problem."))
                    .font(.system(size: 11))
                    .foregroundColor(.black.opacity(0.55))
            }
            .padding(60)
        }
    }
}

private struct ViewingAngleView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = min(size.width, size.height) * 0.08
            let inset: CGFloat = 90
            let points = [
                CGPoint(x: size.width / 2, y: size.height / 2),
                CGPoint(x: inset + radius, y: inset + radius),
                CGPoint(x: size.width - inset - radius, y: inset + radius),
                CGPoint(x: inset + radius, y: size.height - inset - radius),
                CGPoint(x: size.width - inset - radius, y: size.height - inset - radius)
            ]

            Canvas { context, _ in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.18)))
                for point in points {
                    let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                        width: radius * 2, height: radius * 2))
                    context.stroke(circle, with: .color(.white), lineWidth: 3)
                }
            }
        }
    }
}

/// 移动方块：拖影越短越好。以约 600 pt/s 横扫，下方留一条静止参考条对比。
private struct MotionView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Color(white: 0.25)))

                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let travel = size.width + 240
                let x = (seconds * 600).truncatingRemainder(dividingBy: travel) - 120
                let block = CGRect(x: x, y: size.height / 2 - 70, width: 60, height: 140)
                context.fill(Path(block), with: .color(.white))

                let reference = CGRect(x: 0, y: size.height / 2 + 110, width: 60, height: 8)
                context.fill(Path(reference), with: .color(.white.opacity(0.7)))
            }
        }
    }
}

// MARK: - 窗口控制

final class PanelTestController {
    static let shared = PanelTestController()

    private var window: NSWindow?
    private var monitor: Any?
    private var state: PanelTestState?
    private var onFinish: (() -> Void)?

    private init() {}

    /// startIndex 只给自动化核验用（MACVERIFY_PANEL_TEST=12 直接停在某一项），正常点击始终从 0 开始。
    func start(startIndex: Int = 0, onFinish: @escaping () -> Void) {
        guard window == nil else { return }
        self.onFinish = onFinish

        // 全屏测试要落在用户正在看的这块屏上：接外接显示器时 NSScreen.main
        // 可能是另一块，按 App 主窗口所在的屏取，才和用户点的那个页面一致。
        let host = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.level == .normal }
        let screen = host?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let state = PanelTestState()
        state.index = max(0, min(startIndex, state.steps.count - 1))
        self.state = state

        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.setFrame(frame, display: true)
        window.contentView = NSHostingView(rootView: PanelTestOverlayView(state: state, onExit: { [weak self] in
            self?.stop()
        }))

        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSCursor.hide()
        // 从命令行或后台启动时 App 可能不是前台进程，不激活的话窗口建出来也不可见
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let state = self.state else { return event }
            switch event.keyCode {
            case 53:
                self.stop()
                return nil
            case 49, 124:
                state.next()
                return nil
            case 123:
                state.previous()
                return nil
            default:
                return event
            }
        }

        self.window = window
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        NSApp.presentationOptions = []
        NSCursor.unhide()
        window?.orderOut(nil)
        window = nil
        state = nil

        let finish = onFinish
        onFinish = nil
        finish?()
    }
}
