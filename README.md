# Agent Harness Manager

[한국어](README.ko.md)

A native macOS library for agent skills, built with SwiftUI. Browse skills and their installation locations, organize groups, and review file changes before applying them. Starts with Codex, Claude Code, Grok Build, Antigravity, OpenCode, Pi, Devin CLI, and Cursor.

**Early development:** the interface uses a sidebar, list, and persistent detail column. Visual styling remains our own. AI review, automatic grouping, plugin installation, and MCP/hook/instruction management are not implemented. The app interface is currently in Korean.

## What works today

- Browse registered skill folders using summary filters, agent and location filters, repository sources, search, and a link-only filter.
- Inspect a logical skill and its installations together. A discovered direct source and links to it share a row; independent same-name copies remain separate. “Variants” compares readable `SKILL.md` hashes for same-name skills, not their entire resource directories.
- Read original documents, inspect installation paths and provenance, and save favorites.
- Create, edit, and delete groups. Existing work configurations are imported once, with original notes and missing references preserved in the legacy view.
- Switch groups together or turn other groups off. Overlapping members remain enabled for another active group; ungrouped skills are unaffected.
- Enable or disable independent directories and healthy single-hop installation links directly inside the ten built-in discovery roots after a change preview. Shared source directories stay in place; nested/custom locations and protected provider caches remain read-only. Broken, indirect, or unapproved links are blocked. A fresh scan and identity/content checks run before applying changes.
- Keep a durable journal, reject destination collisions, and resume interrupted changes. A pending operation blocks other writes until recovery succeeds.
- Browse pending and completed changes, search installation paths, and review an inverse plan before undoing a supported completed operation. Both records are retained. Group selections are reconciled from the journal after restart or recovery.
- Inspect local document/metadata/path findings and save up to 50 review snapshots, with hashes and a current-state comparison. This is a local check, not AI review.
- Manage paths and system/light/dark appearance in Settings. Removing a registered path does not remove files.
- Connect Codex, Claude Code, and Grok Build through the bundled CLI/stdio MCP server. Agents can inspect skills and local findings, preview enable/disable changes, and queue requests for human review in the app. Connection installation/removal previews the command or MCP entry and backs up existing configuration. Shared compatibility paths remain one installation and show affected agents.

Group and whole-skill switches act on installation links when a skill has a shared source. The source stays enabled and counts toward the library’s observed file state, even when all its installation links are off. Individual agent links can be switched separately.

Group activation selections are separate from actual installation state. Group editing and favorites change metadata only. File switches require a separate preview and Apply action. Discovered or enabled files do not prove that an agent loaded them into its current conversation.

## Build and run

Requirements: macOS 26+, Xcode 26+ with Swift 6.2+, and the full Xcode installation selected as the active developer directory. There are no external Swift package dependencies. Node.js 22+ is needed for design checks and Python 3 for CLI/MCP checks. The built app includes its management executable; end users do not need a Swift SDK to use it.

Open the checked-in project, select the `AgentHarnessManager` scheme, and run:

```sh
open AgentHarnessManager.xcodeproj
```

To build and launch a local Release app from the repository root:

```sh
xcodebuild -project AgentHarnessManager.xcodeproj \
  -scheme AgentHarnessManager -configuration Release \
  -derivedDataPath build build
open "build/Build/Products/Release/Agent Harness Manager.app"
```

The default build uses ad-hoc signing and requires no Apple team. Debug builds use a separate `Agent Harness Manager Dev.app` and preferences domain. These instructions produce a local build; Developer ID signing and notarized distribution have not been verified.

The generated Xcode project is included. XcodeGen is needed only when changing [project.yml](project.yml):

```sh
xcodegen generate --spec project.yml
```

Personal signing settings belong in the ignored `Config/Local.xcconfig`. See [CONTRIBUTING.md](CONTRIBUTING.md) for configuration and checks.

## Use it

1. Open Settings (`⌘,`) → **스킬 경로** and choose an agent to inspect its default/shared roots or add a folder for browsing.
2. Choose a summary filter, agent, or group in the sidebar; select a skill in the middle list to read its locations, groups, provenance, and original document on the right. Refresh with `⌘R` after external changes.
3. Create a group with “새 그룹”. Use “모든 그룹” to edit membership or request a group switch; select whether other groups should remain enabled.
4. Request a supported file switch, review every source and destination, then choose Apply. If interrupted, resolve any reported conflict and use “복구 재시도” to finish the recorded operation.
5. Open “변경 이력” to inspect recorded moves or choose “되돌리기 검토…” and review the inverse plan before applying it.
6. Refresh and choose “검사” to save a local review snapshot; open its history entry to inspect the saved evidence.

## Agent CLI / MCP connection

Open Settings (`⌘,`) → **에이전트 연동 · CLI / MCP** → **연결 설치…** for the agent you use. Review the configuration path and exact command or MCP entry, then install. Codex, Claude Code, and Grok Build use their installed CLI's config command. Antigravity, OpenCode, Pi, Devin CLI, and Cursor use reviewed JSON/JSONC configuration edits; their CLI does not need to be installed to save a registration. **등록 상태 확인** checks the saved entry without starting these five agents or their MCP servers. Registration does not prove that an agent is installed or has loaded the tools. Open a new agent session to verify use. The app does not sign in to a model provider or read the agent's credentials; authentication remains with the agent.

Ask the agent to inspect your skills or prepare enable/disable requests. Open **에이전트 요청** in the app, choose **현재 상태로 검토…**, inspect the regenerated plan, and apply it. Requests expire after 24 hours and are rejected if settings, documents, resources, or relevant history changed. Queuing never applies changes. Group definitions/selections are readable; agent-driven group editing or activation is not yet provided.

The CLI is inside the app at `Contents/Helpers/ahm`; copy its path in Settings. See [CLI and MCP usage](docs/agent-integration.md) for commands, configuration scopes, backups, and limits. This exposes the app as an MCP server; it does not implement a general MCP-server manager.

## Local data and file access

The app stores groups, favorites, local review history, legacy work configurations, manual source associations, additional paths, and appearance preferences locally in `UserDefaults`. Group migration leaves the original work-configuration bytes intact. Corrupt group/review/provenance data is preserved and its writes are blocked. Local skill management requires no account or network access and does not execute skill scripts. The app does not store model-provider credentials or access the Keychain. There is no telemetry.

File changes use `~/Library/Application Support/<bundle-id>/Library/library-journal.json`, protected by an exclusive lock and atomic, synced journal writes. Disabled folders or installation links are moved to unique `.ahm-disabled-<UUID>` siblings of the discovery root (for example, under `~/.agents`, outside `~/.agents/skills`) on the same volume, and are read through their journal records. The original installation identity survives disable/restore. Keep the journal and these folders when backing up or removing the app while skills are disabled. Interrupted operations resume the recorded plan. The latest 100 completed operations are retained. Undo records a new inverse operation and rejects newer changes to the same installation, edited content, path collisions, and newly discovered shared readers. Older records without a directory fingerprint remain readable but cannot be undone. Undoing an undo and force recovery are not supported.

Directory fingerprints cover included file bytes, names, permission modes, directory structure, and embedded symlink text without opening those embedded targets. Installation-link moves also verify the approved source directory identity and fingerprint; the source itself is never moved or rewritten. Fingerprinting is bounded at 64 MiB of regular file content, 10,000 entries, and 32 directory levels; unsupported or unreadable items block the change. Group-selection intent is journaled with file moves and reconciled into preferences after completion or recovery. Group definitions, favorites, and review history are not reverted by undo.

Installation links retain their exact text and inode when archived. Relative links are read using the recorded original location; the app never follows the archived link, whose text may resolve differently there. Do not open an archived relative link directly in Finder; use the displayed source path or in-app document view. Restoration and undo reject changed link identity/text, replaced sources, destination collisions, and incoming references to either the installed or archived link. The first link operation upgrades the journal to version 2 while retaining prior records; older apps refuse that journal rather than writing it without link metadata.

The scanner reads registered roots. Raw content is limited to regular UTF-8 files up to 2 MiB; link targets outside registered roots are blocked. Scans are bounded at depth 8 and 10,000 candidates per root and report partial results. These are app limits, not agent specifications.

Source classification reads the optional version-3 [Vercel Skills installation receipt](https://github.com/vercel-labs/skills/blob/main/src/skill-lock.ts) at `~/.agents/.skill-lock.json`. It associates supported GitHub/Git records only with the corresponding real directory under `~/.agents/skills` and registered entries resolving to that directory. Same-name copies in other locations remain unknown. Metadata reads reject symlinks and special files and use the same 2 MiB limit. Alternate `XDG_STATE_HOME` receipt locations, project receipts, and plugin receipts are not currently supported.

“설치 기록” means an installation receipt; “직접 연결” means a local user association. Neither verifies the current files against the remote repository. Installation counts include separate installed copies and links; logical-skill counts distinguish shared source rows. Neither is the number of skills available remotely. A mixed skill can appear in both On and Off filters. Manual associations are tied to the discovered installation identity; replacing a directory does not transfer its association. Removing a manual override restores the receipt source if one exists. Manual associations survive disable/restore. Automatic receipt provenance may be unavailable while a folder is in storage; it is verified again after restoration. Source selection and metadata edits do not change skill files.

Legacy bundle IDs (`forked.agentskillmanager.local` and `.dev`) are retained to preserve existing settings after the rename. See [Config/Base.xcconfig](Config/Base.xcconfig).

## Roadmap

- Extend verified discovery rules, provenance formats, and plugin membership.
- Extend file-switch support beyond default-root directories and single-hop installation links; add broader recovery tools, AI review, and automatic grouping.
- Add plugin installation and updates through verified agent-supported workflows, then support MCP servers, hooks, and instructions where applicable.
- Complete accessibility and distribution validation.

A plugin is a distribution package; a repository is a source; a work configuration is the user's selection. Standalone skills remain standalone. Design prototypes may show future features; they are not a statement of current app support.

## Contributing and documentation

Bug reports, feature discussions, code, and documentation improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

[Documentation index](docs/README.md) covers architecture, terminology, and design references. Most detailed design notes are currently in Korean. Please keep the English and Korean READMEs in sync.

## License

[MIT License](LICENSE). Third-party products and trademarks retain their own rights; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
