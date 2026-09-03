import AppKit
import Foundation
import NaturalLanguage

/// Extracts context from the frontmost application to prime Whisper models on-device.
/// Runs completely in memory; never saved to disk or network.
enum DictationContextExtractor {
    private static let maxContextLength = 1500

    @MainActor
    static func extractContext(from targetApp: NSRunningApplication?) -> String? {
        guard let targetApp else { return nil }
        let appName = targetApp.localizedName ?? "App"
        let windowText = extractWindowText(for: targetApp.processIdentifier)

        var lines: [String] = ["App: \(appName)"]

        if let windowText, !windowText.isEmpty {
            let entities = extractEntities(from: windowText)

            if !entities.names.isEmpty {
                lines.append("Names: " + entities.names.joined(separator: ", "))
            }
            if !entities.organizations.isEmpty {
                lines.append("Organizations: " + entities.organizations.joined(separator: ", "))
            }
            if !entities.places.isEmpty {
                lines.append("Places: " + entities.places.joined(separator: ", "))
            }
            if !entities.urls.isEmpty {
                lines.append("URLs: " + entities.urls.joined(separator: ", "))
            }
            if !entities.emails.isEmpty {
                lines.append("Emails: " + entities.emails.joined(separator: ", "))
            }
        }

        // Truncate to maximum length
        var totalLength = 0
        var truncatedLines: [String] = []
        for line in lines {
            if totalLength + line.count + 1 > maxContextLength {
                break
            }
            truncatedLines.append(line)
            totalLength += line.count + 1
        }

        guard !truncatedLines.isEmpty else { return nil }
        return truncatedLines.joined(separator: "\n")
    }

    /// Synthesizes the full conditioning prompt for Whisper (Style + Vocabulary + App Context).
    static func synthesizePrompt(
        style: DictationStyle,
        vocabulary: String?,
        appContext: String?
    ) -> String? {
        var sections: [String] = []

        if let template = style.promptTemplate?.trimmingCharacters(in: .whitespacesAndNewlines), !template.isEmpty {
            sections.append("Style:\n\(template)")
        }

        if let vocab = vocabulary?.trimmingCharacters(in: .whitespacesAndNewlines), !vocab.isEmpty {
            sections.append("Vocabulary:\n\(vocab)")
        }

        if let context = appContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            sections.append("Frontmost Window Context:\n\(context)")
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Private Accessibility Helpers

    private static func extractWindowText(for pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard windowResult == .success, let windowRef = focusedWindow else { return nil }
        let windowElement = windowRef as! AXUIElement

        var texts: [String] = []

        // Window Title
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String, !title.isEmpty {
            texts.append(title)
        }

        // Focused Element Selected Text / Value
        var focusedElement: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
           let elementRef = focusedElement {
            let elem = elementRef as! AXUIElement

            var selectedText: AnyObject?
            if AXUIElementCopyAttributeValue(elem, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
               let text = selectedText as? String, !text.isEmpty {
                texts.append(text)
            } else {
                var elemValue: AnyObject?
                if AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &elemValue) == .success,
                   let text = elemValue as? String, !text.isEmpty {
                    texts.append(String(text.prefix(500)))
                }
            }
        }

        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    // MARK: - Entity Extraction

    private struct ExtractedEntities {
        var names: [String] = []
        var organizations: [String] = []
        var places: [String] = []
        var urls: [String] = []
        var emails: [String] = []
    }

    private static func extractEntities(from text: String) -> ExtractedEntities {
        var entities = ExtractedEntities()
        let cleanText = String(text.prefix(2000))

        // NaturalLanguage tagger for Names, Organizations, Places
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = cleanText

        var seenNames = Set<String>()
        var seenOrgs = Set<String>()
        var seenPlaces = Set<String>()

        tagger.enumerateTags(in: cleanText.startIndex..<cleanText.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            guard let tag else { return true }
            let term = String(cleanText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count > 1 else { return true }

            switch tag {
            case .personalName:
                if !seenNames.contains(term) && entities.names.count < 8 {
                    seenNames.insert(term)
                    entities.names.append(term)
                }
            case .organizationName:
                if !seenOrgs.contains(term) && entities.organizations.count < 8 {
                    seenOrgs.insert(term)
                    entities.organizations.append(term)
                }
            case .placeName:
                if !seenPlaces.contains(term) && entities.places.count < 8 {
                    seenPlaces.insert(term)
                    entities.places.append(term)
                }
            default:
                break
            }
            return true
        }

        // NSDataDetector for URLs and Emails
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count))
            var seenURLs = Set<String>()
            var seenEmails = Set<String>()

            for match in matches {
                if let url = match.url {
                    if url.scheme == "mailto" {
                        let email = (url as NSURL).resourceSpecifier ?? url.path
                        if !seenEmails.contains(email) && entities.emails.count < 5 {
                            seenEmails.insert(email)
                            entities.emails.append(email)
                        }
                    } else if let host = url.host, !seenURLs.contains(host) && entities.urls.count < 5 {
                        seenURLs.insert(host)
                        entities.urls.append(host)
                    }
                }
            }
        }

        return entities
    }
}
