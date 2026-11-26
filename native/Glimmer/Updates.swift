#if os(macOS)
import Combine
import Sparkle
import SwiftUI

/// Sparkle updates for the Mac build downloaded from glimmertoday.ai.
/// Debug builds and builds without a feed or signing key leave the updater off.
@MainActor
final class AppUpdates: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController?

    init() {
        #if DEBUG
        controller = nil
        #else
        guard Self.configured("SUFeedURL"), Self.configured("SUPublicEDKey") else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        #endif
    }

    var isAvailable: Bool { controller != nil }

    func check() { controller?.checkForUpdates(nil) }

    private static func configured(_ key: String) -> Bool {
        !((Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "").isEmpty
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updates: AppUpdates

    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck)
    }
}
#endif
