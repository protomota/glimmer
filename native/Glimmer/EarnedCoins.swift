import SwiftUI

struct EarnedCoins: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
}

struct EarnedCoinsToast: View {
    let award: EarnedCoins
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var settled = false

    var body: some View {
        HStack(spacing: 9) {
            CoinMark(size: 24)
                .scaleEffect(settled || reduceMotion ? 1 : 1.14)
                .offset(y: settled || reduceMotion ? 0 : -7)
                .opacity(settled || reduceMotion ? 1 : 0)
                .task {
                    guard !reduceMotion else { return }
                    try? await Task.sleep(for: .milliseconds(24))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.42, bounce: 0.18)) { settled = true }
                }
            Text("+\(award.amount)").font(.callout.monospacedDigit().weight(.semibold))
            Text("coins earned").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .glimmerGlass(.capsule, tint: GlimmerColor.honey.opacity(0.40))
        .shadow(color: .black.opacity(0.09), radius: 8, y: 3)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(award.amount) coins earned")
        .accessibilityIdentifier("earnedCoins")
    }
}
