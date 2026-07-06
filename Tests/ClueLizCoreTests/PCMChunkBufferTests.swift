import Foundation
import Testing
@testable import ClueLizCore

@Suite struct PCMChunkBufferTests {
    private func data(_ byte: UInt8, count: Int = 4) -> Data {
        Data(repeating: byte, count: count)
    }

    @Test func makeChunkAssignsMonotonicSequenceNumbers() {
        var buffer = PCMChunkBuffer(maxBytes: 100)
        #expect(buffer.makeChunk(data(1)).seq == 0)
        #expect(buffer.makeChunk(data(2)).seq == 1)
        #expect(buffer.makeChunk(data(3)).seq == 2)
    }

    @Test func inOrderInsertsAppend() {
        var buffer = PCMChunkBuffer(maxBytes: 100)
        let a = buffer.makeChunk(data(1))
        let b = buffer.makeChunk(data(2))
        buffer.insert(a)
        buffer.insert(b)
        #expect(buffer.drain().map(\.seq) == [0, 1])
    }

    // The bug this type exists to prevent: a chunk whose send failed is
    // re-inserted AFTER newer chunks were buffered — it must land back in
    // sequence order, not at the end.
    @Test func failedSendReinsertsInSequenceOrder() {
        var buffer = PCMChunkBuffer(maxBytes: 100)
        let inFlight = buffer.makeChunk(data(1))      // seq 0, sent, will fail
        let newer1 = buffer.makeChunk(data(2))        // seq 1, buffered while down
        let newer2 = buffer.makeChunk(data(3))        // seq 2
        buffer.insert(newer1)
        buffer.insert(newer2)
        buffer.insert(inFlight)                       // late failure re-buffers
        #expect(buffer.drain().map(\.seq) == [0, 1, 2])
    }

    @Test func byteBudgetDropsOldestFirst() {
        var buffer = PCMChunkBuffer(maxBytes: 8)      // holds two 4-byte chunks
        let a = buffer.makeChunk(data(1))
        let b = buffer.makeChunk(data(2))
        let c = buffer.makeChunk(data(3))
        buffer.insert(a)
        buffer.insert(b)
        buffer.insert(c)                              // evicts seq 0
        #expect(buffer.drain().map(\.seq) == [1, 2])
    }

    @Test func bytesTracksInsertsAndEvictions() {
        var buffer = PCMChunkBuffer(maxBytes: 8)
        let a = buffer.makeChunk(data(1))
        buffer.insert(a)
        #expect(buffer.bytes == 4)
        let b = buffer.makeChunk(data(2))
        let c = buffer.makeChunk(data(3))
        buffer.insert(b)
        buffer.insert(c)
        #expect(buffer.bytes == 8)                    // capped
        #expect(buffer.count == 2)
    }

    @Test func drainEmptiesTheBuffer() {
        var buffer = PCMChunkBuffer(maxBytes: 100)
        let a = buffer.makeChunk(data(1))
        buffer.insert(a)
        #expect(!buffer.drain().isEmpty)
        #expect(buffer.isEmpty)
        #expect(buffer.bytes == 0)
        #expect(buffer.drain().isEmpty)
    }
}
