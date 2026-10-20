# Documentation

Start with the [English README](../README.md) or [한국어 README](../README.ko.md) for the current feature set and build instructions. [CONTRIBUTING.md](../CONTRIBUTING.md) covers development checks; [SECURITY.md](../SECURITY.md) covers vulnerability reporting.

## Implementation and design

Most detailed notes are currently in Korean. They include proposed behavior beyond the running app: broader file changes/recovery, extended source classification, AI review, plugin management, and other planned features. Treat the READMEs and source code as the description of current support, and check each document's implementation-status notes before relying on a design contract.

[CLI review authentication research](cli-review-auth-research.md) records the 2026-10-20 Codex/Claude Code policy, authentication, and process-isolation findings. Local CLI review is a proposal, not an implemented feature.

| Document | Purpose |
| --- | --- |
| [Agent CLI / MCP](agent-integration.md) | Management commands, agent connection setup, reviewed requests, backups, and limits |
| [Architecture](architecture.md) | Current library, group, local review, limited file-change/recovery support, and broader proposed contracts |
| [Product scenarios](product-scenarios.md) | User flows, scope, failure handling, and acceptance criteria |
| [Glossary](../GLOSSARY.md) | Plugins, skills, sources, work configurations, and planned file states |
| [Design system](design-system.md) | Native UI principles, tokens, component states, and accessibility |
| [Design review](design-review.md) | Historical prototype findings and proposed safety requirements |
| [Selected design](design/final-candidate.md) | Adopted visual direction and historical native validation notes |
| [Icon notes](design/icons/README.md) | App icon sources, development variant, and generation prompts |
| [Agent logo usage review](agent-logo-usage-review.md) | Official identity-asset terms, identification use, and unresolved public-distribution questions |

## Prototypes

[Selected prototype](design/final-preview.html) and [initial prototype](design/preview.html) are review materials. Open the HTML files locally. They use example data and may simulate features that are not implemented in the native app. The prototype checks run with `node scripts/check-design.mjs`.

The source-navigation A/B/C comparison was a design exploration; A was selected and implemented in the native app. Historical prototypes use synthetic examples and do not define current production support.

Older screenshots are historical records, not current product screenshots. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Before publishing

- Keep the MIT license notice in source and binary distributions; review third-party notices separately.
- Review the history being published as well as the current files, especially older reference images, screenshots, personal paths, and credentials. Keep `Config/Local.xcconfig` and signing material out of Git.
- Enable private vulnerability reporting in the public repository's security settings and confirm the reporting path in `SECURITY.md`.
- Confirm GitHub Actions passes after upload. Local checks alone do not verify the hosted workflow.
- Publish binary releases only after verifying signing, notarization, and clean-machine installation. Until then, document source builds without claiming a notarized installer is available.

Source repository: [mabyko/AgentHarnessManager](https://github.com/mabyko/AgentHarnessManager). Downloadable binary releases will be linked after distribution validation.
