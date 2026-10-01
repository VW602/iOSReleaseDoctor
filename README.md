# iOSReleaseDoctor

I built iOSReleaseDoctor because every App Store release has a handful of small details that are easy to forget: a version string left blank, a `localhost` URL from testing, an `NSAllowsArbitraryLoads` that was only supposed to be temporary. I kept checking the same things by hand on my own apps, so I turned the checklist into a tool.

It's a Swift command-line tool that reads an iOS project folder and reports what it finds: version and build values, the privacy manifest, purpose strings, App Transport Security settings, entitlements, the app icon set, `http://` URLs, and leftover development markers.

It doesn't modify your project, run your code, or send anything over the network. It also doesn't know what Apple will decide. A clean report means these specific checks found nothing, not that the app will pass review.

## Install

You need macOS 13 or newer and Swift 6.0 or newer (Xcode or the command-line tools). There's no prebuilt binary yet, so build it from a checkout:

```sh
swift build -c release
mkdir -p "$HOME/.local/bin"
cp .build/release/ios-release-doctor "$HOME/.local/bin/"
export PATH="$HOME/.local/bin:$PATH"
```

There are no third-party dependencies. The CLI only has two flags, so I wrote a small parser instead of pulling in swift-argument-parser.

## Usage

```sh
ios-release-doctor /path/to/MyApp
ios-release-doctor /path/to/MyApp --json
ios-release-doctor --help
ios-release-doctor --version
ios-release-doctor -- -MyApp    # path that starts with a dash
```

The path must be a folder containing an `.xcodeproj`, an `.xcworkspace`, or a `Package.swift`. If the path is a symlink to that folder, the tool follows it.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Scan finished with no ERROR findings. Warnings are allowed. |
| 1 | Scan finished with at least one ERROR, or the path couldn't be scanned. |
| 2 | Invalid command-line usage. |

Warnings don't fail the command. I wanted v0.1 to point out things worth reviewing without pretending every warning means the app can't ship.

### Example output

This is the real output for the `MissingPrivacy` test fixture:

```text
iOS Release Doctor
────────────────────────────────
[INFO] Entitlements files: Found 0.
[PASS] App icon asset set: Found 1. Image completeness and target membership are not validated.
[PASS] Project detected: Recognizable project marker found.
[WARNING] Privacy manifest: No PrivacyInfo.xcprivacy found.
[INFO] NSCameraUsageDescription: Nonempty purpose string present; suitability requires review. (Info.plist)
[INFO] Purpose-string analysis: Runtime/API usage analysis is not implemented. Missing purpose keys are not assumed to be required.
[PASS] App version: 1.2 (Info.plist)
[PASS] Build number: 42 (Info.plist)
Result: 0 errors, 1 warnings
```

Findings are sorted by check ID, then by path, so the same project always produces the same report. Paths are relative to the scanned folder. There are no timestamps.

- **PASS**: the check ran and found nothing to flag.
- **INFO**: context, not a problem.
- **WARNING**: worth a look before you submit.
- **ERROR**: something is clearly broken (for example a version key that's present but empty), or the scan itself couldn't complete.

### JSON output (experimental)

`--json` prints the same findings as JSON:

```json
{
  "findings" : [
    { "id" : "privacy.manifest", "message" : "No PrivacyInfo.xcprivacy found.", "severity" : "WARNING", "title" : "Privacy manifest" }
  ],
  "schemaVersion" : 1
}
```

Each finding has `id`, `title`, `severity`, `message`, and, when there is one, a `path`. The format is experimental in v0.1: finding IDs and messages may change before 1.0. `schemaVersion` is there so scripts can detect when the structure changes.

## What v0.1 checks

| Area | What it does |
| --- | --- |
| Version and build | Reads `CFBundleShortVersionString` and `CFBundleVersion` from the app's Info.plist files. A key that's present but empty or not a string is an ERROR. A missing key, or no Info.plist at all, is a WARNING, because Xcode often generates these values from build settings. Unresolved `$(...)` values are a WARNING. |
| Privacy manifest | WARNING if there's no `PrivacyInfo.xcprivacy`. Having one doesn't mean its contents are right. |
| Purpose strings | Looks at nine common `NS…UsageDescription` keys. Empty values and unresolved build settings are WARNINGs. It doesn't guess which keys your app needs. |
| App Transport Security | Reports `NSAllowsArbitraryLoads` (WARNING when enabled) and lists exception domains. |
| App icon | WARNING if no `AppIcon.appiconset` exists inside an asset catalog. |
| Entitlements | Counts `.entitlements` files and lists push, associated domains, iCloud, Sign in with Apple, and app groups as INFO. |
| Development leftovers | WARNING for `localhost`, `127.0.0.1`, `TODO RELEASE`, `FIXME RELEASE`, and URLs inside `#if DEBUG` blocks or on lines that mention DEBUG. |
| HTTP | WARNING for lines containing `http://`, at most once per line. `localhost` and `127.0.0.1` are exempt from this check but still get the development warning above, and the standard plist `DOCTYPE` line is ignored. |
| Hygiene | WARNING for `.DS_Store`, `xcuserdata`, and `*.xcuserstate`. It reports them and leaves them alone. |
| Unreadable plists | A malformed `Info.plist` or `.entitlements` file is an ERROR. Other malformed plists are a WARNING. Valid plists whose root is an array or a single value are simply ignored. |

The nine purpose keys are `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSContactsUsageDescription`, `NSSpeechRecognitionUsageDescription`, and `NSBluetoothAlwaysUsageDescription`.

## Limitations

Xcode projects are complicated, and v0.1 reads files on disk rather than understanding your build. That shapes most of what it can and can't tell you.

- **Build settings aren't resolved.** Many projects let Xcode generate most of the Info.plist from build settings like `MARKETING_VERSION`. The tool doesn't read those settings, so it can't always tell you the real version. That's why a missing version is a WARNING, not an ERROR.
- **It isn't target-aware.** Every Info.plist it finds is checked on its own, including those for tests and extensions. It doesn't know which files belong to which target, or whether an icon or privacy manifest is actually included in the app.
- **Metadata discovery is conservative.** A plist counts as app metadata if it's named `Info.plist` or has `CFBundle…` or `NS…` keys. Plists inside `.xcframework`, `.framework`, and `.bundle` folders are left out of the version and purpose-string checks, because they describe dependencies. Their text is still scanned.
- **It doesn't know what your code does.** There's no analysis of which APIs the app calls, so it can't tell you a purpose string is missing. Localized `InfoPlist.strings` values aren't read either.
- **Text checks are heuristics.** DEBUG detection is line-based: code in the `#else` branch of `#if DEBUG` can be flagged, and URLs built at runtime are missed. Matching is case-sensitive. An `http://` in a comment still counts. Treat these findings as "go look", not as proof of a problem.
- **Signing isn't checked**, and neither are provisioning, release configuration, or version format.
- **A PASS doesn't guarantee App Store approval.** This tool isn't affiliated with Apple and doesn't replace reading the App Review Guidelines.

## What gets read

The scan only lists folders and reads files; it never writes to the project. It skips `.git`, `DerivedData`, `.build`, `build`, `Pods`, and `Carthage`. It doesn't follow symbolic links inside the project, so it can't wander outside the folder you gave it.

Only these file types are read as text, up to 2 MB each: `swift`, `m`, `mm`, `h`, `c`, `cpp`, `plist`, `entitlements`, `xcconfig`, `pbxproj`, `json`, `yaml`, `yml`, `xml`, `strings`, `storyboard`, `xib`, `xcprivacy`, `config`, `txt`. Binary files and non-UTF-8 files (including UTF-16 `.strings`) aren't text-scanned. Binary plists are decoded for metadata but not searched for URLs.

Reports leave out source lines, but they can include file paths, version numbers, and ATS domain names, so check a report before posting it publicly. Scan a checkout that isn't being changed at the same time.

## How it's put together

`CLI → ProjectScanner → checks → Finding → Reporter`

`ProjectScanner` walks the folder once and builds a snapshot of paths, text, and parsed plists. Three checks read that snapshot: `MetadataCheck`, `InventoryCheck`, and `TextRiskCheck`. `Reporter` formats the result as text or JSON. The executable handles arguments, output, and exit codes.

## Development

```sh
swift build
swift test
swift run ios-release-doctor Tests/ReleaseDoctorCoreTests/Fixtures/Healthy
```

The tests use small fake projects in `Tests/ReleaseDoctorCoreTests/Fixtures` and temporary folders. A few tests run the built executable to check exit codes. See [CONTRIBUTING.md](CONTRIBUTING.md) if you'd like to help.

## Possible next steps

These are ideas, not promises:

- Reading build settings from `.pbxproj` and `.xcconfig` files so generated Info.plist values can be checked.
- Matching API usage to the purpose strings it needs.
- Signing and configuration checks.
- A way to turn individual checks on or off.

If the tool misses something, or flags something that's fine, please open an issue with a small example. Those reports are the most useful thing right now.

## License

MIT. See [LICENSE](LICENSE).
