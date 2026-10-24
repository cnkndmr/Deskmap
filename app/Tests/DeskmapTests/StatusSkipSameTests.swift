import Foundation
import Testing
@testable import Deskmap

/// status.json içerik aynıysa yazılmaz (perf/PLAN-perf.md §6.5).
struct StatusSkipSameTests {
    private let a = Data("a".utf8), b = Data("b".utf8)

    @Test func sameContentWithoutRequestIsSkipped() {
        #expect(StatusFile.shouldSkip(request: nil, content: a, last: a))
    }
    @Test func changedContentIsWritten() {
        #expect(!StatusFile.shouldSkip(request: nil, content: b, last: a))
        #expect(!StatusFile.shouldSkip(request: nil, content: a, last: nil))
    }
    /// CLI isteğin yanıtını `request` alanından bekler: her zaman yazılır.
    @Test func requestIsAlwaysWritten() {
        #expect(!StatusFile.shouldSkip(request: "ab12cd34", content: a, last: a))
    }
}
