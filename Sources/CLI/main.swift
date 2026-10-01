import Foundation
import ReleaseDoctorCore

let help = """
iOS Release Doctor 0.1.0
Usage: ios-release-doctor <path> [--json]
       ios-release-doctor --help
       ios-release-doctor --version
Use -- before a path beginning with a dash.
Read-only local audit. No network access or Xcode builds.
Exit codes: 0 = no errors (warnings allowed), 1 = errors, 2 = invalid usage.
"""
guard let arguments = CLIArguments.parse(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((help + "\n").utf8))
    exit(2)
}
switch arguments {
case .help: print(help)
case .version: print("0.1.0")
case let .scan(path, json):
    let report = ProjectScanner().scan(path: path)
    do {
        print(try json ? Reporter.json(report) : Reporter.terminal(report))
        exit(report.exitCode)
    } catch {
        FileHandle.standardError.write(Data("Cannot encode report: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
