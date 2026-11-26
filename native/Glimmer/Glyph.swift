import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Glimmer's one icon system: every row gets a solid, single-colour SF Symbol tinted from the theme.
/// Built-in content may still carry emoji (older catalogs, remote editions, saved tasks); they are
/// translated to symbols here and stripped from names for display, so nothing is shown in colour.
enum Glyph {
    // MARK: Emoji handling

    /// Whether a character draws as a colour emoji.
    static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Text-default emoji such as ☀ or ✍ followed by the emoji variation selector.
        return first.properties.isEmoji && first.value > 0x238C
    }

    /// The name without leading or trailing emoji, such as "Deep work" for "💻 Deep work".
    static func plainName(_ text: String) -> String {
        var characters = Substring(text)
        while let first = characters.first, isEmoji(first) || first.isWhitespace { characters = characters.dropFirst() }
        while let last = characters.last, isEmoji(last) || last.isWhitespace { characters = characters.dropLast() }
        let plain = String(characters)
        return plain.isEmpty ? text : plain
    }

    /// The first emoji at the start of a name, if any.
    static func leadingEmoji(_ text: String) -> String? {
        guard let first = text.first, isEmoji(first) else { return nil }
        return String(first)
    }

    // MARK: Resolving a symbol

    /// The symbol for a row. `icon` is a stored icon (an SF Symbol name or a legacy emoji),
    /// `name` is the row's title and `category` a catalog category or kind such as "focus" or "Activity".
    static func symbol(icon: String? = nil, name: String, category: String? = nil) -> String {
        if let icon, !icon.isEmpty {
            if isSymbolName(icon), exists(icon) { return icon }
            if let mapped = GlyphMap.emoji[normalized(icon)] { return mapped }
        }
        let plain = plainName(name)
        let key = plain.lowercased()
        if let known = GlyphMap.names[key] { return known }
        if let emoji = leadingEmoji(name), let mapped = GlyphMap.emoji[normalized(emoji)] { return mapped }
        if let match = GlyphMap.keywords.first(where: { key.contains($0.0) }) { return match.1 }
        if let category, let fallback = GlyphMap.categoryFallback[category.lowercased()] { return fallback }
        return GlyphMap.fallback
    }

    /// The theme colour for a category or kind.
    static func tint(for category: String?) -> Color {
        guard let category else { return GlimmerColor.accent }
        return GlyphMap.categoryTint[category.lowercased()] ?? GlimmerColor.accent
    }

    static func isSymbolName(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }

    /// Whether this system has the symbol, so a newer name never draws as an empty square.
    static func exists(_ symbol: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: symbol) != nil
        #endif
    }

    /// Drops variation selectors so "☀️" and "☀" find the same entry.
    private static func normalized(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }))
    }
}

/// A row's leading icon: a solid glyph on a softly tinted rounded square.
struct GlyphTile: View {
    @Environment(\.readingTheme) private var theme
    let symbol: String
    var tint: Color = GlimmerColor.accent
    @ScaledMetric(relativeTo: .body) private var size = GlyphTile.defaultSize

    static var defaultSize: CGFloat {
        #if os(macOS)
        24
        #else
        30
        #endif
    }

    init(_ symbol: String, tint: Color = GlimmerColor.accent, size: CGFloat? = nil) {
        self.symbol = Glyph.exists(symbol) ? symbol : GlyphMap.fallback
        self.tint = tint
        if let size { _size = ScaledMetric(wrappedValue: size, relativeTo: .body) }
    }

    var body: some View {
        glyph
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(theme == .glimmer ? 0.2 : 0.13), in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The glyph at 54% of the tile, stepping down to 44% for very wide symbols such as person.3.fill.
    private var glyph: some View {
        ViewThatFits(in: .horizontal) {
            symbolImage(size * 0.54).frame(maxWidth: size * 0.86)
            symbolImage(size * 0.44)
        }
    }

    private func symbolImage(_ points: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: points, weight: .semibold)).symbolRenderingMode(.monochrome).fixedSize()
    }
}
