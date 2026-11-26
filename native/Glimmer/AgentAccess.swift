#if os(macOS)
import CoreFoundation
import Foundation

/// Glimmer's local MCP server. An agent launches the app executable with `--mcp`, which reads and
/// writes the journal on this Mac and never opens a window. Glimmer's Settings decides what it may do.
enum AgentAccess {
    static let argument = "--mcp"
    static let marker = "AllowAgentSummaries"
    static let changesMarker = "AllowAgentChanges"
    static let activityFile = "AgentActivity.json"
    static let checkClient = "Glimmer connection check"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    enum Level: Equatable {
        case off, summaries, changes
    }

    static func level(in directory: URL) -> Level {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.appending(path: marker).path) else { return .off }
        return manager.fileExists(atPath: directory.appending(path: changesMarker).path) ? .changes : .summaries
    }

    static let instructions = """
    Glimmer is a private, neurodivergent-friendly spiritual life coach for deep thinkers and anyone too busy thinking to stay organized, with daily reflections and a journal on this Mac. People log moments (an app, activity or person) with an aftertaste \
    from -2 (drained) to +2 (nourished), check off a daily plan, record energy and run 7-day experiments.
    Glimmer Settings → Agent access controls this server. "Share read-only summaries" allows summaries, get_daily_glimmer and list_practices. \
    "Let agents log and check off" also allows get_today and the tools that change the journal.
    For a daily dashboard, call get_daily_glimmer with no arguments on the person's chosen schedule using their Mac time zone. \
    Upsert the dashboard card by day_id and an external practice task by task_id. Use list_practices to choose another exercise. \
    If the person wants it on their plan, call save_practice with the practice_id and day. After the person confirms they did it, \
    call set_task_done with that task_id, the same day, and done=true. A read never marks the task complete. Scheduling belongs to the client. \
    For personal to-dos use list_personal_todos, add_personal_todo and set_personal_todo_done. These are separate from the coaching plan. \
    A to-do can carry small steps (with one level of smaller steps) and a time estimate in minutes. Pass steps and estimate_minutes to add_personal_todo, \
    or replace a to-do's steps later with set_todo_steps. Keep each step short and start it with a verb. \
    Only set a reminder time when requested. Glimmer schedules device-local reminders after it reads the saved task, if notifications are allowed on that device. \
    For other plan tasks call get_today first and use the IDs it returns. Log a moment only when the person \
    describes it or asks you to, using their own rating. Summaries describe self-reported patterns; they are not medical advice.
    Setup: Claude Code uses Glimmer's Save Project Connection in Settings → Agent access, Codex uses a STDIO server with the \
    command and argument Glimmer shows, Gemini CLI uses a project .gemini/settings.json, and Claude chat uses the Glimmer.mcpb extension saved from the same place.
    """

    @MainActor
    static func run() {
        let bundled = AppResources.url("Catalog", extension: "json").flatMap { try? Catalog.load(from: $0) }
        let content = bundled.map { EditorialLibrary(bundled: $0) }
        let session = Session(journal: JournalStore.storageURL, catalog: content?.edition?.content ?? bundled)
        while let line = readLine() {
            guard let response = session.handle(line) else { continue }
            send(response)
        }
    }

    private static func send(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        FileHandle.standardOutput.write(data + Data([10]))
    }

    @MainActor
    final class Session {
        private let journal: URL
        private let catalog: Catalog?
        private var initialized = false
        private var client = "An agent"

        init(journal: URL, catalog: Catalog? = AppResources.url("Catalog", extension: "json").flatMap { try? Catalog.load(from: $0) }) {
            self.journal = journal
            self.catalog = catalog
        }

        private var directory: URL { journal.deletingLastPathComponent() }

        /// Answers one JSON-RPC line. Notifications get no answer.
        func handle(_ line: String) -> [String: Any]? {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return error(NSNull(), -32700, "Invalid JSON")
            }
            guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
                return error(request["id"] ?? NSNull(), -32600, "Invalid Request")
            }
            guard let id = request["id"] else { return nil }
            let params = request["params"] as? [String: Any] ?? [:]
            switch method {
            case "initialize":
                let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
                let requested = params["protocolVersion"] as? String ?? ""
                if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String, !name.isEmpty {
                    client = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(80))
                }
                initialized = true
                if client != AgentAccess.checkClient { recordActivity(tool: nil) }
                return result(id, [
                    "protocolVersion": supported.contains(requested) ? requested : supported[0],
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "glimmer", "title": "Glimmer", "version": AgentAccess.version],
                    "instructions": AgentAccess.instructions
                ])
            case "ping":
                return result(id, [:])
            case "tools/list" where initialized:
                return result(id, ["tools": AgentAccess.tools])
            case "tools/call" where initialized:
                return result(id, call(params))
            default:
                return error(id, -32601, "Method not available")
            }
        }

        private func call(_ params: [String: Any]) -> [String: Any] {
            guard let name = params["name"] as? String, let tool = Tool(rawValue: name) else {
                return failure("Unknown Glimmer tool.")
            }
            guard let arguments = (params["arguments"] ?? [:]) as? [String: Any] else {
                return failure("Provide a JSON object for tool arguments.")
            }
            let level = AgentAccess.level(in: directory)
            guard level != .off else {
                return failure("Agent access is off. Open Glimmer → Settings → Agent access and turn on Share read-only summaries.")
            }
            guard !tool.needsChanges || level == .changes else {
                return failure("This needs Glimmer → Settings → Agent access → Let agents log and check off. Ask the person to turn it on.")
            }
            let store = JournalStore(url: journal, catalogURL: nil)
            guard store.loadError == nil, store.journal.onboardingComplete else {
                return failure("Finish Glimmer setup on this Mac first.")
            }
            let outcome = run(tool, arguments, store: store)
            if outcome["isError"] == nil && client != AgentAccess.checkClient { recordActivity(tool: name) }
            return outcome
        }

        private func run(_ tool: Tool, _ arguments: [String: Any], store: JournalStore) -> [String: Any] {
            let now = Date()
            store.day = now
            switch tool {
            case .attention:
                guard Set(arguments.keys).isSubset(of: ["days"]), let days = integer(arguments["days"] ?? 7), (1...30).contains(days) else {
                    return failure("Provide a whole number of days between 1 and 30.")
                }
                return AgentAccess.attentionSummary(store.journal, days: days, now: now)
            case .plan:
                guard arguments.isEmpty else { return failure("This tool does not accept arguments.") }
                return AgentAccess.planSummary(store.journal, now: now)
            case .daily:
                guard arguments.isEmpty else { return failure("This tool does not accept arguments.") }
                guard let catalog, let selected = catalog.dailyPractice(on: now, level: store.journal.guidanceLevel(asOf: now)),
                      let lesson = catalog.dailyLesson(for: store.journal, on: now) else { return failure("The coaching catalog is unavailable.") }
                let day = PracticeDate.key(now)
                let practice = datedPracticeFields(selected.practice, in: selected.topic, on: now, journal: store.journal)
                let takeaway = lesson.pages.first(where: { $0.kind == "takeaway" })?.tryToday ?? lesson.tagline
                var result: [String: Any] = ["day": day, "day_id": "glimmer:daily:\(day)", "time_zone": TimeZone.current.identifier,
                                            "source": ["author": CoachingSource.author, "role": CoachingSource.role, "credit": CoachingSource.credit, "note": CoachingSource.note, "url": CoachingSource.sourcesURL.absoluteString],
                                            "lesson": ["lesson_id": lesson.slug, "title": lesson.title, "takeaway": takeaway], "practice": practice]
                if let topic = catalog.reflectionTopic, let reflection = catalog.dailyReflection(on: now, level: store.journal.guidanceLevel(asOf: now)) {
                    result["reflection"] = datedPracticeFields(reflection, in: topic, on: now, journal: store.journal)
                }
                return AgentAccess.success(result)
            case .practices:
                guard Set(arguments.keys).isSubset(of: ["topic_id"]), let catalog else { return failure("Provide an optional topic_id.") }
                let topics: [PracticeTopic]
                if let requested = arguments["topic_id"] {
                    guard let id = requested as? String, let topic = catalog.practiceTopics.first(where: { $0.id == id }) else {
                        return failure("Unknown topic_id. Call list_practices without arguments to see available topics.")
                    }
                    topics = [topic]
                } else { topics = catalog.practiceTopics }
                return AgentAccess.success(["practices": topics.flatMap { topic in topic.exercises.map { practiceFields($0, in: topic) } }])
            case .savePractice:
                guard Set(arguments.keys) == ["day", "practice_id"], let day = arguments["day"] as? String,
                      let date = PracticeDate.parse(day), let practiceID = arguments["practice_id"] as? String,
                      let practice = catalog?.practiceTopics.lazy.flatMap(\.exercises).first(where: { $0.id == practiceID }) else {
                    return failure("Provide a valid day (YYYY-MM-DD) and a practice_id from get_daily_glimmer or list_practices.")
                }
                let task = practice.task(on: date)
                var added = false
                guard store.change({ journal in
                    guard !journal.tasks.contains(where: { $0.id == task.id }) else { return }
                    journal.tasks.append(task)
                    added = true
                }) else { return failure("Glimmer couldn’t save the practice.") }
                return AgentAccess.success(["practice_id": practice.id, "task_id": task.id, "day": day, "added": added,
                                            "done": store.journal.completions[CalendarDay.key(date)]?.contains(task.id) == true])
            case .today:
                guard arguments.isEmpty else { return failure("This tool does not accept arguments.") }
                return today(store.journal, now: now)
            case .logMoment:
                return logMoment(arguments, store: store, now: now)
            case .addTask:
                return addTask(arguments, store: store, now: now)
            case .personalTodos:
                let filter = arguments["filter"] as? String ?? "open"
                guard Set(arguments.keys).isSubset(of: ["filter"]),
                      arguments["filter"] == nil || arguments["filter"] is String,
                      ["open", "due", "completed", "all"].contains(filter) else {
                    return failure("Use an optional filter of open, due, completed or all.")
                }
                let day = PracticeDate.key(now)
                let todos = PersonalTodo.ordered((store.journal.personalTodos ?? []).filter { task in
                    filter == "all" || (filter == "open" && !task.completed) ||
                    (filter == "due" && task.isDue(by: day)) || (filter == "completed" && task.completed)
                })
                return AgentAccess.success(["day": day, "time_zone": TimeZone.current.identifier,
                                            "todos": todos.map { personalTodoFields($0, journal: store.journal) }])
            case .addPersonalTodo:
                return addPersonalTodo(arguments, store: store, now: now)
            case .setPersonalTodo:
                guard Set(arguments.keys) == ["task_id", "done"],
                      let id = (arguments["task_id"] as? String).flatMap(UUID.init(uuidString:)),
                      let done = boolean(arguments["done"]) else {
                    return failure("Provide task_id and done (true or false).")
                }
                guard store.setPersonalTodoDone(id, done: done),
                      let task = store.journal.personalTodos?.first(where: { $0.id == id }) else {
                    return failure("Glimmer couldn’t update that personal to-do. Verify the ID with list_personal_todos.")
                }
                return AgentAccess.success(personalTodoFields(task, journal: store.journal))
            case .setTodoSteps:
                return setTodoSteps(arguments, store: store)
            case .setTask:
                guard Set(arguments.keys).isSubset(of: ["task_id", "done", "day"]), let id = arguments["task_id"] as? String,
                      let done = arguments["done"] == nil ? true : boolean(arguments["done"]) else {
                    return failure("Provide task_id and optionally done (true or false) and day (YYYY-MM-DD).")
                }
                let date: Date
                if let raw = arguments["day"] {
                    guard let day = raw as? String, let parsed = PracticeDate.parse(day), day <= PracticeDate.key(now) else {
                        return failure("Provide today’s date or a past date in YYYY-MM-DD format.")
                    }
                    date = parsed
                } else { date = now }
                let day = CalendarDay.key(date)
                var updatedTask: PlanTask?
                guard store.change({ journal in
                    guard let task = journal.tasks.first(where: { $0.id == id && $0.occurs(on: date) }) else { return }
                    updatedTask = task
                    if (journal.completions[day]?.contains(id) == true) != done { journal.toggleTask(task, on: date) }
                }) else { return failure("Glimmer couldn’t save this change.") }
                guard let task = updatedTask else { return failure("No task with that ID is scheduled on the requested day.") }
                return AgentAccess.success(["task_id": task.id, "task": task.name, "day": PracticeDate.key(date), "done": done, "coins": store.journal.coins])
            case .energy:
                guard Set(arguments.keys) == ["level"], let id = arguments["level"] as? String,
                      let levels = catalog?.energy, let index = levels.firstIndex(where: { $0.id == id }) else {
                    return failure("Provide level: one of empty, low, mid, high or full.")
                }
                let value = Double(index) / Double(max(1, levels.count - 1))
                guard store.change({ $0.recordEnergy(.init(level: id, value: value), on: now) }) else {
                    return failure("Glimmer couldn't save this change.")
                }
                return AgentAccess.success(["day": CalendarDay.key(now), "energy": levels[index].label])
            case .checkIn:
                guard Set(arguments.keys) == ["outcome"], let raw = arguments["outcome"] as? String,
                      let outcome = ["held": Experiment.Outcome.held, "slipped": .slip][raw] else {
                    return failure("Provide outcome: held or slipped.")
                }
                guard let active = store.journal.experiment else { return failure("There is no experiment running.") }
                let day = CalendarDay.key(now)
                if let existing = active.checkins[day] {
                    return failure("Today's check-in is already recorded as \(existing.rawValue.lowercased()).")
                }
                guard !active.readyToReview else { return failure("This experiment is finished. The person reviews it in Glimmer.") }
                guard store.change({ $0.checkIn(outcome, on: now) }), store.journal.experiment?.checkins[day] != nil else {
                    return failure("Glimmer couldn't record this check-in.")
                }
                let checkins = store.journal.experiment?.checkins.count ?? 0
                return AgentAccess.success(["experiment": active.suggestion.title, "outcome": outcome.rawValue,
                                            "checkIns": checkins, "readyToReview": checkins >= active.duration])
            }
        }

        private func datedPracticeFields(_ practice: Practice, in topic: PracticeTopic, on date: Date, journal: Journal) -> [String: Any] {
            let id = practice.taskID(day: PracticeDate.key(date))
            var result = practiceFields(practice, in: topic)
            result["task_id"] = id
            result["saved"] = journal.tasks.contains { $0.id == id }
            result["done"] = journal.completions[CalendarDay.key(date)]?.contains(id) == true
            return result
        }

        private func practiceFields(_ practice: Practice, in topic: PracticeTopic) -> [String: Any] {
            ["practice_id": practice.id, "topic_id": topic.id, "topic": topic.title, "title": practice.title, "instruction": practice.sub,
             "stage": practice.stage, "stage_name": JourneyStage.name(practice.stage)]
        }

        private func today(_ journal: Journal, now: Date) -> [String: Any] {
            let day = CalendarDay.key(now)
            let done = journal.completions[day] ?? []
            let tasks: [[String: Any]] = journal.tasks.filter { $0.occurs(on: now) }.map {
                ["id": $0.id, "name": $0.name, "icon": $0.icon, "done": done.contains($0.id)]
            }
            var experiment: Any = NSNull()
            if let active = journal.experiment {
                experiment = ["title": active.suggestion.title, "detail": active.suggestion.sub,
                              "checkIns": active.checkins.count, "checkedInToday": active.checkins[day] != nil,
                              "readyToReview": active.readyToReview] as [String: Any]
            }
            let energy: Any = journal.energy[day].map { $0.level } ?? NSNull()
            return AgentAccess.success([
                "day": day,
                "tasks": tasks,
                "energy": energy,
                "momentsLoggedToday": journal.moments.filter { $0.day == day }.count,
                "favoriteSources": journal.favoriteSources ?? [],
                "experiment": experiment
            ])
        }

        private func logMoment(_ arguments: [String: Any], store: JournalStore, now: Date) -> [String: Any] {
            let source = (arguments["source"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard Set(arguments.keys).isSubset(of: ["source", "aftertaste", "decision", "tags", "day"]),
                  (1...60).contains(source.count),
                  let aftertaste = integer(arguments["aftertaste"]), (-2...2).contains(aftertaste) else {
                return failure("Provide source (what the moment was about) and aftertaste, a whole number from -2 (drained) to 2 (nourished).")
            }
            let decision = (arguments["decision"] as? String).flatMap(Decision.init(rawValue:))
            guard arguments["decision"] == nil || decision != nil else { return failure("decision must be less, same or more.") }
            let tags = arguments["tags"] as? [String] ?? []
            guard arguments["tags"] == nil || (arguments["tags"] is [String] && tags.count <= 5 && tags.allSatisfy { (1...40).contains($0.count) }) else {
                return failure("tags must be up to five short words.")
            }
            let date: Date
            if let supplied = arguments["day"] {
                guard let day = supplied as? String, let parsed = PracticeDate.parse(day), day <= PracticeDate.key(now) else {
                    return failure("Use today or a past date in YYYY-MM-DD format.")
                }
                date = day == PracticeDate.key(now) ? now : parsed
            } else { date = now }
            let name = matchingSource(source, journal: store.journal)
            let kind = catalog.map { Moment.kind(of: name, catalog: $0) } ?? "Feed"
            let moment = Moment(source: name, kind: kind, tags: tags, value: Double(aftertaste + 2) / 4,
                                decision: decision ?? .same, date: date, day: CalendarDay.key(date))
            guard store.change({ $0.record(moment) }) else { return failure("Glimmer couldn't save this moment.") }
            return AgentAccess.success(["logged": name, "day": moment.day, "category": kind, "aftertaste": moment.word,
                                        "decision": moment.decision.title, "momentsLoggedToday": store.todayLogs.count])
        }

        /// Adds a one-time task to today's or tomorrow's plan. The same name on the same day is not added twice.
        private func addTask(_ arguments: [String: Any], store: JournalStore, now: Date) -> [String: Any] {
            let name = (arguments["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = (arguments["icon"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dayName = arguments["day"] as? String ?? "today"
            guard Set(arguments.keys).isSubset(of: ["name", "day", "icon"]), (1...60).contains(name.count),
                  arguments["icon"] == nil || (1...60).contains(icon.count) else {
                return failure("Provide name (up to 60 characters), optionally day (today or tomorrow) and icon (one emoji).")
            }
            guard let offset = ["today": 0, "tomorrow": 1][dayName],
                  let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now)) else {
                return failure("day must be today or tomorrow.")
            }
            let day = CalendarDay.key(date)
            if let existing = store.journal.tasks.first(where: {
                $0.occurs(on: date) && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                return AgentAccess.success(["task_id": existing.id, "name": existing.name, "day": day, "added": false])
            }
            var task = PlanTask()
            task.name = name
            if !icon.isEmpty { task.icon = icon }
            task.anchor = date
            task.repeats = false
            guard store.change({ $0.tasks.append(task) }) else { return failure("Glimmer couldn't save this task.") }
            return AgentAccess.success(["task_id": task.id, "name": name, "day": day, "added": true])
        }

        private func personalTodoFields(_ task: PersonalTodo, journal: Journal) -> [String: Any] {
            var fields: [String: Any] = ["task_id": task.id.uuidString, "title": task.title, "done": task.completed]
            fields["due_day"] = task.dueDay
            fields["reminder_at"] = task.reminderAt.map { ISO8601DateFormatter().string(from: $0) }
            let steps = journal.steps(for: task.id)
            if !steps.isEmpty {
                fields["steps"] = steps.map { step -> [String: Any] in
                    var fields = stepFields(step)
                    let smaller = journal.steps(for: task.id, parent: step.id)
                    if !smaller.isEmpty { fields["steps"] = smaller.map(stepFields) }
                    return fields
                }
            }
            if let estimate = journal.estimate(for: task.id) {
                fields["estimate_minutes"] = estimate.minutes
                fields["estimate_source"] = estimate.source
            }
            return fields
        }

        private func stepFields(_ step: TodoStep) -> [String: Any] {
            ["step_id": step.id.uuidString, "title": step.title, "done": step.done]
        }

        /// Reads an optional list of step titles. Returns nil when the value is invalid.
        private func stepTitles(_ value: Any?) -> [String]?? {
            guard let value else { return .some(nil) }
            guard let raw = value as? [Any], raw.count <= 12 else { return nil }
            let titles = raw.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard titles.count == raw.count, titles.allSatisfy({ (1...TodoStep.titleLimit).contains($0.count) }) else { return nil }
            return .some(titles)
        }

        private func setTodoSteps(_ arguments: [String: Any], store: JournalStore) -> [String: Any] {
            guard Set(arguments.keys).isSubset(of: ["task_id", "steps", "parent_step_id"]),
                  let id = (arguments["task_id"] as? String).flatMap(UUID.init(uuidString:)),
                  case .some(.some(let titles)) = stepTitles(arguments["steps"]) else {
                return failure("Provide task_id and steps (0–12 titles of 1–160 characters), and optionally parent_step_id.")
            }
            let parent = (arguments["parent_step_id"] as? String).flatMap(UUID.init(uuidString:))
            guard arguments["parent_step_id"] == nil || parent != nil else { return failure("parent_step_id must be a step_id UUID.") }
            guard let task = store.journal.personalTodos?.first(where: { $0.id == id }) else {
                return failure("No personal to-do has that task_id. Verify it with list_personal_todos.")
            }
            if let parent {
                guard let step = store.journal.todoSteps?.first(where: { $0.id == parent && $0.todoID == id }), step.parentID == nil else {
                    return failure("parent_step_id must be a top-level step of this to-do. Steps go two levels deep.")
                }
            }
            guard store.change({ $0.replaceSteps(for: id, parent: parent, with: titles) }) else {
                return failure("Glimmer couldn’t save these steps.")
            }
            return AgentAccess.success(personalTodoFields(task, journal: store.journal))
        }

        private func addPersonalTodo(_ arguments: [String: Any], store: JournalStore, now: Date) -> [String: Any] {
            guard Set(arguments.keys).isSubset(of: ["title", "due_day", "reminder_at", "request_id", "steps", "estimate_minutes"]),
                  let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  (1...PersonalTodo.titleLimit).contains(title.count) else {
                return failure("Provide a title of 1–160 characters and optional due_day, reminder_at, request_id, steps and estimate_minutes.")
            }
            guard case .some(let steps) = stepTitles(arguments["steps"]) else {
                return failure("steps must be a list of up to 12 short titles, each 1–160 characters.")
            }
            let minutes = integer(arguments["estimate_minutes"])
            guard arguments["estimate_minutes"] == nil || minutes.map({ (1...1440).contains($0) }) == true else {
                return failure("estimate_minutes must be a whole number from 1 to 1440.")
            }
            let dueDay = arguments["due_day"] as? String
            guard arguments["due_day"] == nil || dueDay.flatMap(PracticeDate.parse) != nil else {
                return failure("due_day must be a valid local date in YYYY-MM-DD format.")
            }
            let requestedID = (arguments["request_id"] as? String).flatMap(UUID.init(uuidString:))
            guard arguments["request_id"] == nil || requestedID != nil else {
                return failure("request_id must be a UUID. Reuse it for retries.")
            }
            if let existing = store.journal.personalTodos?.first(where: { $0.id == requestedID }) {
                return personalTodoResult(existing, added: false, journal: store.journal)
            }
            let reminderAt = (arguments["reminder_at"] as? String).flatMap { raw -> Date? in
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: raw) { return date }
                formatter.formatOptions.insert(.withFractionalSeconds)
                return formatter.date(from: raw)
            }
            guard arguments["reminder_at"] == nil || reminderAt.map({ $0 > now }) == true else {
                return failure("reminder_at must be a future ISO 8601 timestamp with a UTC offset or Z.")
            }
            var task = PersonalTodo(id: requestedID ?? UUID(), title: title, dueDay: dueDay, reminderAt: reminderAt)
            var added = false
            guard store.change({ journal in
                // Check again under the write lock for parallel retries from multiple clients.
                var todos = journal.personalTodos ?? []
                if let existing = todos.first(where: { $0.id == task.id }) {
                    task = existing
                } else {
                    todos.append(task)
                    journal.personalTodos = todos
                    if let steps { journal.replaceSteps(for: task.id, with: steps) }
                    if let minutes { journal.setEstimate(minutes, source: ToolkitSource.agent.rawValue, for: task.id) }
                    added = true
                }
            }) else { return failure("Glimmer couldn’t save this personal to-do.") }
            return personalTodoResult(task, added: added, journal: store.journal)
        }

        private func personalTodoResult(_ task: PersonalTodo, added: Bool, journal: Journal) -> [String: Any] {
            var fields = personalTodoFields(task, journal: journal)
            fields["added"] = added
            if task.reminderAt != nil {
                fields["reminder_delivery"] = "Glimmer schedules this locally when the app reads the task on a device with notifications enabled."
            }
            return AgentAccess.success(fields)
        }

        /// Uses the journal's own spelling (and emoji) when the name matches a source Glimmer already knows.
        private func matchingSource(_ source: String, journal: Journal) -> String {
            let known = (journal.favoriteSources ?? []) + journal.customSources + (catalog?.activities ?? []) + (catalog?.people ?? [])
            func plain(_ text: String) -> String {
                let kept = text.unicodeScalars.drop { !CharacterSet.alphanumerics.contains($0) }
                return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).lowercased()
            }
            return known.first { plain($0) == plain(source) } ?? source
        }

        private func integer(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue else { return nil }
            return number.intValue
        }

        private func boolean(_ value: Any?) -> Bool? {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }

        private func recordActivity(tool: String?) {
            var activity = AgentActivity.read(in: directory) ?? AgentActivity()
            activity.client = client
            activity.clientDate = Date()
            if let tool {
                activity.tool = tool
                activity.toolDate = Date()
            }
            activity.write(in: directory)
        }

        private func result(_ id: Any, _ result: [String: Any]) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "result": result]
        }

        private func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }

        private func failure(_ message: String) -> [String: Any] { AgentAccess.failure(message) }
    }

    private enum Tool: String {
        case attention = "get_attention_summary", plan = "get_plan_summary", today = "get_today"
        case daily = "get_daily_glimmer", practices = "list_practices", savePractice = "save_practice"
        case logMoment = "log_moment", addTask = "add_plan_task", setTask = "set_task_done", energy = "record_energy", checkIn = "check_in_experiment"
        case personalTodos = "list_personal_todos", addPersonalTodo = "add_personal_todo", setPersonalTodo = "set_personal_todo_done"
        case setTodoSteps = "set_todo_steps"

        var needsChanges: Bool { ![.attention, .plan, .daily, .practices].contains(self) }
    }

    static var tools: [[String: Any]] {
        func tool(_ name: String, _ title: String, _ description: String, _ properties: [String: Any] = [:],
                  required: [String] = [], readOnly: Bool, idempotent: Bool = true) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
            if !required.isEmpty { schema["required"] = required }
            return ["name": name, "title": title, "description": description, "inputSchema": schema,
                    "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": false,
                                    "idempotentHint": idempotent, "openWorldHint": false]]
        }
        let changes = " Requires Let agents log and check off in Glimmer's Agent access settings."
        return [
            tool("get_attention_summary", "Attention summary",
                 "Read an aggregate of self-reported aftertaste from the last 1–30 calendar days, grouped by general activity category. Individual entries, source names and timestamps are excluded. Patterns are descriptive, not medical conclusions.",
                 ["days": ["type": "integer", "minimum": 1, "maximum": 30, "description": "Days to include, today counting as one. Default 7."]],
                 readOnly: true),
            tool("get_plan_summary", "Plan summary",
                 "Read counts of scheduled and completed tasks for today, today's energy and progress on the current experiment. Excludes task titles and journal entries.",
                 readOnly: true),
            tool("get_daily_glimmer", "Daily Glimmer",
                 "Read today’s public coaching lesson, practice and a quiet reflection with stable day_id and task_id, local time zone, and saved/done flags. Excludes private journal text, custom task names and onboarding answers. Upsert by these IDs in your own dashboard.", readOnly: true),
            tool("list_practices", "Coaching practices", "Browse the editorial practice catalog. Without topic_id this returns every available topic and practice.",
                 ["topic_id": ["type": "string"]], readOnly: true),
            tool("save_practice", "Save a practice to the plan", "Add a catalog exercise as one dated plan task. Repeating the same day and practice returns the same task_id." + changes,
                 ["practice_id": ["type": "string"], "day": ["type": "string", "format": "date"]], required: ["practice_id", "day"], readOnly: false),
            tool("get_today", "Today in Glimmer",
                 "Read today's plan with task IDs, names and whether each is done, today's energy, how many moments were logged, favourite sources and the running experiment." + changes,
                 readOnly: true),
            tool("log_moment", "Log a moment",
                 "Record a moment the person describes: what it was about and how it left them feeling." + changes,
                 ["source": ["type": "string", "minLength": 1, "maxLength": 60, "description": "The app, activity or person, such as Instagram, Walk or Called a friend."],
                  "aftertaste": ["type": "integer", "minimum": -2, "maximum": 2, "description": "-2 drained, -1 off, 0 neutral, 1 lighter, 2 nourished."],
                  "day": ["type": "string", "format": "date", "description": "Optional local date for a past moment. Defaults to today."],
                  "decision": ["type": "string", "enum": ["less", "same", "more"], "description": "Whether they want less, the same or more of it. Default same."],
                  "tags": ["type": "array", "items": ["type": "string", "maxLength": 40], "maxItems": 5, "description": "Optional short words, such as Bored or Before bed."]],
                 required: ["source", "aftertaste"], readOnly: false, idempotent: false),
            tool("add_plan_task", "Add a plan task",
                 "Add a one-time task to today's or tomorrow's plan, such as a goal the person wants to get done. A task with the same name on that day is not added twice." + changes,
                 ["name": ["type": "string", "minLength": 1, "maxLength": 60, "description": "What to do, in a few words."],
                  "day": ["type": "string", "enum": ["today", "tomorrow"], "description": "Default today."],
                  "icon": ["type": "string", "maxLength": 60, "description": "Optional SF Symbol name, such as drop.fill. Glimmer picks one from the name when it is left out."]],
                 required: ["name"], readOnly: false),
            tool("set_task_done", "Check off a task",
                 "Set a task’s completion explicitly. Omit day for today. Use the original day and task_id when writing back a saved practice, including after midnight." + changes,
                 ["task_id": ["type": "string"], "day": ["type": "string", "format": "date"], "done": ["type": "boolean", "description": "Default true."]],
                 required: ["task_id"], readOnly: false),
            tool("list_personal_todos", "Personal to-dos",
                 "Read personal to-dos with stable IDs, due dates, reminder times, steps (with step_id and done) and any estimate_minutes. Due includes today's and overdue unfinished tasks." + changes,
                 ["filter": ["type": "string", "enum": ["open", "due", "completed", "all"], "default": "open"]],
                 readOnly: true),
            tool("add_personal_todo", "Add a personal to-do",
                 "Save a personal to-do separate from the coaching plan. Supply the same request_id when retrying. Reminders are scheduled locally after the app reads the task." + changes,
                 ["title": ["type": "string", "minLength": 1, "maxLength": PersonalTodo.titleLimit],
                  "due_day": ["type": "string", "format": "date", "description": "Optional local date, YYYY-MM-DD."],
                  "reminder_at": ["type": "string", "format": "date-time", "description": "Optional requested future time including a UTC offset or Z."],
                  "request_id": ["type": "string", "format": "uuid", "description": "Client-generated UUID. Reuse on retries."],
                  "steps": ["type": "array", "maxItems": 12, "description": "Optional small steps, in order. Start each with a verb.",
                            "items": ["type": "string", "minLength": 1, "maxLength": TodoStep.titleLimit]],
                  "estimate_minutes": ["type": "integer", "minimum": 1, "maximum": 1440, "description": "Optional time estimate in minutes."]],
                 required: ["title"], readOnly: false, idempotent: false),
            tool("set_todo_steps", "Set to-do steps",
                 "Replace the steps of a personal to-do, or the smaller steps under one top-level step when parent_step_id is given. Steps whose titles stay the same keep their IDs and done state. Pass an empty list to clear them." + changes,
                 ["task_id": ["type": "string", "format": "uuid"],
                  "steps": ["type": "array", "maxItems": 12, "items": ["type": "string", "minLength": 1, "maxLength": TodoStep.titleLimit]],
                  "parent_step_id": ["type": "string", "format": "uuid", "description": "Optional top-level step_id to break down further."]],
                 required: ["task_id", "steps"], readOnly: false),
            tool("set_personal_todo_done", "Set personal to-do completion",
                 "Complete or reopen a personal to-do using its task_id." + changes,
                 ["task_id": ["type": "string", "format": "uuid"], "done": ["type": "boolean"]],
                 required: ["task_id", "done"], readOnly: false),
            tool("record_energy", "Record energy",
                 "Record today's energy level. A new value replaces today's earlier one." + changes,
                 ["level": ["type": "string", "enum": ["empty", "low", "mid", "high", "full"]]],
                 required: ["level"], readOnly: false),
            tool("check_in_experiment", "Experiment check-in",
                 "Record today's check-in for the running 7-day experiment. One check-in per day." + changes,
                 ["outcome": ["type": "string", "enum": ["held", "slipped"]]],
                 required: ["outcome"], readOnly: false)
        ]
    }

    static func attentionSummary(_ journal: Journal, days: Int, now: Date) -> [String: Any] {
        let categories = ["Activity", "People", "AI", "Messages", "Work", "Streaming", "News", "Feed"]
        let moments = journal.moments.map { original in
            var moment = original
            if !categories.contains(moment.kind) { moment.kind = "Other" }
            return moment
        }
        let summary = ReflectionSummary(moments, day: now, days: days)
        let groups: [[String: Any]] = summary.kinds.map {
            ["category": $0.name, "count": $0.count, "averageAftertaste": $0.average]
        }
        return success([
            "days": days,
            "loggedMoments": summary.moments.count,
            "neutralOrBetterPercent": summary.alignment.map { $0 as Any } ?? NSNull(),
            "aftertasteScale": "−2 (drained) to +2 (nourished)",
            "categories": groups
        ])
    }

    static func planSummary(_ journal: Journal, now: Date) -> [String: Any] {
        let today = CalendarDay.key(now)
        let tasks = journal.tasks.filter { $0.occurs(on: now) }
        let completed = journal.completions[today] ?? []
        return success([
            "day": today,
            "scheduledTasks": tasks.count,
            "completedTasks": tasks.filter { completed.contains($0.id) }.count,
            "energy": journal.energy[today].map(\.level)
                .flatMap { ["empty", "low", "mid", "high", "full"].contains($0) ? $0 as Any : nil } ?? NSNull(),
            "experimentCheckIns": journal.experiment.map { $0.checkins.count as Any } ?? NSNull(),
            "experimentReviewReady": journal.experiment?.readyToReview ?? false
        ])
    }

    static func success(_ data: [String: Any]) -> [String: Any] {
        guard let bytes = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys) else {
            return failure("Could not prepare the Glimmer result.")
        }
        return ["content": [["type": "text", "text": String(decoding: bytes, as: UTF8.self)]]]
    }

    static func failure(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }
}

/// The last agent that connected and the last tool it used, shown in Settings → Agent access.
struct AgentActivity: Codable, Equatable {
    var client: String?
    var clientDate: Date?
    var tool: String?
    var toolDate: Date?

    static func read(in directory: URL) -> AgentActivity? {
        guard let data = try? Data(contentsOf: directory.appending(path: AgentAccess.activityFile)) else { return nil }
        return try? JSONDecoder().decode(AgentActivity.self, from: data)
    }

    func write(in directory: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: directory.appending(path: AgentAccess.activityFile), options: .atomic)
    }
}
#endif
