import Foundation

public enum Reporter {
    public static func terminal(_ report: ScanReport) -> String {
        let lines = report.findings.map { finding in
            "[\(finding.severity.rawValue)] \(finding.title): \(finding.message)" +
                (finding.path.map { " (\($0))" } ?? "")
        }
        let warnings = report.findings.filter { $0.severity == .warning }.count
        let errors = report.findings.filter { $0.severity == .error }.count
        return (["iOS Release Doctor", "────────────────────────────────"] + lines +
            ["Result: \(errors) errors, \(warnings) warnings"]).joined(separator: "\n")
    }

    public static func json(_ report: ScanReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(JSONReport(findings: report.findings)), as: UTF8.self)
    }

    /// Experimental in v0.1. The schema version lets consumers notice future changes.
    private struct JSONReport: Encodable {
        let schemaVersion = 1
        let findings: [Finding]
    }
}

public enum CLIArguments: Equatable {
    case help, version, scan(path: String, json: Bool)

    public static func parse(_ arguments: [String]) -> CLIArguments? {
        if arguments == ["--help"] { return .help }
        if arguments == ["--version"] { return .version }
        var paths: [String] = []
        var json = false
        var literal = false
        for argument in arguments {
            if !literal && argument == "--" { literal = true; continue }
            if !literal && argument == "--json" {
                guard !json else { return nil }
                json = true
            } else {
                if !literal && argument.hasPrefix("-") { return nil }
                paths.append(argument)
            }
        }
        guard paths.count == 1, let path = paths.first, !path.isEmpty else { return nil }
        return .scan(path: path, json: json)
    }
}
