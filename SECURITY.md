# Security

## What the tool does

iOSReleaseDoctor reads files in the folder you point it at. It doesn't write to that folder, execute project code, or make network requests. It doesn't follow symbolic links inside the project.

It isn't hardened against a folder that is being changed while the scan runs (for example, files being swapped for links mid-scan). Scan a checkout that isn't changing at the same time.

Reports leave out source lines, but they can include file paths, version numbers, and ATS domain names. Check a report before posting it publicly.

## Reporting a vulnerability

Please don't report vulnerabilities in public issues.

Use GitHub's private vulnerability reporting on this repository: open the **Security** tab and choose **Report a vulnerability**. If that option isn't available yet, open a short public issue asking for a private contact. Leave out any details of the problem.

A useful report includes:

- the version or commit you tested,
- what an attacker could do, and
- a synthetic reproduction (a small made-up project folder is ideal).

Never send real signing keys, provisioning profiles, credentials, or proprietary project source. This is a personal project maintained in spare time, so there's no guaranteed response time, but security reports get looked at first.

Fixes should keep the tool local and read-only, and should come with a regression test.
