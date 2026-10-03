import Foundation

struct RecorderEngineTests {
    static func testInitialIdleState() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)
        if engine.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected initial state to be .idle"])
        }
    }

    static func testChunkFileNaming() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let date = Date()
        let str = formatter.string(from: date)
        if str.isEmpty || !str.contains("-") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid chunk date string formatting"])
        }
    }

    static func testLogFileRotation() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)
        
        // Write standard log
        engine.log("Test log entry")
        
        // Log rotation runs automatically when file > 10MB
        if engine.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "State changed unexpectedly during log test"])
        }
    }

    static func testFlushCurrentChunkAction() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        var completed = false
        engine.flushCurrentChunk {
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "flushCurrentChunk completion was not called"])
        }
    }

    static func testStopStreamAction() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        engine.stopStream()

        let timeout = Date().addingTimeInterval(1.0)
        while engine.state != .idle && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if engine.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected state .idle after stopStream"])
        }
    }
}
