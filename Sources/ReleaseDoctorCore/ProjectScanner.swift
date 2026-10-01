import Foundation

public struct ProjectScanner {
    public init() {}
    private let excluded: Set<String> = [".git", "DerivedData", ".build", "build", "Pods", "Carthage"]
    private let textExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "plist", "entitlements",
        "xcconfig", "pbxproj", "json", "yaml", "yml", "xml", "strings", "storyboard", "xib", "xcprivacy", "config", "txt"]

    public func scan(path: String) -> ScanReport {
        // Resolve the root itself so a symlinked project folder scans normally.
        // Links inside the tree are still skipped during traversal below.
        let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ScanReport(findings: [Finding("input.invalid", "Invalid project path", .error, "Path must exist and be a directory.")])
        }
        var entries: [String] = []
        var directories: Set<String> = []
        var files: Set<String> = []
        var texts: [String: String] = [:]
        var plists: [String: [String: Any]] = [:]
        var issues: [Finding] = []
        func visit(_ directory: URL, relative: String) {
            do {
                let children = try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                for url in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if excluded.contains(url.lastPathComponent) { continue }
                    let name = relative + url.lastPathComponent
                    do {
                        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                        if values.isSymbolicLink == true {
                            issues.append(Finding("scan.symlink", "Symbolic link skipped", .info, "Links are not followed.", path: name))
                            continue
                        }
                        entries.append(name)
                        if values.isDirectory == true {
                            directories.insert(name)
                            visit(url, relative: name + "/")
                            continue
                        }
                        guard values.isRegularFile == true else { continue }
                        files.insert(name)
                        let ext = url.pathExtension.lowercased()
                        guard textExtensions.contains(ext) else { continue }
                        guard (values.fileSize ?? 0) <= 2_000_000 else {
                            issues.append(Finding("scan.size", "File skipped", .warning, "Relevant file exceeds the 2 MB read limit.", path: name))
                            continue
                        }
                        let data = try Data(contentsOf: url)
                        if ["plist", "entitlements"].contains(ext) {
                            do {
                                // Array or scalar roots are valid plists; they just aren't app metadata.
                                if let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                                    plists[name] = dictionary
                                }
                            } catch {
                                let metadata = url.lastPathComponent == "Info.plist" || ext == "entitlements"
                                issues.append(Finding("scan.plist", "Unreadable property list", metadata ? .error : .warning,
                                    "Cannot parse property list: \(error.localizedDescription)", path: name))
                            }
                        }
                        if !data.contains(0), let text = String(data: data, encoding: .utf8) { texts[name] = text }
                    } catch {
                        issues.append(Finding("scan.read", "Cannot inspect entry", .error, error.localizedDescription, path: name))
                    }
                }
            } catch {
                issues.append(Finding("scan.directory", "Cannot enumerate directory", .error, error.localizedDescription, path: relative))
            }
        }
        visit(root, relative: "")
        guard directories.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) ||
                files.contains(where: { $0 == "Package.swift" || $0.hasSuffix("/Package.swift") }) else {
            return ScanReport(findings: issues + [Finding("input.project", "No project found", .error,
                "Expected an .xcodeproj, .xcworkspace, or Package.swift.")])
        }
        let context = ScanContext(rootURL: root, entries: entries.sorted(), directories: directories, files: files, text: texts, plists: plists)
        let checks: [any Check] = [MetadataCheck(), InventoryCheck(), TextRiskCheck()]
        let findings = [Finding("input.project", "Project detected", .pass, "Recognizable project marker found.")]
            + issues + checks.flatMap { $0.run(context) }
        return ScanReport(findings: findings.sorted {
            ($0.id, $0.path ?? "", $0.message) < ($1.id, $1.path ?? "", $1.message)
        })
    }
}

