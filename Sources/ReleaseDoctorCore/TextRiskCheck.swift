import Foundation

struct TextRiskCheck: Check {
    let identifier = "text"
    func run(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = []
        for path in context.text.keys.sorted() {
            guard let text = context.text[path] else { continue }
            var debugDepths: [Bool] = []
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if ") { debugDepths.append(trimmed.contains("DEBUG")) }
                if trimmed.hasPrefix("#endif"), !debugDepths.isEmpty { debugDepths.removeLast() }
                let location = "Line \(index + 1). Review context; this is a textual indicator."
                if line.contains("localhost") || line.contains("127.0.0.1") {
                    findings.append(Finding("development.loopback", "Loopback reference", .warning, location, path: path))
                }
                for marker in ["TODO RELEASE", "FIXME RELEASE"] where line.contains(marker) {
                    findings.append(Finding("development.marker", marker, .warning, location, path: path))
                }
                if (debugDepths.contains(true) || line.contains("DEBUG")) && (line.contains("https://") || line.contains("http://")) {
                    findings.append(Finding("development.debugURL", "URL in DEBUG context", .warning, location, path: path))
                }
                // Ignore standard XML property-list DTD declarations, which are not app endpoints.
                if trimmed.hasPrefix("<!DOCTYPE plist") { continue }
                // One finding per line, even when the line holds several insecure URLs.
                let insecure = line.components(separatedBy: "http://").dropFirst().contains { part in
                    let authority = String(part.prefix { !$0.isWhitespace && !"/\"'<>)]}".contains($0) })
                    let host = URLComponents(string: "http://" + authority)?.host?.lowercased()
                    return host != "localhost" && host != "127.0.0.1"
                }
                if insecure {
                    findings.append(Finding("url.http", "Insecure HTTP URL indicator", .warning, location, path: path))
                }
            }
        }
        return findings
    }
}
