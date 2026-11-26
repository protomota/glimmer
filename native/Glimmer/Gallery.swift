import AVFoundation
import ImageIO
import SwiftUI

struct Artwork: View {
    let slot: Int
    var featured = false
    var height: CGFloat = 190
    var corner: CGFloat = 18
    @Environment(JournalStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            let catalog = store.editorialLibrary?.edition?.gallery ?? GalleryLibrary.shared.catalog
            if let plate = catalog.pick(slot: slot, date: store.day,
                                                       aspect: proxy.size.width / height, featured: featured) {
                GalleryPhoto(plate: plate, size: CGSize(width: proxy.size.width, height: height))
                    .contentShape(.rect)
                    .clipShape(.rect(cornerRadius: corner, style: .continuous))
                    .accessibilityElement(children: .contain)
            }
        }
        .frame(height: height)
    }
}

private struct GalleryPhoto: View {
    let plate: GalleryPlate
    let size: CGSize
    private var allowsMotion: Bool { size.height >= 100 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var animateImages
    @Environment(\.scenePhase) private var scene
    @Environment(\.readingTheme) private var theme
    @Environment(JournalStore.self) private var store
    @State private var soundID = UUID()
    @State private var visible = false
    @State private var loadedPoster: CGImage?
    @State private var loadedURL: URL?
    private static let posters: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private func poster() -> CGImage? {
        if let loadedPoster, loadedURL == plate.posterURL { return loadedPoster }
        if let cached = Self.posters.object(forKey: plate.id as NSString) { return cached }
        guard let url = plate.localPoster ?? GalleryCatalog.bundled.plates.first?.localPoster, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        Self.posters.setObject(image, forKey: plate.id as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    var body: some View {
        let fit = plate.wholeSubject == true
        ZStack {
            theme.inset
            if let image = poster() {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.description)
        .accessibilityAddTraits(.isImage)
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            if allowsMotion, !reduceMotion, animateImages, visible, scene == .active,
               let url = plate.filmURL {
                GalleryFilm(url: url, fit: fit)
                    .id(url)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsMotion, visible, scene == .active, !reduceMotion, animateImages,
               let url = plate.ambienceURL {
                let playing = GalleryAmbience.shared.owner == soundID
                Button {
                    GalleryAmbience.shared.toggle(id: soundID, url: url) { store.notice = "The nature sound couldn’t load. Try again when you’re connected." }
                } label: {
                    Image(systemName: playing ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(.black.opacity(0.76), in: Circle())
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Mute nature sounds" : "Play nature sounds")
                .padding(6)
            }
        }
        .onChange(of: visible && scene == .active && !reduceMotion && animateImages) { _, active in
            if !active { GalleryAmbience.shared.stop(for: soundID) }
        }
        .onChange(of: plate.filmURL) { GalleryAmbience.shared.stop(for: soundID) }
        .onDisappear { GalleryAmbience.shared.stop(for: soundID) }
        .task(id: visible && scene == .active ? plate.posterURL : nil) {
            guard visible, scene == .active, let url = plate.posterURL else { return }
            let image = await GalleryPosters.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedPoster = image
            loadedURL = url
        }
        .onGeometryChange(for: Bool.self) { proxy in
            guard proxy.size.width > 0, proxy.size.height > 0 else { return false }
            guard let viewport = proxy.bounds(of: .scrollView) else { return true }
            return viewport.intersects(CGRect(origin: .zero, size: proxy.size))
        } action: { visible = $0 }
    }
}

// The native layer stays transparent until it has a frame and playback has
// started. Losing the network, switching tabs or pausing exposes the local poster.
@MainActor
private final class FilmPlayback {
    private var asset: AVURLAsset?
    private var preparation: Task<Void, Never>?
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private weak var surface: AVPlayerLayer?
    private var observations: [NSKeyValueObservation] = []

    func start(url: URL, on layer: AVPlayerLayer) {
        let asset = AVURLAsset(url: url)
        self.asset = asset
        surface = layer
        layer.opacity = 0
        // AVPlayerLooper needs the asset duration. Loading off the render path
        // keeps a slow or disconnected media server from delaying the interface.
        preparation = Task { [weak self] in
            guard let (duration, playable) = try? await asset.load(.duration, .isPlayable),
                  !Task.isCancelled, playable, duration.seconds.isFinite, duration.seconds > 0,
                  let self, let layer = self.surface
            else { return }
            self.prepare(item: AVPlayerItem(asset: asset), layer: layer)
        }
    }

    private func prepare(item: AVPlayerItem, layer: AVPlayerLayer) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        queue = player
        layer.player = player
        let looper = AVPlayerLooper(player: player, templateItem: item)
        self.looper = looper
        observations = [
            layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            looper.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        ]
        player.play()
    }

    private func refresh() {
        guard let layer = surface else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = layer.isReadyForDisplay && looper?.status == .ready && queue?.timeControlStatus == .playing ? 1 : 0
        CATransaction.commit()
    }

    func stop() {
        preparation?.cancel()
        asset?.cancelLoading()
        preparation = nil
        asset = nil
        observations.removeAll()
        queue?.pause()
        looper?.disableLooping()
        surface?.player = nil
        queue?.removeAllItems()
        looper = nil
        queue = nil
        surface = nil
    }
}

#if os(macOS)
private struct GalleryFilm: NSViewRepresentable {
    let url: URL
    let fit: Bool
    func makeCoordinator() -> FilmPlayback { FilmPlayback() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer()
        view.wantsLayer = true
        view.layer = layer
        layer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        context.coordinator.start(url: url, on: layer)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: FilmPlayback) { coordinator.stop() }
}
#else
private final class FilmSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
}
private struct GalleryFilm: UIViewRepresentable {
    let url: URL
    let fit: Bool
    func makeCoordinator() -> FilmPlayback { FilmPlayback() }

    func makeUIView(context: Context) -> FilmSurface {
        let view = FilmSurface()
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        let layer = view.layer as! AVPlayerLayer
        layer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        context.coordinator.start(url: url, on: layer)
        return view
    }
    func updateUIView(_ uiView: FilmSurface, context: Context) {}
    static func dismantleUIView(_ uiView: FilmSurface, coordinator: FilmPlayback) { coordinator.stop() }
}
#endif
