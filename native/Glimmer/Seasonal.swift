import SwiftUI

struct SeasonalView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.readingTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedEdition: String?

    private var edition: SeasonalEdition? {
        let editions = store.seasonalEditions
        return editions.first { $0.id == selectedEdition }
            ?? editions.first { $0.isFeatured(on: store.day) }
            ?? editions.first
    }

    var body: some View {
        GeometryReader { viewport in
            let wide = viewport.size.width >= 650 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let edition {
                        if store.seasonalEditions.count > 1 {
                            Picker("Season", selection: Binding(
                                get: { selectedEdition ?? edition.id },
                                set: { selectedEdition = $0 }
                            )) {
                                ForEach(store.seasonalEditions) { Text($0.title).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                        }
                        header(edition)
                        editionContent(edition, wide: wide)
                            .id(edition.id)
                    } else {
                        Text("Seasonal guides will appear here as they’re added.")
                        NavigationLink("Cleaning & maintenance") {
                            if let catalog = store.catalog { CleaningView(catalog: catalog) }
                        }
                        .glimmerButton()
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Seasonal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background { PageBackdrop() }
        .tint(GlimmerColor.accent)
    }

    private func header(_ edition: SeasonalEdition) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(edition.title)
                .font(GlimmerFont.reading(.largeTitle, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            Text(edition.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.inset.opacity(theme == .glimmer ? 0.67 : 0.58))
        }
    }

    private func editionContent(_ edition: SeasonalEdition, wide: Bool) -> some View {
        let columns = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                           : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
        return VStack(alignment: .leading, spacing: 20) {
            reflections(edition, wide: wide)
            columns {
                checklists(edition).frame(maxWidth: .infinity, alignment: .topLeading)
                upkeep(edition).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func reflections(_ edition: SeasonalEdition, wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                          : AnyLayout(VStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 9) {
            heading("For now", icon: "sparkle", tint: GlimmerColor.ember)
            layout {
                ForEach(edition.tips) { tip in reflection(tip, wide: wide) }
            }
        }
    }

    private func reflection(_ tip: SeasonalEdition.Tip, wide: Bool) -> some View {
        NavigationLink {
            Page(title: tip.title, width: 660) {
                Text(tip.body)
                    .font(GlimmerFont.reading(.title3))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                GlyphTile(reflectionIcon(tip.id), tint: GlimmerColor.ember)
                VStack(alignment: .leading, spacing: 5) {
                    Text(tip.title).font(.callout.weight(.semibold))
                    Text(tip.summary).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: wide ? 96 : 70, alignment: .topLeading)
            .seasonalSurface(theme)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("seasonal.tip." + tip.id)
    }

    private func checklists(_ edition: SeasonalEdition) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("Short checklists", icon: "checklist", tint: GlimmerColor.sage)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(edition.checklists) { list in
                    SeasonalChecklist(list: list, progressKey: edition.progressKey(for: list, on: store.day))
                    if list.id != edition.checklists.last?.id { Divider().accessibilityHidden(true) }
                }
            }
            .padding(.horizontal, 10)
            .seasonalSurface(theme)
        }
    }

    @ViewBuilder private func upkeep(_ edition: SeasonalEdition) -> some View {
        let chores = edition.maintenance.compactMap { id in store.maintenanceChores.first { $0.id == id } }
        if !chores.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                heading("Around the house", icon: "house", tint: GlimmerColor.dusk)
                VStack(alignment: .leading, spacing: 10) {
                    MaintenanceChores(chores: chores, compact: true)
                    ForEach(edition.resources ?? []) { resource in
                        Link(destination: resource.url) {
                            Label(resource.title, systemImage: "arrow.up.right")
                                .font(.caption.weight(.medium))
                        }
                    }
                }
                .padding(11)
                .seasonalSurface(theme)
            }
        }
    }

    private func reflectionIcon(_ id: String) -> String {
        switch id {
        case "mixed-feelings": "circle.lefthalf.filled"
        case "threshold-pause": "door.left.hand.open"
        case "remember-someone": "flame"
        default: "lightbulb"
        }
    }

    private func heading(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title).font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    func seasonalSurface(_ theme: ReadingTheme) -> some View {
        background {
            RoundedRectangle(cornerRadius: 12).fill(theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

private struct SeasonalChecklist: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let list: SeasonalEdition.Checklist
    let progressKey: String

    var body: some View {
        let saved = store.journal.seasonalChecks?[progressKey] ?? []
        let complete = list.items.filter { saved.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    GlyphTile(icon, tint: GlimmerColor.sage)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.title).font(.callout.weight(.semibold))
                        if !expanded { Text(list.summary).font(.caption).foregroundStyle(.secondary) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    progressRing(complete)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 7)
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(complete) of \(list.items.count) done")
            .accessibilityIdentifier("seasonal.list." + list.id)
            .accessibilityHint(expanded ? "Collapse checklist" : "Expand checklist")

            ReadingDisclosure(expanded: expanded) { visible in
                VStack(spacing: 4) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, checked: saved.contains(item.id))
                            .modifier(DisclosureRowMotion(index: index, count: list.items.count, visible: visible))
                    }
                }
            }
        }
    }

    private var icon: String {
        switch list.id {
        case "make-room": "calendar.badge.clock"
        case "changing-routines": "suitcase"
        case "gentler-day": "cup.and.saucer"
        default: "checklist"
        }
    }

    private func progressRing(_ complete: Int) -> some View {
        let fraction = Double(complete) / Double(max(1, list.items.count))
        return HStack(spacing: 4) {
            ZStack {
                Circle().strokeBorder(.secondary.opacity(0.28), lineWidth: 1.5)
                Circle().trim(from: 0, to: fraction)
                    .stroke(GlimmerColor.sage, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            Text("\(complete)/\(list.items.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityHidden(true)
    }

    private func itemRow(_ item: SeasonalEdition.Checklist.Item, checked: Bool) -> some View {
        Button {
            store.change { $0.toggleSeasonalCheck(item.id, in: progressKey) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Tick(done: checked, size: 24)
                GlyphTile(Glyph.symbol(name: item.title, category: "seasonal"), tint: Glyph.tint(for: "seasonal"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.body.weight(.medium))
                        .foregroundStyle(checked ? Color.secondary : Color.primary)
                    Text(item.detail).font(.callout).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 5).padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
        .tickFeedback(checked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityValue(checked ? "Completed" : "Not completed")
        .accessibilityIdentifier("seasonal.check." + item.id)
    }
}

struct SeasonalRecommendation: View {
    @Environment(JournalStore.self) private var store
    let edition: SeasonalEdition
    let list: SeasonalEdition.Checklist
    let item: SeasonalEdition.Checklist.Item
    let showGuide: () -> Void

    var body: some View {
        let key = edition.progressKey(for: list, on: store.day)
        let checked = store.journal.seasonalChecks?[key]?.contains(item.id) == true
        VStack(alignment: .leading, spacing: 4) {
            Label(edition.title, systemImage: Destination.seasonal.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlimmerColor.honey)
                .accessibilityAddTraits(.isHeader)
            Button {
                store.change { $0.toggleSeasonalCheck(item.id, in: key) }
            } label: {
                HStack(spacing: 10) {
                    Tick(done: checked, size: 22)
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(checked ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(RowPressStyle())
            .tickFeedback(checked)
            .accessibilityValue(checked ? "Completed" : "Not completed")
            .accessibilityIdentifier("today.seasonal.check")

            if !checked, !item.detail.isEmpty {
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }

            Button(action: showGuide) {
                Text("See seasonal guide")
                    .font(.callout.weight(.medium))
                    .frame(minHeight: 44, alignment: .leading)
                    .padding(.leading, 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GlimmerColor.accent)
            .accessibilityIdentifier("today.seasonal")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(GlimmerColor.honey.opacity(0.32))
                .allowsHitTesting(false)
        }
    }
}
