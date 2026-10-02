# Security

Agent Plugin Manager is in early development. Security fixes target the current `main` branch; there are no separately maintained release branches yet.

## Reporting a vulnerability

Use **Security → Report a vulnerability** on this GitHub repository when private vulnerability reporting is available. If it is unavailable, open an issue requesting a private reporting channel without including exploit details, credentials, private paths, or skill content. Share sensitive details only after a private channel has been established.

Include the affected commit or version, macOS version, a minimal reproduction using synthetic files, and the expected and observed impact. Do not attach private `SKILL.md` files or signing material. This project does not currently promise a response deadline.

## Current security boundaries

- Skill discovery and document reading are confined to registered roots. External link targets require registration before their content can be read.
- The reader accepts regular UTF-8 files up to 2 MiB. It does not read devices, sockets, or FIFOs as skill documents.
- The app does not execute skill scripts, install plugins, or make network requests.
- Work configurations and settings are local metadata. Saving or removing them does not change skill files.
- The app is not sandboxed; registered-root checks are application-level protections. Local ad-hoc builds are not notarized distribution builds.

Changes that could bypass root restrictions, read unintended files, corrupt saved metadata, or introduce unreviewed file writes are relevant security reports.
