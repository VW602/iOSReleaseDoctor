import Foundation

struct InventoryCheck: Check {
    let identifier = "inventory"
    func run(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = []
        let privacy = context.files.sorted().filter { URL(fileURLWithPath: $0).lastPathComponent == "PrivacyInfo.xcprivacy" }
        findings.append(Finding("privacy.manifest", "Privacy manifest", privacy.isEmpty ? .warning : .pass,
            privacy.isEmpty ? "No PrivacyInfo.xcprivacy found." : "Found \(privacy.count). Presence does not establish privacy compliance."))
        let icons = context.directories.sorted().filter { $0.hasSuffix(".xcassets/AppIcon.appiconset") }
        findings.append(Finding("icons.app", "App icon asset set", icons.isEmpty ? .warning : .pass,
            icons.isEmpty ? "No AppIcon.appiconset inside an asset catalog found." : "Found \(icons.count). Image completeness and target membership are not validated."))
        let entitlements = context.files.sorted().filter { $0.hasSuffix(".entitlements") }
        findings.append(Finding("entitlements.count", "Entitlements files", .info, "Found \(entitlements.count)."))
        let capabilities = [("aps-environment", "Push notifications"),
            ("com.apple.developer.associated-domains", "Associated domains"),
            ("com.apple.developer.applesignin", "Sign in with Apple"),
            ("com.apple.security.application-groups", "App groups")]
        for path in entitlements {
            guard let plist = context.plists[path] else { continue }
            for (key, label) in capabilities where plist[key] != nil {
                findings.append(Finding("entitlements.\(key)", label, .info, "Capability key present; provisioning is not verified.", path: path))
            }
            if plist.keys.contains(where: { $0.hasPrefix("com.apple.developer.icloud") || $0 == "com.apple.developer.ubiquity-container-identifiers" || $0 == "com.apple.developer.ubiquity-kvstore-identifier" }) {
                findings.append(Finding("entitlements.icloud", "iCloud", .info, "iCloud capability key present.", path: path))
            }
        }
        for path in context.entries {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if name == ".DS_Store" || name == "xcuserdata" || name.hasSuffix(".xcuserstate") {
                findings.append(Finding("hygiene.junk", "Project hygiene", .warning,
                    "User-specific metadata found; inclusion in the shipped app is not established.", path: path))
            }
        }
        return findings
    }
}
