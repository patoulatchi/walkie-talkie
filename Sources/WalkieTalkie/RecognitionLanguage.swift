import Foundation

/// Shared by the final decoder and live captions; sent with every request so
/// changing language does not unload either model.
enum RecognitionLanguage: String, CaseIterable {
    case frenchEnglish = "fr,en"
    case french = "fr"
    case english = "en"
    case german = "de"
    case italian = "it"
    case spanish = "es"
    case romanian = "ro"
    case romanianEnglish = "ro,en"
    case automatic = "auto"

    static let defaultsKey = "localRecognitionLanguage"

    static var selected: RecognitionLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
                ?? ProcessInfo.processInfo.environment["RELAY_WHISPER_LANGUAGES"]
                ?? frenchEnglish.rawValue
            return RecognitionLanguage(rawValue: raw) ?? .frenchEnglish
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var codes: [String] { self == .automatic ? [] : rawValue.split(separator: ",").map(String.init) }

    var title: String {
        switch self {
        case .frenchEnglish: return "French + English"
        case .french: return "French"
        case .english: return "English"
        case .german: return "German"
        case .italian: return "Italian"
        case .spanish: return "Spanish"
        case .romanian: return "Romanian"
        case .romanianEnglish: return "Romanian + English"
        case .automatic: return "Automatic (all languages)"
        }
    }
}
