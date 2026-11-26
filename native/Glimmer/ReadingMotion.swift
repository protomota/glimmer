import SwiftUI

/// A single stroke laps a completed item, then its timeline ends.
private struct CompletionLight<Outline: InsettableShape>: ViewModifier {
    var complete: Bool
    let outline: Outline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = 0

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                Color.clear.keyframeAnimator(initialValue: 1.0, trigger: pulse) { _, phase in
                    let tail = max(0, phase * 1.18 - 0.18)
                    let head = min(1, phase * 1.18)
                    outline.inset(by: 0.8).trim(from: tail, to: head)
                        .stroke(GlimmerColor.accent.opacity(0.82), style: .init(lineWidth: 1.3, lineCap: .round))
                } keyframes: { _ in
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0, duration: 0.72)
                }
                .opacity(complete ? 1 : 0)
                .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .onChange(of: complete) { _, done in if done && !reduceMotion { pulse += 1 } }
    }
}

/// Finite depth change when an editorial surface takes its place.
private struct ReadingArrival: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(settled || reduceMotion ? 0 : -3), axis: (1, 0, 0), anchor: .bottom)
            .offset(y: settled || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.65).delay(delay)) { settled = true }
            }
    }
}

extension View {
    func completionLight(_ completed: Bool, radius: CGFloat = 14) -> some View {
        completionLight(completed, outline: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func completionLight(_ completed: Bool, outline: some InsettableShape) -> some View {
        modifier(CompletionLight(complete: completed, outline: outline))
    }

    func readingArrival(delay: Double = 0) -> some View { modifier(ReadingArrival(delay: delay)) }
}

/// The depth of the orbit changes the radius and brightness of each point.
struct ReflectionOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scene
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || scene != .active)) { clock in
            let angle = reduceMotion ? 0 : clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) * 2 * .pi / 3.6
            Canvas { context, size in
                let radius = min(size.width, size.height) * 0.40
                for index in 0..<16 {
                    let t = angle + Double(index) * .pi / 8
                    let depth = (sin(t) + 1) / 2
                    let diameter = 1.1 + depth * 1.7
                    let x = size.width / 2 + radius * cos(t)
                    let y = size.height / 2 + radius * (0.36 * sin(t) - 0.4 * cos(t))
                    let rect = CGRect(x: x - diameter/2, y: y - diameter/2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(GlimmerColor.sage.opacity(0.35 + depth * 0.65)))
                }
            }
            .overlay { Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(GlimmerColor.honey) }
        }.frame(width: 26, height: 26).accessibilityHidden(true)
    }
}

struct ChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        content.mask(alignment: .leading) {
            Rectangle().scaleEffect(x: revealed || reduceMotion ? 1 : 0.04, anchor: .leading)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { revealed = true }
        }
    }
}

/// Move the incoming sheet a few points above its final position. The underlying
/// paper and controls stay opaque throughout keyboard, pointer and touch navigation.
struct ReadingPageTurn: ViewModifier {
    let forward: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .offset(x: arrived || reduceMotion ? 0 : forward ? 14 : -14)
            .onAppear {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { arrived = true }
            }
    }
}

/// Mount once for layout, then reveal the contents. Closing reverses the reveal before collapsing.
struct ReadingDisclosure<Content: View>: View {
    let expanded: Bool
    @ViewBuilder let content: (Bool) -> Content
    @State private var mounted = false
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mounted {
                content(visible)
                    .accessibilityHidden(!expanded || !visible)
                    .allowsHitTesting(expanded && visible)
                    .modifier(DisclosureRowMotion(index: 0, count: 1, visible: visible))
                    .transition(.opacity)
            }
        }
        .task(id: expanded) {
            if reduceMotion {
                mounted = expanded
                visible = expanded
            } else if expanded {
                withAnimation(.smooth(duration: 0.28)) { mounted = true }
                try? await Task.sleep(for: .milliseconds(30))
                if !Task.isCancelled { visible = true }
            } else if mounted {
                visible = false
                try? await Task.sleep(for: .milliseconds(190))
                if !Task.isCancelled {
                    withAnimation(.smooth(duration: 0.19)) { mounted = false }
                }
            }
        }
    }
}

struct DisclosureRowMotion: ViewModifier {
    let index: Int
    let count: Int
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timing: Animation {
        if visible { return .easeOut(duration: 0.23).delay(Double(min(index, 5)) * 0.044) }
        return .easeOut(duration: 0.10).delay(Double(min(max(count - index - 1, 0), 5)) * 0.016)
    }

    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : -5)
            .animation(reduceMotion ? nil : timing, value: visible)
    }
}

struct GlimmerDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: configuration.isExpanded)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            ReadingDisclosure(expanded: configuration.isExpanded) { _ in configuration.content }
        }
    }
}
