# Agent Plugin Manager

[한국어](README.ko.md)

A native macOS app for browsing agent skills and saving the skill selections you use for different tasks. Built with SwiftUI, starting with Codex and Claude Code.

**Early development:** the app currently reads local `SKILL.md` files and saves work configurations. Plugin installation, updates, and MCP, hook, and instruction management are planned. The app interface is currently in Korean.

## What works today

- Browse skills in `~/.agents/skills` and `~/.claude/skills`, plus folders you register yourself.
- Browse repositories in the source sidebar, with installed-entry counts and an unknown-source section. Search by name, source, or path; combine source, agent, installation location, and symbolic-link filters.
- Agent and location filters stay in sync: choosing an agent lists only its registered locations; choosing a location selects its agent. Changing agents clears an incompatible location. “All locations” retains the selected agent; “All agents” clears the location. Location choices stay available even when a source or search has no matching skills. Locations are shown only in the top filter; manage paths in Settings.
- Classify supported global installation receipts automatically, or connect a repository manually in the skill detail view. Manual associations can be edited or removed.
- View raw `SKILL.md` content and report missing folders, access failures, and incomplete scans.
- Manage default and additional paths together in Settings. Default paths are fixed; additional paths can be edited or removed without changing their files.
- Create, edit, and delete work configurations. Import selections from another configuration as a snapshot; later edits to the source do not affect your saved configuration.
- Keep references to skills that disappear from the catalog, and restore configurations and settings after relaunch.
- Use the system appearance or choose light or dark mode.

Saving a configuration does **not** enable, disable, move, or delete skills. A discovered file is not proof that an agent has loaded it. Other agents can be registered by name and folder for `SKILL.md` browsing; their runtime compatibility is not verified.

## Build and run

Requirements: macOS 26+, Xcode 26+ with Swift 6.2+, and the full Xcode installation selected as the active developer directory. There are no external Swift package dependencies. Node.js 22+ is needed only for the design checks.

Open the checked-in project, select the `AgentPluginManager` scheme, and run:

```sh
open AgentPluginManager.xcodeproj
```

To build and launch a local Release app from the repository root:

```sh
xcodebuild -project AgentPluginManager.xcodeproj \
  -scheme AgentPluginManager -configuration Release \
  -derivedDataPath build build
open "build/Build/Products/Release/Agent Plugin Manager.app"
```

The default build uses ad-hoc signing and requires no Apple team. Debug builds use a separate `Agent Plugin Manager Dev.app` and preferences domain. These instructions produce a local build; Developer ID signing and notarized distribution have not been verified.

The generated Xcode project is included. XcodeGen is needed only when changing [project.yml](project.yml):

```sh
xcodegen generate --spec project.yml
```

Personal signing settings belong in the ignored `Config/Local.xcconfig`. See [CONTRIBUTING.md](CONTRIBUTING.md) for configuration and checks.

## Use it

1. Open Settings (`⌘,`) to check the default skill folders or add a folder containing a `SKILL.md` file or a collection of skills.
2. Choose a source in the sidebar, narrow the list by agent or installation location, and open an entry to read `SKILL.md` or reveal it in Finder. Use “출처 연결…” in the detail view for an unknown source. Refresh with `⌘R` after external changes.
3. Create a work configuration and select skills for that task. Use “다른 구성에서 가져오기” to reuse selections from another configuration. Import is blocked if any source skill is missing from the current catalog.

## Local data and file access

The app stores work configurations, manual source associations, additional paths, and appearance preferences locally in `UserDefaults`. The current app has no accounts, telemetry, or network requests and does not execute skill scripts.

The scanner reads registered roots. Raw content is limited to regular UTF-8 files up to 2 MiB; link targets outside registered roots are blocked. Scans are bounded at depth 8 and 10,000 candidates per root and report partial results. These are app limits, not agent specifications.

Source classification reads the optional version-3 [Vercel Skills installation receipt](https://github.com/vercel-labs/skills/blob/main/src/skill-lock.ts) at `~/.agents/.skill-lock.json`. It associates supported GitHub/Git records only with the corresponding real directory under `~/.agents/skills` and registered entries resolving to that directory. Same-name copies in other locations remain unknown. Metadata reads reject symlinks and special files and use the same 2 MiB limit. Alternate `XDG_STATE_HOME` receipt locations, project receipts, and plugin receipts are not currently supported.

“설치 기록” means an installation receipt; “직접 연결” means a local user association. Neither verifies the current files against the remote repository. Counts include separate installed copies and links, not the number of skills available remotely. Manual associations are tied to the discovered installation identity; replacing a directory does not transfer its association. Removing a manual override restores the receipt source if one exists. Source selection and metadata edits do not change work configurations or skill files.

Legacy bundle IDs (`forked.agentskillmanager.local` and `.dev`) are retained to preserve existing settings after the rename. See [Config/Base.xcconfig](Config/Base.xcconfig).

## Roadmap

- Extend verified discovery rules, provenance formats, and plugin membership.
- Add safe skill changes with previews, conflict checks, and recovery before connecting writes to user files.
- Add plugin installation and updates through verified agent-supported workflows, then support MCP servers, hooks, and instructions where applicable.
- Complete accessibility and distribution validation.

A plugin is a distribution package; a repository is a source; a work configuration is the user's selection. Standalone skills remain standalone. Design prototypes may show future features; they are not a statement of current app support.

## Contributing and documentation

Bug reports, feature discussions, code, and documentation improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

[Documentation index](docs/README.md) covers architecture, terminology, and design references. Most detailed design notes are currently in Korean. Please keep the English and Korean READMEs in sync.

## License

The project license is being selected and will be added before public release. Third-party products referenced in the design notes retain their own rights; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
