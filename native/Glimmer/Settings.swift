import Observation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsPage: View {
    var onReplay: () -> Void = {}

    @AppStorage(ReadingTheme.preference) private var appearance: ReadingTheme = .paper
    @Environment(\.readingTheme) private var theme
    @Environment(JournalStore.self) private var store
    @State private var name = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var showRestore = false
    @State private var backup: JournalBackup?
    @State private var incoming: Journal?
    @State private var message: String?
    @State private var messageIsError = false
    #if os(macOS)
    @State private var agentTutorial = false
    #endif

    var body: some View {
        Page(title: "Settings", width: 680) {
            Panel(title: "Appearance") {
                FlowLayout(spacing: 8) {
                    ForEach(ReadingTheme.allCases) { item in
                        Button { appearance = item } label: {
                            HStack(spacing: 6) {
                                Circle().fill(item.canvas).overlay { Circle().stroke(.secondary, lineWidth: 1) }.frame(width: 14, height: 14)
                                Text(item.rawValue)
                                if appearance == item { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                        }
                        .glimmerButton()
                        .accessibilityAddTraits(appearance == item ? .isSelected : [])
                    }
                }
                .accessibilityIdentifier("settings.theme")
            }
            if store.journal.onboardingComplete {
                Panel(title: "Onboarding") {
                    Button("Welcome to Glimmer", systemImage: "sparkles") {
                        store.showingOnboardingReplay = true
                        onReplay()
                    }
                    .glimmerButton()
                    .accessibilityIdentifier("settingsWelcomeGlimmer")
                    Text("See the onboarding again, from the beginning.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Panel(title: "Your plan") {
                    HStack(spacing: 8) {
                        TextField("First name", text: $name).glimmerField().onSubmit(saveName)
                        Button("Save name", action: saveName).glimmerButton(.standard).besideField()
                    }
                    LabeledContent("Plan tracker") {
                        GlassSegments(label: "Plan tracker", options: Tracker.allCases.map { GlassSegment(value: $0, title: $0.rawValue) },
                          selection: Binding(get: { store.journal.tracker }, set: { value in store.change { $0.tracker = value } }))
                            .frame(maxWidth: 260)
                    }
                }
            }

            #if os(iOS)
            if store.journal.onboardingComplete {
                Panel(title: "Coach", accent: GlimmerColor.ember) {
                    SettingsValueRow(label: "Replies with", value: CoachDeviceRoute.title).font(.callout)
                    Text(CoachDeviceRoute.summary + " To use Claude Code, Codex or Gemini CLI, choose one in Glimmer on your Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            #endif
            CloudSyncPanel()
            DiagnosticsPanel()
            if store.journal.onboardingComplete { CoachDiagnosticsPanel() }
            backupPanel

            #if os(macOS)
            if store.journal.onboardingComplete {
                Panel(title: "Coach", accent: GlimmerColor.ember) {
                    CoachAgentSettings()
                }
                Panel(title: "Agent access") {
                    Button("Walk me through agent setup") { agentTutorial = true }
                    AgentSetupContent(section: .access)
                    if store.agentLevel != .off {
                        Divider()
                        AgentSetupContent(section: .connect)
                    }
                    Divider()
                    AgentSkillSection()
                    if store.agentLevel != .off {
                        Divider()
                        AgentSetupContent(section: .verify)
                    }
                }
            }
            #endif

            AboutPanel()
        }
        .onAppear { name = store.journal.name }
        .onChange(of: store.journal.name) { old, new in
            if name == old { name = new }
        }
        #if os(macOS)
        .onAppear { store.refreshAgentState() }
        .sheet(isPresented: $agentTutorial) { AgentTutorial() }
        #endif
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Glimmer Journal") { result in
            switch result {
            case .success: report("Journal backup exported.")
            case .failure: report("The backup could not be exported.", error: true)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                incoming = try store.readBackup(result.get())
                showRestore = true
            } catch { report("This file could not be opened as a Glimmer journal backup.", error: true) }
        }
        .alert("Replace this device’s journal?", isPresented: $showRestore) {
            Button("Cancel", role: .cancel) { incoming = nil }
            Button("Restore backup", role: .destructive) { restore() }
        } message: {
            if let incoming {
                let effects = store.cloudEnabled
                    ? "The replacement will sync to your other devices."
                    : "It will replace your current journal on this device."
                Text("This backup has \(incoming.moments.count) logged moments and \(incoming.tasks.count) tasks. \(effects) Export the current journal first if you want to keep it.")
            }
        }
    }

    private var backupPanel: some View {
        Panel(title: "Privacy & backups", accent: GlimmerColor.sage) {
            Label("Glimmer has no account or analytics. You choose where to save each backup.",
                  systemImage: "lock.shield")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ActionRow(title: "Export journal backup", detail: "Save a JSON file you can restore later",
                          icon: "square.and.arrow.up", tint: GlimmerColor.sage, trailing: "chevron.right") {
                    do {
                        backup = JournalBackup(data: try store.export())
                        exporting = true
                    } catch { report("Glimmer couldn’t create a backup.", error: true) }
                }
                .disabled(store.loadError != nil)
                ActionRow(title: "Restore journal backup", detail: "Preview it before anything is replaced",
                          icon: "arrow.counterclockwise", tint: GlimmerColor.sage, trailing: "chevron.right") { importing = true }
            }
            .glassGroup(spacing: 8)
            if let message {
                Label(message, systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(messageIsError ? GlimmerColor.ember : GlimmerColor.sage)
            }
        }
    }


    private func report(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
    }

    private func saveName() {
        if store.change({ $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            report("Name saved.")
        }
    }

    private func restore() {
        guard var restored = incoming else { return }
        restored.engagement = store.journal.engagement
        if store.change({ $0 = restored }) {
            name = restored.name
            report("Journal restored.")
        } else { report("Glimmer couldn’t restore this journal.", error: true) }
        incoming = nil
    }
}

struct CloudSyncPanel: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        Panel(title: "iCloud Sync", accent: GlimmerColor.sage) {
            Toggle("Sync with iCloud", isOn: Binding(get: { store.cloudEnabled }, set: store.setCloudEnabled))
                .toggleStyle(.switch)
                .disabled(!store.canUseCloud)
            Text("Keep your journal and progress in sync on devices that use the same Apple Account.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                SettingsValueRow(label: "Apple Account", value: store.accountStatus)
                    .accessibilityIdentifier("settings.libraryStatus")
                SettingsValueRow(label: "Last check", value: SyncTimestamp.text(store.lastCheck))
                SettingsValueRow(label: "Last iCloud response", value: SyncTimestamp.text(store.lastCloudContact))
            }
            .font(.callout)
            if store.cloudEnabled || store.cloudStatus != "Journal stays on this device." {
                Text(store.cloudStatus)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("glimmerCloudStatus")
            }
            Button { Task { await store.syncNow() } } label: {
                RowLabel(title: store.cloudSyncing ? "Checking iCloud…" : "Check Now", icon: "arrow.clockwise", trailing: nil)
            }
            .glassRow()
            .disabled(!store.cloudEnabled || store.cloudSyncing)
        }
    }
}

struct DiagnosticsPanel: View {
    @Environment(JournalStore.self) private var store
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        Panel(title: "Diagnostics") {
            if let code = store.syncErrorCode {
                SettingsValueRow(label: "Error code", value: code).font(.callout)
            }
            ShareLink(item: syncDiagnostics) {
                RowLabel(title: "Share Sync Diagnostics", icon: "square.and.arrow.up", trailing: nil)
            }
            .glassRow()
            .accessibilityIdentifier("settings.shareSyncDiagnostics")
            Text("Includes sync status and timestamps. Your journal entries, tasks, and account details are not included.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var syncDiagnostics: String {
        var lines = [
            "Glimmer \(appVersion) (\(appBuild))",
            "Apple Account: \(store.accountStatus)",
            "Last check: \(SyncTimestamp.text(store.lastCheck))",
            "Last iCloud response: \(SyncTimestamp.text(store.lastCloudContact))"
        ]
        if let code = store.syncErrorCode { lines.append("Error code: \(code)") }
        return lines.joined(separator: "\n")
    }
}

enum SyncTimestamp {
    static func text(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "—"
    }
}

/// A label and value on one line, like LabeledContent in a Form.
struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(value).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AboutPanel: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showSupportCard = false
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "About", padding: 20) {
                HStack(spacing: 14) {
                    GlimmerLogo(size: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glimmer").font(GlimmerFont.display(.title, weight: .bold))
                        Text("Version \(version) (\(build)) · Protomota Software")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text("Glimmer is a gentle spiritual life coach for deep thinkers, neurodivergent minds, and anyone too busy thinking to stay organized. Reflect on what matters, then try one small step in your day.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Log short moments on your own device, try one concrete change at a time, and review your week to see what genuinely helped. Glimmer respects rest and keeps every decision in your hands.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    Link(destination: StoreLinks.website) {
                        RowLabel(title: "Glimmer website", detail: "glimmertoday.ai", icon: "globe", trailing: "arrow.up.right")
                    }.glassRow()
                }
                .glassGroup(spacing: 8)
            }
            Panel(title: "Ratings & support", accent: GlimmerColor.honey) {
                Text("Your App Store rating helps more people discover Glimmer. Every feature is free.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ActionRow(title: "Rate on the App Store",
                              detail: StoreLinks.review == nil ? "Available once Glimmer is on the App Store" : "On the App Store",
                              icon: "star.fill", tint: GlimmerColor.honey) {
                        if let url = StoreLinks.review {
                            openURL(url) { accepted in
                                if accepted { store.change { $0.engagement.actions.insert("review") } }
                            }
                        }
                    }
                    .disabled(StoreLinks.review == nil)
                    .accessibilityIdentifier("reviewGlimmer")
                    SupportTicketRow()
                    ShareLink(item: StoreLinks.website) {
                        RowLabel(title: "Share Glimmer", icon: "square.and.arrow.up.fill", tint: GlimmerColor.accent, trailing: nil)
                    }.glassRow()
                    Link(destination: StoreLinks.feedback) {
                        RowLabel(title: "Send Feedback", icon: "bubble.left.and.bubble.right.fill", tint: GlimmerColor.sage,
                                 trailing: "arrow.up.right")
                    }.glassRow()
                    Link(destination: StoreLinks.protomotaApps) {
                        RowLabel(title: "More Free Apps by Protomota", icon: "square.grid.2x2.fill", tint: GlimmerColor.honey,
                                 trailing: "arrow.up.right")
                    }.glassRow()
                    #if os(macOS)
                    ActionRow(title: "Share or send feedback", detail: "See which ones you’ve opened",
                              icon: "checklist", tint: GlimmerColor.dusk) { showSupportCard = true }
                        .accessibilityIdentifier("glimmerSupportCard")
                    #endif
                }
                .glassGroup(spacing: 8)
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showSupportCard) { GlimmerSupportSheet(isReminder: false) }
        #endif
    }
}

struct JournalBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Free personal technical support on protomota.com, the same on every device.
struct SupportTicketRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ActionRow(title: "Technical Support", detail: "Free help from a real person for Mac, iPhone, and iPad",
                  icon: "headphones", tint: GlimmerColor.dusk, trailing: "arrow.up.right") {
            #if os(macOS)
            GlimmerSupportReminder.record(.support)
            #endif
            openURL(StoreLinks.support)
        }
        .accessibilityIdentifier("glimmerSupportTickets")
    }
}
