// Views/PanelTest.swift
import SwiftUI
import AppKit
import Combine

final class PanelTestState: ObservableObject {
    struct Step {
        let name: String
        let color: Color
        let textColor: Color
    }

    let steps: [Step] = [
        Step(name: T("纯黑 — 检查漏光与亮点", "Black — check backlight bleed and bright spots"), color: .black, textColor: .white),
        Step(name: T("5% 灰 — 检查暗斑与阴阳屏", "5% gray — check dark spots and uneven backlight"), color: Color(white: 0.05), textColor: .white),
        Step(name: T("10% 灰 — 检查色斑与脏点", "10% gray — check stains and dust"), color: Color(white: 0.10), textColor: .white),
        Step(name: T("纯白 — 检查色偏与暗点", "White — check tint and dead pixels"), color: .white, textColor: .black),
        Step(name: T("纯红 — 检查红色子像素", "Red — check red subpixels"), color: Color(red: 1, green: 0, blue: 0), textColor: .white),
        Step(name: T("纯绿 — 检查绿色子像素", "Green — check green subpixels"), color: Color(red: 0, green: 1, blue: 0), textColor: .black),
        Step(name: T("纯蓝 — 检查蓝色子像素", "Blue — check blue subpixels"), color: Color(red: 0, green: 0, blue: 1), textColor: .white)
    ]

    @Published var index = 0
    @Published var showsHint = true

    func next() {
        index = (index + 1) % steps.count
        withAnimation(.easeOut(duration: 0.4)) { showsHint = false }
    }

    func previous() {
        index = (index - 1 + steps.count) % steps.count
        withAnimation(.easeOut(duration: 0.4)) { showsHint = false }
    }
}

struct PanelTestOverlayView: View {
    @ObservedObject var state: PanelTestState
    let onExit: () -> Void

    var body: some View {
        ZStack {
            state.steps[state.index].color.ignoresSafeArea()

            VStack {
                HStack {
                    Text(state.steps[state.index].name)
                        .font(Typo.body)
                        .foregroundColor(state.steps[state.index].textColor.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(state.steps[state.index].textColor.opacity(0.12))
                        .cornerRadius(6)
                    Spacer()
                    Button(action: onExit) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark").font(Typo.captionStrong)
                            Text("Esc").font(Typo.caption)
                        }
                        .foregroundColor(state.steps[state.index].textColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(state.steps[state.index].textColor.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .opacity(state.showsHint ? 1 : 0.15)

                Spacer()

                Text(T("空格 / 点击 切换 · ← → 切换 · Esc 退出",
                       "Space or click to cycle · ← → to navigate · Esc to exit"))
                    .font(Typo.caption)
                    .foregroundColor(state.steps[state.index].textColor.opacity(0.55))
                    .padding(12)
                    .opacity(state.showsHint ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.next() }
    }
}

final class PanelTestController {
    static let shared = PanelTestController()

    private var window: NSWindow?
    private var monitor: Any?
    private var state: PanelTestState?
    private var onFinish: (() -> Void)?

    private init() {}

    func start(onFinish: @escaping () -> Void) {
        guard window == nil else { return }
        self.onFinish = onFinish

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let state = PanelTestState()
        self.state = state

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let state = self.state else { return event }
            switch event.keyCode {
            case 53:
                self.stop()
                return nil
            case 49:
                state.next()
                return nil
            case 123:
                state.previous()
                return nil
            case 124:
                state.next()
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
