import Foundation
import CluelessCore

/// One live Deepgram WebSocket stream. Feed it 16 kHz mono Int16 PCM; get parsed
/// results back. Reconnects with backoff on failure, buffering up to ~30 s of audio.
final class DeepgramStreamClient: NSObject {
    private let apiKey: String
    private let source: String   // "mic" / "system" — logging only

    var onResult: ((DeepgramResult) -> Void)?
    var onStateChange: ((Bool) -> Void)?   // true = connected

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private var keepaliveTimer: Timer?
    private var lastSend = Date.distantPast

    private var finished = false
    private var reconnectAttempt = 0

    // Ring buffer of PCM chunks while disconnected: 30 s at 16 kHz * 2 bytes ≈ 960 KB.
    private var pendingPCM: [Data] = []
    private var pendingBytes = 0
    private let maxPendingBytes = 16_000 * 2 * 30
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
        task.resume()
        receiveLoop(on: task)

        // Flush audio buffered while we were down.
        for chunk in pendingPCM { task.send(.data(chunk)) { _ in } }
        pendingPCM.removeAll()
        pendingBytes = 0

        reconnectAttempt = 0
        onStateChange?(true)
        startKeepalive()
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let parsed = DeepgramMessageParser.parse(Data(text.utf8)) {
                    self.onResult?(parsed)
                }
                self.receiveLoop(on: task)
            case .failure:
                self.queue.async { self.handleDisconnect() }
            }
        }
    }

    private func handleDisconnect() {
        guard !finished else { return }
        onStateChange?(false)
        stopKeepalive()
        task?.cancel()
        task = nil
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        reconnectAttempt += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openSocket()
        }
    }

    func send(pcm: Data) {
        queue.async {
            self.lastSend = Date()
            if let task = self.task, task.state == .running {
                task.send(.data(pcm)) { [weak self] error in
                    if error != nil { self?.queue.async { self?.handleDisconnect() } }
                }
            } else {
                // Buffer while down; drop oldest beyond ~30 s.
                self.pendingPCM.append(pcm)
                self.pendingBytes += pcm.count
                while self.pendingBytes > self.maxPendingBytes, !self.pendingPCM.isEmpty {
                    self.pendingBytes -= self.pendingPCM.removeFirst().count
                }
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
        }
    }

    private func startKeepalive() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.keepaliveTimer?.invalidate()
            self.keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self, let task = self.task, task.state == .running else { return }
                if Date().timeIntervalSince(self.lastSend) >= 5 {
                    task.send(.string(#"{"type":"KeepAlive"}"#)) { _ in }
                }
            }
        }
    }

    private func stopKeepalive() {
        DispatchQueue.main.async { [weak self] in
            self?.keepaliveTimer?.invalidate()
            self?.keepaliveTimer = nil
        }
    }
}
