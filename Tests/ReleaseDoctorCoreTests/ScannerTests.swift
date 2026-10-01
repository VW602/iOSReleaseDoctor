import Foundation
import XCTest
@testable import ReleaseDoctorCore

final class ScannerTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/" + name)
    }
    private func report(_ name: String) throws -> ScanReport {
        ProjectScanner().scan(path: try fixture(name).path)
    }
    private func assertFinding(_ report: ScanReport, _ id: String, _ severity: Severity,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(report.findings.contains { $0.id == id && $0.severity == severity },
                      "Missing \(id) with severity \(severity)", file: file, line: line)
    }
    private func temporary(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture("Healthy"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }
    func testHealthyProjectHasNoErrorsOrWarnings() throws {
        let scan = try report("Healthy")
        XCTAssertEqual(scan.exitCode, 0)
        XCTAssertFalse(scan.findings.contains { [.warning, .error].contains($0.severity) })
        assertFinding(scan, "privacy.manifest", .pass)
        assertFinding(scan, "icons.app", .pass)
        assertFinding(scan, "usage.NSCameraUsageDescription", .info)
        assertFinding(scan, "usage.limit", .info)
    }
    func testMissingPrivacyIsWarningAndExitZero() throws {
        let scan = try report("MissingPrivacy")
        assertFinding(scan, "privacy.manifest", .warning)
        XCTAssertEqual(scan.exitCode, 0)
    }
    func testAbsentVersionAndBuildAreWarnings() throws {
        let scan = try report("MissingVersion")
        assertFinding(scan, "version.unknown.CFBundleShortVersionString", .warning)
        assertFinding(scan, "version.unknown.CFBundleVersion", .warning)
        XCTAssertEqual(scan.exitCode, 0)
    }
    func testBlankVersionAndBuildAreErrors() throws {
        let scan = try report("BlankVersion")
        assertFinding(scan, "version.invalid.CFBundleShortVersionString", .error)
        assertFinding(scan, "version.invalid.CFBundleVersion", .error)
        XCTAssertEqual(scan.exitCode, 1)
    }
    func testNoInfoPlistMeansVersionCannotBeDetermined() throws {
        try temporary { root in
            try FileManager.default.removeItem(at: root.appendingPathComponent("Info.plist"))
            let scan = ProjectScanner().scan(path: root.path)
            assertFinding(scan, "version.unknown.CFBundleShortVersionString", .warning)
            assertFinding(scan, "version.unknown.CFBundleVersion", .warning)
            XCTAssertEqual(scan.exitCode, 0)
        }
    }
    func testEmptyPurposeIsWarningWithoutGuessingOtherKeys() throws {
        let scan = try report("EmptyPurpose")
        assertFinding(scan, "usage.NSCameraUsageDescription", .warning)
        XCTAssertFalse(scan.findings.contains { $0.id == "usage.NSMicrophoneUsageDescription" })
    }
    func testHTTPWarnsButXMLDeclarationDoesNot() throws {
        let scan = try report("HTTP")
        assertFinding(scan, "url.http", .warning)
        XCTAssertEqual(scan.findings.filter { $0.id == "url.http" }.count, 1)
    }
    func testLocalhostHTTPIsExemptFromHTTPButStillDevelopmentWarning() throws {
        let scan = try report("Localhost")
        XCTAssertFalse(scan.findings.contains { $0.id == "url.http" })
        assertFinding(scan, "development.loopback", .warning)
        XCTAssertEqual(scan.exitCode, 0)
    }
    func testATSWarnsAndReportsDomain() throws {
        let scan = try report("ATS")
        assertFinding(scan, "ats.arbitrary", .warning)
        assertFinding(scan, "ats.domains", .info)
        XCTAssertTrue(scan.findings.contains { $0.id == "ats.domains" && $0.message == "example.invalid" })
    }
    func testDevelopmentMarkersAndDebugURL() throws {
        let scan = try report("Development")
        assertFinding(scan, "development.debugURL", .warning)
        XCTAssertEqual(scan.findings.filter { $0.id == "development.marker" && $0.severity == .warning }.count, 2)
    }
    func testInvalidPathAndRegularFile() throws {
        assertFinding(ProjectScanner().scan(path: "/nonexistent-iosrd-" + UUID().uuidString), "input.invalid", .error)
        assertFinding(ProjectScanner().scan(path: try fixture("Healthy").appendingPathComponent("Info.plist").path), "input.invalid", .error)
    }
    func testUnrecognizedProjectFails() throws {
        assertFinding(try report("NoProject"), "input.project", .error)
    }
    func testMissingIconWarns() throws {
        try temporary { root in
            try FileManager.default.removeItem(at: root.appendingPathComponent("Assets.xcassets"))
            assertFinding(ProjectScanner().scan(path: root.path), "icons.app", .warning)
        }
    }
    func testEntitlementsCapabilitiesAreInformational() throws {
        try temporary { root in
            let values: [String: Any] = ["aps-environment": "development",
                "com.apple.developer.associated-domains": ["applinks:example.invalid"],
                "com.apple.developer.applesignin": ["Default"],
                "com.apple.security.application-groups": ["group.example.invalid"],
                "com.apple.developer.icloud-container-identifiers": ["iCloud.example.invalid"]]
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: root.appendingPathComponent("App.entitlements"))
            let scan = ProjectScanner().scan(path: root.path)
            XCTAssertEqual(scan.findings.filter { $0.id.hasPrefix("entitlements.") }.count, 6)
            XCTAssertTrue(scan.findings.filter { $0.id.hasPrefix("entitlements.") }.allSatisfy { $0.severity == .info })
        }
    }
    func testIgnoredDirectoriesBinaryFilesAndSymlinksAreNotScanned() throws {
        try temporary { root in
            for name in [".git", "DerivedData", ".build", "build", "Pods", "Carthage"] {
                let directory = root.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try "http://example.invalid".write(to: directory.appendingPathComponent("Risk.swift"), atomically: true, encoding: .utf8)
            }
            try Data([0] + Array("http://example.invalid".utf8)).write(to: root.appendingPathComponent("Binary.swift"))
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
            let scan = ProjectScanner().scan(path: root.path)
            XCTAssertFalse(scan.findings.contains { $0.id == "url.http" })
            assertFinding(scan, "scan.symlink", .info)
        }
    }
    func testHygieneIsReportedWithoutDeletingFiles() throws {
        try temporary { root in
            let directory = root.appendingPathComponent("xcuserdata")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in [".DS_Store", "xcuserdata/sample.xcuserstate"] {
                try Data("synthetic".utf8).write(to: root.appendingPathComponent(name))
            }
            let scan = ProjectScanner().scan(path: root.path)
            XCTAssertEqual(scan.findings.filter { $0.id == "hygiene.junk" && $0.severity == .warning }.count, 3)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".DS_Store")), Data("synthetic".utf8))
        }
    }
    func testMalformedInfoPlistIsAnError() throws {
        try temporary { root in
            try "not a plist".write(to: root.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            assertFinding(ProjectScanner().scan(path: root.path), "scan.plist", .error)
        }
    }
    func testMalformedDataPlistIsAWarning() throws {
        try temporary { root in
            try "not a plist".write(to: root.appendingPathComponent("Levels.plist"), atomically: true, encoding: .utf8)
            let scan = ProjectScanner().scan(path: root.path)
            assertFinding(scan, "scan.plist", .warning)
            XCTAssertEqual(scan.exitCode, 0)
        }
    }
    func testArrayRootPlistIsNotAnError() throws {
        try temporary { root in
            try PropertyListSerialization.data(fromPropertyList: [1, 2, 3], format: .xml, options: 0)
                .write(to: root.appendingPathComponent("Levels.plist"))
            let scan = ProjectScanner().scan(path: root.path)
            XCTAssertFalse(scan.findings.contains { $0.id == "scan.plist" })
            XCTAssertFalse(scan.findings.contains { $0.severity == .error })
            XCTAssertEqual(scan.exitCode, 0)
        }
    }
    func testVendoredXCFrameworkPlistIsNotAppMetadata() throws {
        let scan = try report("VendoredFramework")
        XCTAssertFalse(scan.findings.contains { $0.path?.hasPrefix("Vendor/") == true })
        XCTAssertEqual(scan.findings.filter { $0.id.hasPrefix("version.") }.map(\.severity), [.pass, .pass])
        XCTAssertEqual(scan.exitCode, 0)
    }
    func testSymlinkedRootIsScanned() throws {
        try temporary { root in
            let link = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
            defer { try? FileManager.default.removeItem(at: link) }
            let viaLink = ProjectScanner().scan(path: link.path)
            assertFinding(viaLink, "input.project", .pass)
            XCTAssertEqual(viaLink.exitCode, 0)
            XCTAssertEqual(viaLink.findings, ProjectScanner().scan(path: root.path).findings)
        }
    }
    func testNestedSymlinkDoesNotEscapeRoot() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "http://outside.invalid".write(to: outside.appendingPathComponent("Outside.swift"), atomically: true, encoding: .utf8)
        try temporary { root in
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("External"), withDestinationURL: outside)
            let scan = ProjectScanner().scan(path: root.path)
            assertFinding(scan, "scan.symlink", .info)
            XCTAssertFalse(scan.findings.contains { $0.path?.hasPrefix("External/") == true })
        }
    }
    func testBinaryPlistAndUnresolvedBuildSettings() throws {
        try temporary { root in
            let values = ["CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "42"]
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
                .write(to: root.appendingPathComponent("Info.plist"))
            let scan = ProjectScanner().scan(path: root.path)
            assertFinding(scan, "version.value.CFBundleShortVersionString", .warning)
            assertFinding(scan, "version.value.CFBundleVersion", .pass)
        }
    }
    func testOversizedRelevantFileIsReported() throws {
        try temporary { root in
            try Data(repeating: 65, count: 2_000_001).write(to: root.appendingPathComponent("Large.swift"))
            assertFinding(ProjectScanner().scan(path: root.path), "scan.size", .warning)
        }
    }
    func testSeveralHTTPURLsOnOneLineProduceOneFinding() throws {
        try temporary { root in
            try #"let urls = ["http://a.invalid", "http://b.invalid", "http://localhost"]"#
                .write(to: root.appendingPathComponent("URLs.swift"), atomically: true, encoding: .utf8)
            let scan = ProjectScanner().scan(path: root.path)
            XCTAssertEqual(scan.findings.filter { $0.id == "url.http" }.count, 1)
        }
    }
    func testLookalikeLocalhostDomainIsNotExempt() throws {
        try temporary { root in
            try "http://localhost.example.invalid/api".write(to: root.appendingPathComponent("URL.swift"), atomically: true, encoding: .utf8)
            assertFinding(ProjectScanner().scan(path: root.path), "url.http", .warning)
        }
    }
    func testRepeatedScansAreDeterministicAndDoNotChangeContents() throws {
        let root = try fixture("Healthy")
        let before = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
        XCTAssertEqual(try report("Healthy").findings, try report("Healthy").findings)
        XCTAssertEqual(before, try Data(contentsOf: root.appendingPathComponent("Info.plist")))
    }
    func testTerminalAndJSONReporting() throws {
        let scan = try report("MissingPrivacy")
        let terminal = Reporter.terminal(scan)
        XCTAssertTrue(terminal.hasPrefix("iOS Release Doctor\n"))
        XCTAssertTrue(terminal.contains("[WARNING] Privacy manifest"))
        XCTAssertTrue(terminal.hasSuffix("Result: 0 errors, 1 warnings"))
        let json = try Reporter.json(scan)
        let decoded = try JSONDecoder().decode(ScanReport.self, from: Data(json.utf8))
        XCTAssertEqual(scan.findings, decoded.findings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertFalse(json.contains("\u{1B}"))
    }
    func testAllNinePurposeStringsAreInspected() throws {
        try temporary { root in
            var values: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
            for key in MetadataCheck.purposeKeys { values[key] = "Synthetic purpose" }
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: root.appendingPathComponent("Info.plist"))
            let scan = ProjectScanner().scan(path: root.path)
            for key in MetadataCheck.purposeKeys { assertFinding(scan, "usage." + key, .info) }
        }
    }
    func testDirectoryCannotImpersonatePrivacyManifestOrPackageFile() throws {
        try temporary { root in
            for name in ["PrivacyInfo.xcprivacy", "Package.swift"] {
                try FileManager.default.removeItem(at: root.appendingPathComponent(name))
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            assertFinding(ProjectScanner().scan(path: root.path), "input.project", .error)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
            let scan = ProjectScanner().scan(path: root.path)
            assertFinding(scan, "input.project", .pass)
            assertFinding(scan, "privacy.manifest", .warning)
        }
    }
    func testWorkspaceMarkerIsAccepted() throws {
        try temporary { root in
            try FileManager.default.removeItem(at: root.appendingPathComponent("Package.swift"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcworkspace"), withIntermediateDirectories: true)
            assertFinding(ProjectScanner().scan(path: root.path), "input.project", .pass)
        }
    }
    func testDisabledArbitraryLoadsIsInformational() throws {
        try temporary { root in
            let values: [String: Any] = ["CFBundleShortVersionString": "1", "CFBundleVersion": "1",
                "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": false]]
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: root.appendingPathComponent("Info.plist"))
            assertFinding(ProjectScanner().scan(path: root.path), "ats.arbitrary", .info)
        }
    }
    func testCLIParsing() {
        XCTAssertEqual(CLIArguments.parse(["--help"]), .help)
        XCTAssertEqual(CLIArguments.parse(["--version"]), .version)
        XCTAssertEqual(CLIArguments.parse(["some path", "--json"]), .scan(path: "some path", json: true))
        XCTAssertEqual(CLIArguments.parse(["--", "-project"]), .scan(path: "-project", json: false))
        for arguments in [[], ["--unknown"], ["a", "b"], ["--json"], ["a", "--json", "--json"], ["--help", "a"]] {
            XCTAssertNil(CLIArguments.parse(arguments))
        }
    }
}
