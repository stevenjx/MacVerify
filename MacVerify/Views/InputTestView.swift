// Views/InputTestView.swift
import SwiftUI
import AppKit

// MARK: - 数据

struct KeyCap: Identifiable {
    let id = UUID()
    let code: UInt16
    let label: String
    var weight: CGFloat = 1
    var count: Int = 0
    var isDown = false
}

struct TouchStroke {
    var points: [CGPoint] = []
    var pressures: [CGFloat] = []
}

// MARK: - 触控板画布

struct TrackpadCanvas: NSViewRepresentable {
    @Binding var resetToken: Int
    var onPressure: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackpadView {
        let view = TrackpadView()
        view.onPressure = onPressure
        return view
    }

    func updateNSView(_ nsView: TrackpadView, context: Context) {
        if nsView.lastResetToken != resetToken {
            nsView.lastResetToken = resetToken
            nsView.clear()
        }
    }

    final class TrackpadView: NSView {
        var onPressure: ((CGFloat) -> Void)?
        var lastResetToken = 0
        private var strokes: [TouchStroke] = []

        override var isFlipped: Bool { true }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            strokes.append(TouchStroke(points: [point], pressures: [CGFloat(event.pressure)]))
            onPressure?(CGFloat(event.pressure))
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard !strokes.isEmpty else { return }
            let point = convert(event.locationInWindow, from: nil)
            strokes[strokes.count - 1].points.append(point)
            strokes[strokes.count - 1].pressures.append(CGFloat(event.pressure))
            onPressure?(CGFloat(event.pressure))
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            onPressure?(0)
        }

        func clear() {
            strokes.removeAll()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.textBackgroundColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

            for stroke in strokes where stroke.points.count > 1 {
                for index in 1..<stroke.points.count {
                    let pressure = stroke.pressures.indices.contains(index) ? stroke.pressures[index] : 0
                    let color = NSColor(calibratedHue: 0.58 - min(pressure, 1) * 0.42,
                                        saturation: 0.75,
                                        brightness: 0.95,
                                        alpha: 0.9)
                    color.setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = 2 + pressure * 5
                    path.lineCapStyle = .round
                    path.move(to: stroke.points[index - 1])
                    path.line(to: stroke.points[index])
                    path.stroke()
                }
            }

            if strokes.isEmpty {
                let text = T("在此滑动或按压，检查触控板定位与压力感应", "Trace or press here to test tracking and pressure")
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
            }
        }
    }
}

// MARK: - 页面

struct InputTestView: View {
    @State private var rows: [[KeyCap]] = InputTestView.makeRows()
    @State private var pressedCodes = Set<UInt16>()
    @State private var lastEventText = "—"
    @State private var pressure: CGFloat = 0
    @State private var resetToken = 0
    @State private var monitor: Any?

    private let keySpacing: CGFloat = 5

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("键盘与触控板", "Keyboard & Trackpad"),
                subtitle: T("逐个按键验证触发，触控板验证定位与压力", "Verify every key, then tracking and pressure on the trackpad")
            )

            keyboardCard
            trackpadCard
        }
        .onAppear(perform: installMonitor)
        .onDisappear {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    // MARK: - 键盘

    private var keyboardCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: T("键盘", "KEYBOARD"))
                    Spacer()
                    StatusBadge(text: T("已测 \(testedCount)/\(totalCount)", "\(testedCount)/\(totalCount) tested"),
                                level: testedCount == totalCount ? .ok : .neutral)
                    SecondaryButton(title: T("重置", "Reset")) {
                        rows = Self.makeRows()
                        pressedCodes.removeAll()
                        lastEventText = "—"
                    }
                }

                GeometryReader { geometry in
                    let width = geometry.size.width
                    VStack(spacing: keySpacing) {
                        ForEach(rows.indices, id: \.self) { rowIndex in
                            keyRow(rows[rowIndex], width: width)
                        }
                    }
                }
                .frame(height: 6 * 40 + 5 * keySpacing)

                Text(lastEventText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func keyRow(_ keys: [KeyCap], width: CGFloat) -> some View {
        let totalWeight = keys.reduce(CGFloat(0)) { $0 + $1.weight }
        let available = width - CGFloat(keys.count - 1) * keySpacing
        return HStack(spacing: keySpacing) {
            ForEach(keys) { key in
                let keyWidth = max(20, available * key.weight / totalWeight)
                Text(key.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: keyWidth, height: 40)
                    .background(keyBackground(key))
                    .foregroundColor(key.count > 0 ? .white : .primary)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(key.isDown ? 0.0 : 0.08), lineWidth: 1)
                    )
            }
        }
    }

    private func keyBackground(_ key: KeyCap) -> Color {
        if key.isDown { return .accentColor }
        switch key.count {
        case 0: return Color.primary.opacity(0.05)
        case 1: return Color.green.opacity(0.75)
        default: return Color.green
        }
    }

    private var testedCount: Int {
        rows.flatMap { $0 }.filter { $0.count > 0 }.count
    }

    private var totalCount: Int {
        rows.flatMap { $0 }.count
    }

    private static func makeRows() -> [[KeyCap]] {
        [
            [
                KeyCap(code: 53, label: "esc", weight: 1.4),
                KeyCap(code: 122, label: "F1"), KeyCap(code: 120, label: "F2"), KeyCap(code: 99, label: "F3"),
                KeyCap(code: 118, label: "F4"), KeyCap(code: 96, label: "F5"), KeyCap(code: 97, label: "F6"),
                KeyCap(code: 98, label: "F7"), KeyCap(code: 100, label: "F8"), KeyCap(code: 101, label: "F9"),
                KeyCap(code: 109, label: "F10"), KeyCap(code: 103, label: "F11"), KeyCap(code: 111, label: "F12")
            ],
            [
                KeyCap(code: 50, label: "`"), KeyCap(code: 18, label: "1"), KeyCap(code: 19, label: "2"),
                KeyCap(code: 20, label: "3"), KeyCap(code: 21, label: "4"), KeyCap(code: 23, label: "5"),
                KeyCap(code: 22, label: "6"), KeyCap(code: 26, label: "7"), KeyCap(code: 28, label: "8"),
                KeyCap(code: 25, label: "9"), KeyCap(code: 29, label: "0"), KeyCap(code: 27, label: "-"),
                KeyCap(code: 24, label: "="), KeyCap(code: 51, label: "delete", weight: 1.5)
            ],
            [
                KeyCap(code: 48, label: "tab", weight: 1.5), KeyCap(code: 12, label: "Q"), KeyCap(code: 13, label: "W"),
                KeyCap(code: 14, label: "E"), KeyCap(code: 15, label: "R"), KeyCap(code: 17, label: "T"),
                KeyCap(code: 16, label: "Y"), KeyCap(code: 32, label: "U"), KeyCap(code: 34, label: "I"),
                KeyCap(code: 31, label: "O"), KeyCap(code: 35, label: "P"), KeyCap(code: 33, label: "["),
                KeyCap(code: 30, label: "]"), KeyCap(code: 42, label: "\\", weight: 1.2)
            ],
            [
                KeyCap(code: 57, label: "caps", weight: 1.7), KeyCap(code: 0, label: "A"), KeyCap(code: 1, label: "S"),
                KeyCap(code: 2, label: "D"), KeyCap(code: 3, label: "F"), KeyCap(code: 5, label: "G"),
                KeyCap(code: 4, label: "H"), KeyCap(code: 38, label: "J"), KeyCap(code: 40, label: "K"),
                KeyCap(code: 37, label: "L"), KeyCap(code: 41, label: ";"), KeyCap(code: 39, label: "'"),
                KeyCap(code: 36, label: "return", weight: 1.9)
            ],
            [
                KeyCap(code: 56, label: "shift", weight: 2.3), KeyCap(code: 6, label: "Z"), KeyCap(code: 7, label: "X"),
                KeyCap(code: 8, label: "C"), KeyCap(code: 9, label: "V"), KeyCap(code: 11, label: "B"),
                KeyCap(code: 45, label: "N"), KeyCap(code: 46, label: "M"), KeyCap(code: 43, label: ","),
                KeyCap(code: 47, label: "."), KeyCap(code: 44, label: "/"), KeyCap(code: 60, label: "shift", weight: 2.3)
            ],
            [
                KeyCap(code: 63, label: "fn", weight: 1.1), KeyCap(code: 59, label: "ctrl", weight: 1.3),
                KeyCap(code: 58, label: "opt", weight: 1.2), KeyCap(code: 55, label: "cmd", weight: 1.4),
                KeyCap(code: 49, label: "space", weight: 5),
                KeyCap(code: 54, label: "cmd", weight: 1.4), KeyCap(code: 61, label: "opt", weight: 1.2),
                KeyCap(code: 123, label: "←"), KeyCap(code: 126, label: "↑"),
                KeyCap(code: 125, label: "↓"), KeyCap(code: 124, label: "→")
            ]
        ]
    }

    // MARK: - 触控板

    private var trackpadCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: T("触控板", "TRACKPAD"))
                    Spacer()
                    Text(T("压力 \(Int(pressure * 100))%", "Pressure \(Int(pressure * 100))%"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(pressure > 0.05 ? .accentColor : .secondary)
                    SecondaryButton(title: T("清空", "Clear")) { resetToken += 1 }
                }

                TrackpadCanvas(resetToken: $resetToken) { value in
                    pressure = value
                }
                .frame(height: 190)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                Text(T("按下并拖动可绘制轨迹，颜色由压力决定。逐步测试四个角落与中心，确认定位准确、无漂移、无死区。",
                       "Press and drag to draw — colour reflects pressure. Test the four corners and the centre for accurate tracking, drift or dead zones."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 事件

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let code = event.keyCode
        switch event.type {
        case .keyDown:
            if event.isARepeat { return }
            bumpCount(code)
            pressedCodes.insert(code)
            lastEventText = "keyCode \(code) · down · \(event.charactersIgnoringModifiers ?? "")"
        case .keyUp:
            pressedCodes.remove(code)
            lastEventText = "keyCode \(code) · up"
        case .flagsChanged:
            // caps lock 是"切换键"：.capsLock 表示锁定状态而不是按下状态。
            // 按状态判断会让该键永远检测不到，这里按每次事件计数，不做按下高亮。
            if code == 57 {
                bumpCount(code)
                lastEventText = "keyCode \(code) · caps lock · \(event.modifierFlags.contains(.capsLock) ? "on" : "off")"
                applyPressedState()
                return
            }
            let isDown = modifierIsDown(code: code, flags: event.modifierFlags)
            if isDown {
                bumpCount(code)
                pressedCodes.insert(code)
            } else {
                pressedCodes.remove(code)
            }
            lastEventText = "keyCode \(code) · \(isDown ? "down" : "up") · modifier"
        default:
            break
        }
        applyPressedState()
    }

    private func modifierIsDown(code: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch code {
        case 56, 60: return flags.contains(.shift)
        case 59, 62: return flags.contains(.control)
        case 58, 61: return flags.contains(.option)
        case 55, 54: return flags.contains(.command)
        case 63: return flags.contains(.function)
        // caps lock 按下时 .capsLock 为 true，松开后仍保持锁定状态（true），
        // 所以这里不能用标志位判断按下，交给 handle() 里的翻转逻辑。
        default: return false
        }
    }

    private func bumpCount(_ code: UInt16) {
        for rowIndex in rows.indices {
            if let keyIndex = rows[rowIndex].firstIndex(where: { $0.code == code }) {
                rows[rowIndex][keyIndex].count += 1
                return
            }
        }
    }

    private func applyPressedState() {
        for rowIndex in rows.indices {
            for keyIndex in rows[rowIndex].indices {
                rows[rowIndex][keyIndex].isDown = pressedCodes.contains(rows[rowIndex][keyIndex].code)
            }
        }
    }
}
