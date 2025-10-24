//
//  LanguageConstants.swift
//  dogetionary
//
//  Created for centralized language configuration
//

import Foundation

/// Centralized source of truth for all supported languages
struct LanguageConstants {
    /// All supported languages in the app
    /// Format: (language_code, display_name)
    static let availableLanguages: [(String, String)] = [
        ("af", "Afrikaans"),
        ("ar", "Arabic"),
        ("hy", "Armenian"),
        ("az", "Azerbaijani"),
        ("be", "Belarusian"),
        ("bs", "Bosnian"),
        ("bg", "Bulgarian"),
        ("ca", "Catalan"),
        ("zh", "Chinese"),
        ("hr", "Croatian"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("nl", "Dutch"),
        ("en", "English"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("gl", "Galician"),
        ("de", "German"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("hu", "Hungarian"),
        ("is", "Icelandic"),
        ("id", "Indonesian"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("kn", "Kannada"),
        ("kk", "Kazakh"),
        ("ko", "Korean"),
        ("lv", "Latvian"),
        ("lt", "Lithuanian"),
        ("mk", "Macedonian"),
        ("ms", "Malay"),
        ("mr", "Marathi"),
        ("mi", "Maori"),
        ("ne", "Nepali"),
        ("no", "Norwegian"),
        ("fa", "Persian"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ro", "Romanian"),
        ("ru", "Russian"),
        ("sr", "Serbian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("es", "Spanish"),
        ("sw", "Swahili"),
        ("sv", "Swedish"),
        ("tl", "Tagalog"),
        ("ta", "Tamil"),
        ("th", "Thai"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("ur", "Urdu"),
        ("vi", "Vietnamese"),
        ("cy", "Welsh")
    ]

    /// Get language display name from code
    static func getLanguageName(for code: String) -> String {
        return availableLanguages.first(where: { $0.0 == code })?.1 ?? code.uppercased()
    }
}
