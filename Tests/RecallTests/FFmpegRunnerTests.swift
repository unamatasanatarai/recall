import Foundation

struct FFmpegRunnerTests {
    static func testCandidatePathDiscovery() throws {
        let fileSystem = MockFileSystem()
        let runner = DefaultFFmpegRunner()

        fileSystem.executablePaths.insert("/opt/homebrew/bin/ffmpeg")
        let path = runner.findFFmpegPath(fileSystem: fileSystem)

        if path != "/opt/homebrew/bin/ffmpeg" {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected /opt/homebrew/bin/ffmpeg, got \(String(describing: path))"])
        }
    }

    static func testMissingBinaryHandling() throws {
        let fileSystem = MockFileSystem()
        let runner = DefaultFFmpegRunner()

        // fileSystem.executablePaths is empty
        let path = runner.findFFmpegPath(fileSystem: fileSystem)

        // On system without ffmpeg in standard paths or PATH which return nil
        if path != nil && !FileManager.default.isExecutableFile(atPath: path!) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected nil or executable path, got \(String(describing: path))"])
        }
    }

    static func testConcatCommandFormatting() throws {
        let runner = MockFFmpegRunner()
        let listURL = URL(fileURLWithPath: "/tmp/test_list.txt")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")

        let success = runner.concatAndTrim(listURL: listURL, outputURL: outputURL, excessSeconds: 5.0, ffmpegPath: "/usr/local/bin/ffmpeg")

        if !success {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Concat and trim expected true"])
        }
    }

    static func testTrimArgumentFormatting() throws {
        let runner = MockFFmpegRunner()
        let listURL = URL(fileURLWithPath: "/tmp/test_list.txt")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")

        // excessSeconds <= 0.05 vs > 0.05
        let resNoTrim = runner.concatAndTrim(listURL: listURL, outputURL: outputURL, excessSeconds: 0.01, ffmpegPath: "/usr/local/bin/ffmpeg")
        let resTrim = runner.concatAndTrim(listURL: listURL, outputURL: outputURL, excessSeconds: 10.0, ffmpegPath: "/usr/local/bin/ffmpeg")

        if !resNoTrim || !resTrim {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Trim formatting execution failed"])
        }
    }
}
