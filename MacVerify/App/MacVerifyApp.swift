// App/MacVerifyApp.swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 命令行自检：`MACVERIFY_DUMP_REPORT=/tmp/report.md open -a MacVerify`
    /// 采集完毕后写出报告并退出，用于验证采集链路（不参与正常使用）。
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = ProcessInfo.processInfo.environment["MACVERIFY_DUMP_REPORT"] else { return }
        let store = SystemInfoStore()
        let info = store.collectNow()
        let battery = BatteryStore.readBattery()

        let text = ReportService.markdown(info: info, battery: battery)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        if let data = ReportService.json(info: info, battery: battery) {
            try? data.write(to: URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("json"))
        }
        NSApp.terminate(nil)
    }
}

@main
struct MacVerifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var system = SystemInfoStore()
    @StateObject private var battery = BatteryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(system)
                .environmentObject(battery)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(T("重新扫描硬件", "Rescan hardware")) {
                    system.refresh()
                    battery.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
