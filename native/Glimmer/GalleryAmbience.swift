import AVFAudio
import Foundation
import Observation

/// Play one field recording at a time. Scheduling decoded PCM keeps the sound
/// independent of video item changes, decoder priming and network latency.
@MainActor @Observable
final class GalleryAmbience {
    static let shared = GalleryAmbience()
    private(set) var owner: UUID?
    private var preparation: Task<Void, Never>?
    private var engine: AVAudioEngine?

    func stop(for id: UUID) {
        guard owner == id else { return }
        preparation?.cancel()
        preparation = nil
        engine?.stop()
        engine = nil
        owner = nil
    }

    func toggle(id: UUID, url: URL, onFailure: @escaping () -> Void) {
        let wasPlaying = owner == id
        if let owner { stop(for: owner) }
        guard !wasPlaying else { return }
        owner = id
        preparation = Task {
            do {
                // The field recording has its own immutable URL. Audio starts after its
                // complete track is locally available; subsequent loops need no network.
                let (tmp, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: tmp) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url == url else { throw CocoaError(.fileReadCorruptFile) }
                let file = try AVAudioFile(forReading: tmp)
                guard file.length > 0, file.length <= Int64(file.processingFormat.sampleRate * 30),
                      (1...2).contains(file.processingFormat.channelCount),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
                else { throw CocoaError(.fileReadCorruptFile) }
                try file.read(into: buffer)
                try Task.checkCancellation()
                guard owner == id else { return }
                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.ambient)
                #endif
                try engine.start()
                self.engine = engine
                player.play()
            } catch {
                guard !Task.isCancelled, owner == id else { return }
                stop(for: id)
                onFailure()
            }
        }
    }
}
