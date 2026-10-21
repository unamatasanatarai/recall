import Foundation

/// A slice of one chunk, in seconds from the chunk's start.
struct ExportSegment: Equatable {
    let url: URL
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        return end - start
    }
}

enum ExportPlanner {
    /// Shorter slices are dropped; they would contribute less than one frame.
    static let minimumSegmentDuration: TimeInterval = 1.0 / 30.0

    /// Walks back from `endDate` through `chunks` (sorted by start time) and collects up to
    /// `footageSeconds` of recording. Footage after `endDate` is cut, which keeps the drag gesture
    /// itself out of the clip. Gaps between chunks (pauses, sleep) are skipped.
    static func plan(chunks: [ChunkFile], footageSeconds: TimeInterval, endingAt endDate: Date) -> [ExportSegment] {
        var remaining = footageSeconds
        var segments: [ExportSegment] = []

        for chunk in chunks.reversed() {
            guard remaining >= minimumSegmentDuration else { break }
            let usableEnd = min(chunk.duration, endDate.timeIntervalSince(chunk.startTime))
            guard usableEnd >= minimumSegmentDuration else { continue }

            let take = min(usableEnd, remaining)
            segments.append(ExportSegment(url: chunk.url, start: usableEnd - take, end: usableEnd))
            remaining -= take
        }

        return segments.reversed()
    }

    /// Wall-clock time where the footage `plan` selects begins; earlier than
    /// `endDate - footageSeconds` when the span includes a pause.
    static func footageStart(chunks: [ChunkFile], footageSeconds: TimeInterval, endingAt endDate: Date) -> Date? {
        guard let first = plan(chunks: chunks, footageSeconds: footageSeconds, endingAt: endDate).first,
              let chunk = chunks.last(where: { $0.url == first.url }) else { return nil }
        return chunk.startTime.addingTimeInterval(first.start)
    }
}
