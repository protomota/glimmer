import SwiftUI
#if os(macOS)
import AppKit
#endif

// Things you touch answer like objects: they give under a finger, settle with a little spring,
// and confirm with a tap you can feel. Every check-off in the app uses the pieces in this file.

// MARK: - Tick

private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.18))
        return path
    }
}

/// The one check mark used across Glimmer. Checking it fills the ring with a soft spring, draws the
/// check as a stroke and lets a ring of light leave it. Unchecking is quick and plain.
struct Tick: View {
    let done: Bool
    var size: CGFloat = 26
    var tint: Color = GlimmerColor.sage
    /// The colour of the check drawn on `tint`.
    var onTint: Color = Color(light: "ffffff", dark: "1c1c1b")
    var ripples = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var ripple = 0

    var body: some View {
        ZStack {
            if ripples && !reduceMotion {
                Circle().stroke(tint, lineWidth: 1.5)
                    .phaseAnimator([0, 1, 2], trigger: ripple) { ring, phase in
                        ring.scaleEffect(phase == 1 ? 1 : 2).opacity(phase == 1 ? 0.55 : 0)
                    } animation: { phase in phase == 2 ? .easeOut(duration: 0.5) : nil }
            }
            Circle().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0.42), lineWidth: 1.5)
                .opacity(done ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: done)
            Circle().fill(tint)
                .scaleEffect(done ? 1 : 0.3).opacity(done ? 1 : 0)
                .animation(fill, value: done)
            CheckStroke().trim(from: 0, to: done ? 1 : 0)
                .stroke(onTint, style: StrokeStyle(lineWidth: max(1.8, size * 0.085), lineCap: .round, lineJoin: .round))
                .padding(size * 0.29)
                .animation(stroke, value: done)
        }
        .frame(width: size, height: size)
        .onChange(of: done) { _, now in if now { ripple += 1 } }
        .accessibilityHidden(true)
    }

    private var fill: Animation {
        guard done else { return .easeOut(duration: 0.12) }
        return reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.42)
    }

    private var stroke: Animation {
        guard done, !reduceMotion else { return .easeOut(duration: 0.12) }
        return .easeOut(duration: 0.26).delay(0.1)
    }
}

/// A control gives a little under the finger and springs back.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : .spring(duration: 0.4, bounce: 0.5),
                       value: configuration.isPressed)
    }
}

/// A row lights softly under the finger, so the whole line reads as touchable.
struct RowPressStyle: ButtonStyle {
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0), in: .rect(cornerRadius: radius, style: .continuous))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
    }
}

private struct TickFeedback: ViewModifier {
    let done: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sensoryFeedback(trigger: done) { _, now in
            now ? .success : .impact(flexibility: .soft, intensity: 0.6)
        }
        #else
        content.onChange(of: done) { _, now in
            if now { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
        #endif
    }
}

extension View {
    /// The feel of a check-off: a success tap on iPhone and iPad, a trackpad click on Mac.
    func tickFeedback(_ done: Bool) -> some View { modifier(TickFeedback(done: done)) }
}

/// The tick as a button, with a full 44 point target on the leading edge of a row.
struct TickButton: View {
    let done: Bool
    /// What VoiceOver says, such as "Complete Drink some water".
    let label: String
    var size: CGFloat = 26
    var tint: Color = GlimmerColor.sage
    var onTint: Color = Color(light: "ffffff", dark: "1c1c1b")
    /// False when the tick only includes or selects something, so it gets a lighter tap.
    var completes = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Tick(done: done, size: size, tint: tint, onTint: onTint, ripples: completes)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle(scale: 0.8))
        .accessibilityLabel(label)
        .tickFeedback(completes && done)
        .sensoryFeedback(.selection, trigger: done) { _, _ in !completes }
    }
}

/// An empty, dashed tick that opens a list for a new line.
struct AddMark: View {
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: "plus").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background { Circle().strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3.5])) }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }
}

// MARK: - Habit stones

private struct RingArc: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

/// Seven arcs around a stone, one for each of the last seven days. The last arc is today.
private struct WeekRing: View {
    let week: [Bool]
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let width: CGFloat = 4
    private let gap = 9.0

    var body: some View {
        let span = 360.0 / Double(week.count)
        ZStack {
            ForEach(week.indices, id: \.self) { index in
                let arc = RingArc(start: -90 + span * Double(index) + gap / 2, end: -90 + span * Double(index + 1) - gap / 2)
                arc.stroke(Color.primary.opacity(0.11), style: StrokeStyle(lineWidth: width, lineCap: .round))
                arc.trim(from: 0, to: week[index] ? 1 : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .opacity(week[index] ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.34), value: week[index])
            }
        }
        .padding(width / 2)
    }
}

/// A habit you press like a smooth stone. Its rim is the week: pressing it lights today's arc,
/// the icon hops, and a ring of light leaves the stone.
struct HabitStone: View {
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let name: String
    /// The last seven days, oldest first. The last entry is today.
    let week: [Bool]
    var size: CGFloat = 78
    var action: () -> Void
    @State private var pulse = 0

    private var done: Bool { week.last == true }
    private var days: Int { week.filter { $0 }.count }
    private var tint: Color { days == week.count ? GlimmerColor.honey : GlimmerColor.sage }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                stone
                Text(name).font(.footnote.weight(.medium))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.center).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .tickFeedback(done)
        .onChange(of: done) { _, now in if now { pulse += 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(done ? "Done today" : "Not done today"), \(days) of the last 7 days")
        .accessibilityAddTraits([.isButton, .isToggle])
    }

    private var stone: some View {
        ZStack {
            if !reduceMotion {
                Circle().stroke(tint, lineWidth: 2)
                    .phaseAnimator([0, 1, 2], trigger: pulse) { ring, phase in
                        ring.scaleEffect(phase == 1 ? 1 : 1.5).opacity(phase == 1 ? 0.5 : 0)
                    } animation: { phase in phase == 2 ? .easeOut(duration: 0.6) : nil }
            }
            Circle().fill(theme.surface)
                .shadow(color: .black.opacity(theme == .glimmer ? 0.35 : 0.10), radius: 5, y: 2)
            Circle().fill(tint.opacity(done ? 0.17 : 0))
                .animation(.easeOut(duration: 0.3), value: done)
            WeekRing(week: week, tint: tint)
            Image(systemName: Glyph.symbol(icon: icon, name: name, category: "habit"))
                .font(.system(size: size * 0.3, weight: .semibold)).symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .keyframeAnimator(initialValue: 1.0, trigger: pulse) { glyph, scale in
                    glyph.scaleEffect(reduceMotion ? 1 : scale)
                } keyframes: { _ in
                    SpringKeyframe(1.28, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy(extraBounce: 0.2))
                }
            Tick(done: done, size: 22, tint: tint, ripples: false)
                .background { Circle().fill(theme.canvas).padding(-2).opacity(done ? 1 : 0) }
                .opacity(done ? 1 : 0)
                .offset(x: size * 0.34, y: size * 0.34)
        }
        .frame(width: size, height: size)
    }
}
