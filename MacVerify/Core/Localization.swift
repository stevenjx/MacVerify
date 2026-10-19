// Core/Localization.swift
// 轻量本地化：T("中文", "English")，切换语言立即生效，无需重启。
import Foundation
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return T("跟随系统", "Follow System")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

public final class Localization: ObservableObject {
    public static let shared = Localization()

    private static let storageKey = "macverify.language"

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            objectWillChange.send()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    public var isChinese: Bool {
        switch language {
        case .chinese: return true
        case .english: return false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh")
        }
    }

    public var locale: Locale {
        Locale(identifier: isChinese ? "zh_Hans_CN" : "en_US")
    }

    public var localeIdentifier: String {
        isChinese ? "zh-Hans" : "en"
    }
}

/// 双语字符串。所有界面文案统一走这里，避免遗漏 key。
public func T(_ chinese: String, _ english: String) -> String {
    Localization.shared.isChinese ? chinese : english
}
