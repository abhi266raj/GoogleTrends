// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct LanguageFilter: Sendable {
    private static let hinglishMarkers: Set<String> = [
        "kya", "kyu", "kyun", "kaise", "kab", "kaha", "kahan", "hai", "hain", "tha", "thi", "the",
        "hoga", "hogi", "hoge", "bhai", "yaar", "namaste", "shubh", "samachar", "desh", "yojana",
        "bharat", "hindustan", "ka", "ki", "ke", "ko", "se", "par", "mein", "aur", "ya", "toh",
        "abhi", "aaj", "kal", "kar", "karo", "raha", "rahi", "rahe", "diwali", "puja", "dhamaka",
        "crore", "lakh", "nrega", "yatra", "vidhan", "sabha", "chunav", "sarkar"
    ]

    public static func detectLanguage(text: String) -> TrendingLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .english }

        // 1. Script checks for Devanagari (Hindi) and other non-Latin scripts
        var hasDevanagari = false
        var hasDisregardedScript = false
        var latinCount = 0

        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x0900...0x097F: // Devanagari
                hasDevanagari = true
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF: // Arabic
                hasDisregardedScript = true
            case 0x0400...0x04FF: // Cyrillic
                hasDisregardedScript = true
            case 0x4E00...0x9FFF, 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF: // CJK / Korean
                hasDisregardedScript = true
            case 0x0B80...0x0BFF: // Tamil
                hasDisregardedScript = true
            case 0x0C00...0x0C7F: // Telugu
                hasDisregardedScript = true
            case 0x0D00...0x0D7F: // Malayalam
                hasDisregardedScript = true
            case 0x0C80...0x0CFF: // Kannada
                hasDisregardedScript = true
            case 0x0980...0x09FF: // Bengali
                hasDisregardedScript = true
            case 0x0A80...0x0AFF: // Gujarati
                hasDisregardedScript = true
            case 0x0A00...0x0A7F: // Gurmukhi
                hasDisregardedScript = true
            case 0x0041...0x005A, 0x0061...0x007A: // Basic Latin A-Z, a-z
                latinCount += 1
            default:
                break
            }
        }

        if hasDevanagari {
            return .hindi
        }
        if hasDisregardedScript {
            return .other
        }

        // 2. Check for Hinglish markers in Latin text
        let lowerWords = trimmed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let matchedHinglishCount = lowerWords.filter { hinglishMarkers.contains($0) }.count
        if matchedHinglishCount > 0 {
            return .hinglish
        }

        // 3. Apple NaturalLanguage recognizer on phrases (>= 3 words)
        #if canImport(NaturalLanguage)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count >= 3 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            if let dominant = recognizer.dominantLanguage {
                switch dominant {
                case .english:
                    return .english
                case .hindi:
                    return .hindi
                case .spanish, .french, .german, .italian, .portuguese, .russian, .japanese, .simplifiedChinese, .traditionalChinese, .arabic:
                    let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
                    if let confidence = hypotheses[dominant], confidence >= 0.85 {
                        return .other
                    }
                default:
                    break
                }
            }
        }
        #endif

        // Latin text defaults to English if no other foreign language or Hinglish identified
        return latinCount > 0 ? .english : .other
    }

    public static func isAllowed(topic: String, articleTitle: String? = nil, allowed: Set<TrendingLanguage>) -> Bool {
        let topicLang = detectLanguage(text: topic)
        if allowed.contains(topicLang) {
            return true
        }

        // If topic language was not directly allowed, check article title if present
        if let articleTitle = articleTitle, !articleTitle.isEmpty {
            let articleLang = detectLanguage(text: articleTitle)
            if allowed.contains(articleLang) {
                return true
            }
        }

        return false
    }
}
