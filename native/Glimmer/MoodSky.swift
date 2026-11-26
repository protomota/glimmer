import SwiftUI

/// One colour of the sky, kept as components so the weather can blend between moods.
private struct Tone {
    let r: Double, g: Double, b: Double

    init(_ hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        r = Double((value >> 16) & 255) / 255
        g = Double((value >> 8) & 255) / 255
        b = Double(value & 255) / 255
    }

    /// The colour at `position` (0...1) along evenly spaced stops.
    static func blend(_ stops: [Tone], at position: Double) -> Color {
        let scaled = min(1, max(0, position)) * Double(stops.count - 1)
        let lower = min(stops.count - 2, Int(scaled))
        let mix = scaled - Double(lower)
        let a = stops[lower], b = stops[lower + 1]
        return Color(red: a.r + (b.r - a.r) * mix, green: a.g + (b.g - a.g) * mix, blue: a.b + (b.b - a.b) * mix)
    }
}

/// The colours of the five moods, from rain to a clear golden sky.
private struct SkyPalette {
    let top: [Tone], bottom: [Tone], cloud: [Tone], sun: [Tone]

    static let day = SkyPalette(
        top: ["6F7C8C", "93A0AD", "8FB3D3", "74AEDF", "5FA6E4"].map(Tone.init),
        bottom: ["A5AEB8", "C6CCD2", "D5E3EC", "F1E3C6", "FADD9F"].map(Tone.init),
        cloud: ["5D6875", "A9B2BC", "F2F5F7", "FFFFFF", "FFFFFF"].map(Tone.init),
        sun: ["E6E3DC", "EFEADB", "F7DC9A", "F8CB62", "FBC23F"].map(Tone.init))

    static let night = SkyPalette(
        top: ["20252C", "2A313A", "27384C", "264566", "264E7A"].map(Tone.init),
        bottom: ["353B44", "444C56", "4B5C72", "7F6E52", "A8873F"].map(Tone.init),
        cloud: ["171B21", "39414B", "8795A6", "B9C4D1", "C8D2DE"].map(Tone.init),
        sun: ["8D9299", "A9A9A2", "DCC68D", "ECC566", "F5C453"].map(Tone.init))
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let puffs: [(x: Double, y: Double, w: Double, h: Double)] = [
            (0.00, 0.46, 0.46, 0.54), (0.20, 0.14, 0.42, 0.74), (0.46, 0.00, 0.36, 0.80), (0.62, 0.34, 0.38, 0.66),
        ]
        for puff in puffs {
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * puff.x, y: rect.minY + rect.height * puff.y,
                                       width: rect.width * puff.w, height: rect.height * puff.h))
        }
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.62,
                                       width: rect.width * 0.72, height: rect.height * 0.38),
                            cornerSize: CGSize(width: rect.height * 0.19, height: rect.height * 0.19))
        return path
    }
}

/// Today's mood as a small sky. Drag the sun: rain thins to cloud, cloud parts, and the light warms.
/// It lands on one of five moods, with a tick you can feel at each one.
struct MoodSky: View {
    static let words = ["Low", "Off", "Okay", "Good", "Great"]

    /// 1...5, or nil when today has no mood yet.
    let mood: Int?
    var onChange: (Int?) -> Void

    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var position = 0.5
    @State private var moved = false
    @GestureState private var dragging = false

    private var step: Int { Int((position * 4).rounded()) }
    private var isSet: Bool { mood != nil || moved }
    private var palette: SkyPalette { theme == .glimmer ? .night : .day }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in sky(proxy.size) }
                .frame(height: 168)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .padding(4)
            footer.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        }
        .background(theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.30 : 0.08), lineWidth: 1)
        }
        .onAppear { if let mood { position = Double(mood - 1) / 4 } }
        .onChange(of: mood) { _, new in
            guard !dragging else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                if let new { position = Double(new - 1) / 4 } else { position = 0.5; moved = false }
            }
        }
        .onChange(of: dragging) { _, active in if !active && moved { settle() } }
        .sensoryFeedback(.selection, trigger: step) { _, _ in moved }
        .sensoryFeedback(.impact(weight: .light), trigger: dragging) { _, active in !active }
    }

    // MARK: Sky

    private func sky(_ size: CGSize) -> some View {
        let light = isSet ? position : 0.5
        let sun = sunPoint(size, at: position)
        return ZStack {
            LinearGradient(colors: [Tone.blend(palette.top, at: light), Tone.blend(palette.bottom, at: light)],
                           startPoint: .top, endPoint: .bottom)
            track(size)
            // The light the sun throws grows as the sky clears.
            Circle()
                .fill(RadialGradient(colors: [Tone.blend(palette.sun, at: light).opacity(0.25 + 0.45 * light), .clear],
                                     center: .center, startRadius: 0, endRadius: 60 + 80 * light))
                .frame(width: 320, height: 320)
                .position(sun)
            glints(size, sun: sun).opacity(isSet ? fade(light, from: 0.82, to: 1) : 0)
            sunDisc(light).position(sun)
            clouds(size, light: light)
            rain(size).opacity(isSet ? 1 - fade(light, from: 0.04, to: 0.26) : 0)
        }
        .saturation(isSet ? 1 : 0.35)
        .contentShape(.rect)
        .onTapGesture(coordinateSpace: .local) { point in
            moved = true
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25)) { position = fraction(point.x, size.width) }
            settle()
        }
        // Runs beside the page's scrolling, so a vertical swipe that starts on the sky still scrolls.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .updating($dragging) { value, active, _ in
                    if abs(value.translation.width) >= abs(value.translation.height) || active { active = true }
                }
                .onChanged { value in
                    guard dragging || abs(value.translation.width) >= abs(value.translation.height) else { return }
                    moved = true
                    position = fraction(value.location.x, size.width)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today’s mood")
        .accessibilityValue(isSet ? Self.words[step] : "Not set")
        .accessibilityHint("Swipe up or down to change")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("habits.mood")
        #if os(macOS)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .right, .up: move(by: 1)
            case .left, .down: move(by: -1)
            @unknown default: break
            }
        }
        #endif
    }

    /// The path the sun travels, with a stop for each mood.
    private func track(_ size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.move(to: sunPoint(size, at: 0))
                for index in 1...40 { path.addLine(to: sunPoint(size, at: Double(index) / 40)) }
            }
            .stroke(Color.white.opacity(0.38), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 6]))
            ForEach(0..<5) { stop in
                Circle().fill(Color.white.opacity(isSet && stop == step ? 0 : 0.7))
                    .frame(width: 5, height: 5)
                    .position(sunPoint(size, at: Double(stop) / 4))
            }
        }
        .accessibilityHidden(true)
    }

    private func sunDisc(_ light: Double) -> some View {
        let color = Tone.blend(palette.sun, at: light)
        return ZStack {
            Circle().fill(color)
                .shadow(color: color.opacity(0.9), radius: 6 + 12 * light)
            Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1.5)
        }
        .frame(width: 38, height: 38)
        .scaleEffect(dragging ? 1.18 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.45), value: dragging)
    }

    private func clouds(_ size: CGSize, light: Double) -> some View {
        let color = Tone.blend(palette.cloud, at: light)
        let heavy = 1 - fade(light, from: 0.05, to: 0.45)
        return ZStack {
            // A grey lid over the whole sky on the lowest days.
            Rectangle().fill(color).opacity(heavy * 0.5)
            CloudShape().fill(color)
                .frame(width: size.width * 0.62, height: 74)
                .position(x: size.width * (0.36 - 0.22 * light), y: size.height * 0.34)
                .opacity(0.94 * (1 - fade(light, from: 0.55, to: 0.95)))
            CloudShape().fill(color)
                .frame(width: size.width * 0.52, height: 62)
                .position(x: size.width * (0.72 + 0.30 * light), y: size.height * 0.50)
                .opacity(0.9 * (1 - fade(light, from: 0.35, to: 0.72)))
            CloudShape().fill(color)
                .frame(width: size.width * 0.30, height: 34)
                .position(x: size.width * (0.20 + 0.10 * light), y: size.height * 0.74)
                .opacity(0.7 * (1 - fade(light, from: 0.62, to: 0.98)))
        }
        .blur(radius: 5)
        .allowsHitTesting(false)
    }

    private func rain(_ size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isSet || position > 0.27)) { timeline in
            Canvas { context, canvas in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for drop in 0..<26 {
                    let seed = Double(drop)
                    let column = (seed * 0.6180339887).truncatingRemainder(dividingBy: 1)
                    let speed = 0.55 + (seed * 0.37).truncatingRemainder(dividingBy: 1) * 0.4
                    let fall = (time * speed + seed * 0.173).truncatingRemainder(dividingBy: 1)
                    let x = canvas.width * (column * 1.1 - 0.05) - fall * 14
                    let y = canvas.height * (0.42 + fall * 0.62)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 3, y: y + 11))
                    context.stroke(path, with: .color(.white.opacity(0.5 * sin(fall * .pi))),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A few small glints around the sun on the brightest days.
    private func glints(_ size: CGSize, sun: CGPoint) -> some View {
        Canvas { context, _ in
            let spots: [(x: Double, y: Double, r: Double)] = [(-74, 18, 5), (-44, -34, 3.5), (30, 52, 4), (-104, -18, 3)]
            for spot in spots {
                var path = Path()
                for point in 0..<8 {
                    let angle = Double(point) * .pi / 4 - .pi / 2
                    let distance = point.isMultiple(of: 2) ? spot.r : spot.r * 0.24
                    let corner = CGPoint(x: sun.x + spot.x + cos(angle) * distance, y: sun.y + spot.y + sin(angle) * distance)
                    if point == 0 { path.move(to: corner) } else { path.addLine(to: corner) }
                }
                path.closeSubpath()
                context.fill(path, with: .color(.white.opacity(0.9)))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today’s mood").font(.caption).foregroundStyle(.secondary)
                Text(isSet ? Self.words[step] : "How does today feel?")
                    .font(GlimmerFont.reading(.title2, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .id(isSet ? step : -1)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isSet)
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            if mood != nil {
                Button("Clear") {
                    moved = false
                    onChange(nil)
                }
                .buttonStyle(.plain).font(.footnote).foregroundStyle(.secondary)
                .frame(minHeight: 30).contentShape(.rect)
                .accessibilityLabel("Clear today’s mood")
            } else {
                Text("Drag the sun").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    // MARK: Geometry

    private func sunPoint(_ size: CGSize, at position: Double) -> CGPoint {
        let rise = 1 - pow(1 - position, 2)
        return CGPoint(x: size.width * (0.13 + 0.74 * position), y: size.height * (0.74 - 0.44 * rise))
    }

    private func fraction(_ x: CGFloat, _ width: CGFloat) -> Double {
        min(1, max(0, (x / max(1, width) - 0.13) / 0.74))
    }

    /// 0 below `from`, 1 above `to`, and a straight ramp between.
    private func fade(_ value: Double, from: Double, to: Double) -> Double {
        min(1, max(0, (value - from) / (to - from)))
    }

    private func settle() {
        let landed = step
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.35)) { position = Double(landed) / 4 }
        if mood != landed + 1 { onChange(landed + 1) }
    }

    private func move(by amount: Int) {
        let next = isSet ? min(4, max(0, step + amount)) : 2
        moved = true
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3)) { position = Double(next) / 4 }
        if mood != next + 1 { onChange(next + 1) }
    }
}
