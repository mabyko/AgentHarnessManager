# Security

Agent Harness Manager is in early development. Security fixes target the current `main` branch; there are no separately maintained release branches yet.

## Reporting a vulnerability

Use **Security → Report a vulnerability** on this GitHub repository when private vulnerability reporting is available. If it is unavailable, open an issue requesting a private reporting channel without including exploit details, credentials, private paths, or skill content. Share sensitive details only after a private channel has been established.

Include the affected commit or version, macOS version, a minimal reproduction using synthetic files, and the expected and observed impact. Do not attach private `SKILL.md` files or signing material. This project does not currently promise a response deadline.

## Current security boundaries

- Skill discovery and document reading are confined to registered roots and verified journal storage entries. External link targets require registration before their content can be read.
- The reader accepts regular UTF-8 files up to 2 MiB. It does not read devices, sockets, or FIFOs as skill documents.
- The app does not execute skill scripts, install plugins, or make network requests.
- The app does not authenticate with model providers, store their credentials, access the Keychain, or send inference requests. Each connected agent manages its own authentication. Legacy direct-connection Keychain items are left untouched; removing this feature does not revoke any previously issued remote session.
- The optional version-3 global installer receipt at `~/.agents/.skill-lock.json` is read separately for source classification. The metadata reader uses anchored, no-follow directory/file opens and rejects symlinks, special files, invalid UTF-8, and files over 2 MiB. Receipt and manual repository URLs reject embedded credentials. Source associations are not content verification or file-access authorization.
- Groups, favorites, review history, legacy work configurations, source associations, and settings are local metadata. Editing or removing them does not change skill files.
- File changes require a preview and apply action, and are limited to independent direct child directories of the two default roots. Shared readers, links, nested/custom roots, and provider caches stay read-only. Device/inode, parent, content, and destination checks run again before moving; no destination is overwritten.
- A locked, atomic, synced journal records pending changes before moves. Interrupted plans resume only after revalidation. Conflicts and changed files preserve the journal and block other writes. Storage folders and the journal must be kept while skills are disabled. Force recovery and completed-operation undo are not implemented.
- The app is not sandboxed; registered-root checks are application-level protections. Local ad-hoc builds are not notarized distribution builds.

Changes that could bypass root restrictions, read unintended files, corrupt saved metadata, or introduce unreviewed file writes are relevant security reports.
