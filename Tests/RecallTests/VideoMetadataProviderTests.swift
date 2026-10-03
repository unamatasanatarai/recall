import Foundation
import AVFoundation

struct VideoMetadataProviderTests {
    static func testValidMP4Validation() throws {
        let provider = DefaultVideoMetadataProvider()
        // Non-existent URL should return invalid
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_video_\(UUID().uuidString).mp4")
        let res = provider.durationAndIsValid(for: fakeURL)
        if res.isValid {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected isValid = false for missing file"])
        }
    }

    static func testZeroDurationValidation() throws {
        let provider = MockVideoMetadataProvider(defaultDuration: 0.0, isValid: false)
        let fakeURL = URL(fileURLWithPath: "/tmp/zero_duration.mp4")
        let res = provider.durationAndIsValid(for: fakeURL)
        if res.isValid || res.duration != 0.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected zero duration to be invalid"])
        }
    }

    static func testMissingVideoTrackValidation() throws {
        let provider = MockVideoMetadataProvider(defaultDuration: 10.0, isValid: false)
        let fakeURL = URL(fileURLWithPath: "/tmp/audio_only.mp4")
        let res = provider.durationAndIsValid(for: fakeURL)
        if res.isValid {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected audio-only track without video to be invalid"])
        }
    }

    static func testInfiniteDurationGuard() throws {
        let provider = MockVideoMetadataProvider(defaultDuration: .infinity, isValid: false)
        let fakeURL = URL(fileURLWithPath: "/tmp/infinite.mp4")
        let res = provider.durationAndIsValid(for: fakeURL)
        if res.isValid {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected infinite duration to be invalid"])
        }
    }
}
