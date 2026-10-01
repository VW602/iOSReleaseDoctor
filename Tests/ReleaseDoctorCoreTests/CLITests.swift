import Foundation
import XCTest

/// Runs the built executable to check the exit-code contract end to end.
final class CLITests: XCTestCase {
    private func executable() throws -> URL {
        let products = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            .bundleURL.deletingLastPathComponent()
        let url = products.appendingPathComponent("ios-release-doctor")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw XCTSkip("ios-release-doctor was not built next to the test bundle; run `swift build` first.")
        }
        return url
    }
    private func fixture(_ name: String) throws -> String {
        try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/" + name).path
    }
    private func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = try executable()
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testHelpAndVersionExitZero() throws {
        XCTAssertEqual(try run(["--help"]).status, 0)
        let version = try run(["--version"])
        XCTAssertEqual(version.status, 0)
        XCTAssertEqual(version.output, "0.1.0\n")
    }
    func testInvalidUsageExitsTwo() throws {
        for arguments in [[], ["--unknown"], ["a", "b"], ["--json"]] {
            XCTAssertEqual(try run(arguments).status, 2, "\(arguments)")
        }
    }
    func testHealthyAndWarningOnlyProjectsExitZero() throws {
        XCTAssertEqual(try run([fixture("Healthy")]).status, 0)
        let warning = try run([fixture("MissingPrivacy")])
        XCTAssertEqual(warning.status, 0)
        XCTAssertTrue(warning.output.contains("[WARNING] Privacy manifest"))
    }
    func testErrorFindingsExitOne() throws {
        let blank = try run([fixture("BlankVersion"), "--json"])
        XCTAssertEqual(blank.status, 1)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(blank.output.utf8)))
        XCTAssertEqual(try run([fixture("NoProject")]).status, 1)
    }
}
