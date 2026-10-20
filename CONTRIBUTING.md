# Contributing

Thanks for helping improve Agent Harness Manager. Bug reports, feature proposals, code, and documentation changes are welcome in English or Korean.

## Before making a change

Read the [README](README.md) for implemented features and the [documentation index](docs/README.md) for design context. Discuss larger changes in an issue first. Include a concrete user task and the agent involved; support can differ between agents.

For bugs, include your macOS and Xcode versions, build configuration, reproduction steps, and expected and actual behavior. Use a small synthetic skill folder when possible. Remove personal paths, credentials, and private skill content from screenshots and logs. Report security issues through [SECURITY.md](SECURITY.md).

## Development setup

Use macOS 26+ and Xcode 26+ with Swift 6.2+. Open `AgentHarnessManager.xcodeproj` and select the `AgentHarnessManager` scheme. Debug builds have a separate app name, icon, and preferences domain from Release.

No Apple team is required for the default ad-hoc signing setup. To customize your local identity, create `Config/Local.xcconfig`, which is ignored by Git:

```xcconfig
AGENT_SKILL_MANAGER_BUNDLE_ID = org.example.agentharnessmanager
AGENT_SKILL_MANAGER_BUNDLE_ID[config=Debug] = org.example.agentharnessmanager.dev
// DEVELOPMENT_TEAM = <your-Apple-team-id>
```

The legacy setting name is intentional. Changing the bundle ID also changes the preferences domain, so existing configurations will not appear under the new ID. Never commit signing identities or private keys.

`project.yml` is the source for the checked-in Xcode project. If you change project configuration, regenerate with XcodeGen and include the generated changes:

```sh
xcodegen generate --spec project.yml
```

## Checks

Run these from the repository root:

```sh
swift test --package-path Packages/SkillCore
scripts/check-app-state.sh
scripts/check-management.sh
node scripts/check-design.mjs
xcodebuild -project AgentHarnessManager.xcodeproj \
  -scheme AgentHarnessManager -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Node.js 22+ is needed for the design check and Python 3 for CLI/MCP checks; no npm dependencies are required. Core tests use temporary folders, and the app-state check uses a temporary home and isolated preferences. They do not modify your installed skills or saved app settings.

The GitHub Actions workflow is configured to run these checks on pull requests and pushes to `main`. It uses the [macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) and a pinned [checkout action](https://github.com/actions/checkout).

For UI changes, also inspect the native app in light and dark mode and verify keyboard access to the affected controls. Run `scripts/check-settings.sh` from a logged-in macOS desktop to check actual settings-category clicks, General, all eight connection rows, and the native skill-path agent picker. It uses synthetic paths and refreshes the native settings screenshots; it is separate from headless CI. Prototype checks do not validate native UI behavior or filesystem writes.

Run `scripts/check-settings.sh --accessibility` for native accessibility-tree names, values and actions, sidebar Tab/Shift-Tab/Space, accessible picker selection, and group-sheet focus/Escape checks. The optional runner requires existing macOS Accessibility access and exits without requesting it when unavailable. It launches only its own isolated fixture; it never changes system keyboard navigation or VoiceOver settings. Spoken VoiceOver output and global all-controls Tab traversal still need manual verification. Failed expectations exit with a log message instead of generating crash dialogs.

## Pull requests

- Keep changes focused and explain the user-visible result and relevant checks.
- Reuse existing types and platform controls; add dependencies only for a demonstrated need.
- Preserve separate identities for copies and links. Catalog discovery must not imply that an agent loaded a skill.
- Keep discovery, reading, metadata editing, and group selection free of file changes. File switches require explicit previews, conflict handling, durable recovery, and tests. Exercise writes only with synthetic temporary skills during development checks.
- Update both [README.md](README.md) and [README.ko.md](README.ko.md) when behavior or setup changes. Detailed design notes may remain in Korean; new contributor-facing documentation should be in English.
- Use synthetic examples and original assets in new documentation. Link to third-party reference material instead of copying it into the repository.

Be respectful in issues and reviews. Critique changes and ideas, and give others enough context to reproduce a problem.
