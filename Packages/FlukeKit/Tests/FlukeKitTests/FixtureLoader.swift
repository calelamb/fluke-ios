import Foundation

enum FixtureLoader {
    static func data(named name: String) throws -> Data {
        if let bundledURL = Bundle.module.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: bundledURL)
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("\(name).json")
        return try Data(contentsOf: sourceURL)
    }
}
