import Foundation

struct ExportPlannerTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// Consecutive 10 s chunks starting at `base`, optionally with gaps before given indices.
    private static func chunks(count: Int, gapBefore: [Int: TimeInterval] = [:]) -> [ChunkFile] {
        var start = base
        return (0..<count).map { index in
            start = start.addingTimeInterval(gapBefore[index] ?? 0)
            defer { start = start.addingTimeInterval(10) }
            return ChunkFile(url: URL(fileURLWithPath: "/tmp/c\(index).mp4"), startTime: start, duration: 10, sizeBytes: 100)
        }
    }

    static func testSelectsNewestFootage() throws {
        let store = chunks(count: 3)
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 15, endingAt: base.addingTimeInterval(30))
        try check(plan == [
            ExportSegment(url: store[1].url, start: 5, end: 10),
            ExportSegment(url: store[2].url, start: 0, end: 10)
        ], "Unexpected plan \(plan)")
    }

    static func testTrimsFootageAfterEndDate() throws {
        let store = chunks(count: 3)
        // The gesture started 4 s into the last chunk; nothing after that belongs in the clip.
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 6, endingAt: base.addingTimeInterval(24))
        try check(plan == [
            ExportSegment(url: store[1].url, start: 8, end: 10),
            ExportSegment(url: store[2].url, start: 0, end: 4)
        ], "Unexpected plan \(plan)")
    }

    static func testSkipsChunksThatStartAfterEndDate() throws {
        let store = chunks(count: 3)
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 5, endingAt: base.addingTimeInterval(15))
        try check(plan == [ExportSegment(url: store[1].url, start: 0, end: 5)], "Unexpected plan \(plan)")
    }

    static func testCollectsFootageAcrossPauses() throws {
        // A 5 minute pause between the first and second chunk.
        let store = chunks(count: 2, gapBefore: [1: 300])
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 15, endingAt: store[1].startTime.addingTimeInterval(10))
        try check(plan == [
            ExportSegment(url: store[0].url, start: 5, end: 10),
            ExportSegment(url: store[1].url, start: 0, end: 10)
        ], "Footage should be collected across the gap: \(plan)")
    }

    static func testFootageStartSkipsPauses() throws {
        let store = chunks(count: 2, gapBefore: [1: 300])
        let start = ExportPlanner.footageStart(chunks: store, footageSeconds: 15, endingAt: store[1].startTime.addingTimeInterval(10))
        try check(start == store[0].startTime.addingTimeInterval(5), "Expected the start inside the first chunk, got \(String(describing: start))")
        try check(ExportPlanner.footageStart(chunks: [], footageSeconds: 15, endingAt: Date()) == nil, "No footage, no start")
    }

    static func testOffsetLargerThanStoreUsesEverything() throws {
        let store = chunks(count: 3)
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 3600, endingAt: base.addingTimeInterval(30))
        try check(plan.count == 3 && plan.reduce(0) { $0 + $1.duration } == 30, "Expected all 30 s, got \(plan)")
    }

    static func testEmptyStoreProducesNoSegments() throws {
        try check(ExportPlanner.plan(chunks: [], footageSeconds: 30, endingAt: Date()).isEmpty, "Expected an empty plan")
    }

    static func testIgnoresSliversShorterThanAFrame() throws {
        let store = chunks(count: 2)
        let plan = ExportPlanner.plan(chunks: store, footageSeconds: 10.01, endingAt: base.addingTimeInterval(20))
        try check(plan == [ExportSegment(url: store[1].url, start: 0, end: 10)], "A 0.01 s sliver should be dropped: \(plan)")
    }
}
