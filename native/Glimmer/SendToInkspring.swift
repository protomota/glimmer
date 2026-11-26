import SwiftUI

/// A small button under today's quote that saves it as a post idea in Inkspring.
/// It only shows when Inkspring is installed, and checks again whenever Glimmer comes forward.
struct SendToInkspringButton: View {
    let quote: DailyQuote
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var installed = false
    @State private var sentQuoteID: String?
    @State private var launches = 0

    private var sent: Bool { sentQuoteID == quote.id }

    var body: some View {
        Group {
            if installed, let url = InkspringLink.newIdea(quote: quote.text, author: quote.author) {
                Button {
                    InkspringLink.open(url)
                    launches += 1
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { sentQuoteID = quote.id }
                } label: {
                    Label {
                        Text(sent ? "Sent to Inkspring" : "Send to Inkspring")
                    } icon: {
                        Image(systemName: sent ? "checkmark.circle.fill" : "paperplane.fill")
                            .symbolRenderingMode(.monochrome)
                            .fontWeight(.medium)
                            .foregroundStyle(GlimmerColor.accent)
                            .symbolEffect(.bounce.up, options: .nonRepeating, value: launches)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                    }
                }
                .glimmerButton()
                .controlSize(.small)
                .font(.callout)
                .help("Save today’s quote as a post idea in Inkspring")
                .accessibilityHint("Opens Inkspring with this quote as a new post idea")
                .accessibilityIdentifier("today.quote.sendToInkspring")
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: phase) { _, newPhase in if newPhase == .active { refresh() } }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        #endif
    }

    private func refresh() { installed = InkspringLink.isInstalled }
}
