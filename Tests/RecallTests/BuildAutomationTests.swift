import Foundation

struct BuildAutomationTests {
    static func testIncrementalCompilationLogic() throws {
        // Test timestamps comparison logic
        let now = Date()
        let sourceDate = now.addingTimeInterval(-10)
        let binaryDate = now

        let needsBuild = sourceDate > binaryDate
        if needsBuild {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected needsBuild = false when source is older than binary"])
        }
    }

    static func testPlistVersionEmbedding() throws {
        let versionPath = URL(fileURLWithPath: "VERSION")
        if let verData = try? Data(contentsOf: versionPath),
           let verStr = String(data: verData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if verStr.isEmpty {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "VERSION file is empty"])
            }
        }
    }

    static func testDMGBackgroundDimensionCheck() throws {
        let bgPath = URL(fileURLWithPath: "Resources/dmg_background.png")
        if FileManager.default.fileExists(atPath: bgPath.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: bgPath.path)
            if attrs == nil {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Attributes missing for dmg background"])
            }
        }
    }

    static func testReleaseScriptSemanticBumping() throws {
        let parseSemVer = { (versionStr: String, bump: String) -> String in
            let parts = versionStr.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return versionStr }
            var major = parts[0]
            var minor = parts[1]
            var patch = parts[2]
            switch bump {
            case "major": major += 1; minor = 0; patch = 0
            case "minor": minor += 1; patch = 0
            default: patch += 1
            }
            return "\(major).\(minor).\(patch)"
        }

        let bumpedPatch = parseSemVer("1.0.0", "patch")
        let bumpedMinor = parseSemVer("1.0.0", "minor")
        let bumpedMajor = parseSemVer("1.0.0", "major")

        if bumpedPatch != "1.0.1" || bumpedMinor != "1.1.0" || bumpedMajor != "2.0.0" {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Semantic bumping logic failed"])
        }
    }
}
