import Foundation
import CluelessCore

/// Wires audio taps to Deepgram streams and routes results into the TranscriptStore.
/// Mic stream → "Me"; system stream → "Them" (diarized).
final class TranscriptionService {
    private let store: TranscriptStore
    private let micTap = MicTap()
    private let systemTap = SystemAudioTap()
    private var micClient: DeepgramStreamClient?
    private var systemClient: DeepgramStreamClient?

    /// True while either Deepgram stream is reconnecting.
    var onReconnecting: ((Bool) -> Void)?
    private var micConnected = true
    private var systemConnected = true

    /// Updated whenever any speech result arrives — used for silence detection.
    private(set) var lastAudioActivity = Date()

    init(store: TranscriptStore) {
        self.store = store
    }

    func start(deepgramKey: String) async throws {
        let mic = DeepgramStreamClient(apiKey: deepgramKey, source: "mic")
        let system = DeepgramStreamClient(apiKey: deepgramKey, source: "system")
        micClient = mic
        systemClient = system

        mic.onResult = { [weak self] result in
            guard let self else { return }
            self.lastAudioActivity = Date()
            if result.isFinal {
                self.store.applyFinal(speaker: .me, text: result.transcript)
            } else {
                self.store.applyPartial(speaker: .me, text: result.transcript)
            }
        }
        system.onResult = { [weak self] result in
            guard let self else { return }
            self.lastAudioActivity = Date()
            let speaker = Speaker.them(result.speakerID ?? 0)
            if result.isFinal {
                self.store.applyFinal(speaker: speaker, text: result.transcript)
            } else {
                self.store.applyPartial(speaker: speaker, text: result.transcript)
            }
        }
        mic.onStateChange = { [weak self] connected in
            guard let self else { return }
            self.micConnected = connected
            self.onReconnecting?(!(self.micConnected && self.systemConnected))
        }
        system.onStateChange = { [weak self] connected in
            guard let self else { return }
            self.systemConnected = connected
            self.onReconnecting?(!(self.micConnected && self.systemConnected))
        }

        mic.connect()
        system.connect()

        micTap.onPCM = { [weak mic] pcm in mic?.send(pcm: pcm) }
        systemTap.onPCM = { [weak system] pcm in system?.send(pcm: pcm) }

        // Mic and system capture start independently; a failure in one should not
        // kill the other (graceful degradation per spec §5).
        var startErrors: [Error] = []
        do { try micTap.start() } catch { startErrors.append(error) }
        do { try await systemTap.start() } catch { startErrors.append(error) }
        if startErrors.count == 2 {
            stop()                 // nothing captures — close the sockets, then surface it
            throw startErrors[0]
        }
    }

    func stop() {
        micTap.stop()
        systemTap.stop()
        micClient?.finish()
        systemClient?.finish()
        micClient = nil
        systemClient = nil
    }
}
