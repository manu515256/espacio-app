import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    static let defaultsKey = "language"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .spanish: "🇪🇸"
        case .english: "🇺🇸"
        }
    }

    var name: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }

    var menuTitle: String { "\(flag)  \(name)" }

    var locale: Locale {
        switch self {
        case .spanish: Locale(identifier: "es_AR")
        case .english: Locale(identifier: "en_US")
        }
    }

    nonisolated(unsafe) static var current: AppLanguage = stored() {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: defaultsKey) }
    }

    private static func stored() -> AppLanguage {
        if let raw = ProcessInfo.processInfo.environment["ESPACIO_LANG"], let l = AppLanguage(rawValue: raw) { return l }
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let l = AppLanguage(rawValue: raw) { return l }
        return .english
    }

    private static let bundles: [AppLanguage: Bundle] = {
        var map: [AppLanguage: Bundle] = [:]
        for lang in allCases {
            if let url = Bundle.main.url(forResource: lang.rawValue, withExtension: "lproj"), let b = Bundle(url: url) {
                map[lang] = b
            }
        }
        return map
    }()

    func string(_ key: String) -> String {
        guard let bundle = Self.bundles[self] else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

func L(_ key: String) -> String {
    AppLanguage.current.string(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: AppLanguage.current.string(key), locale: AppLanguage.current.locale, arguments: args)
}
