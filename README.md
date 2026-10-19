# Agent Harness Manager

[한국어](README.ko.md)

A native macOS library for agent skills, built with SwiftUI. Browse skills and their installation locations, organize groups, and review file changes before applying them. Starts with Codex and Claude Code.

**Early development:** the interface uses a sidebar, list, and persistent detail column. Visual styling remains our own. AI review, automatic grouping, plugin installation, and MCP/hook/instruction management are not implemented. The app interface is currently in Korean.

## What works today

- Browse registered skill folders using summary filters, agent and location filters, repository sources, search, and a link-only filter.
- Inspect a logical skill and its installations together. A discovered direct source and links to it share a row; independent same-name copies remain separate. “Variants” compares readable `SKILL.md` hashes for same-name skills, not their entire resource directories.
- Read original documents, inspect installation paths and provenance, and save favorites.
- Create, edit, and delete groups. Existing work configurations are imported once, with original notes and missing references preserved in the legacy view.
- Switch groups together or turn other groups off. Overlapping members remain enabled for another active group; ungrouped skills are unaffected.
- Enable or disable independent skill directories directly inside the two default roots after a change preview. Links, shared readers, nested or custom locations, and protected provider caches remain read-only. A fresh scan and identity/content checks run before applying changes.
- Keep a durable journal, reject destination collisions, and resume interrupted changes. A pending operation blocks other writes until recovery succeeds.
- Inspect local document/metadata/path findings and save up to 50 review snapshots, with hashes and a current-state comparison. This is a local check, not AI review.
- Manage paths and system/light/dark appearance in Settings. Removing a registered path does not remove files.

Group activation selections are separate from actual installation state. Group editing and favorites change metadata only. File switches require a separate preview and Apply action. Discovered or enabled files do not prove that an agent loaded them into its current conversation.

## Build and run

Requirements: macOS 26+, Xcode 26+ with Swift 6.2+, and the full Xcode installation selected as the active developer directory. There are no external Swift package dependencies. Node.js 22+ is needed only for the design checks.

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

1. Open Settings (`⌘,`) to inspect the default roots or add a folder for browsing.
2. Choose a summary filter, agent, or group in the sidebar; select a skill in the middle list to read its locations, groups, provenance, and original document on the right. Refresh with `⌘R` after external changes.
3. Create a group with “새 그룹”. Use “모든 그룹” to edit membership or request a group switch; select whether other groups should remain enabled.
4. Request a supported file switch, review every source and destination, then choose Apply. If interrupted, resolve any reported conflict and use “복구 재시도” to finish the recorded operation.
5. Refresh and choose “검사” to save a local review snapshot; open its history entry to inspect the saved evidence.

## Local data and file access

The app stores groups, favorites, local review history, legacy work configurations, manual source associations, additional paths, and appearance preferences locally in `UserDefaults`. Group migration leaves the original work-configuration bytes intact. Corrupt group/review/provenance data is preserved and its writes are blocked. The current app has no accounts, telemetry, or network requests and does not execute skill scripts.

File changes use `~/Library/Application Support/<bundle-id>/Library/library-journal.json`, protected by an exclusive lock and atomic, synced journal writes. Disabled folders are moved to unique `.ahm-disabled-<UUID>` siblings of the discovery root (for example, under `~/.agents`, outside `~/.agents/skills`) on the same volume, and are read through their journal records. The original installation identity survives disable/restore. Keep the journal and these folders when backing up or removing the app while skills are disabled. Interrupted operations resume the recorded plan; completed-operation undo and force recovery are not implemented.

The scanner reads registered roots. Raw content is limited to regular UTF-8 files up to 2 MiB; link targets outside registered roots are blocked. Scans are bounded at depth 8 and 10,000 candidates per root and report partial results. These are app limits, not agent specifications.

Source classification reads the optional version-3 [Vercel Skills installation receipt](https://github.com/vercel-labs/skills/blob/main/src/skill-lock.ts) at `~/.agents/.skill-lock.json`. It associates supported GitHub/Git records only with the corresponding real directory under `~/.agents/skills` and registered entries resolving to that directory. Same-name copies in other locations remain unknown. Metadata reads reject symlinks and special files and use the same 2 MiB limit. Alternate `XDG_STATE_HOME` receipt locations, project receipts, and plugin receipts are not currently supported.

“설치 기록” means an installation receipt; “직접 연결” means a local user association. Neither verifies the current files against the remote repository. Installation counts include separate installed copies and links; logical-skill counts distinguish shared source rows. Neither is the number of skills available remotely. A mixed skill can appear in both On and Off filters. Manual associations are tied to the discovered installation identity; replacing a directory does not transfer its association. Removing a manual override restores the receipt source if one exists. Manual associations survive disable/restore. Automatic receipt provenance may be unavailable while a folder is in storage; it is verified again after restoration. Source selection and metadata edits do not change skill files.

Legacy bundle IDs (`forked.agentskillmanager.local` and `.dev`) are retained to preserve existing settings after the rename. See [Config/Base.xcconfig](Config/Base.xcconfig).

## Roadmap

- Extend verified discovery rules, provenance formats, and plugin membership.
- Extend file-switch support beyond independent default-root directories; add completed-operation undo, broader recovery tools, AI review, and automatic grouping.
- Add plugin installation and updates through verified agent-supported workflows, then support MCP servers, hooks, and instructions where applicable.
- Complete accessibility and distribution validation.

A plugin is a distribution package; a repository is a source; a work configuration is the user's selection. Standalone skills remain standalone. Design prototypes may show future features; they are not a statement of current app support.

## Contributing and documentation

Bug reports, feature discussions, code, and documentation improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

[Documentation index](docs/README.md) covers architecture, terminology, and design references. Most detailed design notes are currently in Korean. Please keep the English and Korean READMEs in sync.

## License

The project license is being selected and will be added before public release. Third-party products referenced in the design notes retain their own rights; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
