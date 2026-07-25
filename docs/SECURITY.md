# Security Policy

## Supported version

Security fixes are made against the latest released version. Older builds may
not receive backports.

## Reporting a vulnerability

Do not post cookies, passwords, tokens, private URLs, downloaded media, or
other personal data in a public Issue.

Use GitHub's private vulnerability reporting feature under
**Security > Advisories**. Include:

- affected version and macOS version
- a concise description of the impact
- minimal reproduction steps using synthetic data
- relevant source file and function names
- a proposed mitigation, when known

Keep credentials and copyrighted test material out of the report. A public
Issue is appropriate only after sensitive details have been removed.

## Distribution security

The 0.4.1 beta release is ad-hoc signed and is not notarized by Apple.
Users should obtain release archives from the project's own GitHub Releases,
verify the published SHA-256 digest, and avoid mirrors that modify the bundle.

Optional helper tools execute with the user's account permissions. Install them
only through the in-app managed-tool flow or from their official projects.
