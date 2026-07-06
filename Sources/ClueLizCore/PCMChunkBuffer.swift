import Foundation

/// Ordered ring buffer of PCM chunks awaiting (re)send. Every chunk carries a
/// monotonic sequence number so chunks whose send failed re-insert *in order* —
/// a plain append would land them after newer audio buffered in the meantime,
/// and replaying out-of-order audio garbles transcription. Drops oldest chunks
/// beyond a byte budget. Not thread-safe; callers serialize access.
public struct PCMChunkBuffer {
    /// One PCM chunk tagged with its position in the audio stream.
    public struct Chunk: Equatable {
        public let seq: UInt64
        public let data: Data

        public init(seq: UInt64, data: Data) {
            self.seq = seq
            self.data = data
        }
    }

    private var chunks: [Chunk] = []
    private var byteCount = 0
    private var nextSeq: UInt64 = 0
    private let maxBytes: Int

    public init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    public var isEmpty: Bool { chunks.isEmpty }
    public var count: Int { chunks.count }
    public var bytes: Int { byteCount }

    /// Tags new audio with the next sequence number. Call for *every* chunk —
    /// including ones sent directly — so ordering survives a later re-insert.
    public mutating func makeChunk(_ data: Data) -> Chunk {
        defer { nextSeq += 1 }
        return Chunk(seq: nextSeq, data: data)
    }

    /// Inserts in sequence order (fast-path append for in-order arrivals),
    /// then drops oldest chunks beyond the byte budget.
    public mutating func insert(_ chunk: Chunk) {
        if let last = chunks.last, last.seq > chunk.seq {
            let index = chunks.firstIndex { $0.seq > chunk.seq } ?? chunks.endIndex
            chunks.insert(chunk, at: index)
        } else {
            chunks.append(chunk)
        }
        byteCount += chunk.data.count
        while byteCount > maxBytes, !chunks.isEmpty {
            byteCount -= chunks.removeFirst().data.count
        }
    }

    /// Removes and returns all buffered chunks, oldest first.
    public mutating func drain() -> [Chunk] {
        defer {
            chunks.removeAll()
            byteCount = 0
        }
        return chunks
    }
}
