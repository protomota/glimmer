import SwiftUI

/// Coins rise from both bottom corners, then settle among brief glints.
/// It is decoration only and never intercepts touches.
struct CoinBurst: View {
    let startedAt: Date
    let amount: Int
    static let duration = 2.2

    private static func variation(_ index: Int, _ channel: Int) -> Double {
        let value = sin(Double(index * 73 + channel * 193) * 12.9898) * 43758.5453
        return value - floor(value)
    }

    private struct Flight {
        let fromLeft: Bool
        let delay: Double
        let duration: Double
        let startX: Double
        let startY: Double
        let drift: Double
        let rise: Double
        let radius: Double
        let phase: Double
        let turn: Double
    }

    private static let basePairs = 22
    private static let maxExtraPairs = 8
    private static let maxDensity = 2.10

    // Set up the particles once so frame updates only advance their motion.
    private static let flights = (0..<(2 * (Int((Double(basePairs) * maxDensity).rounded()) + maxExtraPairs))).map { index in
        let fromLeft = index.isMultiple(of: 2)
        return Flight(
            fromLeft: fromLeft,
            delay: variation(index, 1) * 0.34 + (fromLeft ? 0 : 0.055),
            duration: 1.37 + variation(index, 2) * 0.40,
            startX: 0.018 + variation(index, 3) * 0.051,
            startY: 0.95 + variation(index, 6) * 0.085,
            drift: 0.25 + variation(index, 4) * 0.37,
            rise: 0.37 + variation(index, 5) * 0.46,
            radius: 6.5 + pow(variation(index, 8), 1.35) * 6,
            phase: variation(index, 11) * 2 * .pi,
            turn: 0.33 + variation(index, 10) * 0.60
        )
    }

    private static let outline = CGRect(x: -1, y: -1, width: 2, height: 2)
    private static let rimPath = Path(ellipseIn: outline)
    private static let facePath = Path(ellipseIn: outline.insetBy(dx: 0.16, dy: 0.16))
    private static let ringPath = Path(ellipseIn: outline.insetBy(dx: 0.34, dy: 0.34))

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let shortEdge = min(size.width, size.height)
                let particleScale = min(1.55, max(0.80, sqrt(shortEdge / 398)))
                let densityScale = min(Self.maxDensity, max(1, sqrt(size.width * size.height / 342_000)))
                drawCoins(context, size: size, elapsed: elapsed, scale: particleScale, density: densityScale)
                drawGlints(context, size: size, elapsed: elapsed, scale: particleScale, density: densityScale)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawCoins(_ context: GraphicsContext, size: CGSize, elapsed: Double, scale: Double, density: Double) {
        let face = Color(red: 0.95, green: 0.76, blue: 0.29)
        let rim = Color(red: 0.85, green: 0.63, blue: 0.18)
        let shine = Color(red: 1, green: 0.92, blue: 0.67).opacity(0.72)
        let addedPairs = min(Self.maxExtraPairs, max(0, amount - 10) / 4)
        let count = 2 * (Int((Double(Self.basePairs) * density).rounded()) + addedPairs)
        for flight in Self.flights.prefix(count) {
            let age = elapsed - flight.delay
            let progress = age / flight.duration
            guard progress >= 0, progress < 1 else { continue }

            // Horizontal momentum keeps the coins moving through the top of the arc.
            let horizontal = flight.startX + flight.drift * age * (1 - 0.10 * age)
            let x = size.width * (flight.fromLeft ? horizontal : 1 - horizontal)
            let y = size.height * (flight.startY - flight.rise * 4 * progress * (1 - progress))
            let radius = flight.radius * scale
            let rock = sin(flight.phase + flight.turn * 2 * .pi * progress)

            var coin = context
            coin.opacity = min(1, progress * 12) * min(1, (1 - progress) * 4.5)
            coin.translateBy(x: x, y: y)
            coin.rotate(by: .radians(0.24 * rock))
            coin.scaleBy(x: radius * (0.83 + 0.16 * rock), y: radius)
            coin.fill(Self.rimPath, with: .color(rim))
            coin.fill(Self.facePath, with: .color(face))
            coin.stroke(Self.ringPath, with: .color(shine), lineWidth: 0.10)
        }
    }

    private func drawGlints(_ context: GraphicsContext, size: CGSize, elapsed: Double, scale: Double, density: Double) {
        for index in 0..<Int((14 * density).rounded()) {
            let age = elapsed - (0.25 + Self.variation(index, 12) * 0.85)
            let lifetime = 0.35 + Self.variation(index, 13) * 0.10
            guard age >= 0, age < lifetime else { continue }
            let shimmer = sin(age / lifetime * .pi)
            let radius = (4 + Self.variation(index, 16) * 3) * (0.4 + 0.6 * shimmer) * scale
            var path = Path()
            for point in 0..<8 {
                let angle = Double(point) * .pi / 4 - .pi / 2
                let distance = point.isMultiple(of: 2) ? radius : radius * 0.22
                let position = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
                if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
            path.closeSubpath()
            var glint = context
            glint.opacity = shimmer
            glint.translateBy(x: size.width * (0.08 + Self.variation(index, 14) * 0.84), y: size.height * (0.13 + Self.variation(index, 15) * 0.65))
            glint.rotate(by: .degrees((age / lifetime - 0.5) * 20))
            glint.fill(path, with: .color(Color(red: 1, green: 0.93, blue: 0.66)))
            glint.stroke(path, with: .color(Color(red: 0.91, green: 0.73, blue: 0.29)), lineWidth: 0.8)
        }
    }
}
