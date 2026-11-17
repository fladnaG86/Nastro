import Foundation

/// Keyed localization. Every key must have both an Italian and an English string.
public enum L10n {
    public enum Language: Sendable {
        case it, en

        /// Italian if the first preferred system language starts with "it", English otherwise.
        public static var current: Language {
            from(preferred: Locale.preferredLanguages)
        }

        public static func from(preferred: [String]) -> Language {
            (preferred.first ?? "en").lowercased().hasPrefix("it") ? .it : .en
        }
    }

    /// Later tasks add their keys here.
    public enum Key: CaseIterable, Sendable {
        case appName
        case quit
    }

    public static func t(_ key: Key, language: Language = .current) -> String {
        switch language {
        case .it: return italian(key)
        case .en: return english(key)
        }
    }

    private static func italian(_ key: Key) -> String {
        switch key {
        case .appName: return "Nastro"
        case .quit: return "Esci"
        }
    }

    private static func english(_ key: Key) -> String {
        switch key {
        case .appName: return "Nastro"
        case .quit: return "Quit"
        }
    }
}
