import Foundation

struct InstalledPort: Identifiable, Hashable {
    let name: String
    /// version_revision, e.g. "1.18.4_2"
    let version: String
    /// e.g. ["quartz", "x11"]
    let variants: [String]
    let isActive: Bool

    var id: String { "\(name)@\(version)\(variantSuffix)" }
    var variantSuffix: String { variants.map { "+\($0)" }.joined() }
    /// Registry spec pinning this exact entry, e.g. "@1.18.4_2+quartz+x11".
    var versionSpec: String { "@\(version)\(variantSuffix)" }
    var versionDisplay: String { version + variantSuffix }
}

struct OutdatedPort: Identifiable, Hashable {
    let name: String
    /// The raw remainder of the outdated line, e.g. "1.0_0 < 1.1_0".
    let detail: String
    var id: String { name }

    /// Installed version parsed from `detail`; the whole detail when it does
    /// not follow the "old < new" shape (e.g. platform-mismatch lines).
    var currentVersion: String {
        guard let split = detail.firstIndex(of: "<") else { return detail }
        return detail[..<split].trimmingCharacters(in: .whitespaces)
    }

    /// Available version parsed from `detail`; empty when not parseable.
    var newVersion: String {
        guard let split = detail.firstIndex(of: "<") else { return "" }
        return detail[detail.index(after: split)...].trimmingCharacters(in: .whitespaces)
    }
}

struct SearchResult: Identifiable, Hashable {
    let name: String
    let version: String
    let categories: String
    let summary: String
    var id: String { name }
}

struct PortInfo: Hashable {
    let version: String
    let summary: String
    let homepage: String
    let variants: [String]
    let license: String
    let categories: String
    let longDescription: String
}

struct DependencySection: Identifiable, Hashable {
    /// "Library", "Build", "Runtime", "Extract", "Fetch", …
    let kind: String
    let items: [String]
    var id: String { kind }
}

struct ConsoleChunk {
    let text: String
    let isStderr: Bool
}
