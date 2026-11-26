import SwiftUI

/// A month grid uses Glimmer's selection and focus colors on every supported platform.
struct GlimmerCalendarGrid: View {
    @Binding var selection: Date
    var latestDay: Date? = nil
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.readingTheme) private var theme
    @State private var displayedMonth: Date?
    @FocusState private var focusedDay: Date?

    private var month: Date { displayedMonth ?? monthStart(selection) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 2), count: 7) }

    private var weekdayNames: [String] {
        var localized = calendar
        localized.locale = locale
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let cells = Array<Date?>(repeating: nil, count: leading)
            + range.map { calendar.date(byAdding: .day, value: $0 - range.lowerBound, to: month) }
        return cells + Array<Date?>(repeating: nil, count: max(0, 42 - cells.count))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(month.formatted(.dateTime.month(.wide).year().locale(locale)))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("calendar.month")
                Spacer(minLength: 4)
                if month != monthStart(.now) {
                    Button("Today") { displayedMonth = monthStart(.now) }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.selectionInk)
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                }
                arrow(-1, title: "Previous month", glyph: "chevron.left", enabled: true)
                arrow(1, title: "Next month", glyph: "chevron.right", enabled: latestDay.map { month < monthStart($0) } ?? true)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdayNames.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date { day(date) } else { Color.clear.frame(minHeight: 34).accessibilityHidden(true) }
                }
            }
        }
    }

    private func arrow(_ step: Int, title: String, glyph: String, enabled: Bool) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: step, to: month) { displayedMonth = next }
        } label: {
            Label(title, systemImage: glyph).labelStyle(.iconOnly).font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? theme.selectionInk : Color.secondary.opacity(0.45))
                .frame(width: 42, height: 42)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func day(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let isEnabled = latestDay.map { date <= $0 } ?? true
        return Button {
            selection = date
        } label: {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.callout.monospacedDigit().weight(isSelected ? .semibold : .medium))
                Circle()
                    .frame(width: 3, height: 3)
                    .opacity(isToday ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isSelected ? theme.selectionOnInk : isEnabled ? Color.primary : Color.secondary.opacity(0.58))
            .frame(width: 32, height: 32)
            .background(isSelected ? theme.selectionInk : Color.clear, in: .circle)
            .overlay {
                Circle().strokeBorder(focusedDay == date ? theme.selectionInk : .clear, lineWidth: 2)
                    .padding(-3)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($focusedDay, equals: date)
        .focusEffectDisabled()
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
