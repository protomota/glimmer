import SwiftUI
#if os(macOS)
import AppKit
#endif

enum StoreLinks {
    static let website = URL(string: "https://glimmertoday.ai/")!
    static let protomotaApps = URL(string: "https://protomota.com/apps")!
    static let feedback = URL(string: "https://protomota.com/apps?app=glimmer#feedback")!
    /// Help articles and personal support tickets on protomota.com.
    static let support = URL(string: "https://protomota.com/support?app=glimmer")!

    static var review: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GlimmerAppStoreID") as? String,
              !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}

#if os(macOS)
/// The Mac "support Glimmer" card, shared with the other Protomota Mac apps: after five logged
/// moments it returns at most once a week until every action has been opened. Later hides it for a week;
/// Don't show again turns it off for good.
@MainActor
enum GlimmerSupportReminder {
    enum Action: String, CaseIterable, Identifiable {
        case feedback, share, support, apps
        var id: Self { self }
    }

    static let actionsKey = "glimmer.community.supportActions"
    static let presentedKey = "glimmer.community.supportPresentedAt"
    static let dismissedKey = "glimmer.community.supportDismissed"
    static let milestone = 5
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    static func clicked(_ values: String) -> Set<Action> {
        Set(values.split(separator: ",").compactMap { Action(rawValue: String($0)) })
    }

    /// Records an opened action and says whether every action has now been opened.
    @discardableResult
    static func record(_ action: Action, in defaults: UserDefaults = .standard) -> Bool {
        var actions = clicked(defaults.string(forKey: actionsKey) ?? "")
        actions.insert(action)
        defaults.set(actions.map(\.rawValue).sorted().joined(separator: ","), forKey: actionsKey)
        return actions.count == Action.allCases.count
    }

    /// Turns the reminder off for good. Settings still opens the card on request.
    static func dismissForever(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dismissedKey)
    }

    /// Whether the reminder should show now. Showing it starts the next week-long wait.
    static func claim(activity: Int, now: Date = .now, in defaults: UserDefaults = .standard) -> Bool {
        guard activity >= milestone, !defaults.bool(forKey: dismissedKey),
              clicked(defaults.string(forKey: actionsKey) ?? "").count < Action.allCases.count else { return false }
        let last = defaults.double(forKey: presentedKey)
        guard last == 0 || now.timeIntervalSince1970 - last >= interval else { return false }
        defaults.set(now.timeIntervalSince1970, forKey: presentedKey)
        return true
    }
}

/// Feedback, share, support and more apps, each ticked once opened.
struct GlimmerSupportSheet: View {
    let isReminder: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GlimmerSupportReminder.actionsKey) private var clicks = ""
    @State private var sharePicker = SupportSharePicker()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                GlimmerLogo(size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free software.\nSupported by people.")
                        .font(GlimmerFont.display(.title2, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Help more people discover Glimmer and tell us what we can improve.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                row("Send feedback", detail: "Tell us what’s working and what could be better",
                    symbol: "bubble.left.and.bubble.right.fill", tint: GlimmerColor.sage, action: .feedback) {
                    visit(.feedback, url: StoreLinks.feedback)
                }
                row("Share Glimmer", detail: "Send someone a link to the app", symbol: "square.and.arrow.up.fill",
                    tint: GlimmerColor.accent, action: .share) {
                    sharePicker.show {
                        if GlimmerSupportReminder.record(.share), isReminder { dismiss() }
                    }
                }
                .background(SupportShareAnchor(view: sharePicker.anchor).allowsHitTesting(false))
                row("Open a Support Ticket", detail: "Free help or follow replies for Mac, iPhone, and iPad",
                    symbol: "headphones", tint: GlimmerColor.dusk, action: .support) {
                    visit(.support, url: StoreLinks.support)
                }
                row("More Free Apps by Protomota", detail: "Explore more free apps from our studio",
                    symbol: "square.grid.2x2.fill", tint: GlimmerColor.honey, action: .apps) {
                    visit(.apps, url: StoreLinks.protomotaApps)
                }
            }
            .glassGroup(spacing: 8)
            Text("Checkmarks show which buttons you’ve opened.")
                .font(.caption).foregroundStyle(.secondary)
            if isReminder {
                HStack {
                    Button("Don’t show again") {
                        GlimmerSupportReminder.dismissForever()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("support.dontShowAgain")
                    Spacer()
                    PrimaryAction(title: "Later", systemImage: "clock") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("support.later")
                }
            } else {
                HStack {
                    Spacer()
                    PrimaryAction(title: "Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityIdentifier("supportReminder")
    }

    private func visit(_ action: GlimmerSupportReminder.Action, url: URL) {
        let finished = GlimmerSupportReminder.record(action)
        openURL(url)
        if finished, isReminder { dismiss() }
    }

    private func row(_ title: String, detail: String, symbol: String, tint: Color,
                     action: GlimmerSupportReminder.Action, perform: @escaping () -> Void) -> some View {
        let clicked = GlimmerSupportReminder.clicked(clicks).contains(action)
        return ActionRow(title: title, detail: detail, icon: symbol, tint: tint,
                         trailing: clicked ? "checkmark.circle.fill" : "arrow.up.right", selected: clicked, action: perform)
            .accessibilityValue(clicked ? "Previously opened" : "")
            .accessibilityIdentifier("support.\(action.rawValue)")
    }
}

private struct SupportShareAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class SupportSharePicker: NSObject, NSSharingServicePickerDelegate {
    let anchor = NSView()
    private var picker: NSSharingServicePicker?
    private var finished: (() -> Void)?

    func show(finished: @escaping () -> Void) {
        guard picker == nil, anchor.window != nil else { return }
        let picker = NSSharingServicePicker(items: [StoreLinks.website])
        self.picker = picker
        self.finished = finished
        picker.delegate = self
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Task { @MainActor in self.complete() }
    }

    private func complete() {
        let completion = finished
        finished = nil
        picker = nil
        completion?()
    }
}
#endif
