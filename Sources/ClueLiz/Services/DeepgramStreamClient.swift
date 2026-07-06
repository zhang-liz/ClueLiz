import Foundation
import ClueLizCore

/// One live Deepgram WebSocket stream. Feed it 16 kHz mono Int16 PCM; get parsed
/// results back. Network drops reconnect with backoff indefinitely, buffering up
/// to ~30 s of audio. The one unrecoverable case — the server rejecting the
/// handshake with HTTP 4xx (bad/revoked API key) — gives up via `onTerminalError`
/// instead of reconnecting forever.
final class DeepgramStreamClient: NSObject {
    private let apiKey: String
    private let source: String   // "mic" / "system" — logging only

    var onResult: ((DeepgramResult) -> Void)?
    var onStateChange: ((Bool) -> Void)?   // true = connected
    /// Fired once when the server rejects the handshake with HTTP 4xx — the key
    /// is bad, so reconnecting can't help. No further reconnects are attempted.
    /// The message is stream-agnostic; the owner dedupes across mic + system.
    var onTerminalError: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private var keepaliveTimer: DispatchSourceTimer?
    private var lastSend = Date.distantPast

    private var finished = false
    private var reconnectAttempt = 0
    /// Send and receive can fail for the same drop — only schedule one reconnect.
    private var reconnectScheduled = false
    /// True once the current socket has received a message — the only proof that
    /// the handshake (and the API key) is good. Connected state is only reported
    /// after this, never merely because `resume()` was called.
    private var connectionConfirmed = false

    // Ordered ring buffer of PCM chunks while disconnected:
    // 30 s at 16 kHz * 2 bytes ≈ 960 KB.
    private var pendingPCM = PCMChunkBuffer(maxBytes: 16_000 * 2 * 30)
    private let queue = DispatchQueue(label: "deepgram.client")

    init(apiKey: String, source: String) {
        self.apiKey = apiKey
        self.source = source
    }

    func connect() {
        queue.async { self.openSocket() }
    }

    private func openSocket() {
        guard !finished else { return }
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "channels", value: "1"),
            .init(name: "interim_results", value: "true"),
            .init(name: "punctuate", value: "true"),
            .init(name: "diarize", value: "true"),
            .init(name: "model", value: "nova-3"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        connectionConfirmed = false
        task.resume()
        receiveLoop(on: task)

        // Flush audio buffered while we were down; chunks that fail to send are
        // re-buffered (in sequence order) so a dead reconnect doesn't drop them.
        for chunk in pendingPCM.drain() { sendOrRebuffer(chunk, on: task) }

        startKeepalive()
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                // A received message proves the connection (and the key) works —
                // reset the backoff and report connected.
                self.queue.async {
                    self.reconnectAttempt = 0
                    if !self.connectionConfirmed {
                        self.connectionConfirmed = true
                        self.onStateChange?(true)
                    }
                }
                if case .string(let text) = message,
                   let parsed = DeepgramMessageParser.parse(Data(text.utf8)) {
                    self.onResult?(parsed)
                }
                self.receiveLoop(on: task)
            case .failure:
                self.queue.async { self.handleDisconnect(failedTask: task) }
            }
        }
    }

    private func handleDisconnect(failedTask: URLSessionWebSocketTask) {
        guard !finished, !reconnectScheduled else { return }
        // A delayed failure callback from a socket that a reconnect already
        // replaced must not cancel the healthy current task.
        guard failedTask === task else { return }
        // A confirmed 4xx handshake response (bad/revoked key) is the ONE case
        // where reconnecting can't help. Everything else — network outages fail
        // with no HTTP response at all — keeps retrying with backoff
        // indefinitely, buffering audio, per the reconnect contract.
        if !connectionConfirmed,
           let status = (failedTask.response as? HTTPURLResponse)?.statusCode,
           (400...499).contains(status) {
            failPermanently(status: status)
            return
        }
        reconnectScheduled = true
        onStateChange?(false)
        stopKeepalive()
        task?.cancel()
        task = nil
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        reconnectAttempt += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            self.openSocket()
        }
    }

    /// Runs on `queue`. Stops reconnecting forever and surfaces one terminal error.
    private func failPermanently(status: Int) {
        finished = true
        stopKeepalive()
        task?.cancel()
        task = nil
        _ = pendingPCM.drain()   // the key is bad — buffered audio has nowhere to go
        onStateChange?(false)
        onTerminalError?("Deepgram rejected the connection (HTTP \(status)) — check your API key in Settings.")
        session.finishTasksAndInvalidate()
    }

    func send(pcm: Data) {
        queue.async {
            guard !self.finished else { return }   // gave up or closed — drop audio
            self.lastSend = Date()
            // Every chunk gets a sequence number (even ones sent directly) so a
            // failed send can re-buffer *in order* among newer buffered audio.
            let chunk = self.pendingPCM.makeChunk(pcm)
            if let task = self.task, task.state == .running {
                self.sendOrRebuffer(chunk, on: task)
            } else {
                self.pendingPCM.insert(chunk)
            }
        }
    }

    /// Runs on `queue`. A failed send re-buffers the chunk in sequence order
    /// (instead of dropping it, or appending it after newer audio) and
    /// schedules a reconnect.
    private func sendOrRebuffer(_ chunk: PCMChunkBuffer.Chunk, on task: URLSessionWebSocketTask) {
        task.send(.data(chunk.data)) { [weak self] error in
            guard let self, error != nil else { return }
            self.queue.async {
                guard !self.finished else { return }   // gave up — don't re-buffer
                // Stale completion: a reconnect already replaced this socket
                // with a healthy one. Don't disturb it, and don't re-buffer the
                // chunk — it would replay around some future drop, far out of
                // order; one lost chunk beats a garbled transcript.
                if let current = self.task, current !== task { return }
                // Current socket failed (or is torn down awaiting reconnect —
                // self.task is nil then): re-buffer for the reconnect flush.
                self.pendingPCM.insert(chunk)
                self.handleDisconnect(failedTask: task)
            }
        }
    }

    func finish() {
        queue.async {
            self.finished = true
            self.stopKeepalive()
            if let task = self.task {
                task.send(.string(#"{"type":"CloseStream"}"#)) { _ in
                    task.cancel(with: .normalClosure, reason: nil)
                }
            }
            self.task = nil
            // Without this the session (and its delegate queue) leaks — one per
            // stream per meeting. Lets the CloseStream send above complete first.
            self.session.finishTasksAndInvalidate()
        }
    }

    // Keepalive runs on `queue` (like every other access to `task`/`lastSend`),
    // so there is no cross-thread state sharing. Both methods are called on `queue`.
    private func startKeepalive() {
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let task = self.task, task.state == .running else { return }
            if Date().timeIntervalSince(self.lastSend) >= 5 {
                task.send(.string(#"{"type":"KeepAlive"}"#)) { _ in }
            }
        }
        timer.resume()
        keepaliveTimer = timer
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }
}
