import Foundation
import ImageIO

@main
struct CoreChecks {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "LibraryContent/Gallery/Gallery.json")
        try await galleryRefreshChecks(GalleryCatalog.load(directory), posterDirectory: directory.deletingLastPathComponent())
        try await editorialRefreshChecks(resources: directory.deletingLastPathComponent().deletingLastPathComponent())
        try core()
        try glyphChecks(resources: directory.deletingLastPathComponent().deletingLastPathComponent())
        engagementChecks()
        supportReminderChecks()
        inkspringLinkChecks()
        try agentSkillChecks(native: URL(fileURLWithPath: CommandLine.arguments[1]))
        if CommandLine.arguments.contains("--verify-live-editorial") {
            let resources = directory.deletingLastPathComponent().deletingLastPathComponent()
            let catalog = try Catalog.load(from: resources.appending(path: "Catalog.json"))
            let gallery = try GalleryCatalog.load(directory)
            let cache = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cache) }
            let library = EditorialLibrary(bundled: catalog, bundledGallery: gallery, directory: cache)
            await library.refreshIfNeeded()
            check(library.edition?.content.lessons.map(\.id) == catalog.lessons.map(\.id),
                  "Production R2 returns the published curriculum to the native reader")
            let reopened = EditorialLibrary(bundled: catalog, bundledGallery: gallery, directory: cache)
            check(reopened.edition?.content.lessons.count == catalog.lessons.count,
                  "Production edition reopens from the native cache")
            check(reopened.edition?.content.seasonal?.map(\.id) == catalog.seasonal?.map(\.id),
                  "Production seasonal content reopens from the native cache")
            let quoteIDs = catalog.quotes?.map(\.id) ?? []
            check(reopened.edition?.content.quotes?.prefix(quoteIDs.count).map(\.id) == quoteIDs,
                  "Production quotes reopen from the native cache in the published order")
            print("PASS: production R2 edition downloaded, validated, and reopened from cache.")
        }
    }

    /// Every row gets a single-colour symbol, built-in names carry no emoji, and old journals migrate.
    @MainActor
    static func glyphChecks(resources: URL) throws {
        let catalog = try Catalog.load(from: resources.appending(path: "Catalog.json"))
        let isEmoji: (String) -> Bool = { $0.contains(where: Glyph.isEmoji) }
        check(!catalog.activities.contains(where: isEmoji) && !catalog.people.contains(where: isEmoji),
              "Built-in activities and people have no emoji")
        check(catalog.activities.contains("Deep work"), "Deep work reads without its emoji")
        check(Glyph.plainName("💻 Deep work") == "Deep work" && Glyph.plainName("Walk 🚶") == "Walk",
              "Emoji are stripped from either end of a name")
        check(Glyph.plainName("🎉") == "🎉", "A name that is only an emoji is kept")
        check(Glyph.plainName("C++ and Swift") == "C++ and Swift", "Ordinary text is untouched")
        var symbols: [String] = []
        symbols += catalog.sources.map { Glyph.symbol(name: $0, category: "app") }
        symbols += catalog.activities.map { Glyph.symbol(name: $0, category: "activity") }
        symbols += catalog.people.map { Glyph.symbol(name: $0, category: "person") }
        symbols += catalog.library.flatMap { category in
            category.tasks.map { Glyph.symbol(icon: $0.icon, name: $0.name, category: category.id) } }
        symbols += catalog.habits.map { Glyph.symbol(icon: $0.icon, name: $0.name, category: "habit") }
        symbols += catalog.challenges.map { Glyph.symbol(icon: $0.icon, name: $0.title, category: "challenge") }
        symbols += catalog.lessons.flatMap { $0.pages.map { Glyph.symbol(icon: $0.emoji, name: $0.title) } }
        symbols += catalog.challenges.flatMap { $0.opts.map { Glyph.symbol(icon: $0.e, name: $0.l) } }
        let missing = Set(symbols.filter { !Glyph.exists($0) })
        check(missing.isEmpty, "Every built-in row resolves to a real SF Symbol (missing: \(missing.sorted()))")
        check(!symbols.contains(where: isEmoji), "No built-in row resolves to an emoji")
        let lessonPages = catalog.lessons.flatMap(\.pages)
        let unmapped = lessonPages.filter { Glyph.symbol(icon: $0.emoji, name: $0.title) == GlyphMap.fallback }
        check(unmapped.count <= lessonPages.count / 20, "Lesson illustrations map to meaningful symbols (\(unmapped.count) fall back)")
        for source in ["TikTok", "YouTube", "Reddit", "Slack", "Claude", "News"] {
            check(Glyph.symbol(name: source, category: "app") == GlyphMap.names[source.lowercased()], "\(source) has its own glyph")
        }
        check(Glyph.symbol(name: "Practice violin", category: "activity") != GlyphMap.fallback,
              "A typed activity finds a glyph from its words")
        check(Glyph.exists(Glyph.symbol(name: "Zxqv", category: "activity")), "Unknown names fall back to a real symbol")
        check(Glyph.symbol(icon: "drop.fill", name: "Anything") == "drop.fill", "A stored symbol name is kept")
        check(Glyph.symbol(icon: "💧", name: "Anything") == Glyph.symbol(icon: "💧", name: "Other"),
              "A stored emoji icon maps to a fixed symbol")

        var journal = Journal()
        let day = CalendarDay.key(.now)
        journal.moments = [
            Moment(source: "💻 Deep work", kind: "Activity", tags: [], value: 0.8, decision: .same, date: .now, day: day),
            Moment(source: "🦄 My own thing", kind: "Feed", tags: [], value: 0.5, decision: .same, date: .now, day: day),
        ]
        journal.favoriteSources = ["💻 Deep work", "Deep work", "🦄 My own thing"]
        let migrated = journal.droppingBuiltInEmoji()
        check(migrated.moments.map(\.source) == ["Deep work", "🦄 My own thing"],
              "Old built-in moments lose their emoji; names people typed stay as written")
        check(migrated.favoriteSources == ["Deep work", "🦄 My own thing"], "Favourites migrate without duplicates")
    }

    /// The App Store prompt waits for five logged moments and is asked for once.
    static func engagementChecks() {
        var engagement = Engagement()
        engagement.count = 4
        check(!engagement.shouldRequestReview, "No rating prompt before five moments")
        engagement.count = 5
        check(engagement.shouldRequestReview, "Rating prompt is due after five moments")
        engagement.requestedReview = true
        check(!engagement.shouldRequestReview, "Rating prompt is never asked twice")
        var rated = Engagement()
        rated.count = 9
        rated.actions.insert("review")
        check(!rated.shouldRequestReview, "No rating prompt after someone rated from Settings")
    }

    /// Send to Inkspring builds a well-formed inkspring://new-idea link within Inkspring's limits.
    static func inkspringLinkChecks() {
        func query(_ url: URL?) -> [String: String] {
            guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        }
        let url = InkspringLink.newIdea(quote: "Small steps & big leaps = 1+1 #today?", author: "Maya Angelou")
        check(url?.scheme == "inkspring" && url?.host == "new-idea", "Inkspring link uses inkspring://new-idea")
        let raw = url?.absoluteString ?? ""
        check(raw.contains("%2B") && raw.contains("%26") && raw.contains("%3D") && raw.contains("%23")
              && !raw.contains("+") && !raw.contains(" "),
              "Inkspring link percent-encodes plus, ampersand, equals, hash and spaces")
        let fields = query(url)
        check(fields["source"] == "glimmer", "Inkspring link names Glimmer as the source")
        check(fields["text"] == "“Small steps & big leaps = 1+1 #today?”\n— Maya Angelou",
              "Inkspring idea text is the quote and its attribution on its own line")
        check(fields["title"] == "Small steps & big leaps = 1+1 #today?", "A short quote is its own idea title")
        check(raw.contains("%0A"), "The line break before the attribution is kept as %0A")

        let long = String(repeating: "Notice what nourishes you today. ", count: 120)
        let longFields = query(InkspringLink.newIdea(quote: long, author: "Glimmer"))
        check((longFields["text"]?.utf16.count ?? .max) <= InkspringLink.textLimit && longFields["text"]?.hasSuffix("…") == true,
              "Inkspring idea text stays within 2,000 UTF-16 units and ends in an ellipsis")
        let title = longFields["title"] ?? ""
        check(title.utf16.count <= InkspringLink.shortTitleLimit && title.hasSuffix("…") && title.hasPrefix("Notice what nourishes"),
              "A long quote's title is its opening words, cut at a word boundary")
        check(!title.contains("\n"), "The idea title stays on one line")

        let emoji = String(repeating: "🌱", count: 1_500)
        let clipped = InkspringLink.clip(emoji, to: InkspringLink.textLimit)
        check(clipped.utf16.count <= InkspringLink.textLimit && clipped.unicodeScalars.allSatisfy { $0 == "🌱" || $0 == "…" },
              "Clipping never splits an emoji's surrogate pair")
        check(InkspringLink.clip(String(repeating: "a", count: 500), to: InkspringLink.titleLimit).utf16.count <= InkspringLink.titleLimit,
              "Titles stay within 140 UTF-16 units")
        check(InkspringLink.newIdea(title: "Empty", text: "  \n ") == nil, "Blank text builds no link")
        check(query(InkspringLink.newIdea(quote: "Rest is part of the work.", author: "")).keys.sorted() == ["source", "text", "title"],
              "A quote with no author still sends title, text and source")
        print("PASS: Send to Inkspring link building, percent-encoding, attribution and length limits.")
    }

    /// The Mac support card returns weekly until every action is opened or the person picks Don't show again.
    @MainActor
    static func supportReminderChecks() {
        #if os(macOS)
        let suite = "glimmer.checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return check(false, "Support reminder defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        check(!GlimmerSupportReminder.claim(activity: 4, now: start, in: defaults), "Support card waits for five moments")
        check(GlimmerSupportReminder.claim(activity: 5, now: start, in: defaults), "Support card shows after five moments")
        check(!GlimmerSupportReminder.claim(activity: 9, now: start.addingTimeInterval(6 * 86_400), in: defaults),
              "Support card waits a week before returning")
        let nextWeek = start.addingTimeInterval(7 * 86_400)
        for action in GlimmerSupportReminder.Action.allCases.dropLast() {
            check(!GlimmerSupportReminder.record(action, in: defaults), "Opening \(action.rawValue) leaves others unticked")
        }
        check(GlimmerSupportReminder.claim(activity: 9, now: nextWeek, in: defaults),
              "Support card returns while any checkbox is still empty")
        check(GlimmerSupportReminder.record(.apps, in: defaults), "Opening the last action ticks every box")
        check(!GlimmerSupportReminder.claim(activity: 9, now: nextWeek.addingTimeInterval(30 * 86_400), in: defaults),
              "Support card stops once every action has been opened")
        defaults.removeObject(forKey: GlimmerSupportReminder.actionsKey)
        defaults.removeObject(forKey: GlimmerSupportReminder.presentedKey)
        check(GlimmerSupportReminder.claim(activity: 9, now: start, in: defaults), "Later brings the card back")
        GlimmerSupportReminder.dismissForever(in: defaults)
        check(!GlimmerSupportReminder.claim(activity: 9, now: start.addingTimeInterval(60 * 86_400), in: defaults),
              "Don't show again stops the card for good")
        #endif
    }

    static func agentSkillChecks(native: URL) throws {
        let home = URL.temporaryDirectory.appending(path: "skill-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        func text(_ version: String, name: String = "glimmer-mcp") -> String {
            "---\nname: \(name)\nmetadata:\n  version: \"\(version)\"\n---\nbody \(version)"
        }
        func skill(_ version: String = "1.2.0") -> AgentSkillInstaller {
            AgentSkillInstaller(app: "Glimmer", skillID: "glimmer-mcp", instructions: Data(text(version).utf8), home: home)
        }
        try skill("1.1.0").install(.claudeCode)
        check(skill().status(.claudeCode).state == .updateAvailable, "Agent skill offers an update for an older version")
        try skill().install(.claudeCode)
        check(skill().status(.claudeCode).state == .installed, "Agent skill updates to the bundled version")
        try skill("1.10.0").install(.codex, replacing: true)
        check(skill().status(.codex).state == .installed, "Agent skill treats a newer version as installed")
        let gemini = skill().status(.gemini)
        check(gemini.shared, "Codex and Gemini CLI share one agent skill copy")
        let other = AgentSkillInstaller(app: "Other", skillID: "glimmer-mcp", instructions: Data(text("9.0.0", name: "other").utf8), home: home)
        try other.install(.claudeCode, replacing: true)
        check(skill().status(.claudeCode).state == .differentVersion, "Agent skill keeps a different skill unless replacing")
        let bundled = try String(contentsOf: native.appending(path: "Glimmer/AgentSkill.md"), encoding: .utf8)
        check(bundled.hasPrefix("---\nname: glimmer-mcp\n"), "Bundled agent skill is glimmer-mcp")
        check(AgentSkillInstaller.frontMatter(Data(bundled.utf8)).version != nil, "Bundled agent skill has a version")
    }

    @MainActor
    static func editorialRefreshChecks(resources: URL) async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalogURL = resources.appending(path: "Catalog.json")
        let baseline = try Catalog.load(from: catalogURL)
        let media = try GalleryCatalog.load(resources.appending(path: "Gallery/Gallery.json"))
        let library = EditorialLibrary(bundled: baseline, bundledGallery: media, directory: folder)
        var content = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
        var lessons = content["lessons"] as! [[String: Any]]
        lessons[0]["title"] = "Remote title without a new binary"
        content["lessons"] = lessons
        let gallery = try JSONSerialization.jsonObject(with: JSONEncoder().encode(media))
        let document: [String: Any] = ["schemaVersion": 1, "content": content, "gallery": gallery]
        let bytes = try JSONSerialization.data(withJSONObject: document)
        let now = Date()
        let url = EditorialLibrary.endpoint
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                 headerFields: ["Content-Type": "application/json", "ETag": "\"edition-a\""])!
        check(library.edition == nil, "No network is needed to open the bundled catalog")
        await library.refreshIfNeeded(now: now) { request, _ in
            check(request.url == url, "The app reads only the public editorial catalog")
            return (bytes, ok)
        }
        check(library.edition?.content.lessons.first?.title == lessons[0]["title"] as? String,
              "New editorial text is available in the same app session")
        check(library.edition?.gallery == media, "Gallery references ship with the editorial edition")
        let reopened = EditorialLibrary(bundled: baseline, bundledGallery: media, directory: folder)
        check(reopened.edition?.content.lessons.first?.title == lessons[0]["title"] as? String,
              "The offline app opens the last accepted edition")
        let unchanged = HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: nil)!
        await reopened.refreshIfNeeded(now: now) { request, _ in
            check(request.value(forHTTPHeaderField: "If-None-Match") == "\"edition-a\"", "Cache revalidation uses the saved ETag")
            return (Data(), unchanged)
        }
        var bad = document
        lessons[0]["slug"] = "new-id-would-break-progress"
        content["lessons"] = lessons
        bad["content"] = content
        let invalid = try JSONSerialization.data(withJSONObject: bad)
        await reopened.refreshIfNeeded(now: now.addingTimeInterval(1_000)) { _, _ in (invalid, ok) }
        await reopened.refreshIfNeeded(now: now.addingTimeInterval(2_000)) { _, _ in throw URLError(.notConnectedToInternet) }
        check(reopened.edition?.content.lessons.first?.id == baseline.lessons[0].id,
              "Edits that break journal identities and outages preserve the last valid edition")
        print("PASS: remote content updates, media references, ETag, offline relaunch, and stable journal identities.")
    }

    @MainActor
    static func galleryRefreshChecks(_ bundled: GalleryCatalog, posterDirectory: URL) async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let remote = GalleryPlate(id: "new-summer-scene", description: "Sunlit reeds beside the river.", aspectRatio: 2.4, wholeSubject: false,
                                  video: "summer/reeds-abc123.mp4", poster: "summer/reeds-ef4321.jpg")
        let expanded = GalleryCatalog(schemaVersion: 1, plates: [remote] + bundled.plates)
        let library = GalleryLibrary(bundled: bundled, directory: folder)
        let now = Date()
        let bytes = try JSONEncoder().encode(expanded)
        let ok = HTTPURLResponse(url: GalleryCatalog.endpoint, statusCode: 200, httpVersion: nil, headerFields: ["ETag":"\"revision-1\""])!
        check(library.catalog == bundled, "First launch works from bundled posters")
        await library.refreshIfNeeded(now: now) { request, _ in
            check(request.url == GalleryCatalog.endpoint && request.value(forHTTPHeaderField: "If-None-Match") == nil, "First gallery request goes to canonical index")
            return (bytes, ok)
        }
        check(library.catalog.plates.first?.id == remote.id && library.catalog.plates.count == bundled.plates.count + 1, "New remote media appears without an app build")
        let restarted = GalleryLibrary(bundled: bundled, directory: folder)
        check(restarted.catalog == expanded, "Offline restart uses the last validated snapshot")
        await restarted.refreshIfNeeded(now: now.addingTimeInterval(60)) { _,_ in preconditionFailure("Fresh catalog was re-requested") }
        let later = now.addingTimeInterval(7 * 3600)
        await restarted.refreshIfNeeded(now: later) { request, _ in
            check(request.value(forHTTPHeaderField: "If-None-Match") == "\"revision-1\"", "Refresh validates the stored ETag")
            return (Data(), HTTPURLResponse(url: GalleryCatalog.endpoint, statusCode: 304, httpVersion: nil, headerFields: nil)!)
        }
        let after304 = GalleryLibrary(bundled: bundled, directory: folder)
        check(after304.catalog == expanded, "304 preserves the complete cached catalog")
        await after304.refreshIfNeeded(now: later.addingTimeInterval(7 * 3600)) { _,_ in (Data("{}".utf8), ok) }
        check(after304.catalog == expanded, "Invalid responses preserve the working catalog")
        await after304.refreshIfNeeded(now: later.addingTimeInterval(8 * 3600)) { _,_ in throw URLError(.notConnectedToInternet) }
        check(after304.catalog == expanded, "Disconnected devices retain their remote collection")
        let animal = GalleryPlate(id: "full-subject", description: "A rabbit in a meadow.", aspectRatio: 1.0,
                                  wholeSubject: true, video: "new/rabbit.mp4", poster: "new/rabbit.jpg")
        let wildlife = GalleryCatalog(schemaVersion: 1, plates: [animal])
        check(wildlife.pick(slot: 0, date: now, aspect: 8, featured: true)?.id == animal.id, "A new themed collection still presents a full subject in a wide slot")
        let ids = Set(bundled.plates.map(\.id))
        let missing = GalleryPlate(id: "unseen", description: "New image", aspectRatio: 1, wholeSubject: nil, video: nil, poster: nil)
        check((try? GalleryCatalog(schemaVersion: 1, plates: [missing]).validate(bundledIDs: ids)) == nil, "New IDs require an available poster")
        check((try? GalleryCatalog(schemaVersion: 1, plates: [remote, remote]).validate(bundledIDs: ids)) == nil, "Duplicate IDs rejected")
        for bad in ["https://invalid.example/clip.mp4", "//invalid.example/clip.mp4", "../clip.mp4", "v1/../clip.mp4",
                    "v1/%2e%2e/x.mp4", "v1/%2Ffilm.mp4", "v1/file.mp4?secret", "C:\\file.mp4", "/root.mp4", "v1/file.mov"] {
            check(GalleryCatalog.asset(bad, extensions: ["mp4"]) == nil, "Invalid remote path rejected: \(bad)")
        }
        let address = GalleryCatalog.endpoint.deletingLastPathComponent().appending(path: "summer/reeds-abc123.mp4")
        check(remote.filmURL == address, "New subdirectories resolve under the canonical base")
        let posterFolder = folder.appending(path: "posters")
        let original = try Data(contentsOf: posterDirectory.appending(path: bundled.plates[0].id + ".jpg"))
        let posterURL = remote.posterURL!
        let onlineCache = GalleryPosters(directory: posterFolder) { request, limit in
            check(request.url == posterURL && limit >= original.count, "Only the remote plate's JPEG is requested")
            return (original, HTTPURLResponse(url: posterURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let fetched = await onlineCache.image(for: posterURL)
        check(fetched != nil, "A previously unknown remote poster decodes as a JPEG")
        let offlineCache = GalleryPosters(directory: posterFolder) { _,_ in throw URLError(.notConnectedToInternet) }
        let cached = await offlineCache.image(for: posterURL)
        check(cached?.width == fetched?.width, "New remote posters remain available across an offline relaunch")
        print("PASS: gallery discovery, conditional refresh, atomic cache, offline fallback, new remote posters and path validation.")
    }

    static func checkJourneyStages(_ catalog: Catalog) {
        check(JourneyStage.level(days: 0) == 1 && JourneyStage.level(days: 13) == 1 && JourneyStage.level(days: 14) == 2
              && JourneyStage.level(days: 30) == 3 && JourneyStage.level(days: 60) == 4 && JourneyStage.level(days: 500) == 5,
              "Journey stages follow the reader rank thresholds")
        let challengeStages = catalog.challenges.map(\.stage)
        let practiceStages = catalog.practiceTopics.flatMap(\.exercises).map(\.stage)
        check(Set(challengeStages) == Set(1...5) && Set(practiceStages) == Set(1...5), "Every stage has challenges and practices")
        check(challengeStages == challengeStages.sorted(), "Challenges are listed from first stage to last")
        let coins = (1...5).map { stage in catalog.challenges.filter { $0.stage == stage }.map(\.coins).max() ?? 0 }
        check(coins == coins.sorted() && coins[4] <= 40, "Challenge rewards stay modest so small wins never look second-class")
        for topic in catalog.practiceTopics {
            check(topic.exercises.first?.stage == 1, "Topic \(topic.id) starts with an opening practice")
        }
        let start = PracticeDate.parse("2026-11-23")!
        for level in 1...5 {
            let days = (0..<120).compactMap { PracticeDate.calendar.date(byAdding: .day, value: $0, to: start) }
            let picks = days.compactMap { catalog.dailyPractice(on: $0, level: level)?.practice }
            check(picks.count == days.count && picks.allSatisfy { $0.stage <= level }, "Daily practice stays open at stage \(level)")
            if level > 1 {
                check(picks.filter { $0.stage >= level - 1 }.count * 2 > picks.count, "Daily practice favors stage \(level) content")
            }
            let reflections = days.compactMap { catalog.dailyReflection(on: $0, level: level) }
            check(reflections.allSatisfy { $0.stage <= level }, "Daily reflection stays open at stage \(level)")
        }
        var fresh = Journal()
        check(catalog.nextChallenge(for: fresh, level: 1)?.id == "pad", "A new journal starts with the first tiny win")
        for challenge in catalog.challenges where challenge.stage == 1 { fresh.challenges[challenge.id] = ChallengeRecord(choice: "Done", date: start) }
        check(catalog.nextChallenge(for: fresh, level: 1) == nil && catalog.nextChallenge(for: fresh, level: 2)?.stage == 2, "Finished stages hand off to the next open stage")
        check(catalog.nextChallenge(for: Journal(), level: 3)?.stage == 3, "The next challenge meets the person at their stage")
        var tired = Journal()
        for offset in 0..<70 { tired.readerDays = (tired.readerDays ?? []).union([PracticeDate.key(PracticeDate.calendar.date(byAdding: .day, value: -offset, to: start)!)]) }
        check(tired.journeyLevel(asOf: start) == 4 && tired.guidanceLevel(asOf: start) == 4, "Seventy active days reach the fourth stage")
        tired.energy[CalendarDay.key(start)] = EnergyCheck(level: "low", value: 0.25)
        check(tired.guidanceLevel(asOf: start) == 2 && tired.journeyLevel(asOf: start) == 4, "A low-energy day brings suggestions back to gentle ground without losing progress")
        check(catalog.suggestions(level: 4, goals: ["rest"]).contains { suggestion in
            catalog.practiceTopics.flatMap(\.exercises).contains { $0.suggestion == suggestion && $0.stage >= 3 } }, "Coach suggestions include practices from the person's stage")
    }

    static func checkReaderRanks(catalog: Catalog) throws {
        let day = PracticeDate.parse("2025-01-01")!
        func date(_ offset: Int) -> Date { PracticeDate.calendar.date(byAdding: .day, value: offset, to: day)! }
        let cutoff = date(200)
        var reader = Journal()
        reader.started = date(-1_000)
        reader.award(40, key: "welcome")
        reader.lessons["retired-lesson"] = LessonRecord(completed: true)
        for lesson in catalog.lessons { reader.lessons[lesson.id] = LessonRecord(completed: true) }
        func progress(_ journal: Journal) -> ReaderProgress { ReaderProgress(journal: journal, catalog: catalog, asOf: cutoff) }
        let legacy = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(reader))
        check(progress(legacy).completed == 90 && progress(legacy).days == 0 && progress(legacy).rank == .fledgling,
              "Undated legacy lessons count as lessons only; rewards and account age earn no practice days")
        let boundaries: [Int: ReaderRank] = [0:.fledgling, 13:.fledgling, 14:.seeker, 29:.seeker, 30:.scholar,
                                              59:.scholar, 60:.sage, 89:.sage, 90:.guru]
        for count in 0...90 {
            if let expected = boundaries[count] { check(progress(reader).rank == expected, "Rank after \(count) distinct days, including days apart") }
            if count < 90 { reader.moods[PracticeDate.key(date(2 * count))] = 3 }
        }
        // Guru stays tied to the first 90 lessons, so the Deep Path never moves the goal.
        let deepPath = catalog.lessons.last!
        reader.lessons[deepPath.id] = nil
        check(progress(reader).rank == .guru, "Unread Deep Path lessons don't hold back Guru")
        let last = catalog.lessons.first { $0.number == ReaderProgress.curriculumLength }!
        reader.lessons[last.id] = nil
        check(progress(reader).rank == .sage && progress(reader).remaining(until: .guru) == "1 more lesson to unlock Guru.", "Guru checks both requirements")
        reader.completeLesson(last, on: date(178))
        check(progress(reader).days == 90 && progress(reader).rank == .guru && reader.readerDays == [PracticeDate.key(date(178))], "Completing the final lesson on an existing practice day unlocks Guru")
        var mixed = Journal()
        let key = PracticeDate.key(day)
        mixed.completions[key] = ["task"]
        mixed.completions[PracticeDate.key(date(5))] = []
        mixed.moments = [Moment(source: "Walking", kind: "Activity", tags: [], value: 0.5, decision: .same, date: day, day: key)]
        mixed.energy[key] = EnergyCheck(level: "Good", value: 0.6)
        mixed.habits["read"] = [key, PracticeDate.key(date(2))]
        mixed.challenges["one"] = ChallengeRecord(choice: "Try", date: day)
        mixed.cleaningLast["desk"] = key
        mixed.experiment = Experiment(suggestion: Suggestion(type: "Try", title: "read", sub: ""), start: day)
        mixed.experiment?.checkins[key] = .held
        mixed.moods["2025-02-31"] = 2
        mixed.moods[PracticeDate.key(date(201))] = 2
        mixed.preserveReaderDays(asOf: cutoff)
        check(mixed.readerDays == [key, PracticeDate.key(date(2))], "Practice sources deduplicate across days and discard impossible or future keys")
        mixed.habits.removeAll()
        check(progress(mixed).days == 2, "Earned practice dates survive housekeeping of detail records")
        let first = UUID(), second = UUID()
        var a = try JournalReplica(seed: mixed, device: first)
        var b = a
        var phone = mixed
        phone.readerDays?.insert(PracticeDate.key(date(3)))
        try a.observe(from: mixed, to: phone, device: first)
        var mac = mixed
        mac.readerDays?.insert(PracticeDate.key(date(4)))
        try b.observe(from: mixed, to: mac, device: second)
        a.merge(b)
        let data = try JSONEncoder().encode(a)
        let replica = try JSONDecoder().decode(JournalReplica.self, from: data)
        let merged = try replica.materialize(keepingEngagement: .init())
        check(progress(merged).days == 4, "Independent practice dates survive replica merging and snapshot persistence")
        struct LegacyWire: Decodable { let entries: [JournalReplica.Key: JournalReplica.Entry] }
        let wire = try JSONDecoder().decode(LegacyWire.self, from: data)
        check(wire.entries.keys.allSatisfy { $0.path.first != "readerDays" }, "Older replicas can decode all familiar journal fields")
        print("PASS: Fledgling through Guru, dated and undated journal migration, missed days, deduplication, and offline date merging.")
    }

    @MainActor
    static func core() throws {
        try checkPersonalTodos()
        try checkToolkit()
        checkCoachPrompts()
        checkCheckOffRewards()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resources = root.appending(path: "LibraryContent")
        let catalogURL = resources.appending(path: "Catalog.json")
        let catalog = try Catalog.load(from: catalogURL)
        try checkSeasonal(catalog)
        checkQuotes(catalog)
        check(catalog.onboarding.count == 14, "Original onboarding")
        check(catalog.lessons.count >= 120 && catalog.lessons.map(\.number) == Array(1...catalog.lessons.count)
              && catalog.lessons.allSatisfy { !$0.pages.isEmpty && $0.pages.last?.kind == "takeaway" && $0.pages.last?.tryToday != nil }, "Complete lesson catalog with the Deep Path")
        check(Array(catalog.challenges.prefix(4).map(\.id)) == ["pad", "patch", "sweep", "coffee"] && catalog.challenges.allSatisfy { !$0.teach.isEmpty && $0.opts.count >= 2 }, "Original challenges first, every challenge complete")
        checkJourneyStages(catalog)
        let practices = catalog.practiceTopics.flatMap(\.exercises)
        check(practices.count == Set(practices.map(\.id)).count && practices.count >= 8, "Distinct life coaching exercises")
        let referenceDay = PracticeDate.parse("2026-11-23")!
        let reflectionIDs = Set((0..<(12 * (catalog.reflectionTopic?.exercises.count ?? 0))).compactMap { offset in
            PracticeDate.calendar.date(byAdding: .day, value: offset, to: referenceDay)
                .flatMap { catalog.dailyReflection(on: $0)?.id }
        })
        check(reflectionIDs == Set(catalog.reflectionTopic?.exercises.map(\.id) ?? []) && reflectionIDs.contains("would-you-do-it-offline"), "Daily reflections cover every practice, including the online fads reflection")
        try checkReaderRanks(catalog: catalog)
        let goalStep = catalog.onboarding.first { $0.key == "primary_goal" }!
        let goalIDs = goalStep.options!.map(\.v)
        let allGoals = goalIDs.reduce([String]()) { goalStep.toggling($1, in: $0) }
        check(allGoals == goalIDs && goalStep.toggling(goalIDs[0], in: allGoals) == Array(goalIDs.dropFirst()), "Any number of goals can be selected and deselected")
        let mixed = catalog.startingSuggestions(["primary_goal": allGoals])
        for topic in catalog.practiceTopics where goalIDs.contains(topic.id) {
            check(mixed.contains(topic.exercises[0].suggestion), "Personalization includes selected topics")
        }
        for goal in ["work_growth", "learn_build"] {
            let suggestions = catalog.startingSuggestions(["primary_goal": [goal]])
            check(suggestions.first == catalog.practiceTopics.first(where: { $0.id == goal })?.exercises.first?.suggestion, "Goal selects its practice exercises")
        }
        let directory = resources.appending(path: "Gallery")
        let gallery = try GalleryCatalog.load(directory.appending(path: "Gallery.json"))
        let plates = gallery.plates
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        check(files.allSatisfy { ["json","jpg"].contains($0.pathExtension.lowercased()) }, "Only posters and their manifest ship in the gallery")
        let videos = plates.compactMap(\.video)
        check(!videos.isEmpty && Set(videos).count == videos.count, "Different remote films are available for the daily feature")
        try gallery.validate(bundledIDs: Set(plates.map(\.id)))
        check(!plates.isEmpty && Set(plates.map(\.id)).count == plates.count, "Gallery covers the full rotation")
        check(plates.allSatisfy { !$0.description.isEmpty && $0.aspectRatio > 0 }, "Gallery includes descriptions and proportions")
        for plate in plates {
            let url = directory.appending(path: plate.id + ".jpg")
            guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let poster = CGImageSourceCreateImageAtIndex(image, 0, nil)
            else { fatalError("Missing gallery poster: \(plate.id)") }
            check(abs(Double(poster.width) / Double(poster.height) - plate.aspectRatio) < 0.001, "Catalog uses actual image dimensions")
            if let video = plate.video {
                check(plate.filmURL == GalleryCatalog.endpoint.deletingLastPathComponent().appending(path: video), "Film URL uses the configured location")
            } else {
                check(plate.filmURL == nil, "Still photographs never request video")
            }
        }
        let veryWide = (0..<plates.count).compactMap { gallery.pick(slot: $0, date: referenceDay, aspect: 8) }
        check(!veryWide.isEmpty && veryWide.allSatisfy { $0.wholeSubject != true }, "Narrow strips avoid cropping people and animals")
        let followingDay = Calendar.current.date(byAdding: .day, value: 1, to: referenceDay)!
        for aspect in [1.0, 1.5, 2.5, 6.0] {
            let first = gallery.pick(slot: 1, date: referenceDay, aspect: aspect)
            let second = gallery.pick(slot: 1, date: followingDay, aspect: aspect)
            check(first != nil && first?.id != second?.id, "Artwork rotates across days")
            check(second?.id == gallery.pick(slot: 2, date: referenceDay, aspect: aspect)?.id,
                  "Adjacent cards show distinct stable choices")
        }

        for aspect in [1.0, 1.5, 2.5, 6.0] {
            let weekly = (0..<7).compactMap { index -> GalleryPlate? in
                let date = Calendar.current.date(byAdding: .day, value: index, to: referenceDay)!
                return gallery.pick(slot: 0, date: date, aspect: aspect, featured: true)
            }
            check(weekly.count == 7 && weekly.allSatisfy { $0.video != nil }, "Today offers a real motion scene on every day")
            check(Set(weekly.map(\.id)).count > 1, "Featured motion rotates between distinct scenes")
            let regular = (0..<plates.count).compactMap { gallery.pick(slot: $0, date: referenceDay, aspect: aspect) }
            check(regular.filter { $0.video == nil }.count > regular.count / 2, "Regular gallery slots are primarily still photographs")
        }

        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let today = CalendarDay.key(now)
        let testDirectory = URL.temporaryDirectory.appending(path: "glimmer-core-" + UUID().uuidString)
        let journalURL = testDirectory.appending(path: "journal.json")
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let store = JournalStore(url: journalURL, catalogURL: catalogURL)
        store.start(name: " Sample ")
        check(store.journal.name == "Sample" && store.journal.coins == 40, "Onboarding persisted")
        let task = store.journal.tasks[0]
        check(task.occurs(on: now) && task.occurs(on: tomorrow) && !task.occurs(on: yesterday), "Daily task recurrence")
        var alternate = task
        alternate.every = 2
        check(!alternate.occurs(on: tomorrow), "Repeat interval")
        alternate.repeats = false
        check(!alternate.occurs(on: tomorrow), "One-time task recurrence")
        var weekly = task
        weekly.cadence = .weekly
        weekly.weekdays = [calendar.component(.weekday, from: tomorrow)]
        check(!weekly.occurs(on: now) && weekly.occurs(on: tomorrow), "Selected weekdays")

        store.change { $0.toggleTask(task, on: now) }
        check(store.journal.coins == 45 && store.todayCompletion.contains(task.id), "Task reward")
        store.change { $0.toggleTask(task, on: now) }
        check(store.journal.coins == 40 && !store.todayCompletion.contains(task.id), "Undo removes reward")
        let log = Moment(source: "Sample", kind: "Feed", tags: ["Learning"], value: 0.8,
                         decision: .more, date: now, day: today)
        let drain = Moment(source: "Other", kind: "Feed", tags: [], value: 0,
                           decision: .less, date: now, day: today)
        store.change {
            $0.record(log)
            $0.record(log)
            $0.record(drain)
            $0.recordEnergy(.init(level: "mid", value: 0.5), on: now)
            $0.recordEnergy(.init(level: "high", value: 0.8), on: now)
        }
        check(store.journal.coins == 55 && store.journal.moments.count == 2, "Reward only once per day")
        check(store.journal.engagement.count == 2 && !store.journal.engagement.shouldRequestReview, "Successful saves count once")
        let summary = ReflectionSummary(store.journal.moments, day: now, days: 14)
        check(summary.alignment == 50 && summary.best.first?.name == "Sample" && summary.rough.first?.name == "Other",
              "Grounded insight scores and groups")
        check(ReflectionSummary([], day: now, days: 7).alignment == nil, "No demo values in an empty journal")

        let flat = (0..<5).map { offset in
            var item = log
            item.date = calendar.date(byAdding: .day, value: -offset, to: now)!
            item.day = CalendarDay.key(item.date)
            return item
        }
        let steady = ReflectionSummary(flat, day: now, days: 14)
        check(!summary.hasHistory, "One day's entries cannot form a history")
        check(steady.hasHistory, "Enough logs form a history even when every rating is the same")

        let lesson = catalog.lessons[0]
        check(!store.journal.lessonIsOpen(2, on: now) && store.journal.lessonIsOpen(2, on: tomorrow), "Daily unlock")
        store.change {
            $0.completeLesson(lesson, on: now)
            $0.completeLesson(lesson, on: now)
            $0.completeChallenge(catalog.challenges[0], choice: "Sample", on: now)
            $0.completeChallenge(catalog.challenges[0], choice: "Sample", on: now)
        }
        check(store.journal.coins == 90 && store.journal.coffeeUnlocked, "One-time lesson and challenge rewards")
        let suggestion = catalog.startingSuggestions(["distraction": ["short_video"]])[0]
        store.startOrQueue(suggestion)
        store.change { $0.checkIn(.held, on: now); $0.checkIn(.slip, on: now) }
        check(store.journal.experiment?.checkins.count == 1, "One experiment check-in per calendar day")
        for offset in 1...6 {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            store.change { $0.checkIn(.held, on: date) }
        }
        check(store.journal.experiment?.readyToReview == true, "Experiment review gate")
        store.change { $0.reviewExperiment(.keep, on: now); $0.reviewExperiment(.keep, on: now) }
        check(store.journal.experiment == nil && store.journal.history.count == 1 && store.journal.coins == 150, "Experiment reward")
        var engagement = Engagement(count: 5)
        check(engagement.shouldRequestReview, "Review becomes eligible at milestone")
        engagement.actions.insert("review")
        check(!engagement.shouldRequestReview, "Manual review link suppresses automatic request")
        engagement.actions.removeAll()
        engagement.requestedReview = true
        check(!engagement.shouldRequestReview, "Automatic review only once")

        let relaunched = JournalStore(url: journalURL, catalogURL: catalogURL)
        check(relaunched.journal.moments.count == 2 && relaunched.journal.coins == 150, "Relaunch persistence")
        let exportURL = testDirectory.appending(path: "export.json")
        try store.export().write(to: exportURL)
        let restored = try relaunched.readBackup(exportURL)
        check(restored.moments == relaunched.journal.moments && restored.lessons[lesson.id]?.completed == true, "Backup round trip")
        try Data("broken".utf8).write(to: journalURL)
        let broken = JournalStore(url: journalURL, catalogURL: catalogURL)
        check(broken.loadError != nil && !broken.change { $0.name = "Overwrite" }, "Corrupt file is preserved")
        try checkSync(in: testDirectory, catalog: catalog, now: now, tomorrow: tomorrow)
        try checkAgentAccess(in: testDirectory, catalog: catalog, catalogURL: catalogURL)
        print("PASS: catalog, recurring tasks, rewards, insight math, unlocks, experiment review, review eligibility, persistence, backup, sync and agent access.")
    }

    @MainActor
    private static func checkSeasonal(_ catalog: Catalog) throws {
        let season = catalog.seasonal!.first!
        let list = season.checklists[0]
        let november = PracticeDate.parse("2026-11-15")!
        let january = PracticeDate.parse("2027-01-07")!
        let later = PracticeDate.parse("2027-01-08")!
        let nextSeason = PracticeDate.parse("2027-11-15")!
        let key = season.progressKey(for: list, on: november)
        check(season.isFeatured(on: november) && season.isFeatured(on: january) && !season.isFeatured(on: later),
              "Seasonal promotion starts and ends on the local calendar dates across New Year")
        let nextDay = PracticeDate.parse("2026-11-16")!
        check(season.recommendation(on: november)?.item.id == list.items.first?.id
              && season.recommendation(on: nextDay)?.item.id == list.items.dropFirst().first?.id
              && season.recommendation(on: january) != nil
              && season.recommendation(on: later) == nil,
              "Today offers a single rotating checklist action inside the seasonal window")
        check(season.progressKey(for: list, on: january) == key && season.progressKey(for: list, on: later) == key
              && season.progressKey(for: list, on: nextSeason) != key, "A holiday checklist persists through New Year")
        check(Set(season.maintenance).isSubset(of: Set((catalog.cleaning.maintenance ?? []).map(\.id))),
              "Seasonal upkeep references the same chores as Cleaning & maintenance")
        let phone = UUID(), mac = UUID()
        let empty = Journal()
        var phoneJournal = empty
        phoneJournal.toggleSeasonalCheck(list.items[0].id, in: key)
        var macJournal = empty
        macJournal.toggleSeasonalCheck(list.items[1].id, in: key)
        let saved = try JournalStore.decode(JSONEncoder().encode(phoneJournal))
        check(saved.seasonalChecks == phoneJournal.seasonalChecks, "Checklist progress survives reopening a saved journal")
        var phoneCopy = try JournalReplica(seed: phoneJournal, device: phone)
        let macCopy = try JournalReplica(seed: macJournal, device: mac)
        phoneCopy.merge(macCopy)
        let wire = try JSONEncoder().encode(phoneCopy)
        let merged = try JSONDecoder().decode(JournalReplica.self, from: wire).materialize(keepingEngagement: .init())
        check(merged.seasonalChecks?[key] == Set(list.items.prefix(2).map(\.id)),
              "Independent devices preserve both checked items")
        var previousWire = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
        previousWire.removeValue(forKey: "seasonalEntries")
        let oldReader = try JSONDecoder().decode(JournalReplica.self, from: JSONSerialization.data(withJSONObject: previousWire))
        let oldJournal = try oldReader.materialize(keepingEngagement: .init())
        check(oldJournal.seasonalChecks == nil, "Older replicas can read the original journal fields")
    }

    private static func checkQuotes(_ catalog: Catalog) {
        let quotes = catalog.quotes ?? []
        let start = PracticeDate.parse("2026-11-23")!
        check(quotes.count >= 180 && Set(quotes.map(\.id)).count == quotes.count
              && Set(quotes.map(\.text)).count == quotes.count, "The launch rotation contains 180 distinct quotes")
        check(quotes.allSatisfy { !$0.text.contains("://") && !$0.author.contains("://") },
              "Display quotes contain text and attribution without URLs")
        let calendar = PracticeDate.calendar
        let scheduled = (0..<quotes.count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start).flatMap { DailyQuote.quote(on: $0, from: quotes)?.id }
        }
        check(scheduled == quotes.map(\.id), "One quote advances per local calendar day in catalog order")
        let cycleEnd = calendar.date(byAdding: .day, value: quotes.count, to: start)!
        check(DailyQuote.quote(on: cycleEnd, from: quotes)?.id == quotes.first?.id,
              "Quote rotation starts over only after every entry")
    }

    private static func checkCoachPrompts() {
        let texts = CoachPrompts.pool.map(\.text)
        check(Set(texts).count == texts.count && texts.count >= 40, "Coach has at least 40 unique suggested prompts")
        // Spelled out so the banned label never appears in source or copy.
        let banned = [["a", "d", "h", "d"].joined(), "attention journal"]
        check(!texts.contains { text in banned.contains { text.lowercased().contains($0) } }, "Coach prompts avoid banned wording")
        check(CoachPrompts.fixed.allSatisfy { CoachPrompts.pool.contains($0) }, "The fixed test prompts are in the pool")
        check(CoachPrompts.pool.allSatisfy { CoachPrompts.category(for: $0.text) == $0.category },
              "Every pooled prompt routes to its own category in the practice guide")
        let typed: [(String, CoachPrompt.Category)] = [
            ("I'm so tired today", .rest), ("Can you suggest a lesson?", .read), ("I feel stuck at work", .kindness),
            ("I want some quiet", .stillness), ("Help me plan my morning", .focus), ("Any pattern in my moments?", .reflect),
        ]
        check(typed.allSatisfy { CoachPrompts.category(for: $0.0) == $0.1 }, "Typed questions route to a sensible guide category")
        var previous = Set<String>()
        var overlaps = 0, mixed = true
        for _ in 0..<500 {
            let set = CoachPrompts.draw(excluding: previous)
            if set.count != 3 || Set(set.map(\.category)).count != 3 { mixed = false }
            if !previous.isDisjoint(with: set.map(\.text)) { overlaps += 1 }
            previous = Set(set.map(\.text))
        }
        check(mixed && overlaps == 0, "Coach shows three prompts from three categories with no repeat from the last set")
    }

    private static func checkCheckOffRewards() {
        var journal = Journal()
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let before = journal.coins
        journal.toggleHabit("water", on: day)
        let afterHabit = journal.coins
        journal.toggleHabit("water", on: day)
        check(afterHabit > before && journal.coins == before && journal.habits["water"]?.isEmpty != false,
              "Checking off a habit earns coins once; unchecking takes them back")
        let todo = PersonalTodo(title: "Call the bank")
        journal.personalTodos = [todo]
        let found = journal.setPersonalTodo(todo.id, done: true)
        let afterTodo = journal.coins
        _ = journal.setPersonalTodo(todo.id, done: true)
        let again = journal.coins
        _ = journal.setPersonalTodo(todo.id, done: false)
        check(found && afterTodo > before && again == afterTodo && journal.coins == before && !journal.setPersonalTodo(UUID(), done: true),
              "Finishing a personal to-do earns coins once; reopening takes them back")
    }

    private static func checkToolkit() throws {
        // Steps and estimates: model, validation, sync and old-peer safety.
        let todo = PersonalTodo(title: "Write the quarterly report", dueDay: PracticeDate.key(.now))
        var journal = Journal()
        journal.personalTodos = [todo]
        journal.replaceSteps(for: todo.id, with: ["Open a blank page", "List three points", "  ", "Write it"])
        let first = journal.steps(for: todo.id)
        check(first.map(\.title) == ["Open a blank page", "List three points", "Write it"], "Breakdowns drop blank steps and keep order")
        journal.setStepDone(first[0].id, done: true)
        journal.replaceSteps(for: todo.id, parent: first[1].id, with: ["Point one", "Point two"])
        check(journal.flatSteps(for: todo.id).map(\.title) == ["Open a blank page", "List three points", "Point one", "Point two", "Write it"],
              "Smaller steps sit under their parent step")
        check(journal.nextStep(for: todo.id)?.title == "Point one", "One thing starts with the first unfinished smaller step")
        let points = journal.steps(for: todo.id, parent: first[1].id)
        journal.setStepDone(points[0].id, done: true)
        journal.setStepDone(points[1].id, done: true)
        check(journal.steps(for: todo.id)[1].done && journal.nextStep(for: todo.id)?.title == "Write it",
              "Finishing the last smaller step finishes its step")
        check(journal.nextStep(for: todo.id, skipping: [first[2].id]) == nil, "Skipped steps are passed over")
        journal.setStepDone(first[1].id, done: false)
        journal.replaceSteps(for: todo.id, with: ["Open a blank page", "Write it", "Share it"])
        check(journal.steps(for: todo.id).first?.done == true && journal.steps(for: todo.id).count == 3,
              "Rebreaking keeps finished steps with unchanged text")
        check(!(journal.todoSteps ?? []).contains { $0.title == "Point one" }, "Removing a step removes its smaller steps")
        journal.setEstimate(25, source: ToolkitSource.device.rawValue, for: todo.id)
        journal.setEstimate(30, source: ToolkitSource.person.rawValue, for: todo.id)
        check(journal.todoEstimates?.count == 1 && journal.estimate(for: todo.id)?.minutes == 30, "One estimate per to-do")
        let restored = try JournalStore.decode(JSONEncoder().encode(journal))
        check(restored.todoSteps == journal.todoSteps && restored.todoEstimates == journal.todoEstimates, "Steps and estimates survive backup and restore")
        var oldBackup = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as! [String: Any]
        oldBackup.removeValue(forKey: "todoSteps")
        oldBackup.removeValue(forKey: "todoEstimates")
        let old = try JournalStore.decode(JSONSerialization.data(withJSONObject: oldBackup))
        check(old.todoSteps == nil && old.personalTodos?.count == 1, "Backups from before the Toolkit still restore")
        var invalid = journal
        invalid.todoEstimates = [TodoEstimate(id: todo.id, minutes: 0, source: "device")]
        check((try? JournalStore.decode(JSONEncoder().encode(invalid))) == nil, "Invalid estimates are rejected on restore")

        // Two devices edit different steps of the same to-do offline; both edits survive.
        let phone = UUID(), mac = UUID()
        var phoneReplica = try JournalReplica(seed: journal, device: phone)
        var macReplica = phoneReplica
        let steps = journal.steps(for: todo.id)
        var onPhone = journal
        onPhone.setStepDone(steps[1].id, done: true)
        try phoneReplica.observe(from: journal, to: onPhone, device: phone)
        var onMac = journal
        onMac.replaceSteps(for: todo.id, parent: steps[2].id, with: ["Find the shared folder"])
        onMac.setEstimate(45, source: "agent", for: todo.id)
        try macReplica.observe(from: journal, to: onMac, device: mac)
        phoneReplica.merge(macReplica)
        let merged = try phoneReplica.materialize(keepingEngagement: Engagement())
        check(merged.steps(for: todo.id)[1].done && merged.steps(for: todo.id, parent: steps[2].id).count == 1
              && merged.estimate(for: todo.id)?.minutes == 45, "Concurrent step edits on two devices merge")
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(phoneReplica)) as! [String: Any]
        check(wire["toolkitEntries"] != nil && !((wire["entries"] as? [Any])?.description.contains("todoSteps") ?? false),
              "Toolkit records live in their own replica extension for older peers")
        var legacy = wire
        legacy.removeValue(forKey: "toolkitEntries")
        let legacyReplica = try JSONDecoder().decode(JournalReplica.self, from: JSONSerialization.data(withJSONObject: legacy))
        phoneReplica.merge(legacyReplica)
        let afterLegacy = try phoneReplica.materialize(keepingEngagement: Engagement())
        check(afterLegacy.todoSteps?.count == merged.todoSteps?.count,
              "Older peers that omit the extension cannot erase steps")
        var removed = merged
        removed.removePersonalTodo(todo.id)
        check(removed.todoSteps?.isEmpty == true && removed.todoEstimates?.isEmpty == true, "Deleting a to-do deletes its steps and estimate")

        // Offline guide.
        for size in StepSize.allCases {
            let plan = OfflineToolkit.breakDown("Reply to Sam's email", size: size)
            check(plan.count >= 3 && plan.count <= 10 && Set(plan).count == plan.count, "Offline breakdown at \(size.title) has 3 to 10 steps")
        }
        check(OfflineToolkit.breakDown("Pay the water bill", size: .tinySteps).count > OfflineToolkit.breakDown("Pay the water bill", size: .bigStrides).count,
              "Tiny steps give more steps than big strides")
        check(OfflineToolkit.breakDown("Sort the garage", size: .balanced).first?.contains("Sort the garage") == true,
              "Generic breakdowns name the task")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let dump = """
        ugh so much to do
        - email Priya about the venue tomorrow
        I need to buy cat food, pay the electric bill by Friday and then call the dentist
        also tidy the desk; email Priya about the venue tomorrow
        """
        let items = OfflineToolkit.unload(dump, today: monday, calendar: calendar)
        check(items.map(\.title) == ["Email Priya about the venue", "Buy cat food", "Pay the electric bill", "Call the dentist", "Tidy the desk"],
              "Unload splits a brain dump into to-dos, drops filler and duplicates")
        let messy = OfflineToolkit.unload("ugh need to email Sam about friday\nalso dentist?? and coffee filters\nand start that report",
                                          today: monday, calendar: calendar)
        check(messy.map(\.title) == ["Email Sam about friday", "Dentist", "Coffee filters", "Start that report"] && messy[0].dueDay == nil,
              "Unload keeps actions after a sigh and splits at question marks")
        check(items[0].dueDay == "2026-11-24" && items[2].dueDay == "2026-11-27" && items[1].dueDay == nil, "Unload finds due days")
        check(OfflineToolkit.estimate("Reply to an email", focus: .clear) == 10
              && OfflineToolkit.estimate("Reply to an email", focus: .scattered) == 15
              && OfflineToolkit.estimate("Something new", steps: 8, focus: .clear) == 50, "Time check adjusts for focus and steps")
        check(ToolkitClean.lines(["1. Open the laptop", "- Open the laptop", "", "• Start"]) == ["Open the laptop", "Start"],
              "Model and agent lists are cleaned before saving")
        check(OfflineToolkit.reword("I just wanted to say I really think it's done.", tone: .shorter) == "I wanted to say it's done."
              && OfflineToolkit.reword("One. Two.", tone: .bullets) == "• One\n• Two"
              && OfflineToolkit.reword("Hi", tone: .kinder) == nil, "Offline Reword offers only Shorter and Bullet points")
        let urgent = OfflineToolkit.readTone("I need this ASAP. Thanks!", received: true)?.tones.map(\.tone) ?? []
        let curt = OfflineToolkit.readTone("ok.", received: true)?.tones.map(\.tone) ?? []
        let plain = OfflineToolkit.readTone("The meeting moved to 3pm", received: false)?.tones.map(\.tone) ?? []
        check(urgent.contains("Emphatic") && urgent.contains("Urgent") && urgent.contains("Warm")
              && curt == ["Brief"] && plain == ["Neutral"]
              && OfflineToolkit.readTone("  ", received: true) == nil, "Offline Read the room names tones and the words behind them")
        let frustrated = OfflineToolkit.readTone("Per my last email, still waiting.", received: true)?.tones ?? []
        check(frustrated.first { $0.tone == "Frustrated" }?.why.contains("“Per my last”") == true,
              "Offline Read the room quotes the longest phrase as written")
        check(OfflineToolkit.weighing("Should I take the pottery class?").experiment
              == "Pick one small, reversible step toward “take the pottery class” and try it for 7 days. Note how it feels each evening."
              && OfflineToolkit.weighing("Move house").pros.isEmpty, "Offline Weigh it suggests a plain experiment")
        let quick = PersonalTodo(title: "Text Mum", dueDay: "2026-11-25")
        let overdue = PersonalTodo(title: "Return the form", dueDay: "2026-11-20")
        let big = PersonalTodo(title: "Write the essay")
        let picks = OneThingPicker.choices([big, quick, overdue], estimates: [TodoEstimate(id: quick.id, minutes: 5, source: "guide"),
                                           TodoEstimate(id: big.id, minutes: 120, source: "guide")],
                                           focus: .scattered, today: "2026-11-24", hour: 19)
        check(picks.count == 2 && picks[0].id == overdue.id && picks[1].id == quick.id, "One thing offers two choices, overdue and small first")
        let reply = try ToolkitReply.decode(ToolkitReply.Items.self, from: ["items": [["title": "Buy milk", "due_day": "2026-11-25"]]])
        check(reply.items.first?.dueDay == "2026-11-25", "Agent replies decode snake_case fields")
        print("PASS: Toolkit steps, estimates, sync, backup, offline guide and agent replies.")
    }

    private static func checkPersonalTodos() throws {
        let now = Date()
        let day = PracticeDate.key(now)
        let tomorrow = PracticeDate.key(Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        let open = PersonalTodo(title: "Return the library book", dueDay: day, reminderAt: now + 600)
        let later = PersonalTodo(title: "Check the mail", dueDay: tomorrow, reminderAt: now + 1200)
        let undated = PersonalTodo(title: "Look up pottery lessons")
        var done = PersonalTodo(title: "Buy stamps", dueDay: day, reminderAt: now + 300)
        done.completed = true
        let past = PersonalTodo(title: "Pick up a parcel", dueDay: day, reminderAt: now - 600)
        check(open.isDue(by: day) && open.isDue(by: tomorrow), "Due tasks remain visible after their due day")
        check(!later.isDue(by: day) && !undated.isDue(by: day) && !done.isDue(by: day), "Future, undated and completed tasks stay out of Today")
        check(PersonalReminders.upcoming([done, later, undated, past, open], now: now, limit: 1) == [open],
              "Schedule only the soonest unfinished future reminders up to capacity")

        let oldJournal = try JournalStore.decode(JSONEncoder().encode(Journal()))
        check(oldJournal.personalTodos == nil, "Old journals load without personal to-dos")
        let firstDevice = UUID()
        let secondDevice = UUID()
        var first = oldJournal
        first.personalTodos = [open]
        var second = oldJournal
        second.personalTodos = [later]
        var firstReplica = try JournalReplica(seed: first, device: firstDevice)
        let secondReplica = try JournalReplica(seed: second, device: secondDevice)
        firstReplica.merge(secondReplica)
        let restored = try firstReplica.materialize(keepingEngagement: Engagement())
        check(Set(restored.personalTodos?.map(\.id) ?? []) == [open.id, later.id] && restored.tasks.isEmpty && restored.coins == 0,
              "Personal tasks merge independently of the coaching plan and rewards")

        let bytes = try JSONEncoder().encode(firstReplica)
        var legacy = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        check(legacy.removeValue(forKey: "personalTodoEntries") != nil, "New records occupy their own replica extension")
        let legacyReplica = try JSONDecoder().decode(JournalReplica.self, from: JSONSerialization.data(withJSONObject: legacy))
        firstReplica.merge(legacyReplica)
        let afterLegacy = try firstReplica.materialize(keepingEngagement: Engagement())
        check(afterLegacy.personalTodos?.count == 2, "Old peers that omit the extension cannot erase personal tasks")
        var afterDelete = restored
        afterDelete.personalTodos?.removeAll { $0.id == later.id }
        try firstReplica.observe(from: restored, to: afterDelete, device: firstDevice)
        firstReplica.merge(secondReplica)
        let remaining = try firstReplica.materialize(keepingEngagement: Engagement())
        check(remaining.personalTodos == [open], "Deleted personal tasks stay deleted after merging a stale peer")
    }

    private static func checkSync(in directory: URL, catalog: Catalog, now: Date, tomorrow: Date) throws {
        let day = CalendarDay.key(now)
        let nextDay = CalendarDay.key(tomorrow)
        let phone = UUID()
        let pad = UUID()
        let mac = UUID()
        let first = PlanTask()
        let second = PlanTask()
        let lesson = catalog.lessons[0]
        let challenge = catalog.challenges[0]
        let suggestion = catalog.startingSuggestions([:])[0]
        var base = Journal()
        base.started = now
        base.name = "Alex"
        base.tasks = [first, second]
        base.favoriteSources = ["Claude", "YouTube"]
        base.experiment = Experiment(suggestion: suggestion, start: now)
        let seed = try JournalReplica(seed: base, device: phone)
        var phoneState = seed
        var padState = seed
        var macState = seed

        var phoneJournal = base
        let moment = Moment(source: "Claude", kind: "AI", tags: ["Coding help"], value: 0.8,
                            decision: .more, date: now, day: day)
        phoneJournal.record(moment)
        phoneJournal.recordEnergy(.init(level: "high", value: 0.8), on: now)
        phoneJournal.toggleTask(first, on: now)
        phoneJournal.completeLesson(lesson, on: now)
        phoneJournal.checkIn(.held, on: now)
        try phoneState.observe(from: base, to: phoneJournal, device: phone)

        var padJournal = base
        padJournal.toggleTask(second, on: now)
        padJournal.habits[day] = ["read"]
        padJournal.moods[day] = 3
        padJournal.lessons[lesson.id, default: LessonRecord()].choices["2"] = "A reply"
        padJournal.checkIn(.slip, on: tomorrow)
        padJournal.toggleFavoriteChore("maintenance:hvac-filter")
        padJournal.toggleMaintenanceChore("maintenance:hvac-filter", on: tomorrow)
        try padState.observe(from: base, to: padJournal, device: pad)

        var macJournal = base
        macJournal.name = "Alex R"
        macJournal.tracker = .ring
        macJournal.favoriteSources?.removeAll { $0 == "YouTube" }
        macJournal.customSources = ["My book"]
        macJournal.cleaningChecks["daily"] = [0, 1]
        macJournal.cleaningLast["daily"] = day
        let daily = catalog.cleaning.daily
        let choreID = daily.choreID(at: 2)
        macJournal.toggleFavoriteChore(choreID)
        macJournal.toggleCleaningChore(daily, at: 2, on: now)
        macJournal.toggleCleaningChore(daily, at: 2, on: now)
        macJournal.completeChallenge(challenge, choice: "Keys", on: now)
        try macState.observe(from: base, to: macJournal, device: mac)

        let file = directory.appending(path: "phone-snapshot.glimmerjournal")
        try JournalCloud.write(phoneState, to: file)
        let readback = try JournalCloud.read(file)
        check(readback == phoneState, "Coordinated replica transfer round trip")
        var all = readback
        all.merge(padState)
        all.merge(macState)
        var reverse = macState
        reverse.merge(padState)
        reverse.merge(readback)
        check(all == reverse, "Three independently edited devices converge")

        let merged = try all.materialize(keepingEngagement: phoneJournal.engagement)
        check(merged.tasks == base.tasks && merged.completions[day] == [first.id, second.id], "Same-day task completions merge")
        check(merged.moments == [moment] && merged.energy[day]?.value == 0.8, "Moment and energy merge")
        check(merged.lessons[lesson.id]?.completed == true && merged.lessons[lesson.id]?.choices["2"] == "A reply", "Independent lesson changes merge")
        check(merged.experiment?.checkins == [day: .held, nextDay: .slip], "Experiment check-ins merge by day")
        check(merged.name == "Alex R" && merged.tracker == .ring && merged.favoriteSources == ["Claude"], "Preferences and deletions merge")
        check(merged.customSources == ["My book"] && merged.habits[day] == ["read"] && merged.moods[day] == 3, "Sources, habits and moods merge")
        check(merged.cleaningChecks["daily"] == [0, 1] && merged.cleaningLast["daily"] == day
              && merged.challenges[challenge.id]?.choice == "Keys", "Cleaning and Tiny wins merge")
        check(merged.favoriteChores == [choreID, "maintenance:hvac-filter"]
              && merged.recentChores?["maintenance:hvac-filter"] == [CalendarDay.key(tomorrow)]
              && merged.recentChores?[choreID]?.contains(day) != true,
              "Chore favorites and completion dates merge, and an undone check stays out of Recent")
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(all)) as? [String: Any]
        if var oldWire = wire {
            oldWire.removeValue(forKey: "choreEntries")
            let oldReplica = try JSONDecoder().decode(JournalReplica.self, from: JSONSerialization.data(withJSONObject: oldWire))
            let oldJournal = try oldReplica.materialize(keepingEngagement: .init())
            check(oldJournal.favoriteChores == nil && oldJournal.cleaningLast["daily"] == day,
                  "Older releases can read existing cleaning state independently of new chore fields")
        }
        check(merged.engagement.count == phoneJournal.engagement.count && merged.rewards["log:\(day)"] == 10, "Review milestones stay local and rewards deduplicate")

        var undone = merged
        undone.toggleTask(first, on: now)
        undone.tasks.removeAll { $0.id == first.id }
        try all.observe(from: merged, to: undone, device: phone)
        all.merge(seed)
        all.merge(macState)
        let afterUndo = try all.materialize(keepingEngagement: .init())
        check(afterUndo.tasks.map(\.id) == [second.id] && afterUndo.completions[day] == [second.id]
              && afterUndo.rewards["task:\(day):\(first.id)"] == nil, "A stale replica cannot resurrect a deleted task or undone check")

        let saved = SavedJournal(journal: afterUndo, cloud: JournalCloudState(device: phone, replica: all))
        let data = try JSONEncoder().encode(saved)
        let oldReader = try JSONDecoder().decode(Journal.self, from: data)
        let newReader = try JSONDecoder().decode(SavedJournal.self, from: data)
        check(oldReader.tasks == afterUndo.tasks && newReader.cloud?.replica == all, "Local sync metadata preserves the existing journal format")
        print("PASS: three independent journal replicas, coordinated file exchange, conflicting offline edits, deletions and relaunch compatibility.")
    }

    @MainActor
    private static func checkAgentAccess(in directory: URL, catalog: Catalog, catalogURL: URL) throws {
        let folder = directory.appending(path: "agent", directoryHint: .isDirectory)
        let journalURL = folder.appending(path: "Journal.json")
        let app = JournalStore(url: journalURL, catalogURL: catalogURL)
        app.start(name: "Agent")
        let session = AgentAccess.Session(journal: journalURL, catalog: catalog)
        var next = 1
        func send(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
            next += 1
            let request: [String: Any] = ["jsonrpc": "2.0", "id": next, "method": method, "params": params]
            let line = String(decoding: try! JSONSerialization.data(withJSONObject: request), as: UTF8.self)
            return session.handle(line) ?? [:]
        }
        func call(_ name: String, _ arguments: [String: Any] = [:]) -> (error: Bool, body: [String: Any], text: String) {
            let result = send("tools/call", ["name": name, "arguments": arguments])["result"] as? [String: Any] ?? [:]
            let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            let body = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (result["isError"] as? Bool == true, body, text)
        }
        check(send("tools/list")["error"] != nil, "Tools wait for initialize")
        let initialized = send("initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "Checks"]])["result"] as? [String: Any]
        check(initialized?["instructions"] is String, "Server sends agent instructions")
        check(session.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil, "Notifications get no reply")
        let advertised = (send("tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        check(Set(advertised.compactMap { $0["name"] as? String }).isSuperset(of:
            ["list_personal_todos", "add_personal_todo", "set_personal_todo_done", "set_todo_steps"]), "Personal task tools are advertised")
        check(call("get_plan_summary").error, "Access off blocks summaries")

        try app.setAgentLevel(.summaries)
        check(!call("get_plan_summary").error && call("get_attention_summary", ["days": 7]).body["days"] as? Int == 7, "Summaries allowed")
        check(call("get_attention_summary", ["days": 31]).error && call("get_attention_summary", ["days": true]).error, "Day range validated")
        check(call("get_today").error && call("log_moment", ["source": "Walk", "aftertaste": 2]).error, "Summaries mode cannot read titles or write")
        check(call("list_personal_todos").error && call("add_personal_todo", ["title": "Books"]).error,
              "Summaries mode keeps personal task titles private")

        let daily = call("get_daily_glimmer")
        let attribution = daily.body["source"] as? [String: String]
        check(attribution?["credit"] == "Brad Dunlap, author and life coach" && attribution?["note"] == CoachingSource.note, "Daily guidance credits its author and explains its scope")
        let dayKey = PracticeDate.key(.now)
        let reflection = daily.body["reflection"] as? [String: Any]
        check(reflection?["topic_id"] as? String == Catalog.reflectionTopicID && reflection?["saved"] as? Bool == false && reflection?["done"] as? Bool == false, "Read-only dashboard includes today’s public reflection")
        let featured = daily.body["practice"] as! [String: Any]
        let practiceID = featured["practice_id"] as! String
        let practiceTaskID = featured["task_id"] as! String
        let saveArguments = ["practice_id": practiceID, "day": dayKey]
        let listed = call("list_practices").body["practices"] as! [[String: Any]]
        check(!daily.error && daily.body["day_id"] as? String == "glimmer:daily:\(dayKey)" && daily.text == call("get_daily_glimmer").text, "Repeatable daily content")
        check(listed.count == catalog.practiceTopics.flatMap(\.exercises).count && listed.contains { $0["practice_id"] as? String == practiceID }, "Complete public coaching catalog")
        check(call("list_practices", ["topic_id": "missing"]).error && call("save_practice", saveArguments).error, "Read-only boundaries")
        check(!daily.text.contains(app.journal.tasks[0].name) && !daily.text.contains("favoriteSources"), "Personal task titles and journal records excluded")
        try app.setAgentLevel(.changes)
        let reminder = ISO8601DateFormatter().string(from: .now + 3600)
        let todoID = UUID().uuidString
        let todoArguments: [String: Any] = ["title": "Return a library book", "due_day": dayKey,
                                           "reminder_at": reminder, "request_id": todoID]
        let todo = call("add_personal_todo", todoArguments)
        let retry = call("add_personal_todo", todoArguments)
        check(todo.body["task_id"] as? String == todoID && todo.body["added"] as? Bool == true
              && retry.body["added"] as? Bool == false && retry.body["reminder_at"] as? String == reminder,
              "An agent can save a dated, timed personal task and safely retry")
        check(call("add_personal_todo", ["title": "Impossible date", "due_day": "2026-02-30"]).error &&
              call("add_personal_todo", ["title": "Elapsed reminder", "reminder_at": "2025-11-25T12:00:00Z"]).error,
              "The agent rejects invalid dates and elapsed reminders")
        check((call("list_personal_todos", ["filter": "due"]).body["todos"] as? [[String: Any]])?.count == 1,
              "The agent can read today's personal tasks")
        check(call("set_personal_todo_done", ["task_id": todoID, "done": true]).body["done"] as? Bool == true
              && (call("list_personal_todos", ["filter": "due"]).body["todos"] as? [[String: Any]])?.isEmpty == true,
              "Checking off a personal task removes it from the due list")
        check(call("set_personal_todo_done", ["task_id": todoID, "done": false]).body["done"] as? Bool == false,
              "Personal tasks can be reopened")
        let stepped = call("add_personal_todo", ["title": "Plan the party", "steps": ["Pick a date", "Write the guest list"],
                                                  "estimate_minutes": 45])
        let steppedID = stepped.body["task_id"] as? String ?? ""
        let firstSteps = stepped.body["steps"] as? [[String: Any]] ?? []
        check(firstSteps.map { $0["title"] as? String } == ["Pick a date", "Write the guest list"]
              && stepped.body["estimate_minutes"] as? Int == 45 && stepped.body["estimate_source"] as? String == "agent",
              "An agent can add a to-do with steps and an estimate")
        check(call("add_personal_todo", ["title": "Bad", "steps": [""]]).error
              && call("add_personal_todo", ["title": "Bad", "estimate_minutes": 0]).error
              && call("add_personal_todo", ["title": "Bad", "steps": "Pick a date"]).error, "Step and estimate input is validated")
        let pickID = firstSteps.first?["step_id"] as? String ?? ""
        let smaller = call("set_todo_steps", ["task_id": steppedID, "parent_step_id": pickID, "steps": ["Check the calendar", "Ask Sam"]])
        let nested = (smaller.body["steps"] as? [[String: Any]])?.first?["steps"] as? [[String: Any]] ?? []
        check(nested.count == 2 && (smaller.body["steps"] as? [[String: Any]])?.first?["step_id"] as? String == pickID,
              "set_todo_steps adds smaller steps and keeps the parent")
        let replaced = call("set_todo_steps", ["task_id": steppedID, "steps": ["Pick a date", "Book the room"]])
        check((replaced.body["steps"] as? [[String: Any]])?.first?["step_id"] as? String == pickID
              && (replaced.body["steps"] as? [[String: Any]])?.last?["title"] as? String == "Book the room",
              "Replacing steps keeps unchanged steps")
        let grandchild = nested.first?["step_id"] as? String ?? ""
        check(call("set_todo_steps", ["task_id": steppedID, "parent_step_id": grandchild, "steps": ["Too deep"]]).error
              && call("set_todo_steps", ["task_id": UUID().uuidString, "steps": []]).error, "Steps stay two levels deep on real to-dos")
        check(call("set_todo_steps", ["task_id": steppedID, "steps": []]).body["steps"] == nil
              && JournalStore(url: journalURL, catalogURL: catalogURL).journal.todoSteps?.isEmpty == true,
              "An agent can clear steps")
        _ = call("set_personal_todo_done", ["task_id": steppedID, "done": true])
        let reopenedApp = JournalStore(url: journalURL, catalogURL: catalogURL)
        check(reopenedApp.journal.personalTodos?.count == 2 && reopenedApp.journal.tasks.count == catalog.initialTasks.count,
              "Agent writes persist in the same journal and leave the coaching plan intact")
        let today = call("get_today")
        let tasks = today.body["tasks"] as? [[String: Any]] ?? []
        check(!today.error && !tasks.isEmpty && tasks.allSatisfy { $0["name"] is String }, "Today lists tasks with names")
        let logged = call("log_moment", ["source": "walk", "aftertaste": 2, "decision": "more", "tags": ["Outside"]])
        check(!logged.error && logged.body["logged"] as? String == "Walk" && logged.body["category"] as? String == "Activity", "Moment matches a catalog source")
        check(call("log_moment", ["source": "Instagram", "aftertaste": 3]).error, "Aftertaste range validated")
        let historicalDay = PracticeDate.key(Calendar.current.date(byAdding: .day, value: -2, to: .now)!)
        check(call("log_moment", ["day": historicalDay, "source": "Walk", "aftertaste": 1]).body["day"] as? String == historicalDay, "Backdated moments retain their local day")
        check(call("log_moment", ["day": "2099-11-29", "source": "Walk", "aftertaste": 1]).error, "Future logs rejected")
        let id = tasks[0]["id"] as! String
        check(!call("set_task_done", ["task_id": id]).error && !call("set_task_done", ["task_id": id, "done": true]).error, "Check off is idempotent")
        check(call("set_task_done", ["task_id": "missing"]).error, "Unknown task rejected")
        let added = call("add_plan_task", ["name": "Call the bank", "day": "tomorrow", "icon": "📞"])
        check(!added.error && added.body["added"] as? Bool == true, "Task added to tomorrow")
        check(call("add_plan_task", ["name": "call the bank", "day": "tomorrow"]).body["added"] as? Bool == false, "Same task not added twice")
        check(!(call("get_today").body["tasks"] as? [[String: Any]] ?? []).contains { $0["name"] as? String == "Call the bank" }, "Tomorrow's task stays off today")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        check(JournalStore(url: journalURL, catalogURL: nil).journal.tasks.contains { $0.name == "Call the bank" && !$0.repeats && $0.occurs(on: tomorrow) }, "Tomorrow's task is saved once")
        check(call("add_plan_task", ["name": "", "day": "today"]).error && call("add_plan_task", ["name": "X", "day": "monday"]).error, "Task input validated")
        check(!call("record_energy", ["level": "high"]).error && call("record_energy", ["level": "loud"]).error, "Energy levels validated")
        check(call("check_in_experiment", ["outcome": "held"]).error, "No experiment means no check-in")

        let saved = call("save_practice", saveArguments)
        check(saved.body["added"] as? Bool == true && saved.body["task_id"] as? String == practiceTaskID && call("save_practice", saveArguments).body["added"] as? Bool == false, "Practice save and retry")
        let complete = call("set_task_done", ["task_id": practiceTaskID, "day": dayKey, "done": true])
        check(!complete.error && complete.body["coins"] as? Int == call("set_task_done", ["task_id": practiceTaskID, "day": dayKey, "done": true]).body["coins"] as? Int, "Dated completion is idempotent")
        let prior = PracticeDate.key(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        check(call("set_task_done", ["task_id": practiceTaskID, "day": prior]).error && call("save_practice", ["practice_id": practiceID, "day": "2026-02-30"]).error, "Stale day mismatch and invalid date rejected")
        check((call("get_daily_glimmer").body["practice"] as? [String: Any])?["done"] as? Bool == true, "Dashboard reads completed state")
        _ = call("record_energy", ["level": "high"])
        // The running app sees the agent's changes before it saves its own.
        check(app.journal.moments.isEmpty, "App holds its earlier copy")
        Thread.sleep(forTimeInterval: 0.01)
        check(app.change { $0.name = "Agent R" }, "App saves after an agent change")
        let reread = JournalStore(url: journalURL, catalogURL: nil)
        let day = CalendarDay.key(Date())
        check(reread.journal.moments.count == 2 && reread.journal.moments.contains(where: { $0.day == historicalDay }) && reread.journal.completions[day]?.contains(id) == true
              && reread.journal.energy[day]?.level == "high" && reread.journal.name == "Agent R", "Agent and app changes both kept")
        check(AgentActivity.read(in: folder)?.client == "Checks" && AgentActivity.read(in: folder)?.tool == "record_energy", "Activity recorded")

        try app.setAgentLevel(.off)
        check(AgentAccess.level(in: folder) == .off && call("get_plan_summary").error, "Turning access off revokes it")

        let merged = try AgentSetup.mergedProjectConfiguration(existing: Data(#"{"mcpServers":{"other":{"command":"x"}},"keep":1}"#.utf8), command: "/Applications/Glimmer.app/Contents/MacOS/Glimmer")
        let root = try JSONSerialization.jsonObject(with: merged.data) as? [String: Any]
        let servers = root?["mcpServers"] as? [String: Any]
        check(servers?["other"] != nil && root?["keep"] as? Int == 1 && (servers?["glimmer"] as? [String: Any])?["args"] as? [String] == ["--mcp"] && !merged.replaces,
              "Project connection keeps other servers")
        check((try? AgentSetup.mergedProjectConfiguration(existing: Data("[1]".utf8), command: "x")) == nil, "Invalid project configuration left alone")
        let manifest = try JSONSerialization.jsonObject(with: AgentSetup.extensionManifest(command: "/Applications/Glimmer.app/Contents/MacOS/Glimmer")) as? [String: Any]
        check(manifest?["name"] as? String == "glimmer" && (manifest?["tools"] as? [Any])?.count == advertised.count,
              "Claude extension manifest advertises the same tools")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
