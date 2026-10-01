import Foundation

public enum Severity: String, Codable, Sendable {
    case pass = "PASS", info = "INFO", warning = "WARNING", error = "ERROR"
}

public struct Finding: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let severity: Severity
    public let message: String
    public let path: String?

    public init(_ id: String, _ title: String, _ severity: Severity, _ message: String, path: String? = nil) {
        self.id = id
        self.title = title
        self.severity = severity
        self.message = message
        self.path = path
    }
}

public struct ScanReport: Codable, Sendable {
    public let findings: [Finding]
    public var exitCode: Int32 { findings.contains { $0.severity == .error } ? 1 : 0 }
}

protocol Check {
    var identifier: String { get }
    func run(_ context: ScanContext) -> [Finding]
}

struct ScanContext {
    let rootURL: URL
    let entries: [String]
    let directories: Set<String>
    let files: Set<String>
    let text: [String: String]
    let plists: [String: [String: Any]]
}
