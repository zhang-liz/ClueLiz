import Foundation
import ClueLizCore

/// Wires audio taps to Deepgram streams and routes results into the TranscriptStore.
/// Mic stream → "Me"; system stream → "Them" (diarized).
final class TranscriptionService {
    private let store: TranscriptStore
    private let micTap = MicTap()
    private let systemTap = SystemAudioTap()
    private var micClient: DeepgramStreamClient?
    private var systemClient: DeepgramStreamClient?

    /// True while either Deepgram stream or the system tap is reconnecting.
    var onReconnecting: ((Bool) -> Void)?
    /// A capture tap or transcription stream died for good — message for a banner.
    var onStreamError: ((String) -> Void)?

    // State below is touched from the SCStream delegate queue, both URLSession
    // callback queues, the tap-restart Task, and the main thread — everything
    // is guarded by one lock; callbacks are always invoked outside the lock.
    private let stateLock = NSLock()
    private var _stopped = false
    private var _micConnected = true
    private var _systemConnected = true
    private var _systemTapRunning = true
    private var _terminalErrorReported = false
    private var _lastAudioActivity = Date()

    /// Set by `stop()` — suppresses restart attempts and late error reports.
    private var stopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _stopped
    }

    /// Updated whenever any speech result arrives — used for silence detection.
    var lastAudioActivity: Date {
        stateLock.lock(); defer { stateLock.unlock() }
        return _lastAudioActivity
    }

    private func touchAudioActivity() {
        stateLock.lock()
        _lastAudioActivity = Date()
        stateLock.unlock()
    }

    /// Updates connection flags under the lock, then reports the combined
    /// reconnecting state (the callback runs outside the lock).
    private func setConnectionFlags(mic: Bool? = nil, system: Bool? = nil, tap: Bool? = nil) {
        stateLock.lock()
        if let mic { _micConnected = mic }
        if let system { _systemConnected = system }
        if let tap { _systemTapRunning = tap }
        let reconnecting = !(_micConnected && _systemConnected && _systemTapRunning)
        stateLock.unlock()
        onReconnecting?(reconnecting)
    }

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
            self.touchAudioActivity()
            if result.isFinal {
                self.store.applyFinal(speaker: .me, text: result.transcript)
            } else {
                self.store.applyPartial(speaker: .me, text: result.transcript)
            }
        }
        system.onResult = { [weak self] result in
            guard let self else { return }
            self.touchAudioActivity()
            let speaker = Speaker.them(result.speakerID ?? 0)
            if result.isFinal {
                self.store.applyFinal(speaker: speaker, text: result.transcript)
            } else {
                self.store.applyPartial(speaker: speaker, text: result.transcript)
            }
        }
        mic.onStateChange = { [weak self] connected in
            self?.setConnectionFlags(mic: connected)
        }
        system.onStateChange = { [weak self] connected in
            self?.setConnectionFlags(system: connected)
        }
        mic.onTerminalError = { [weak self] message in
            self?.handleTerminalError(message, mic: true)
        }
        system.onTerminalError = { [weak self] message in
            self?.handleTerminalError(message, mic: false)
        }

        mic.connect()
        system.connect()

        micTap.onPCM = { [weak mic] pcm in mic?.send(pcm: pcm) }
        systemTap.onPCM = { [weak system] pcm in system?.send(pcm: pcm) }

        // SCStream can die mid-session (Screen Recording revoked, display
        // reconfiguration). Show "reconnecting", try to restart the tap, and
        // surface an error if it won't come back — otherwise "Them" would
        // silently stop transcribing.
        systemTap.onStopped = { [weak self] error in
            self?.handleSystemTapStopped(error)
        }

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

    /// Terminal = a Deepgram client gave up for good (HTTP 4xx handshake). Both
    /// streams share one API key, so a rejection usually kills both within
    /// moments — surface only the FIRST banner; a second would race and
    /// overwrite it. Clears that stream's "reconnecting" state (nothing is
    /// retrying anymore); the banner explains instead.
    private func handleTerminalError(_ message: String, mic: Bool) {
        stateLock.lock()
        let stopped = _stopped
        let firstReport = !_terminalErrorReported
        _terminalErrorReported = true
        stateLock.unlock()
        guard !stopped else { return }
        setConnectionFlags(mic: mic ? true : nil, system: mic ? nil : true)
        if firstReport { onStreamError?(message) }
    }

    /// Restart attempts before declaring the system tap dead.
    private let systemTapRestartAttempts = 3

    private func handleSystemTapStopped(_ error: Error?) {
        guard !stopped else { return }
        setConnectionFlags(tap: false)
        Task { [weak self] in
            guard let self else { return }
            for attempt in 1...self.systemTapRestartAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                guard !self.stopped else { return }
                do {
                    try await self.systemTap.start()
                    // stop() may have raced the await above — shut the fresh
                    // stream down, or capture (and the macOS recording
                    // indicator) would outlive the session.
                    guard !self.stopped else {
                        self.systemTap.stop()
                        return
                    }
                    self.setConnectionFlags(tap: true)
                    return
                } catch {
                    // Retry with a longer pause; give up after the last attempt.
                }
            }
            guard !self.stopped else { return }
            // Gave up — clear "reconnecting" and let the banner explain.
            self.setConnectionFlags(tap: true)
            let detail = error.map { " (\($0.localizedDescription))" } ?? ""
            self.onStreamError?(
                "System audio capture stopped and could not be restarted\(detail) — check Screen Recording permission. Your mic is still transcribing.")
        }
    }

    func stop() {
        stateLock.lock()
        _stopped = true
        stateLock.unlock()
        systemTap.onStopped = nil   // intentional stop, not an error
        micTap.stop()
        systemTap.stop()
        micClient?.finish()
        systemClient?.finish()
        micClient = nil
        systemClient = nil
    }
}
