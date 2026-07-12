import Foundation

/// Pure parsers for `port` command output. No I/O — fully unit-testable.
/// Every parser skips lines it does not understand instead of failing.
enum PortParser {
    /// Parses `port -q installed` lines like:
    ///   `  cairo @1.18.4_2+quartz+x11 (active)`
    ///   `  aom @3.13.1_2` (inactive entries have no parenthetical)
    static func parseInstalled(_ output: String) -> [InstalledPort] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 2, tokens[1].first == "@" else { return nil }
            let spec = tokens[1].dropFirst()
            let parts = spec.split(separator: "+", omittingEmptySubsequences: true)
            guard let versionPart = parts.first else { return nil }
            return InstalledPort(
                name: String(tokens[0]),
                version: String(versionPart),
                variants: parts.dropFirst().map(String.init),
                isActive: trimmed.hasSuffix("(active)")
            )
        }
    }

    /// Parses `port -q outdated` lines; documented format `name  old < new`.
    static func parseOutdated(_ output: String) -> [OutdatedPort] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let name = trimmed.prefix(while: { $0 != " " })
            guard !name.isEmpty else { return nil }
            let detail = trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            return OutdatedPort(name: String(name), detail: detail)
        }
    }

    /// Parses `port search --name --line --glob '*term*'` output: TAB-separated
    /// `name\tversion\tcategories\tdescription`. Lines without a tab (e.g.
    /// "No match for *x* found") are skipped.
    static func parseSearch(_ output: String) -> [SearchResult] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return SearchResult(
                name: name,
                version: String(fields[1]),
                categories: fields.count > 2 ? String(fields[2]) : "",
                summary: fields.count > 3 ? fields[3...].joined(separator: " ") : ""
            )
        }
    }

    /// Parses the output of
    /// `port -q info --index --version --description --homepage --variants --license --categories --long_description NAME`
    /// — one line per field in that order. Anything past the sixth line belongs
    /// to the long description (which is requested last for that reason).
    static func parseInfo(_ output: String) -> PortInfo? {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lines = output.components(separatedBy: "\n")
        func field(_ index: Int) -> String {
            index < lines.count ? lines[index].trimmingCharacters(in: .whitespaces) : ""
        }
        let variants = field(3)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let longDescription = lines.count > 6
            ? lines[6...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return PortInfo(
            version: field(0),
            summary: field(1),
            homepage: field(2),
            variants: variants,
            license: field(4),
            categories: field(5),
            longDescription: longDescription
        )
    }

    /// Parses `port -q deps NAME` lines like
    ///   `Library Dependencies: expat, fontconfig, freetype`
    static func parseDeps(_ output: String) -> [DependencySection] {
        output.split(separator: "\n").compactMap { line in
            guard let range = line.range(of: " Dependencies:") else { return nil }
            let kind = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let items = line[range.upperBound...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return nil }
            return DependencySection(kind: kind, items: items)
        }
    }

    /// Parses `port -q echo inactive` / `port -q echo leaves`: one port spec
    /// per line, empty output when there is nothing to report.
    static func parseEchoList(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
