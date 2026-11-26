import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Builds Inkspring's `inkspring://new-idea` link, which saves one open post idea.
/// Contract: Inkspring `native-mac/README.md`, "Send an idea from another app" (Mac 1.0.89+, iPhone 1.0.51+).
enum InkspringLink {
    static let source = "glimmer"
    static let probe = URL(string: "inkspring://new-idea")!
    static let textLimit = 2_000
    static let titleLimit = 140
    static let shortTitleLimit = 60

    /// Letters, digits and `-._~` stay as they are; everything else is percent-encoded,
    /// so `+`, `&`, `=` and `#` in the quote can't change the meaning of the link.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func newIdea(title: String, text: String) -> URL? {
        let body = clip(text.trimmingCharacters(in: .whitespacesAndNewlines), to: textLimit)
        guard !body.isEmpty else { return nil }
        let heading = clip(oneLine(title), to: titleLimit)
        var query = [("title", heading), ("text", body), ("source", source)]
        if heading.isEmpty { query.removeFirst() }
        let encoded = query.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "inkspring://new-idea?\(encoded)")
    }

    /// Today's quote as an idea: a short title from the quote, and the quote with its attribution as the text.
    static func newIdea(quote: String, author: String) -> URL? {
        let words = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = name.isEmpty ? "“\(words)”" : "“\(words)”\n— \(name)"
        return newIdea(title: shortTitle(words), text: text)
    }

    /// The quote itself when it is short, otherwise its opening words ending in "…".
    static func shortTitle(_ quote: String) -> String {
        let line = oneLine(quote)
        guard line.utf16.count > shortTitleLimit else { return line.isEmpty ? "Today’s Glimmer" : line }
        var title = ""
        for word in line.split(separator: " ") {
            let next = title.isEmpty ? String(word) : title + " " + word
            if next.utf16.count + 1 > shortTitleLimit { break }
            title = next
        }
        if title.isEmpty { return clip(line, to: shortTitleLimit) }
        return title.trimmingCharacters(in: .punctuationCharacters) + "…"
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Shortens to `limit` UTF-16 units ending in "…", never splitting a character.
    static func clip(_ value: String, to limit: Int) -> String {
        guard value.utf16.count > limit else { return value }
        var result = ""
        for character in value {
            if result.utf16.count + character.utf16.count + 1 > limit { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func oneLine(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when a version of Inkspring that handles the link is installed.
    @MainActor static var isInstalled: Bool {
        #if os(macOS)
        NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
        #elseif os(iOS)
        UIApplication.shared.canOpenURL(probe)
        #else
        false
        #endif
    }

    @MainActor static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}
