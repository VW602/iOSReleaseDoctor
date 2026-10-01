import Foundation

struct MetadataCheck: Check {
    let identifier = "metadata"
    static let purposeKeys = ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
        "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription",
        "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSContactsUsageDescription", "NSSpeechRecognitionUsageDescription", "NSBluetoothAlwaysUsageDescription"]
    /// Plists inside these containers describe a dependency, not the app.
    static let vendoredContainers = [".xcframework", ".framework", ".bundle"]

    static func isVendored(_ path: String) -> Bool {
        path.split(separator: "/").dropLast().contains { component in
            vendoredContainers.contains { component.hasSuffix($0) }
        }
    }

    func run(_ context: ScanContext) -> [Finding] {
        var results: [Finding] = []
        let infos = context.plists.filter { path, dictionary in
            URL(fileURLWithPath: path).lastPathComponent == "Info.plist" ||
            dictionary.keys.contains(where: { $0.hasPrefix("CFBundle") || $0.hasPrefix("NS") })
        }.filter { !$0.key.hasSuffix(".entitlements") && !Self.isVendored($0.key) }
        for (key, label) in [("CFBundleShortVersionString", "App version"), ("CFBundleVersion", "Build number")] {
            // Missing keys are warnings because Xcode often generates them from build
            // settings, which v0.1 doesn't resolve. A key that is present but blank is an error.
            if infos.isEmpty {
                results.append(Finding("version.unknown.\(key)", "\(label) not found", .warning,
                    "Could not determine \(key) from project files. It may be generated from build settings, which v0.1 doesn't resolve."))
            }
            for path in infos.keys.sorted() {
                guard let raw = infos[path]?[key] else {
                    results.append(Finding("version.unknown.\(key)", "\(label) not found", .warning,
                        "\(key) is not in this plist. It may be generated from build settings, which v0.1 doesn't resolve.", path: path))
                    continue
                }
                guard let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    results.append(Finding("version.invalid.\(key)", "\(label) invalid", .error, "\(key) is present but empty or not a string.", path: path))
                    continue
                }
                let unresolved = value.contains("$(") || value.contains("${")
                results.append(Finding("version.value.\(key)", label, unresolved ? .warning : .pass,
                    unresolved ? "Unresolved build-setting expression: \(value)" : value, path: path))
            }
        }
        results.append(Finding("usage.limit", "Purpose-string analysis", .info,
            "Runtime/API usage analysis is not implemented. Missing purpose keys are not assumed to be required."))
        for path in infos.keys.sorted() {
            guard let plist = infos[path] else { continue }
            for key in Self.purposeKeys {
                guard let value = plist[key] else { continue }
                let string = value as? String
                let empty = string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                let unresolved = string?.contains("$(") == true || string?.contains("${") == true
                results.append(Finding("usage.\(key)", key, empty || unresolved ? .warning : .info,
                    empty ? "Purpose string is empty or not a string." : unresolved ? "Purpose string contains an unresolved build setting." : "Nonempty purpose string present; suitability requires review.", path: path))
            }
            if let ats = plist["NSAppTransportSecurity"] as? [String: Any] {
                if let arbitrary = ats["NSAllowsArbitraryLoads"] {
                    let enabled = (arbitrary as? NSNumber)?.boolValue == true
                    results.append(Finding("ats.arbitrary", "NSAllowsArbitraryLoads", enabled ? .warning : .info,
                        "Configured value: \(arbitrary)", path: path))
                }
                if let domains = ats["NSExceptionDomains"] as? [String: Any] {
                    results.append(Finding("ats.domains", "ATS exception domains", .info,
                        domains.keys.sorted().joined(separator: ", "), path: path))
                }
            }
        }
        return results
    }
}
