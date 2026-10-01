# Contributing

Thanks for taking a look. This is a small project, and small, focused contributions are the easiest to review and merge.

## The most useful thing you can send

A clear bug report. If the tool flags something that's fine, or misses something it should have caught, open an issue with:

- what you ran,
- what it reported,
- what you expected, and
- a tiny fake project that reproduces it. Often an `Info.plist` and an empty `Package.swift` are enough.

Please don't attach real app source, signing files, provisioning profiles, credentials, or anything from a client or employer. A made-up example that shows the same problem is better anyway, because it can become a test fixture.

## Pull requests

- Keep each PR to one change. A fix plus an unrelated cleanup is two PRs.
- If you change behavior, add or update a test. Most tests either use a fixture in `Tests/ReleaseDoctorCoreTests/Fixtures` or build a small project in a temporary folder. Fixtures must be fabricated and safe to publish.
- For bigger changes, like a new category of checks, parsing `.pbxproj` files, or restructuring the scanner, please open an issue first so we can agree on the approach before you put in the time.
- New dependencies need a concrete reason. So far everything has been doable with Foundation.

Before you open the PR:

```sh
swift build
swift test
```

In the description, say what changed, why, and how you checked it.

## Ground rules for the scanner

These are the parts I'd like to keep true as the project grows:

- It only reads the project. No writes, no running project code, no network requests, no telemetry.
- The same project gives the same output. Keep finding IDs stable and ordering deterministic.
- Findings describe what was found, not what Apple will do. Don't word anything as an App Store approval or rejection, and add new limitations to the README.

For security problems, see [SECURITY.md](SECURITY.md) instead of opening a public issue. Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
