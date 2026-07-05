import Testing
import Foundation
@testable import ClueLizCore

@Suite struct SSEParserTests {
    @Test func singleEvent() {
        var p = SSEParser()
        let out = p.feed(Data("data: {\"a\":1}\n\n".utf8))
        #expect(out == ["{\"a\":1}"])
    }

    @Test func eventSplitAcrossFeeds() {
        var p = SSEParser()
        #expect(p.feed(Data("data: {\"a\"".utf8)) == [])
        #expect(p.feed(Data(":1}\n\n".utf8)) == ["{\"a\":1}"])
    }

    @Test func skipsEventLinesAndDone() {
        var p = SSEParser()
        let out = p.feed(Data("event: message_stop\ndata: [DONE]\ndata: x\n\n".utf8))
        #expect(out == ["x"])
    }

    @Test func multipleEventsInOneFeed() {
        var p = SSEParser()
        let out = p.feed(Data("data: 1\n\ndata: 2\n\n".utf8))
        #expect(out == ["1", "2"])
    }

    @Test func handlesCRLFLineEndings() {
        var p = SSEParser()
        let out = p.feed(Data("data: {\"a\":1}\r\ndata: [DONE]\r\n\r\n".utf8))
        #expect(out == ["{\"a\":1}"])
    }
}
