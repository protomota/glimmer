import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ReadingTheme: String, CaseIterable, Identifiable {
    case paper = "Paper", light = "Light", glimmer = "Glimmer"
    var id: Self { self }
    static let preference = "glimmer.readingTheme"
    var scheme: ColorScheme { self == .glimmer ? .dark : .light }
    var canvas: Color {
        switch self {
        case .paper: Color(hex: "F5F2EC")
        case .light: Color(hex: "FAFBFC")
        case .glimmer: Color(hex: "181918")
        }
    }
    var surface: Color {
        switch self {
        case .paper: Color(hex: "FFFDF9")
        case .light: .white
        case .glimmer: Color(hex: "232523")
        }
    }
    var selectionInk: Color {
        switch self {
        case .paper: Color(hex: "5A4734")
        case .light: Color(hex: "465667")
        case .glimmer: Color(hex: "E1C6A3")
        }
    }
    var selectionFill: Color { selectionInk.opacity(self == .glimmer ? 0.22 : 0.13) }
    var selectionOnInk: Color { self == .glimmer ? Color(hex: "242019") : .white }
    var inset: Color {
        switch self {
        case .paper: Color(hex: "ECE5D9")
        case .light: Color(hex: "EDF0F3")
        case .glimmer: Color(hex: "30332F")
        }
    }
}

extension EnvironmentValues {
    @Entry var readingTheme: ReadingTheme = .paper
}

struct ReadingAppearance: ViewModifier {
    @AppStorage(ReadingTheme.preference) private var selected: ReadingTheme = .paper
    func body(content: Content) -> some View {
        let theme: ReadingTheme = {
            #if DEBUG
            if ReviewLaunch.colorScheme == .dark { return .glimmer }
            if ReviewLaunch.colorScheme == .light { return .light }
            #endif
            return selected
        }()
        return content.buttonStyle(ReadingButtonStyle()).environment(\.readingTheme, theme).preferredColorScheme(theme.scheme)
    }
}

enum GlimmerColor {
    /// The main action colour: warm ink in light mode, warm paper in dark mode.
    static let ink = Color(light: "2b2a28", dark: "ebe7e0")
    /// The label colour that sits on `ink`.
    static let onInk = Color(light: "fbfaf7", dark: "1c1c1b")
    static let accent = Color(light: "4a6f94", dark: "9dbbdc")
    static let ember = Color(light: "b15b3e", dark: "e79c80")
    static let sage = Color(light: "4b7a59", dark: "94c4a2")
    static let honey = Color(light: "8f6a1c", dark: "e2ba5e")
    static let dusk = Color(light: "665a92", dark: "b6a9dd")

    // Earlier names, kept so existing call sites read naturally.
    static let blue = accent
    static let softBlue = Color(light: "5d8fbf", dark: "8fb6df")
    static let warm = ember
    static let gold = honey
}

extension Color {
    init(hex: String) {
        let rgb = Color.rgb(hex)
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    init(light: String, dark: String) {
        let lightRGB = Color.rgb(light), darkRGB = Color.rgb(dark)
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkRGB : lightRGB
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
        #endif
    }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
}

enum GlimmerFont {
    /// Interface headings use SF, like the rest of the system.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default, weight: weight == .bold ? .semibold : weight)
    }

    /// New York is kept for the journal's own voice: lesson text and the line of the day.
    static func reading(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

// MARK: - Page and surfaces

struct Page<Content: View>: View {
    let title: String
    var kicker: String? = nil
    var subtitle: String? = nil
    var width: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    if let kicker {
                        Text(kicker).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(title).font(Page.titleFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 6)
                content
            }
            .frame(maxWidth: width, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PageBackdrop() }
        .tint(GlimmerColor.accent)
    }

    private static var titleFont: Font {
        #if os(macOS)
        .system(.title, weight: .semibold)
        #else
        .system(.largeTitle, weight: .bold)
        #endif
    }
}

/// The flat, opaque backdrop behind every page.
struct PageBackdrop: View {
    @Environment(\.readingTheme) private var theme
    var body: some View { theme.canvas.ignoresSafeArea() }
}

struct Eyebrow: View {
    let title: String
    var color: Color = GlimmerColor.accent
    init(_ title: String, color: Color = GlimmerColor.accent) {
        self.title = title
        self.color = color
    }

    var body: some View {
        // A quiet section heading. The colour argument is kept for call sites but headings stay neutral.
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An opaque reading surface. Panels never use glass, so controls placed on them stay legible.
struct Panel<Content: View>: View {
    @Environment(\.readingTheme) private var theme
    var title: String? = nil
    var accent: Color = GlimmerColor.accent
    var padding: CGFloat = 16
    /// A plain panel has no surface. Use it for groups of glass rows, which sit directly on the page.
    var plain = false
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Eyebrow(title, color: accent) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(plain ? 0 : padding)
        .background {
            if !plain {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.primary.opacity(contrast == .increased ? 0.30 : 0.08), lineWidth: 1)
                    }
            }
        }
        .padding(.top, plain ? 6 : 0)
    }
}

/// Lays children out in rows that wrap, for chips and tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var centerItemsVertically = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let offset = centerItemsVertically ? (row.height - size.height) / 2 : 0
                subviews[index].place(at: CGPoint(x: x, y: y + offset), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Liquid Glass

enum GlimmerButtonRole { case prominent, standard, selected }

extension View {
    func glimmerGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        self.modifier(GlassFallback(shape: shape, tint: tint))
    }

    func glassGroup(spacing: CGFloat = 12) -> some View { self }

    func glimmerButton(_ role: GlimmerButtonRole = .standard, tint: Color? = nil, circle: Bool = false) -> some View {
        buttonStyle(ReadingButtonStyle(role: role, tint: tint, circle: circle))
    }
}

struct ReadingButtonStyle: ButtonStyle {
    var role: GlimmerButtonRole = .standard
    var tint: Color?
    var circle = false
    @Environment(\.readingTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let dark = theme == .glimmer
        let primary = role == .prominent
        let selected = role == .selected
        let accent = tint ?? Color(hex: dark ? "8FB8E8" : "2F4A63")
        // The main action is ink: near-black on light pages, warm white on dark ones. Blue stays for selection.
        let primaryFill = tint ?? Color(hex: dark ? "EBE7E0" : theme == .paper ? "2B2A26" : "1F2328")
        let ink = Color(hex: dark ? "F2F2F5" : theme == .paper ? "2B2A26" : "1F2328")
        let surface = Color(hex: dark ? "2A2A2E" : theme == .paper ? "FBF8F1" : "FFFFFF")
        let outline = Color(hex: dark ? "7C7C85" : theme == .paper ? "8A8272" : "8A8F98")
        let shape = circle ? AnyShape(Circle()) : AnyShape(Capsule())
        #if os(macOS)
        let v: CGFloat = size == .extraLarge ? 12 : size == .large ? 9 : 6
        #else
        let v: CGFloat = size == .large || size == .extraLarge ? 13 : 9
        #endif
        return configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(!enabled ? Color.secondary : configuration.role == .destructive ? Color.red : primary ? Color(hex: dark ? "1C1C1B" : "FBFAF7") : ink)
            .padding(.vertical, v).padding(.horizontal, circle ? v : v + 7)
            .background {
                shape.fill(!enabled ? theme.inset : primary ? primaryFill : surface)
                if enabled && selected { shape.fill(accent.opacity(0.17)) }
                if enabled { shape.stroke(primary ? primaryFill : selected ? accent : outline, lineWidth: contrast == .increased || selected ? 2 : 1) }
                if configuration.isPressed && enabled { shape.fill(primary ? Color(hex: dark ? "1C1C1B" : "FBFAF7").opacity(0.16) : ink.opacity(0.12)) }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .animation(reducedMotion ? nil : .smooth(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassFallback<S: Shape>: ViewModifier {
    @Environment(\.readingTheme) private var theme
    let shape: S
    let tint: Color?
    func body(content: Content) -> some View {
        content.background { shape.fill(theme.inset) }
            .background { shape.fill(theme.surface) }
            .overlay { shape.stroke(tint ?? Color.primary.opacity(0.12), lineWidth: tint == nil ? 1 : 2) }
    }
}

// MARK: - Controls

/// The shared content of a glass row: an icon, a title, an optional detail and a trailing hint.
struct RowLabel: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    var emoji: String? = nil
    var tint: Color = GlimmerColor.accent
    var trailing: String? = "chevron.right"
    var selected = false
    /// When set, the row ends in an animated tick instead of a symbol.
    var tick: Bool? = nil
    var onTint: Color = Color(light: "ffffff", dark: "1c1c1b")

    static var minHeight: CGFloat {
        #if os(macOS)
        30
        #else
        44
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            // Rows whose title starts with an emoji (older catalogs, lesson choices) show its glyph instead.
            if let symbol = icon ?? emoji ?? Glyph.leadingEmoji(title) {
                GlyphTile(Glyph.symbol(icon: symbol, name: title), tint: tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(Glyph.plainName(title)).font(.body.weight(.medium)).foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            if let tick {
                Tick(done: tick, size: 24, tint: tint, onTint: onTint)
            } else if let trailing {
                Image(systemName: trailing).font(.footnote.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, detail == nil ? 0 : 5).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: RowLabel.minHeight, alignment: .leading)
        .contentShape(.rect)
    }
}

extension View {
    /// The glass treatment shared by every full-width row button and navigation link.
    /// A row that ends in a tick says "selected" with the tick alone, so pass `fill: false` for it.
    func glassRow(tint: Color = GlimmerColor.accent, selected: Bool = false, fill: Bool = true) -> some View {
        self.buttonStyle(RowPressStyle())
            .background(selected && fill ? tint.opacity(0.10) : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottom) { Divider().opacity(0.6).accessibilityHidden(true) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A full-width glass row button.
struct ActionRow: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    var emoji: String? = nil
    var tint: Color = GlimmerColor.accent
    var trailing: String = "chevron.right"
    var selected = false
    /// When set, the row ends in an animated tick and gives a tap you can feel.
    var tick: Bool? = nil
    var onTint: Color = Color(light: "ffffff", dark: "1c1c1b")
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RowLabel(title: title, detail: detail, icon: icon, emoji: emoji, tint: tint,
                     trailing: trailing, selected: selected, tick: tick, onTint: onTint)
        }
        .glassRow(tint: tint, selected: selected, fill: tick == nil)
        .sensoryFeedback(.selection, trigger: tick) { _, _ in tick != nil }
    }
}

/// A full-width glass row that pushes a destination.
struct LinkRow<Destination: View>: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    var emoji: String? = nil
    var tint: Color = GlimmerColor.accent
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            RowLabel(title: title, detail: detail, icon: icon, emoji: emoji, tint: tint)
        }
        .glassRow(tint: tint)
    }
}

/// A single or multiple choice, shown as a full-width glass row.
struct SelectRow: View {
    @Environment(\.readingTheme) private var theme
    let label: String
    let selected: Bool
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        ActionRow(title: label, tint: tint ?? theme.selectionInk, selected: selected, tick: selected,
                  onTint: tint == nil ? theme.selectionOnInk : Color(light: "ffffff", dark: "1c1c1b"), action: action)
    }
}

/// A compact glass capsule for tags, moods and short choices.
struct Chip: View {
    let label: String
    let selected: Bool
    var tint: Color = GlimmerColor.accent
    var action: () -> Void

    private static var verticalPadding: CGFloat {
        #if os(macOS)
        5
        #else
        9
        #endif
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true) }
                Text(label).font(.callout)
            }
            .foregroundStyle(Color.primary)
            .frame(minWidth: 24, minHeight: 20)
        }
        .accessibilityLabel(label)
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, Chip.verticalPadding)
        .contentShape(.capsule)
        .glimmerGlass(.capsule, tint: selected ? tint.opacity(0.20) : nil, interactive: true)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PrimaryAction: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    // A thumb-width button on iPhone and iPad; a normal trailing button on Mac.
    private static var minWidth: CGFloat? {
        #if os(macOS)
        96
        #else
        nil
        #endif
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(GlimmerColor.onInk)
            .frame(minWidth: PrimaryAction.minWidth, minHeight: 20)
        }
        .glimmerButton(.prominent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// A secondary glass button that sizes to its label.
struct SecondaryAction: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    var fill = false
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.medium)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 24)
        }
        .glimmerButton(.standard)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// A floating glass action bar pinned to the bottom of a flow, within easy reach of a thumb.
struct ActionBar<Content: View>: View {
    @Environment(\.readingTheme) private var theme
    var width: CGFloat = 560
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            #if os(macOS)
            Spacer(minLength: 0)
            #endif
            content
        }
        .glassGroup(spacing: 10)
        .frame(maxWidth: width)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(theme.canvas)
        .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    /// Pins glass actions to the bottom edge. On 26+ the bar gets the system scroll edge effect.
    @ViewBuilder
    func actionBar<Content: View>(width: CGFloat = 560, @ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { ActionBar(width: width, content: content) }
    }

    /// Adds Cancel where each platform expects it: the navigation bar on iPhone and iPad.
    /// On Mac, sheets place a Cancel button in their action bar instead (see `SheetCancel`).
    func sheetCancel(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel, action: action) {
                    Label("Cancel", systemImage: "xmark").labelStyle(.iconOnly)
                }
                .tint(Color.primary)
            }
        }
        #else
        self
        #endif
    }
}

/// The Mac sheet's Cancel button, shown at the leading edge of the action bar.
struct SheetCancel: View {
    var title = "Cancel"
    var action: () -> Void

    var body: some View {
        #if os(macOS)
        Button(title, role: .cancel, action: action)
            .glimmerButton(.standard).buttonBorderShape(.capsule).controlSize(.large)
            .keyboardShortcut(.cancelAction)
        #else
        EmptyView()
        #endif
    }
}

/// A large, inviting text field: generous padding, a soft sunk surface and a clear focus ring.
private struct GlimmerField: ViewModifier {
    /// Fields and the buttons beside them share this height.
    static var height: CGFloat {
        #if os(macOS)
        40
        #else
        50
        #endif
    }

    var symbol: String? = nil
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            content
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
        }
            .padding(.horizontal, 20)
            .frame(height: GlimmerField.height)
            .background(Color.primary.opacity(0.06), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(focused ? GlimmerColor.accent : Color.primary.opacity(contrast == .increased ? 0.35 : 0.10),
                                  lineWidth: focused ? 2 : 1)
            }
            .contentShape(.capsule)
            .onTapGesture { focused = true }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    /// Styles a `TextField` as Glimmer's large input.
    func glimmerField(symbol: String? = nil) -> some View { modifier(GlimmerField(symbol: symbol)) }

    /// Sizes a glass button to sit beside a `glimmerField`, at the same height.
    func besideField() -> some View { controlSize(.extraLarge) }
}

/// A searchable list for picking one item from many, with Favorites and Recent at the top.
/// Use it wherever a list is too long to scan: rows can be starred, and recent picks float up.
struct ChoiceList: View {
    @Environment(\.readingTheme) private var theme
    let items: [String]
    let selection: String?
    var visible = true
    var favorites: [String] = []
    var recents: [String] = []
    /// What the search field asks for, such as "Search apps and sites".
    var prompt = "Search"
    /// Sorts the full list alphabetically. Leave off for lists with a deliberate order.
    var alphabetical = false
    /// The kind of thing listed, such as "app", "activity" or "person". It picks each row's glyph and tint.
    var kind: String? = nil
    var onSelect: (String) -> Void
    var onToggleFavorite: (String) -> Void
    /// When set, a search with no exact match offers to add what was typed.
    var onAdd: ((String) -> Void)? = nil
    @State private var query = ""

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var everything: [String] {
        alphabetical ? items.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } : items
    }
    private var matches: [String] { everything.filter { $0.localizedCaseInsensitiveContains(term) } }
    private var starred: [String] { favorites.filter(items.contains) }
    private var recent: [String] { Array(recents.filter { items.contains($0) && !favorites.contains($0) }.prefix(4)) }
    private var canAdd: Bool {
        onAdd != nil && !term.isEmpty && !items.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.count > 8 || onAdd != nil {
                TextField(prompt, text: $query).glimmerField(symbol: "magnifyingglass")
                    .autocorrectionDisabled()
                    .onSubmit { if canAdd, matches.isEmpty { add() } else if let first = matches.first, !term.isEmpty { onSelect(first) } }
            }
            if term.isEmpty {
                section("Favorites", starred)
                section("Recent", recent)
                section(starred.isEmpty && recent.isEmpty ? nil : "All", everything)
            } else {
                section(nil, matches)
                if canAdd, matches.isEmpty {
                    Button(action: add) {
                        Label("Add “\(term)”", systemImage: "plus.circle").font(.body.weight(.medium))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, minHeight: RowLabel.minHeight, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .glassRow()
                } else if matches.isEmpty {
                    Text("Nothing matches “\(term)”.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func add() {
        onAdd?(term)
        query = ""
    }

    @ViewBuilder
    private func section(_ title: String?, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.element) { index, name in
                        row(name)
                            .modifier(DisclosureRowMotion(index: index, count: names.count, visible: visible))
                        if index < names.count - 1 { Divider().padding(.leading, 46) }
                    }
                }
                .background(theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        let isFavorite = favorites.contains(name)
        return HStack(spacing: 0) {
            Button { onSelect(name) } label: {
                HStack(spacing: 12) {
                    GlyphTile(Glyph.symbol(name: name, category: kind), tint: Glyph.tint(for: kind))
                    Text(Glyph.plainName(name)).font(.body).foregroundStyle(Color.primary)
                    Spacer(minLength: 4)
                    if selection == name {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(theme.selectionInk)
                    }
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: RowLabel.minHeight + 16, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityAddTraits(selection == name ? .isSelected : [])
            Button { onToggleFavorite(name) } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? AnyShapeStyle(GlimmerColor.honey) : AnyShapeStyle(.tertiary))
                    .frame(width: 44, height: RowLabel.minHeight + 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove \(name) from favorites" : "Add \(name) to favorites")
        }
    }
}

/// One option in a `GlassSegments` control.
struct GlassSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String? = nil
    var id: Value { value }
}

/// A segmented choice drawn in Liquid Glass: a quiet track with a glass thumb that slides to the selection.
struct GlassSegments<Value: Hashable>: View {
    let label: String
    let options: [GlassSegment<Value>]
    @Binding var selection: Value
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat {
        #if os(macOS)
        30
        #else
        42
        #endif
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.footnote.weight(.semibold)) }
                        Text(option.title).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .contentShape(.capsule)
                    .modifier(SegmentThumb(selected: selected, namespace: thumb))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.07), in: .capsule)
        .glassGroup(spacing: 0)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The glass thumb behind the selected segment. On 26+ it morphs between segments as one piece of glass.
private struct SegmentThumb: ViewModifier {
    let selected: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if !selected {
            content
        } else {
            content.background {
                if #available(macOS 26, iOS 26, *) {
                    Capsule().fill(.clear)
                        .glassEffect(.regular.tint(GlimmerColor.accent.opacity(0.22)), in: .capsule)
                        .matchedGeometryEffect(id: "thumb", in: namespace)
                } else {
                Capsule().fill(GlimmerColor.accent.opacity(0.10))
                    .overlay { Capsule().fill(GlimmerColor.accent.opacity(0.25)) }
                    .matchedGeometryEffect(id: "thumb", in: namespace)
                }
            }
        }
    }
}

/// A round glass icon button for back, close and stepping.
struct GlassIconButton: View {
    let label: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.body.weight(.medium)).frame(width: 20, height: 24)
        }
        .glimmerButton(.standard, circle: true)
        .accessibilityLabel(label)
    }
}

/// Step progress as a row of capsules.
struct StepDots: View {
    let current: Int
    let total: Int
    /// Progress colour; plain ink by default.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule().fill(index <= current ? (tint ?? Color.primary.opacity(0.55)) : Color.primary.opacity(0.12))
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(max(1, current + 1)) of \(total)")
    }
}

/// A slim progress bar drawn on content surfaces.
struct Meter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    var tint: Color = GlimmerColor.accent

    var body: some View {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if clamped > 0 { Capsule().fill(tint).frame(width: max(8, proxy.size.width * clamped)) }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.58), value: clamped)
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

/// The Glimmer logo: the AppMark asset, which is brand/glimmer-icon-1024.png masked to a circle.
/// Never draw the mark in code; regenerate the asset with brand/render-icons.cjs.
struct GlimmerLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Image("AppMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CoinMark: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: size * 0.09)
            Circle().inset(by: size * 0.24).strokeBorder(lineWidth: size * 0.06)
        }
        .foregroundStyle(GlimmerColor.honey)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CoinCount: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            CoinMark()
            Text(count.formatted())
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.32), value: count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) coins")
    }
}

/// A small labelled number for summaries.
struct Stat: View {
    let value: String
    let label: String
    var tint: Color = GlimmerColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Artwork

enum AppResources {
    static func url(_ name: String, extension ext: String, folder: String = "LibraryContent") -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}

// MARK: - Reflection dial

private struct DialArc: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
        return path
    }
}

/// The aftertaste and energy dial: one control, dragged around a 270° arc.
/// The arc fills and glows in the colour of the current step, the word in the middle changes with it,
/// and the knob snaps to the nearest of five stops when released.
struct ReflectionDial: View {
    let title: String
    let words: [String]
    let colors: [Color]
    @Binding var value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false

    private let inset: CGFloat = 30
    private let lineWidth: CGFloat = 16
    private var step: Int { Moment.step(value) }
    private var color: Color { colors[min(colors.count - 1, step)] }
    private var gradient: AngularGradient {
        AngularGradient(colors: colors, center: .center, startAngle: .degrees(135), endAngle: .degrees(405))
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let diameter = min(proxy.size.width, proxy.size.height)
                let radius = diameter / 2 - inset
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                ZStack {
                    glow(radius: radius)
                    DialArc(inset: inset)
                        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // The lit part of the arc, with a soft halo of the same light behind it.
                    DialArc(inset: inset).trim(from: 0, to: max(0.002, value))
                        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .round))
                        .blur(radius: 12).opacity(0.55)
                    DialArc(inset: inset).trim(from: 0, to: max(0.002, value))
                        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    ForEach(0..<5) { tick in
                        Circle().fill(Double(tick) / 4 <= value + 0.01 ? Color.white.opacity(0.9) : Color.primary.opacity(0.25))
                            .frame(width: 4, height: 4)
                            .position(point(center, radius, fraction: Double(tick) / 4))
                    }
                    reading.frame(width: radius * 1.4).allowsHitTesting(false)
                    knob.position(point(center, radius, fraction: value))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    let dx = event.location.x - center.x
                    let dy = event.location.y - center.y
                    guard hypot(dx, dy) > 24 else { return }
                    let angle = atan2(dx, -dy) * 180 / .pi
                    let sweep = (angle - 225 + 720).truncatingRemainder(dividingBy: 360)
                    let target = sweep <= 270 ? sweep / 270 : (sweep < 315 ? 1 : 0)
                    if dragging {
                        value = target
                    } else {
                        // A tap or the start of a drag glides to the finger instead of jumping.
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragging = true; value = target }
                    }
                }.onEnded { _ in settle() })
            }
            .frame(width: 280, height: 262)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
            .sensoryFeedback(.selection, trigger: step)
            .sensoryFeedback(.impact(weight: .light), trigger: dragging) { _, isDragging in !isDragging }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(words[step])
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
            #if os(macOS)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .right, .up: move(by: 1)
                case .left, .down: move(by: -1)
                @unknown default: break
                }
            }
            #endif
            HStack {
                Text(words.first ?? "")
                Spacer()
                Text(words.last ?? "")
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(width: 250)
            .padding(.top, -30)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        #if DEBUG
        .task { await runDemoIfRequested() }
        #endif
    }

    /// A pool of light behind the word that grows and brightens as the dial rises.
    private func glow(radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.16 + 0.26 * value), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: radius * 0.95))
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(0.78 + 0.22 * value)
            .allowsHitTesting(false)
    }

    private var reading: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(words[step]).font(GlimmerFont.reading(.largeTitle, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.5)
                .id(step)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
    }

    private var knob: some View {
        ZStack {
            // A ring of light that leaves the knob each time it lands on a new stop.
            Circle().stroke(color, lineWidth: 2).frame(width: 44, height: 44)
                .phaseAnimator([0, 1, 2], trigger: step) { ring, phase in
                    // Rest (0) and the end of the ripple (2) are invisible; 1 is the ring sitting on the knob.
                    ring.scaleEffect(phase == 1 ? 1 : 2.1).opacity(phase == 1 && !reduceMotion ? 0.6 : 0)
                } animation: { phase in phase == 2 ? .easeOut(duration: 0.55) : nil }
            Circle().fill(.clear).frame(width: 44, height: 44)
                .glimmerGlass(.circle, tint: color.opacity(0.45), interactive: true)
            Circle().fill(color).frame(width: 14, height: 14)
                .shadow(color: color.opacity(0.9), radius: dragging ? 9 : 4)
        }
        .scaleEffect(dragging ? 1.16 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.4), value: dragging)
    }

    private func settle() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.35)) {
            dragging = false
            value = Double(step) / 4
        }
    }

    private func move(by amount: Int) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3)) {
            value = Double(min(4, max(0, step + amount))) / 4
        }
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, fraction: Double) -> CGPoint {
        let radians = (225 + fraction * 270) * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }

    #if DEBUG
    /// Moves the dial by itself for design review recordings (GLIMMER_DIAL_DEMO with a test journal).
    private func runDemoIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GLIMMER_TEST_JOURNAL"] != nil, environment["GLIMMER_DIAL_DEMO"] != nil else { return }
        try? await Task.sleep(for: .seconds(5))
        for target in [1.0, 0.0, 0.75] {
            let start = value
            dragging = true
            for frame in 1...90 {
                let progress = Double(frame) / 90
                let eased = progress * progress * (3 - 2 * progress)
                value = start + (target - start) * eased
                try? await Task.sleep(for: .milliseconds(16))
            }
            settle()
            try? await Task.sleep(for: .seconds(1.1))
        }
    }
    #endif
}

extension View {
    /// Uses the tall page-sized sheet on iPad, so the dial is never hidden behind the pinned action bar.
    func tallSheet() -> some View {
        #if os(iOS)
        presentationSizing(.page)
        #else
        self
        #endif
    }

    /// Gives a focused, step-by-step flow the whole screen on iPhone.
    func hidesTabBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}
