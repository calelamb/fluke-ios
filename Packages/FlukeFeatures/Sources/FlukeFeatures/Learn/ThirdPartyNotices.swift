import Foundation

public struct ThirdPartyNotice: Equatable, Sendable {
    public let copyright: String
    public let licenseName: String
    public let licenseText: String
    public let name: String

    public init(
        name: String,
        copyright: String,
        licenseName: String,
        licenseText: String
    ) {
        self.name = name
        self.copyright = copyright
        self.licenseName = licenseName
        self.licenseText = licenseText
    }
}

public enum ThirdPartyNotices {
    public static let fraunces = ThirdPartyNotice(
        name: "Fraunces",
        copyright: "Copyright 2020 The Fraunces Project Authors (github.com/undercasetype/Fraunces)",
        licenseName: "SIL Open Font License, Version 1.1",
        licenseText: bundledFrauncesLicense()
    )

    private static func bundledFrauncesLicense() -> String {
        guard let url = Bundle.module.url(
            forResource: "OFL",
            withExtension: "txt"
        ) else {
            preconditionFailure("Bundled Fraunces license is missing")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Bundled Fraunces license is unreadable: \(error.localizedDescription)")
        }
    }
}
