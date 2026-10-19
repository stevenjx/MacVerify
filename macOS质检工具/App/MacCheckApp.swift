// App/MacCheckApp.swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacCheckApp: App {
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
