import SwiftUI

struct LessonsView: View {
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        let open = catalog.lessons.filter { store.journal.lessonIsOpen($0.number, on: store.day) }
        let plan = catalog.lessons
        let completed = plan.filter { store.journal.lessons[$0.id]?.completed == true }.count
        Page(title: "Lessons", subtitle: "One lesson unlocks each day, and they deepen as you go. After day 90, the Deep Path begins. Come back to any you’ve reached.", width: 900) {
            let featured = open.first(where: { store.journal.lessons[$0.id]?.completed != true }) ?? open.last
            if let featured {
                Panel(padding: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            Artwork(slot: featured.number, height: 220).frame(maxWidth: 380)
                            featuredText(featured, completed: completed, total: plan.count)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Artwork(slot: featured.number, height: 190)
                            featuredText(featured, completed: completed, total: plan.count)
                        }
                    }
                }
            }
            let remaining = open.filter { $0.id != featured?.id }
            let arcs = remaining.reduce(into: [String]()) { if !$0.contains($1.arc) { $0.append($1.arc) } }
            ForEach(arcs, id: \.self) { arc in
                Panel(title: arc, plain: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(remaining.filter { $0.arc == arc }) { lesson in
                            NavigationLink { LessonReader(lesson: lesson) } label: {
                                HStack(spacing: 14) {
                                    Artwork(slot: lesson.number, height: 44, corner: 7).frame(width: 66).accessibilityHidden(true)
                                    VStack(alignment: .leading) {
                                        Text(lesson.title).font(.headline)
                                        Text("Day \(lesson.number) · \(lesson.minutes) min").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if store.journal.lessons[lesson.id]?.completed == true { Image(systemName: "checkmark").accessibilityLabel("Completed") }
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            if open.count < catalog.lessons.count {
                Label("\(catalog.lessons.count - open.count) more lessons unlock one day at a time.", systemImage: "lock.open")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func featuredText(_ lesson: Lesson, completed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Your reading plan · \(completed) of \(total) complete", color: GlimmerColor.dusk)
            Meter(value: Double(completed) / Double(max(1, total)), tint: GlimmerColor.dusk)
            Text(lesson.title).font(GlimmerFont.display(.title2, weight: .bold))
            Text(lesson.tagline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            NavigationLink(store.journal.lessons[lesson.id]?.completed == true ? "Read again" : "Read lesson") { LessonReader(lesson: lesson) }
                .glimmerButton(.prominent)
        }
    }

}

struct LessonReader: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lesson: Lesson
    @State private var forward = true
    @State private var index = 0

    var body: some View {
        if !lesson.pages.isEmpty && store.journal.lessonIsOpen(lesson.number, on: store.day) {
            let page = lesson.pages[index]
            let last = index == lesson.pages.count - 1
            Page(title: page.title, kicker: "Day \(lesson.number) · \(lesson.title)", width: 680) {
                StepDots(current: index, total: lesson.pages.count)
                if index == 0 { Artwork(slot: lesson.number, height: 240) }
                if page.body != nil || page.tryToday != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        GlyphTile(Glyph.symbol(icon: page.emoji, name: page.title), tint: GlimmerColor.dusk, size: 44)
                        if let body = page.body {
                            ForEach(Array(body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                Text(markdown(paragraph)).font(GlimmerFont.reading(.title3)).lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let tryToday = page.tryToday, page.body?.contains(tryToday) != true {
                            Label(tryToday, systemImage: "lightbulb").font(.callout.weight(.medium))
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(GlimmerColor.honey.opacity(0.12), in: .rect(cornerRadius: 14))
                        }
                    }
                }
                if let question = page.question {
                    Panel(title: "Reflect", accent: GlimmerColor.dusk) {
                        if page.body == nil { GlyphTile(Glyph.symbol(icon: page.emoji, name: page.title), tint: GlimmerColor.dusk, size: 48) }
                        Text(question).font(GlimmerFont.display(.title3, weight: .bold))
                        VStack(spacing: 8) {
                            ForEach(page.options ?? [], id: \.self) { option in
                                SelectRow(label: option, selected: currentChoice == option, tint: GlimmerColor.dusk) {
                                    store.change { $0.lessons[lesson.id, default: LessonRecord()].choices[String(index)] = option }
                                }
                            }
                        }
                        .glassGroup(spacing: 8)
                    }
                }
            }
            .id(index)
            .transition(.identity)
            .modifier(ReadingPageTurn(forward: forward))
            .actionBar(width: 680) {
                if index > 0 {
                    GlassIconButton(label: "Previous page", systemImage: "chevron.left") { move(index - 1) }
                }
                PrimaryAction(title: last ? "Complete lesson" : "Next page", systemImage: last ? "checkmark" : nil) {
                    if last {
                        let first = store.journal.lessons[lesson.id]?.completed != true
                        let previous = store.catalog.map { ReaderProgress(journal: store.journal, catalog: $0).rank }
                        if store.change({ $0.completeLesson(lesson, on: store.day) }) {
                            if !first { store.notice = "Lesson complete." }
                            if let catalog = store.catalog {
                                let rank = ReaderProgress(journal: store.journal, catalog: catalog).rank
                                if first && rank != previous {
                                    let text = "\(rank.rawValue) unlocked"
                                    store.notice = text
                                    AccessibilityNotification.Announcement(text).post()
                                }
                            }
                            dismiss()
                        }
                    } else { move(index + 1) }
                }
                .disabled(page.kind == "stop" && currentChoice == nil)
            }
            .hidesTabBar()
            .onAppear {
                let progress = store.journal.lessons[lesson.id]
                if progress?.completed != true { index = min(max(0, progress?.page ?? 0), lesson.pages.count - 1) }
            }
        }
    }

    private var currentChoice: String? { store.journal.lessons[lesson.id]?.choices[String(index)] }

    private func move(_ page: Int) {
        if store.change({ $0.lessons[lesson.id, default: LessonRecord()].page = page }) {
            forward = page > index
            index = page
        }
    }

    private func markdown(_ paragraph: String) -> AttributedString {
        (try? AttributedString(markdown: paragraph,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph)
    }
}
