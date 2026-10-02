# Contributing

Thanks for helping improve Agent Plugin Manager. Bug reports, feature proposals, code, and documentation changes are welcome in English or Korean.

## Before making a change

Read the [README](README.md) for implemented features and the [documentation index](docs/README.md) for design context. Discuss larger changes in an issue first. Include a concrete user task and the agent involved; support can differ between agents.

For bugs, include your macOS and Xcode versions, build configuration, reproduction steps, and expected and actual behavior. Use a small synthetic skill folder when possible. Remove personal paths, credentials, and private skill content from screenshots and logs. Report security issues through [SECURITY.md](SECURITY.md).

## Development setup

Use macOS 26+ and Xcode 26+ with Swift 6.2+. Open `AgentPluginManager.xcodeproj` and select the `AgentPluginManager` scheme. Debug builds have a separate app name, icon, and preferences domain from Release.

No Apple team is required for the default ad-hoc signing setup. To customize your local identity, create `Config/Local.xcconfig`, which is ignored by Git:

```xcconfig
AGENT_SKILL_MANAGER_BUNDLE_ID = org.example.agentpluginmanager
AGENT_SKILL_MANAGER_BUNDLE_ID[config=Debug] = org.example.agentpluginmanager.dev
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
node scripts/check-design.mjs
xcodebuild -project AgentPluginManager.xcodeproj \
  -scheme AgentPluginManager -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Node.js 22+ is needed for the design check; no npm dependencies are required. Core tests use temporary folders, and the app-state check uses a temporary home and isolated preferences. They do not modify your installed skills or saved app settings.

The GitHub Actions workflow is configured to run these checks on pull requests and pushes to `main`. It uses the [macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) and a pinned [checkout action](https://github.com/actions/checkout).

For UI changes, also inspect the native app in light and dark mode and verify keyboard access to the affected controls. Prototype checks do not validate native UI behavior or filesystem writes.

## Pull requests

- Keep changes focused and explain the user-visible result and relevant checks.
- Reuse existing types and platform controls; add dependencies only for a demonstrated need.
- Preserve separate identities for copies and links. Catalog discovery must not imply that an agent loaded a skill.
- Keep user skill files unchanged in the current implementation. File-changing features need explicit previews, conflict handling, recovery, and tests before they can reach user files.
- Update both [README.md](README.md) and [README.ko.md](README.ko.md) when behavior or setup changes. Detailed design notes may remain in Korean; new contributor-facing documentation should be in English.
- Use synthetic examples and original assets in new documentation. Link to third-party reference material instead of copying it into the repository.

Be respectful in issues and reviews. Critique changes and ideas, and give others enough context to reproduce a problem.
