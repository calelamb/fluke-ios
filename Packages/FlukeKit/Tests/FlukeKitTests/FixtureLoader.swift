import Foundation

enum FixtureLoadingError: Error, Equatable, LocalizedError {
    case missingResource(name: String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Required packaged API contract fixture '\(name).json' is missing."
        }
    }
}

enum FixtureLoader {
    static func data(named name: String) throws -> Data {
        guard let bundledURL = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureLoadingError.missingResource(name: name)
        }

        return try Data(contentsOf: bundledURL)
    }
}
