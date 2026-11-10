// Core/Preferences.swift
import SwiftUI
import Combine

public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return T("跟随系统", "Follow System")
        case .light: return T("浅色", "Light")
        case .dark: return T("深色", "Dark")
        }
    }
}

public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()
    private static let storageKey = "macverify.appearance"

    @Published public var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: raw) ?? .system
    }
}

public enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
