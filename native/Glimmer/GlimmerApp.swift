import StoreKit
import SwiftUI

@main
struct GlimmerEntry {
    @MainActor static func main() {
        #if os(macOS)
        if CommandLine.arguments.dropFirst() == ["--mcp"] {
            AgentAccess.run()
            return
        }
        // Settings → Coach → Test Coach from Terminal: --test-coach claude|codex|gemini [model] [effort]
        if CommandLine.arguments.dropFirst().first == "--test-coach" {
            CoachAgentRoute.runTestCommand(Array(CommandLine.arguments.dropFirst(2)))
            return
        }
        #endif
        GlimmerApp.main()
    }
}

struct GlimmerApp: App {
    @State private var store = JournalStore()
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @StateObject private var updates = AppUpdates()
    #endif

    var body: some Scene {
        #if os(macOS)
        mainWindow
            .defaultSize(width: 1000, height: 760)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About Glimmer") { openWindow(id: "about-glimmer") }
                    if updates.isAvailable { CheckForUpdatesButton(updates: updates) }
                }
            }

        Settings {
            SettingsPage(onReplay: { NSApp.keyWindow?.close() }).environment(store).modifier(ReadingAppearance())
                .frame(minWidth: 510, minHeight: 570)
        }
        Window("About Glimmer", id: "about-glimmer") {
            Page(title: "About Glimmer", width: 520) { AboutPanel() }
                .environment(store)
                .modifier(ReadingAppearance()).frame(minWidth: 430, minHeight: 450)
        }.defaultSize(width: 490, height: 570)
        #else
        mainWindow
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RootView().environment(store).modifier(ReadingAppearance())
                .disclosureGroupStyle(GlimmerDisclosureStyle())
            #if DEBUG
            .task {
                let env = ProcessInfo.processInfo.environment
                if env["GLIMMER_TEST_JOURNAL"] != nil, env["GLIMMER_TEST_START_PLAN"] == "1" {
                    store.start(name: "")
                }
            }
            #endif
                #if DEBUG && os(macOS)
                .task {
                    // Design review captures need a key window so glass renders in its active state.
                    guard ProcessInfo.processInfo.environment["GLIMMER_TEST_JOURNAL"] != nil else { return }
                    for _ in 0..<4 {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        try? await Task.sleep(for: .seconds(0.6))
                    }
                }
                #endif
        }
    }
}

enum Destination: String, Hashable, CaseIterable, Identifiable {
    case today = "Today", insights = "Insights", weekly = "Weekly", coach = "Coach"
    case plan = "Plan", toolkit = "Toolkit", habits = "Habits", challenges = "Challenges", lessons = "Lessons"
    case cleaning = "Cleaning", seasonal = "Seasonal", settings = "Settings"

    var id: Self { self }
    var title: String { self == .cleaning ? "Cleaning & maintenance" : rawValue }
    var icon: String {
        switch self {
        case .today: "sun.horizon.fill"
        case .insights: "chart.bar.fill"
        case .weekly: "calendar"
        case .coach: "text.bubble.fill"
        case .plan: "list.bullet.clipboard.fill"
        case .toolkit: "wrench.and.screwdriver.fill"
        case .habits: "leaf.fill"
        case .challenges: "trophy.fill"
        case .lessons: "book.fill"
        case .cleaning: "bubbles.and.sparkles.fill"
        case .seasonal: "tree.fill"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today, .plan, .cleaning: GlimmerColor.accent
        case .insights, .habits: GlimmerColor.sage
        case .weekly, .challenges: GlimmerColor.honey
        case .coach, .seasonal: GlimmerColor.ember
        case .toolkit, .lessons, .settings: GlimmerColor.dusk
        }
    }

    var detail: String {
        switch self {
        case .plan: "Checklist and recurring tasks"
        case .toolkit: "Break things down, size them, focus"
        case .habits: "Daily habits and mood"
        case .challenges: "Short guided challenges"
        case .lessons: "Your 90-day reading plan"
        case .cleaning: "Tidy up and keep things working"
        case .seasonal: "Timely tips and checklists"
        case .settings: "Backups, privacy and support"
        default: ""
        }
    }
}

enum QuickFlow: String, Identifiable {
    case log, energy
    #if os(macOS)
    case agentTutorial
    #endif
    var id: Self { self }
}

struct RootView: View {
    @Environment(\.readingTheme) private var theme
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var destination: Destination? = .today
    @FocusState private var focusedSidebarItem: Destination?
    @State private var mobileTab: Destination = .today
    @State private var mobilePath: [Destination] = []
    @State private var flow: QuickFlow?
    @State private var visibleCoins: EarnedCoins?
    @State private var coinBurst: (award: EarnedCoins, startedAt: Date)?
    @State private var presentedAwardID: UUID?
    #if os(macOS)
    @State private var showsSupportReminder = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool {
        #if os(macOS)
        false
        #else
        sizeClass == .compact
        #endif
    }

    var body: some View {
        Group {
            if let loadError = store.loadError {
                ContentUnavailableView {
                    Label("Journal unavailable", systemImage: "lock.doc")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again") { store.reload() }.glimmerButton(.prominent)
                }
                .background { PageBackdrop() }
            } else if let catalog = store.catalog {
                if store.showingOnboardingReplay {
                    OnboardingView(catalog: catalog, onFinishReplay: { store.showingOnboardingReplay = false })
                        .id("onboarding-replay")
                } else if store.journal.onboardingComplete {
                    if compact {
                        tabs(catalog)
                    } else {
                        split(catalog)
                    }
                } else {
                    OnboardingView(catalog: catalog)
                }
            } else {
                ContentUnavailableView("Glimmer’s library is missing", systemImage: "book.closed")
                    .background { PageBackdrop() }
            }
        }
        .tint(GlimmerColor.accent)
        .sheet(item: $flow) { flow in
            if let catalog = store.catalog {
                switch flow {
                case .log: MomentFlow(catalog: catalog).tallSheet()
                case .energy: EnergyFlow(catalog: catalog).tallSheet()
                #if os(macOS)
                case .agentTutorial: AgentTutorial()
                #endif
                }
            }
        }
        .overlay {
            if let coinBurst, !reduceMotion {
                CoinBurst(startedAt: coinBurst.startedAt, amount: coinBurst.award.amount)
                    .id(coinBurst.award.id)
                    .task(id: coinBurst.award.id) {
                        try? await Task.sleep(for: .seconds(CoinBurst.duration))
                        if !Task.isCancelled, self.coinBurst?.award.id == coinBurst.award.id {
                            self.coinBurst = nil
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let award = visibleCoins {
                EarnedCoinsToast(award: award)
                    .padding(.bottom, compact ? 118 : 24)
                    .padding(.horizontal, 16)
                    .id(award.id)
                    .transition(.opacity)
            } else if store.earnedCoins?.id == presentedAwardID, let notice = store.notice {
                NoticeToast(text: notice)
                    .padding(.bottom, compact ? 118 : 24).padding(.horizontal, 16)
                    .id(notice)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2.6))
                        if !Task.isCancelled, store.notice == notice { store.notice = nil }
                    }
            }
        }
        .animation(.smooth, value: store.notice)
        .sensoryFeedback(.impact(weight: .light), trigger: visibleCoins?.id) { _, next in next != nil }
        .task(id: store.earnedCoins) {
            guard let award = store.earnedCoins, award.id != presentedAwardID else { return }
            // A save can dismiss a sheet or reader. Give that transition room to finish.
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            presentedAwardID = award.id
            await showCoins(award)
        }
        .onChange(of: phase, initial: true) { _, state in
            if state == .active {
                store.day = .now
                refreshPersonalReminders()
            }
        }
        .onChange(of: store.journal.personalTodos) { _, _ in refreshPersonalReminders() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                if let editor = store.editorialLibrary {
                    await editor.refreshIfNeeded()
                }
                if store.editorialLibrary?.edition == nil {
                    await GalleryLibrary.shared.refreshIfNeeded()
                }
                do { try await Task.sleep(for: .seconds(EditorialLibrary.refreshInterval)) } catch { return }
            }
        }
        .task(id: phase == .active && store.cloudEnabled) {
            if phase == .active { await store.syncWhileActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in store.cloudAccountChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in store.day = .now }
        #if DEBUG
        .task { openReviewScreen() }
        #endif
        .task(id: canRequestReview) {
            guard canRequestReview else { return }
            try? await Task.sleep(for: .seconds(2))
            #if !DEBUG
            // The native sheet rates an App Store install. TestFlight and the direct Mac download
            // shouldn't use up the one prompt before someone has the App Store build.
            guard case .verified(let transaction) = try? await AppTransaction.shared,
                  transaction.environment == .production else { return }
            #endif
            guard !Task.isCancelled, canRequestReview else { return }
            if store.change({ $0.engagement.requestedReview = true }) { requestReview() }
        }
        #if os(macOS)
        .task(id: canShowSupportReminder) {
            guard canShowSupportReminder else { return }
            // Let the App Store prompt and any open sheet go first.
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard canShowSupportReminder, NSApp.isActive, let window = NSApp.keyWindow, !window.isSheet,
                  window.attachedSheet == nil,
                  GlimmerSupportReminder.claim(activity: store.journal.engagement.count) else { return }
            showsSupportReminder = true
        }
        .sheet(isPresented: $showsSupportReminder) { GlimmerSupportSheet(isReminder: true) }
        #endif
    }

    #if os(macOS)
    private var canShowSupportReminder: Bool {
        phase == .active && flow == nil && store.notice == nil && store.journal.onboardingComplete
            && store.journal.engagement.count >= GlimmerSupportReminder.milestone
    }
    #endif

    private var canRequestReview: Bool {
        phase == .active && flow == nil && store.notice == nil
            && (compact ? mobileTab == .today && mobilePath.isEmpty : destination == .today)
            && store.journal.engagement.shouldRequestReview && StoreLinks.review != nil
    }

    private func open(_ page: Destination) {
        if compact {
            mobileTab = .today
            mobilePath.append(page)
        } else {
            destination = page
        }
    }

    private func showCoins(_ award: EarnedCoins) async {
        if !reduceMotion { coinBurst = (award, .now) }
        withAnimation(.easeOut(duration: reduceMotion ? 0.10 : 0.16)) { visibleCoins = award }
        AccessibilityNotification.Announcement("\(award.amount) coins earned").post()
        try? await Task.sleep(for: .seconds(2.1))
        if visibleCoins == award {
            withAnimation(.easeInOut(duration: 0.16)) { visibleCoins = nil }
        }
    }

    private func launch(_ quickFlow: QuickFlow) { flow = quickFlow }

    private func refreshPersonalReminders() {
        guard store.loadError == nil, store.usesDeviceReminders else { return }
        PersonalReminders.shared.refresh(store.journal.personalTodos ?? [])
    }

    #if DEBUG
    /// Opens a screen named in the launch environment, for design review captures with test journals.
    private func openReviewScreen() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GLIMMER_TEST_JOURNAL"] != nil else { return }
        if environment["GLIMMER_COIN_DEMO"] != nil {
            // Shows the coin celebration twice for design review recordings.
            Task {
                try? await Task.sleep(for: .seconds(4.5))
                await showCoins(EarnedCoins(amount: 10))
                try? await Task.sleep(for: .seconds(2.9))
                await showCoins(EarnedCoins(amount: 60))
                for message in ["Task added to your plan.", "Nice. Let’s use that momentum.", "Glimmer couldn’t save this change. Please try again."] {
                    try? await Task.sleep(for: .seconds(4))
                    store.notice = message
                }
            }
        }
        if let name = environment["GLIMMER_SCREEN"],
           let page = Destination.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(name) == .orderedSame ||
               $0.title.caseInsensitiveCompare(name) == .orderedSame
           }) {
            if compact && [.insights, .weekly, .coach].contains(page) { mobileTab = page } else if page != .today { open(page) }
        }
        if let name = environment["GLIMMER_FLOW"] { flow = QuickFlow(rawValue: name) }
    }
    #endif

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func split(_ catalog: Catalog) -> some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach([Destination.today, .coach, .lessons, .plan, .toolkit]) { sidebarRow($0) }
                } header: { sidebarHeading("Glimmer") }
                Section {
                    ForEach([Destination.insights, .weekly, .habits, .challenges, .cleaning, .seasonal, .settings]) { sidebarRow($0) }
                } header: { sidebarHeading("Your space") }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            NavigationStack {
                detail(catalog)
                    .toolbar { quickToolbar(catalog) }
            }.id(destination)
        }
        .toolbar(removing: .title)
    }

    #if os(macOS)
    private static let sidebarGlyph: CGFloat = 15
    #else
    private static let sidebarGlyph: CGFloat = 20
    #endif

    private func sidebarRow(_ item: Destination) -> some View {
        let selected = (destination ?? .today) == item
        #if os(macOS)
        let rowHeight: CGFloat = 32
        #else
        let rowHeight: CGFloat = 44
        #endif

        return Button { destination = item } label: {
            Label {
                Text(item.title)
                    .fontWeight(selected ? .semibold : .regular)
                    .underline(focusedSidebarItem == item)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: item.icon)
                    .font(.system(size: Self.sidebarGlyph, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(item.tint)
                    .frame(width: Self.sidebarGlyph + 9)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedSidebarItem, equals: item)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.primary.opacity(selected ? (theme == .glimmer ? 0.12 : 0.075) : 0))
    }

    @ToolbarContentBuilder
    private func quickToolbar(_ catalog: Catalog) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { launch(.energy) } label: { Label("Check in", systemImage: "bolt.heart") }.tint(Color.primary)
                .help("Check in your energy")
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Menu {
                Button("Open your plan", systemImage: "checklist") { open(.plan) }
                Button("Try a tiny win", systemImage: "sparkles") { open(.challenges) }
                Button("Read today’s lesson", systemImage: "book") { open(.lessons) }
            } label: {
                Label("Quick actions", systemImage: "ellipsis")
            }
            .tint(Color.primary)
            .help("More quick actions")
            Button { launch(.log) } label: { Label("Log a moment", systemImage: "plus") }.glimmerButton(.prominent).tint(Color.primary)
                .help("Log a moment")
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    @ViewBuilder
    private func tabs(_ catalog: Catalog) -> some View {
        let view = TabView(selection: $mobileTab) {
            Tab("Today", systemImage: Destination.today.icon, value: Destination.today) {
                NavigationStack(path: $mobilePath) {
                    compactToday(catalog)
                        .navigationDestination(for: Destination.self) { page in
                            if page == .plan || page == .toolkit {
                                screen(page, catalog: catalog).hidesTabBar()
                            } else {
                                screen(page, catalog: catalog)
                            }
                        }
                        .toolbar { compactToolbar }
                }
            }
            ForEach([Destination.insights, .weekly, .coach]) { tab in
                Tab(tab.rawValue, systemImage: tab.icon, value: tab) {
                    NavigationStack { screen(tab, catalog: catalog).toolbar { compactToolbar } }
                }
            }
        }
        #if os(iOS)
        if #available(iOS 26, *) {
            view.tabBarMinimizeBehavior(mobileTab == .coach ? .never : .onScrollDown)
        } else {
            view
        }
        #else
        view
        #endif
    }

    @ViewBuilder private func compactToday(_ catalog: Catalog) -> some View {
        #if DEBUG
        if let name = ReviewLaunch.detail {
            ReviewDetail(name: name, catalog: catalog)
        } else {
            screen(.today, catalog: catalog)
        }
        #else
        screen(.today, catalog: catalog)
        #endif
    }

    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { launch(.energy) } label: { Label("Check in", systemImage: "bolt.heart") }.tint(Color.primary)
            Button { launch(.log) } label: { Label("Log a moment", systemImage: "plus") }.glimmerButton(.prominent).tint(Color.primary)
        }
    }

    @ViewBuilder private func detail(_ catalog: Catalog) -> some View {
        #if DEBUG
        if let name = ReviewLaunch.detail {
            ReviewDetail(name: name, catalog: catalog)
        } else {
            screen(destination ?? .today, catalog: catalog)
        }
        #else
        screen(destination ?? .today, catalog: catalog)
        #endif
    }

    @ViewBuilder private func screen(_ page: Destination, catalog: Catalog) -> some View {
        switch page {
        case .today: TodayView(catalog: catalog, open: open, launch: launch)
        case .insights: InsightsView(catalog: catalog)
        case .weekly: WeeklyView(catalog: catalog)
        case .coach: CoachView(catalog: catalog)
        case .plan: PlanView(catalog: catalog)
        case .toolkit: ToolkitView()
        case .habits: HabitsView(catalog: catalog)
        case .challenges: ChallengesView(catalog: catalog)
        case .lessons: LessonsView(catalog: catalog)
        case .cleaning: CleaningView(catalog: catalog)
        case .seasonal: SeasonalView()
        case .settings: SettingsPage()
        }
    }
}

#if DEBUG
/// Opens nested screens directly for design-review captures using an isolated test journal.
struct ReviewDetail: View {
    @Environment(JournalStore.self) private var store
    let name: String
    let catalog: Catalog
    @State private var sheet = false
    @State private var pushed = false
    @State private var cover = false

    var body: some View {
        content
            #if os(iOS)
            .fullScreenCover(isPresented: $cover) {
                if let todo = store.openPersonalTodos.first(where: { !store.journal.steps(for: $0.id).isEmpty }) { OneThingSheet(start: todo) }
            }
            #endif
            .sheet(isPresented: $sheet) {
                let todo = store.openPersonalTodos.first { !store.journal.steps(for: $0.id).isEmpty } ?? store.openPersonalTodos.first
                switch name {
                case "taskeditor": TaskEditor(task: store.journal.tasks.first ?? PlanTask())
                case "breaksheet": if let todo = store.openPersonalTodos.last { BreakItDownSheet(todo: todo, parent: nil) }
                case "timesheet": if let todo { TimeCheckSheet(todo: todo) }
                case "todoeditor": if let todo { PersonalTodoEditor(task: todo, today: store.day) }
                case "focussheet": if let todo { OneThingSheet(start: todo) }
                #if os(macOS)
                case "support": GlimmerSupportSheet(isReminder: true)
                #endif
                default: EmptyView()
                }
            }
            .task {
                #if os(iOS)
                cover = name == "focussheet"
                sheet = ["taskeditor", "breaksheet", "timesheet", "todoeditor"].contains(name)
                #else
                sheet = ["taskeditor", "support", "breaksheet", "timesheet", "todoeditor", "focussheet"].contains(name)
                #endif
                pushed = toolkitPages.contains(name)
            }
    }

    // Toolkit pages open pushed from the Toolkit, the way people reach them.
    private let toolkitPages = ["onething", "breakitdown", "timecheck", "unload", "readtheroom", "reword", "weighit"]

    @ViewBuilder private var toolkitPage: some View {
        switch name {
        case "onething": OneThingView()
        case "breakitdown": BreakItDownPicker()
        case "timecheck": TimeCheckView()
        case "unload": UnloadView()
        case "readtheroom": ReadTheRoomView()
        case "reword": RewordView()
        default: WeighItView()
        }
    }

    @ViewBuilder private var content: some View {
        switch name {
        case "lesson": LessonReader(lesson: catalog.lessons[0])
        case "challenge": ChallengeView(challenge: catalog.challenges[0])
        case "library": TaskLibraryView(catalog: catalog)
        case "suggestions": PreloadView(catalog: catalog)
        case "cleaninglist": CleaningSession(list: catalog.cleaning.daily)
        case "practices": PracticeView(topics: catalog.practiceTopics, title: "Practice exercises")
        case "screentime": ScreenTimeCheck()
        case "about": Page(title: "About Glimmer") { AboutPanel() }
        #if os(macOS)
        case "coachagent": Page(title: "Coach", width: 680) {
            Panel(title: "Coach", accent: GlimmerColor.ember) { CoachAgentSettings() }
            CoachDiagnosticsPanel()
        }
        #else
        case "coachagent": SettingsPage()
        #endif
        case "toolkit", "breaksheet", "timesheet", "todoeditor": ToolkitView()
        case "focussheet": OneThingView()
        case _ where toolkitPages.contains(name):
            ToolkitView().navigationDestination(isPresented: $pushed) { toolkitPage.hidesTabBar() }
        case "review": if let experiment = store.journal.experiment { ExperimentReview(experiment: experiment) }
        default: PlanView(catalog: catalog)
        }
    }
}

enum ReviewLaunch {
    static var detail: String? {
        let environment = ProcessInfo.processInfo.environment
        return environment["GLIMMER_TEST_JOURNAL"] == nil ? nil : environment["GLIMMER_DETAIL"]
    }

    static var colorScheme: ColorScheme? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GLIMMER_TEST_JOURNAL"] != nil else { return nil }
        return switch environment["GLIMMER_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
#endif

/// A short message that confirms a routine app action.
struct NoticeToast: View {
    let text: String

    private var appearance: (symbol: String, color: Color) {
        if text.contains("couldn’t") { return ("exclamationmark", GlimmerColor.ember) }
        let confirmations = ["added", "copied", "complete", "started", "saved", "logged", "set", "whole day"]
        if confirmations.contains(where: text.localizedCaseInsensitiveContains) { return ("checkmark", GlimmerColor.sage) }
        return ("sparkles", GlimmerColor.dusk)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appearance.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appearance.color)
                .frame(width: 26, height: 26)
                .background(appearance.color.opacity(0.14), in: .circle)
            Text(text).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10).padding(.trailing, 20).padding(.vertical, 10)
        .glimmerGlass(.capsule, tint: appearance.color.opacity(0.16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct TodayView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    let catalog: Catalog
    let open: (Destination) -> Void
    let launch: (QuickFlow) -> Void

    #if os(macOS)
    @AppStorage("glimmer.didSeeAgentInvite") private var didSeeAgentInvite = false
    #endif

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return store.journal.name.isEmpty ? part : "\(part), \(store.journal.name)"
    }

    private var energy: EnergyCheck? { store.journal.energy[store.todayKey] }
    private var completed: Int { store.todaysTasks.filter { store.todayCompletion.contains($0.id) }.count }
    private var featuredSeason: SeasonalEdition? {
        store.seasonalEditions.first { $0.recommendation(on: store.day) != nil }
    }

    var body: some View {
        GeometryReader { viewport in
            if viewport.size.width >= 700 && viewport.size.height >= 745 && !typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        HStack(alignment: .top, spacing: 30) {
                            VStack(alignment: .leading, spacing: 16) {
                                lesson
                                seasonalLink
                                reflection
                                assistantInvite
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 16) {
                                plan
                                PersonalTodoList(openPlan: { open(.plan) })
                            }
                                .frame(width: min(325, viewport.size.width * 0.34))
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1000, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
                .background { PageBackdrop() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        lesson
                        seasonalLink
                        plan
                        PersonalTodoList(openPlan: { open(.plan) })
                        reflection
                        assistantInvite
                        if sizeClass == .compact { space }
                    }
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .background { PageBackdrop() }
            }
        }
    }

    @ViewBuilder private var seasonalLink: some View {
        if let edition = featuredSeason, let recommendation = edition.recommendation(on: store.day) {
            SeasonalRecommendation(edition: edition, list: recommendation.list, item: recommendation.item) {
                open(.seasonal)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(store.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            ReaderRankBar(progress: ReaderProgress(journal: store.journal, catalog: catalog), coins: store.journal.coins)
            Text(greeting).font(GlimmerFont.reading(.largeTitle, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 12, centerItemsVertically: true) {
                Button { launch(.energy) } label: { Label("How’s your energy?", systemImage: "bolt.heart") }.accessibilityIdentifier("today.energy")
                Button { launch(.log) } label: { Label("Log a moment", systemImage: "plus") }.glimmerButton(.prominent).accessibilityIdentifier("today.log")
                if !store.todayLogs.isEmpty { Text("\(store.todayLogs.count) logged today").font(.callout).foregroundStyle(.secondary) }
            }
            .glimmerButton()
            .controlSize(.regular)
            if let quote = store.dailyQuote {
                VStack(alignment: .leading, spacing: 3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("“\(quote.text)”")
                            .font(GlimmerFont.reading(.title3).italic())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(quote.author).font(.callout).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.quote")
                    SendToInkspringButton(quote: quote)
                }
                .padding(.top, 4)
                .frame(maxWidth: 580, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var assistantInvite: some View {
        #if os(macOS)
        if !didSeeAgentInvite && store.agentLevel == .off {
            HStack {
                Button("Connect your assistant to Glimmer") { didSeeAgentInvite = true; launch(.agentTutorial) }.glimmerButton()
                Button("Later") { didSeeAgentInvite = true }.buttonStyle(.borderless)
            }.font(.callout)
        }
        #endif
    }

    @ViewBuilder private var lesson: some View {
        if let lesson = catalog.dailyLesson(for: store.journal, on: store.day) {
            VStack(alignment: .leading, spacing: 8) {
                Artwork(slot: 0, featured: true, height: 145)
                    .readingArrival()
                Eyebrow("Today’s lesson · \(lesson.minutes) min")
                Text(lesson.title).font(GlimmerFont.reading(.title, weight: .medium))
                Text(lesson.tagline).foregroundStyle(.secondary)
                NavigationLink { LessonReader(lesson: lesson) } label: {
                    Text(store.journal.lessons[lesson.id]?.completed == true ? "Read again" : "Read today’s lesson")
                }
                .glimmerButton(.prominent)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var reflection: some View {
        if let practice = catalog.dailyReflection(on: store.day, level: store.journal.guidanceLevel(asOf: store.day)) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("A moment to reflect")
                    Text(practice.title).font(.headline)
                    Text(reflectionBody(practice.sub)).font(.callout)
                }
                Button("Open Coach") { open(.coach) }
                    .glimmerButton(.prominent)
                    .controlSize(.large)
            }
        }
    }

    private func reflectionBody(_ text: String) -> String {
        // Keep the last two words together as the reflection changes each day.
        guard let lastSpace = text.lastIndex(of: " ") else { return text }
        var body = text
        body.replaceSubrange(lastSpace...lastSpace, with: "\u{00A0}")
        return body
    }

    private var plan: some View {
        Panel(title: "Today’s plan") {
            HStack {
                Text("\(completed) of \(store.todaysTasks.count) complete").font(.headline)
                Spacer()
                CoinCount(count: store.journal.coins)
            }
            if !store.todaysTasks.isEmpty {
                Meter(value: Double(completed) / Double(store.todaysTasks.count), tint: GlimmerColor.sage)
                if store.todaysTasks.count > 5 && !typeSize.isAccessibilitySize {
                    ScrollView { taskList }.frame(height: 200)
                } else { taskList }
            }
            Button("Plan my day") { open(.plan) }
                .glimmerButton()
                .controlSize(.large)
        }
        .completionLight(completed > 0 && completed == store.todaysTasks.count, radius: 16)
        .readingArrival(delay: 0.14)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.todaysTasks) { task in
                let done = store.todayCompletion.contains(task.id)
                Button {
                    _ = store.change { $0.toggleTask(task, on: store.day) }
                } label: {
                    HStack(spacing: 2) {
                        Tick(done: done, size: 24).frame(width: 40, height: 44)
                        Text(task.name).multilineTextAlignment(.leading)
                            .foregroundStyle(done ? Color.secondary : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(RowPressStyle())
                .tickFeedback(done)
                .accessibilityValue(done ? "Complete" : "Incomplete")
            }
        }
        // The tick sits in a wider target; pull it out so the mark lines up with the heading.
        .padding(.leading, -8)
    }

    private var space: some View {
        Panel(title: "Make a little space", plain: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 260), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach([Destination.toolkit, .challenges, .habits, .lessons, .cleaning, .seasonal, .settings]
                    .filter { $0 != .seasonal || featuredSeason == nil }) { item in
                    ActionRow(title: item.title, detail: item.detail, icon: item.icon, tint: item.tint) { open(item) }
                }
            }
            .glassGroup(spacing: 10)
        }
    }
}
