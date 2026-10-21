import AppKit
import SkillCore

@main
struct AppStateCheck {
    private static func check(_ condition: Bool, _ message: String = "State regression check") {
        guard condition else { fputs("FAIL: " + message + "\n", stderr); exit(1) }
    }

    @MainActor static func main() async throws {
        try await checkSkillLifecycle()
        try await checkSkillsCLIInstallation()
        try await checkSkillsCLIBatchRemoval()
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("SkillAppCheck-\(UUID().uuidString)")
        let suite = "SkillAppCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? files.removeItem(at: home)
            defaults.removePersistentDomain(forName: suite)
        }
        try files.createDirectory(at: home.appendingPathComponent(".grok/skills"), withIntermediateDirectories: true)
        let body = "---\nname: check\ndescription: Temporary check\n---\nRead only\n"
        for path in [".agents/skills/codex-check", ".claude/skills/claude-check", "manual/custom-check", "replacement/replacement-check"] {
            let directory = home.appendingPathComponent(path)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try body.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        precondition(store.page == .library && store.entries.count == 2)
        check(AppDestination.allCases == [.skills, .instructions, .activity])
        for page in AppPage.allCases {
            let expected: AppDestination = [.library, .findings, .groups].contains(page) ? .skills
                : page == .instructions ? .instructions : .activity
            check(page.destination == expected, "Every page must map to one of the three task destinations")
        }
        check(store.lastActivityPage == .history)
        store.navigate(to: .activity)
        check(store.page == .history)
        store.page = .requests
        store.navigate(to: .instructions)
        check(store.page == .instructions && store.lastActivityPage == .requests)
        store.navigate(to: .activity)
        check(store.page == .requests, "Activity must return to its last section")
        store.page = .changes
        store.search = "retain activity search"
        store.navigate(to: .activity)
        check(store.page == .changes && store.search == "retain activity search",
            "Clicking the current destination must preserve its section and search")
        store.navigate(to: .skills)
        check(store.page == .library && !store.hasFilters && store.lastActivityPage == .changes)
        store.page = .profiles
        store.navigate(to: .instructions)
        store.navigate(to: .activity)
        check(store.page == .history && store.lastActivityPage == .history,
            "Activity must fall back to history when the remembered legacy profiles section is empty")
        store.navigate(to: .skills)
        store.agentFilter = .opencode
        precondition(store.filteredEntries.count == 2 && store.filteredSkills.count == 2)
        store.rootFilterID = store.automaticRoots[0].id
        precondition(store.agentFilter == .opencode && store.filteredEntries.count == 1)
        store.agentFilter = .cursor
        precondition(store.rootFilterID == store.automaticRoots[0].id && store.filteredSkills.count == 1)
        store.agentFilter = .antigravity
        precondition(store.rootFilterID == nil && store.filteredEntries.isEmpty)
        store.resetFilters()
        precondition(store.entries.count == 2 && store.availableAgents.count == 8)
        let profileID = UUID()
        let members = Set(store.entries.map(\.id))
        precondition(store.saveProfile(id: profileID, name: "  Writing  ", note: "Daily work", memberIDs: members))
        precondition(store.selectedProfile?.name == "Writing" && store.selectedProfile?.members.count == 2)
        store.search = "Daily"
        precondition(store.filteredProfiles.count == 1)
        store.search = "no-match"
        precondition(store.filteredProfiles.isEmpty && store.selectedProfile == nil)
        store.showLibrary()
        store.agentFilter = .codex
        precondition(store.filteredEntries.map(\.name) == ["codex-check"])
        store.search = "claude-check"
        precondition(store.filteredEntries.isEmpty)
        store.resetFilters()
        precondition(!store.hasFilters && store.filteredEntries.count == 2)
        let manual = home.appendingPathComponent("manual")
        precondition(store.addRoot(url: manual, agent: .custom, name: "Other Agent"))
        precondition(!store.addRoot(url: manual, agent: .custom, name: "Duplicate"))
        precondition(!store.addRoot(url: URL(string: "https://example.com/skills")!, agent: .custom, name: "Remote"))
        let restored = AppStore(defaults: defaults, home: home)
        await restored.rescan()
        precondition(restored.page == .library && restored.selectedProfile?.id == profileID)
        precondition(!restored.saveProfile(id: profileID, name: " ", note: "", memberIDs: members))
        precondition(!restored.saveProfile(id: profileID, name: String(repeating: "a", count: 81), note: "", memberIDs: members))
        precondition(!restored.saveProfile(id: UUID(), name: "Forged", note: "", memberIDs: ["unregistered-file"]))
        let claudeFolder = home.appendingPathComponent(".claude/skills/claude-check")
        let hiddenFolder = home.appendingPathComponent("hidden-claude-check")
        try files.moveItem(at: claudeFolder, to: hiddenFolder)
        await restored.rescan()
        precondition(restored.entries.count == 2 && restored.selectedProfile?.members.count == 2)
        precondition(restored.saveProfile(id: profileID, name: "Writing updated", note: "", memberIDs: members))
        precondition(Set(restored.selectedProfile!.members.map(\.id)) == members)
        precondition(!restored.saveProfile(id: UUID(), name: "Missing", note: "", memberIDs: members))
        try files.moveItem(at: hiddenFolder, to: claudeFolder)
        await restored.rescan()
        let validData = defaults.data(forKey: "workProfiles")!
        let corruptData = Data("invalid JSON".utf8)
        defaults.set(corruptData, forKey: "workProfiles")
        let corrupt = AppStore(defaults: defaults, home: home)
        await corrupt.rescan()
        precondition(corrupt.profilesLoadFailed && !corrupt.profilesAreEditable)
        precondition(!corrupt.saveProfile(id: UUID(), name: "New", note: "", memberIDs: []))
        precondition(defaults.data(forKey: "workProfiles") == corruptData)
        defaults.set(validData, forKey: "workProfiles")
        precondition(restored.entries.count == 3 && restored.additionalRoots.count == 1)
        var root = restored.additionalRoots[0]
        restored.showLibrary(rootID: root.id)
        precondition(restored.filteredEntries.map(\.name) == ["custom-check"])
        restored.search = "Other Agent"
        precondition(restored.filteredEntries.count == 1)
        let replacement = home.appendingPathComponent("replacement")
        let defaultRoot = restored.automaticRoots[0]
        precondition(!restored.addRoot(url: replacement, agent: defaultRoot.agent, name: "Default edit", replacing: defaultRoot))
        let forgedDefault = DiscoveryRoot(agent: defaultRoot.agent, url: defaultRoot.url, label: "Different label")
        await restored.removeRoot(forgedDefault)
        precondition(restored.registeredRoots.contains { $0.id == defaultRoot.id })
        precondition(restored.addRoot(url: replacement, agent: .custom, name: "Duplicate target"))
        precondition(!restored.addRoot(url: replacement, agent: .custom, name: root.label, replacing: root))
        precondition(restored.additionalRoots.contains { $0.id == root.id })
        let duplicateTarget = restored.additionalRoots.first { $0.url == replacement }!
        await restored.removeRoot(duplicateTarget)
        restored.showLibrary(rootID: root.id)
        restored.selectedEntry = restored.filteredEntries.first
        precondition(restored.addRoot(url: replacement, agent: .custom, name: root.label, replacing: root))
        root = restored.additionalRoots[0]
        await restored.rescan()
        precondition(restored.rootFilterID == root.id && restored.selectedEntry == nil)
        precondition(restored.filteredEntries.map(\.name) == ["replacement-check"])
        precondition(AppStore(defaults: defaults, home: home).additionalRoots[0].url == replacement)
        precondition(!restored.addRoot(url: URL(string: "https://example.com/skills")!, agent: .custom, name: root.label, replacing: root))
        precondition(restored.additionalRoots[0].url == replacement)
        precondition(restored.profiles.first?.members.count == 2)
        restored.page = .findings
        precondition(restored.rootFilterID == nil && !restored.hasFilters && restored.filteredEntries.isEmpty)
        await restored.removeRoot(root)
        precondition(restored.entries.count == 2 && restored.additionalRoots.isEmpty)
        precondition(AppStore(defaults: defaults, home: home).additionalRoots.isEmpty)
        let preserved = try String(contentsOf: manual.appendingPathComponent("custom-check/SKILL.md"), encoding: .utf8)
        precondition(preserved == body)
        await restored.removeRoot(restored.automaticRoots[0])
        precondition(restored.registeredRoots.count == restored.automaticRoots.count)
        let missing = home.appendingPathComponent("missing")
        precondition(restored.addRoot(url: missing, agent: .custom, name: "Missing Agent"))
        await restored.rescan()
        precondition(restored.findingCount == 1 && restored.availableAgents.contains(.custom))
        restored.agentFilter = .custom
        precondition(restored.filteredProblemRoots.count == 1)
        restored.deleteProfile(profileID)
        precondition(AppStore(defaults: defaults, home: home).profiles.isEmpty)
        for path in [".agents/skills/codex-check", ".claude/skills/claude-check", "manual/custom-check", "replacement/replacement-check"] {
            let content = try String(contentsOf: home.appendingPathComponent(path + "/SKILL.md"), encoding: .utf8)
            precondition(content == body)
        }
        let sourceID = UUID()
        precondition(restored.saveProfile(id: sourceID, name: "Shared skills", note: "", memberIDs: members))
        let importedIDs = restored.profileMemberIDs(sourceID)!
        precondition(importedIDs == members && importedIDs.union(members) == members)
        let targetID = UUID()
        precondition(restored.saveProfile(id: targetID, name: "Imported selection", note: "", memberIDs: importedIDs))
        let importedReload = AppStore(defaults: defaults, home: home)
        precondition(importedReload.profiles.first { $0.id == targetID }?.members.count == 2)
        try files.moveItem(at: claudeFolder, to: hiddenFolder)
        await restored.rescan()
        precondition(restored.profileMemberIDs(sourceID) == nil && restored.profiles.first { $0.id == sourceID }?.members.count == 2)
        try files.moveItem(at: hiddenFolder, to: claudeFolder)
        await restored.rescan()
        precondition(restored.saveProfile(id: sourceID, name: "Shared skills", note: "", memberIDs: [members.first!]))
        precondition(restored.profiles.first { $0.id == targetID }?.members.count == 2, "Imports are snapshots")
        restored.deleteProfile(sourceID)
        precondition(restored.profileMemberIDs(sourceID) == nil && restored.profiles.first { $0.id == targetID }?.members.count == 2)
        restored.deleteProfile(targetID)
        precondition(AppStore(defaults: defaults, home: home).profiles.isEmpty)
        try await checkSources()
        try await checkLibrary()
        try await checkChangeHistory()
        try await checkLinkSwitching()
        try await checkAgentRequests()
        try await checkAgentInstallations()
        try await checkInstructions()
        print("PASS: profile create/edit/search/reload/delete, missing members preserved, invalid/corrupt state blocked, filters, fixed default paths, additional path edit/delete/reload, import profiles, reject missing members, preserve imported snapshots, no skill file changes")
    }

    @MainActor private static func checkInstructions() async throws {
        func check(_ condition: Bool, _ message: String) {
            if !condition { fputs("FAIL: " + message + "\n", stderr); exit(1) }
        }
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("ahm-instructions-state-" + UUID().uuidString)
        let suite = "ahm-instructions-state." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let url = home.appendingPathComponent(".codex/AGENTS.md")
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Original\n".write(to: url, atomically: true, encoding: .utf8)
        let app = AppStore(defaults: defaults, home: home, instructionEnvironment: [:])
        let store = app.instructions
        await store.refresh()
        check(store.text == "Original\n" && !store.hasDrafts, "Initial instruction discovery")
        store.edit("Draft\n")
        for agent in [SkillAgent.cursor, .devin] {
            store.chooseAgent(agent)
            check(!store.supported && store.selectedDocument == nil, "Unsupported global instruction agents")
        }
        store.chooseAgent(.codex)
        app.page = .instructions
        for page in [AppPage.groups, .findings, .requests, .changes, .history, .profiles, .library] {
            app.page = page
            app.clearLibraryFilters()
            check(store.text == "Draft\n" && store.hasDrafts, "Task navigation and filter clearing must preserve instruction drafts")
        }
        check(store.text == "Draft\n" && store.hasDrafts, "Navigation must preserve instruction drafts")
        try "External\n".write(to: url, atomically: true, encoding: .utf8)
        await store.refresh()
        check(store.text == "Draft\n" && store.externallyChanged && !store.canSave, "Refresh preserves drafts and blocks external conflicts")
        store.discardDraft()
        check(store.text == "External\n" && !store.hasDrafts, "Discard must expose the current file")
        store.edit("Saved\n")
        await store.prepareSave()
        check(try String(contentsOf: url, encoding: .utf8) == "External\n", "Preview must not write instructions")
        guard let plan = store.preview else { throw NSError(domain: "Instruction preview", code: 1) }
        check(await store.apply(plan), "Apply instruction preview")
        check(store.text == "Saved\n" && !store.hasDrafts && store.backups.count == 1, "Saved instruction state and backup")
        await store.prepareRestore(store.backups[0])
        guard let restore = store.preview else { throw NSError(domain: "Instruction restore", code: 1) }
        check(await store.apply(restore), "Restore instruction backup")
        check(try String(contentsOf: url, encoding: .utf8) == "External\n", "Restore must recover the prior contents")
        check(store.creationUndo == nil, "An existing instruction file must never expose creation undo")
        store.chooseAgent(.grokBuild)
        let createdURL = store.selectedDocument!.url
        check(!store.canSave && !store.isCreating, "Missing files must start without an implicit creation")
        store.beginCreation()
        await store.refresh()
        check(store.isCreating && !store.canSave && !files.fileExists(atPath: createdURL.path), "An empty creation draft survives refresh without creating a file")
        store.edit(" \n\t")
        check(!store.canSave, "Whitespace must not create an empty priority file")
        store.edit("New instruction\n")
        check(store.canSave && store.hasDraft(for: store.selectedDocument!), "A nonempty creation draft can be reviewed")
        await store.prepareSave()
        guard let creation = store.preview else { throw NSError(domain: "Instruction creation", code: 1) }
        check(creation.document.data == nil && !files.fileExists(atPath: createdURL.path), "Creation review must not create a file")
        check(await store.apply(creation), "Apply new instruction creation")
        guard let creationBackup = store.creationUndo else { throw NSError(domain: "Creation undo eligibility", code: 1) }
        try files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: createdURL.path)
        await store.refresh()
        check(store.creationUndo == nil, "Read-only files must not expose creation undo")
        try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: createdURL.path)
        await store.refresh()
        store.edit("Changed since creation\n")
        check(store.creationUndo == nil, "Dirty drafts must block creation undo")
        store.discardDraft()
        await store.prepareRestore(creationBackup)
        guard let undoCreation = store.preview else { throw NSError(domain: "Undo creation review", code: 1) }
        check(undoCreation.replacementData == nil && files.fileExists(atPath: createdURL.path), "Creation undo must remain a preview")
        check(await store.apply(undoCreation), "Apply reviewed creation undo")
        check(!files.fileExists(atPath: createdURL.path) && store.selectedDocument?.data == nil && store.backups.count == 2, "Creation undo removes only the new file and retains its candidate and backups")
        store.beginCreation()
        store.edit("Cancelled draft")
        store.discardDraft()
        check(!store.isCreating && !store.hasDrafts && !files.fileExists(atPath: createdURL.path), "Discarding a new draft must never create a file")
        store.chooseAgent(.codex)
        let override = store.agentDocuments.first { $0.url.lastPathComponent == "AGENTS.override.md" }!
        store.selectedID = override.id
        store.beginCreation()
        store.chooseAgent(.grokBuild)
        store.chooseAgent(.codex)
        check(store.selectedID == override.id && store.isCreating, "Returning to an agent must select its unfinished creation draft")
        try "Created outside the app\n".write(to: override.url, atomically: true, encoding: .utf8)
        await store.refresh()
        check(store.text == "Created outside the app\n" && !store.isCreating && !store.externallyChanged, "An empty draft must yield to a file created externally")
        print("PASS: instruction drafts, unsupported agents, navigation, external conflicts, reviewed writes, explicit nonempty creation, protected existing files and reviewed creation undo")
    }

    @MainActor private static func checkAgentInstallations() async throws {
        func check(_ condition: Bool, _ message: String) {
            if !condition { fputs("FAIL: " + message + "\n", stderr); exit(1) }
        }
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("ahm-installation-check-" + UUID().uuidString)
        let suite = "ahm-installation-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let bin = home.appendingPathComponent("bin")
        let skill = home.appendingPathComponent(".agents/skills/synthetic/SKILL.md")
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try files.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: synthetic\ndescription: Installation fixture\n---\nRead only".write(to: skill, atomically: true, encoding: .utf8)
        let codex = bin.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: codex)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codex.path)
        let detector = AgentInstallationDetector(executableDirectories: [bin], applicationDirectories: [])
        let store = AppStore(defaults: defaults, home: home, installationDetector: detector)
        await store.rescan()
        check(store.availableAgents.count == 8 && store.sidebarAgents == [.codex], "Only a detected agent belongs in the sidebar")
        check(store.entries.count == 1 && store.registeredRoots.count == store.automaticRoots.count, "Detection must preserve skill discovery and paths")
        check(store.addRoot(url: home.appendingPathComponent("manual"), agent: .custom, name: "Manual agent"), "Custom path registration remains available")
        check(store.sidebarAgents == [.codex, .custom], "Explicitly registered custom agents remain accessible")
        store.navigate(agent: .codex)
        try files.removeItem(at: codex)
        await store.refreshAgentInstallations()
        check(store.sidebarAgents == [.custom] && store.agentFilter == nil, "Uninstalling the selected agent must clear its stale filter")
        check(try String(contentsOf: skill, encoding: .utf8) == "---\nname: synthetic\ndescription: Installation fixture\n---\nRead only", "Installation refresh must preserve skill documents")
        print("PASS: installed-agent sidebar, complete settings/path data, explicit custom agents, uninstall refresh and skill preservation")
    }

    @MainActor private static func checkAgentRequests() async throws {
        let files = FileManager.default, domain = "ahm-request-check-" + UUID().uuidString
        let home = files.temporaryDirectory.appendingPathComponent(domain).resolvingSymlinksInPath()
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? files.removeItem(at: home) }
        let document = home.appendingPathComponent(".agents/skills/example/SKILL.md")
        try files.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: example\ndescription: Request check\n---\nHello".write(to: document, atomically: true, encoding: .utf8)
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        let bundleID = Bundle.main.bundleIdentifier ?? "AgentHarnessManager"
        let config = try ManagementConfiguration(home: home, domain: bundleID,
            preferencesData: JSONEncoder().encode(store.preferences), rootsData: nil)
        let snapshot = try await ManagementService.snapshot(configuration: config)
        let ids = snapshot.installations.map(\.id)
        let plan = try snapshot.plan(installationIDs: ids, enabled: false, title: "Agent request")
        let request = AgentChangeRequest(snapshot: snapshot, plan: plan, installationIDs: ids, enabled: false)
        try await AgentRequestStore(stateDirectory: config.stateDirectory).submit(request)
        await store.refreshAgentRequests()
        precondition(store.agentRequests.map(\.id) == [request.id] && store.mutationPreview == nil)
        precondition(files.fileExists(atPath: document.path), "Queueing must not change skills")
        await store.prepareAgentRequest(request)
        precondition(store.mutationPreview?.id == request.id)
        store.cancelPreview()
        precondition(files.fileExists(atPath: document.path), "Cancel must not change skills")
        await store.prepareAgentRequest(request)
        await store.applyPreview()
        precondition(store.agentRequestState(request) == "적용 완료" && store.journal.completed.first?.id == request.id)
        precondition(!files.fileExists(atPath: document.path))
        await store.prepareAgentRequest(request)
        precondition(store.mutationPreview == nil, "Completed requests cannot be replayed")
        await store.dismissAgentRequest(request)
        precondition(store.agentRequests.isEmpty && store.journal.completed.count == 1)
        print("PASS: agent request queue, rebuilt app preview, cancel, explicit apply, journal correlation and replay rejection; isolated files/settings only")
    }

    @MainActor private static func checkSources() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("SourceAppCheck-\(UUID().uuidString)")
        let suite = "SourceAppCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        for path in [".agents/skills/example", ".claude/skills/example", "manual/example"] {
            let directory = home.appendingPathComponent(path)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try "read only".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try files.createSymbolicLink(at: home.appendingPathComponent(".claude/skills/shared"), withDestinationURL: home.appendingPathComponent(".agents/skills/example"))
        let receipt = Data(#"{"version":3,"skills":{"example":{"sourceType":"github","sourceUrl":"https://github.com/Owner/Repo.git"}}}"#.utf8)
        let lock = home.appendingPathComponent(".agents/.skill-lock.json")
        try receipt.write(to: lock)
        let store = AppStore(defaults: defaults, home: home)
        precondition(store.addRoot(url: home.appendingPathComponent("manual"), agent: .custom, name: "Other"))
        await store.rescan()
        precondition(store.entries.count == 4 && store.sourceGroups.count == 1 && store.sourceGroups[0].count == 2)
        precondition(store.unknownSourceCount == 2)
        let repo = SourceRepository("Owner/Repo")!
        precondition(repo.id == SourceRepository("git@github.com:owner/repo.git")?.id)
        for invalid in ["https://token@github.com/owner/repo", "file:///owner/repo", "https://github.com/owner/repo?token=secret", "https://github.com/owner/../repo", "owner/repo/tree/main"] {
            precondition(SourceRepository(invalid) == nil)
        }
        store.showLibrary(sourceID: repo.id)
        precondition(store.filteredEntries.count == 2 && store.sourceEntryCount == 2 && store.sourceTitle == "owner/repo")
        store.agentFilter = .claudeCode
        store.linksOnly = true
        precondition(store.filteredEntries.map(\.name) == ["shared"])
        let codexRoot = store.automaticRoots[0]
        let claudeRoot = store.automaticRoots[1]
        precondition(store.availableRoots.map(\.id) == [claudeRoot.id])
        store.rootFilterID = codexRoot.id
        precondition(store.agentFilter == .codex && store.availableRoots.map(\.id) == [codexRoot.id])
        precondition(store.filteredEntries.isEmpty && store.sourceEntryCount == 2)
        store.linksOnly = false
        precondition(store.filteredEntries.map(\.id) == [store.entries.first { $0.agent == .codex }!.id])
        store.agentFilter = .claudeCode
        precondition(store.rootFilterID == nil && store.filteredEntries.map(\.name) == ["shared"])
        store.rootFilterID = claudeRoot.id
        precondition(store.agentFilter == .claudeCode)
        store.rootFilterID = nil
        precondition(store.agentFilter == .claudeCode && store.availableRoots.count == 1)
        store.rootFilterID = claudeRoot.id
        store.agentFilter = nil
        precondition(store.rootFilterID == nil && store.availableRoots.count == store.automaticRoots.count + 1)
        store.rootFilterID = codexRoot.id
        store.agentFilter = .codex
        precondition(store.rootFilterID == codexRoot.id, "Compatible locations stay selected")
        let empty = home.appendingPathComponent("empty-codex")
        try files.createDirectory(at: empty, withIntermediateDirectories: true)
        precondition(store.addRoot(url: empty, agent: .codex, name: "Codex · additional"))
        let emptyRoot = DiscoveryRoot(agent: .codex, url: empty, label: "Codex · additional")
        precondition(store.additionalRoots.contains { $0.id == emptyRoot.id })
        store.rootFilterID = emptyRoot.id
        store.search = "owner/repo"
        await store.rescan()
        precondition(store.filteredEntries.isEmpty && store.agentFilter == .codex && store.rootFilterID == emptyRoot.id)
        precondition(store.availableRoots.count == 2, "All matching registered paths remain choices even without results")
        await store.removeRoot(emptyRoot)
        precondition(store.rootFilterID == nil && store.agentFilter == .codex && store.sourceFilterID == repo.id && store.search == "owner/repo")
        store.showLibrary(rootID: claudeRoot.id, sourceID: repo.id)
        precondition(store.agentFilter == .claudeCode && store.filteredEntries.map(\.name) == ["shared"])
        store.rootFilterID = "unregistered-location"
        precondition(store.rootFilterID == nil && store.agentFilter == .claudeCode)
        store.resetFilters()
        precondition(store.sourceFilterID == repo.id && store.filteredEntries.count == 2)
        store.search = "owner/repo"
        precondition(store.filteredEntries.count == 2)
        let copy = store.entries.first { $0.agent == .custom }!
        precondition(store.sourceRepository(for: copy) == nil, "Same names are not provenance")
        precondition(!store.saveSource(for: copy, input: "https://user:password@example.com/a/b"))
        precondition(store.saveSource(for: copy, input: "owner/repo"))
        precondition(store.sourceEvidence(for: copy) == "직접 연결" && store.sourceGroups[0].count == 3)
        let profileID = UUID()
        precondition(store.saveProfile(id: profileID, name: "Independent", note: "", memberIDs: [copy.id]))
        let restored = AppStore(defaults: defaults, home: home)
        await restored.rescan()
        precondition(restored.sourceRepository(for: copy) == repo && restored.profiles.first?.members.count == 1)
        let installed = restored.entries.first { $0.agent == .codex }!
        precondition(restored.saveSource(for: installed, input: "another/repo"))
        precondition(restored.sourceEvidence(for: installed) == "직접 연결")
        precondition(restored.saveSource(for: installed, input: nil) && restored.sourceRepository(for: installed) == repo)
        precondition(restored.sourceEvidence(for: installed) == "설치 기록")
        restored.showLibrary(sourceID: AppStore.unknownSourceID)
        precondition(restored.filteredEntries.count == 1)
        restored.page = .profiles
        precondition(restored.sourceFilterID == nil && restored.profiles.first?.members.count == 1)
        try files.moveItem(at: copy.url, to: home.appendingPathComponent("held"))
        try files.createDirectory(at: copy.url, withIntermediateDirectories: true)
        try "replacement".write(to: copy.url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        await restored.rescan()
        let replacement = restored.entries.first { $0.agent == .custom }!
        precondition(replacement.id != copy.id && restored.sourceRepository(for: replacement) == nil)
        precondition(!restored.saveSource(for: copy, input: "another/repo"))
        let corrupt = Data("invalid JSON".utf8)
        defaults.set(corrupt, forKey: "skillSources")
        let blocked = AppStore(defaults: defaults, home: home)
        await blocked.rescan()
        precondition(blocked.sourcesLoadFailed && !blocked.saveSource(for: replacement, input: "owner/repo"))
        precondition(defaults.data(forKey: "skillSources") == corrupt)
        let unchangedReceipt = try Data(contentsOf: lock)
        precondition(unchangedReceipt == receipt)
        let unchangedSkill = try String(contentsOf: home.appendingPathComponent("held/SKILL.md"), encoding: .utf8)
        precondition(unchangedSkill == "read only")
        let customRoot = restored.additionalRoots.first { $0.agent == .custom }!
        restored.showLibrary(rootID: customRoot.id, sourceID: repo.id)
        await restored.removeRoot(customRoot)
        precondition(restored.rootFilterID == nil && restored.agentFilter == nil && restored.sourceFilterID == repo.id)
        precondition(!restored.availableAgents.contains(.custom), "Removing the last path removes its agent option without losing the source")
        print("PASS: receipt provenance, copies/links, source counts/search, linked agent/location filters, multiple/empty paths, root edit/removal, manual override/unlink/reload, independent profiles, replacement identity, credential rejection, corrupt metadata preserved, no source file changes")
    }

    @MainActor private static func checkLinkSwitching() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LinkAppCheck-\(UUID().uuidString)")
        let suite = "LinkAppCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let source = home.appendingPathComponent(".agents/skills/source")
        let codexLink = home.appendingPathComponent(".agents/skills/codex-link")
        let claudeLink = home.appendingPathComponent(".claude/skills/claude-link")
        let body = "---\nname: shared\ndescription: Linked skill\n---\nOriginal content\n"
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        try files.createDirectory(at: claudeLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try files.createSymbolicLink(atPath: codexLink.path, withDestinationPath: "source")
        try files.createSymbolicLink(atPath: claudeLink.path, withDestinationPath: "../../.agents/skills/source")
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        precondition(store.skills.count == 1 && store.allInstallations.count == 3)
        let skillID = store.skills[0].id
        let sourceID = store.allInstallations.first { !$0.isSymbolicLink }!.id
        let group = SkillGroup(name: "Linked group", skillIDs: [skillID])
        precondition(store.saveGroup(group))
        store.toggleFavorite(skillID)
        let claude = store.allInstallations.first { $0.originalPath == claudeLink.path }!
        precondition(store.saveSource(for: claude.entry, input: "owner/shared"))
        await store.prepareGroupChange(group, enabled: true)
        precondition(store.preferences.activeGroupIDs == [group.id])
        await store.prepareChange(title: "Claude link", installations: [claude], enabled: false)
        precondition(store.mutationPreview?.installations.count == 1 && store.mutationPreview?.installations[0].installation.link != nil)
        await store.applyPreview()
        precondition(store.journal.version == 2 && store.skills[0].id == skillID)
        precondition(store.allInstallations.first { $0.originalPath == codexLink.path }!.isEnabled)
        let storedClaude = store.allInstallations.first { $0.id == claude.id }!
        precondition(!storedClaude.isEnabled && storedClaude.isSymbolicLink && storedClaude.readError == nil)
        precondition(store.sourceRepository(for: storedClaude) == SourceRepository("owner/shared"))
        let storedDocument = try LibraryCatalog.readDocument(installation: storedClaude, roots: store.registeredRoots)
        precondition(storedDocument == body)
        await store.prepareUndo(store.journal.completed[0])
        await store.applyPreview()
        await store.prepareGroupChange(group, enabled: false)
        precondition(store.mutationPreview?.installations.count == 2)
        precondition(store.mutationPreview!.installations.allSatisfy { $0.installation.link != nil })
        await store.applyPreview()
        precondition(store.preferences.activeGroupIDs.isEmpty)
        precondition(store.skills[0].activationInstallations.allSatisfy { !$0.isEnabled })
        precondition(store.allInstallations.first { $0.id == sourceID }!.isEnabled)
        precondition(store.skills[0].isEnabled, "The original source remains enabled even when installation links are off")
        let reloaded = AppStore(defaults: defaults, home: home)
        await reloaded.rescan()
        precondition(reloaded.skills[0].id == skillID && reloaded.preferences.favorites.contains(skillID))
        precondition(reloaded.groups[0].skillIDs == [skillID] && reloaded.journal.disabled.count == 2)
        await reloaded.prepareUndo(reloaded.journal.completed[0])
        await reloaded.applyPreview()
        precondition(reloaded.preferences.activeGroupIDs == [group.id] && reloaded.journal.disabled.isEmpty)
        await reloaded.prepareGroupChange(group, enabled: false)
        let pending = reloaded.mutationPreview!
        reloaded.cancelPreview()
        var journal = reloaded.journal; journal.pending = pending
        let journalPath = home.appendingPathComponent("Library/Application Support/" + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager") + "/Library/library-journal.json")
        try JSONEncoder().encode(journal).write(to: journalPath)
        try files.moveItem(atPath: pending.installations[0].source, toPath: pending.installations[0].destination)
        let recovering = AppStore(defaults: defaults, home: home)
        await recovering.rescan()
        precondition(recovering.journal.disabled.count == 1 && recovering.skills[0].id == skillID)
        await recovering.recoverChanges()
        precondition(recovering.journal.disabled.count == 2 && recovering.preferences.activeGroupIDs.isEmpty)
        let original = recovering.allInstallations.first { $0.id == sourceID }!
        await recovering.prepareChange(title: "Protected source", installations: [original], enabled: false)
        precondition(recovering.mutationPreview == nil && recovering.libraryMessage != nil)
        let preservedDocument = try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
        precondition(preservedDocument == body)
        print("PASS: agent-specific relative link switching, canonical/favorite/group/source identity, shared-source protection, group link-only changes, undo, partial link recovery and selection reconciliation")
    }

    @MainActor private static func checkChangeHistory() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ChangeHistoryCheck-\(UUID().uuidString)")
        let suite = "ChangeHistoryCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let directory = home.appendingPathComponent(".agents/skills/history-skill")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: history-skill\ndescription: History test\n---\nBody\n".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        let group = SkillGroup(name: "Test group", skillIDs: [store.skills[0].id])
        precondition(store.saveGroup(group))
        await store.prepareGroupChange(group, enabled: true)
        precondition(store.preferences.activeGroupIDs == [group.id] && store.journal.completed.count == 1)
        let before = defaults.data(forKey: "libraryPreferences.v1")!
        await store.prepareGroupChange(group, enabled: false)
        let plan = store.mutationPreview!
        precondition(plan.groupSelection?.before == [group.id] && plan.groupSelection?.after == [])
        precondition(!store.metadataIsEditable, "Group edits are locked while a plan is open")
        await store.applyPreview()
        precondition(store.preferences.activeGroupIDs.isEmpty && !store.skills[0].isEnabled)
        // Simulate a process ending after the completed journal commit but before preferences were saved.
        defaults.set(before, forKey: "libraryPreferences.v1")
        let restarted = AppStore(defaults: defaults, home: home)
        await restarted.rescan()
        precondition(!restarted.groupSyncFailed && restarted.preferences.activeGroupIDs.isEmpty)
        precondition(restarted.preferences.lastAppliedGroupChangeID == plan.id)
        restarted.page = .changes
        restarted.selectedMutationID = plan.id
        precondition(restarted.selectedMutation?.id == plan.id)
        restarted.search = "history-skill"
        precondition(restarted.filteredMutations.count == 1, "History searches installation paths")
        await restarted.prepareUndo(plan)
        precondition(restarted.mutationPreview?.undoes == plan.id)
        restarted.cancelPreview()
        precondition(!restarted.skills[0].isEnabled && restarted.preferences.activeGroupIDs.isEmpty)
        await restarted.prepareUndo(plan)
        await restarted.applyPreview()
        precondition(restarted.skills[0].isEnabled && restarted.preferences.activeGroupIDs == [group.id])
        precondition(restarted.undoUnavailableReason(for: plan) != nil)
        precondition(restarted.selectedMutation?.undoes == plan.id)
        precondition(restarted.journal.completed.count == 3)

        // Persist a pending group transition, then restart and finish it through the recovery path.
        await restarted.prepareGroupChange(group, enabled: false)
        let pending = restarted.mutationPreview!
        var journal = restarted.journal
        journal.pending = pending
        let journalPath = home.appendingPathComponent("Library/Application Support/" + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager") + "/Library/library-journal.json")
        try JSONEncoder().encode(journal).write(to: journalPath)
        let recovering = AppStore(defaults: defaults, home: home)
        await recovering.rescan()
        precondition(!recovering.canChangeFiles && !recovering.metadataIsEditable)
        precondition(!recovering.canEditRoots && !recovering.addRoot(url: home.appendingPathComponent("new-root"), agent: .custom, name: "Blocked during recovery"))
        precondition(recovering.preferences.activeGroupIDs == [group.id])
        recovering.selectedMutationID = pending.id
        precondition(recovering.selectedMutation?.id == pending.id)
        await recovering.recoverChanges()
        precondition(recovering.journal.pending == nil && recovering.preferences.activeGroupIDs.isEmpty)
        precondition(!recovering.skills[0].isEnabled && recovering.canChangeFiles)
        precondition(recovering.preferences.lastAppliedGroupChangeID == pending.id)
        let reloaded = AppStore(defaults: defaults, home: home)
        await reloaded.rescan()
        precondition(reloaded.journal.completed.count == 4 && !reloaded.groupSyncFailed)
        let corrupt = Data("invalid JSON".utf8)
        defaults.set(corrupt, forKey: "libraryPreferences.v1")
        let blocked = AppStore(defaults: defaults, home: home)
        await blocked.rescan()
        precondition(blocked.groupSyncFailed && !blocked.canChangeFiles)
        precondition(defaults.data(forKey: "libraryPreferences.v1") == corrupt)
        print("PASS: change history search/selection, reviewed undo and cancellation, metadata-only records, group reconciliation after completion/restart/recovery, pending edit locks, corrupt group settings preserved")
    }

    @MainActor private static func checkLibrary() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("LibraryAppCheck-\(UUID().uuidString)")
        let suite = "LibraryAppCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let root = DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "Codex · 사용자 스킬")
        for name in ["one", "two", "three"] {
            let directory = root.url.appendingPathComponent(name)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: A test skill\n---\nBody\n".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let entries = SkillCatalog.scan(roots: [root]).entries
        let legacy = WorkProfile(name: "Legacy", note: "Preserved note", members: [
            ProfileMember(id: entries[0].id, name: entries[0].name, path: entries[0].url.path, agentName: "Codex"),
            ProfileMember(id: "missing-id", name: "Missing", path: "/unavailable", agentName: "Codex")
        ])
        let originalData = try JSONEncoder().encode([legacy])
        defaults.set(originalData, forKey: "workProfiles")
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        precondition(store.page == .library && store.skills.count == 3)
        precondition(store.groups.count == 1 && store.groups[0].id == legacy.id && store.groups[0].skillIDs.count == 2)
        precondition(store.groups[0].skillIDs.contains("legacy:missing-id"))
        precondition(store.profiles[0].note == "Preserved note" && defaults.data(forKey: "workProfiles") == originalData)
        await store.rescan()
        precondition(store.groups.count == 1, "Migration is idempotent")
        store.groupFilterID = legacy.id
        store.selectedGroupID = legacy.id
        store.deleteGroup(legacy.id)
        check(store.groupFilterID == nil && store.selectedGroupID == nil,
            "Deleting a selected group must clear its filter and detail selection")
        await store.rescan()
        precondition(store.groups.isEmpty, "Deleted imported groups do not reappear")
        let one = store.skills.first { $0.name == "one" }!.id
        let two = store.skills.first { $0.name == "two" }!.id
        let three = store.skills.first { $0.name == "three" }!.id
        let a = SkillGroup(name: "A", skillIDs: [one, two])
        let b = SkillGroup(name: "B", skillIDs: [two, three])
        precondition(store.saveGroup(a) && store.saveGroup(b))
        precondition(!store.saveGroup(SkillGroup(name: "Forged", skillIDs: ["invalid"])))
        store.groupFilterID = UUID()
        check(store.groupFilterID == nil, "Unknown groups must not leave a Picker with an invalid selection")
        let oneEntry = store.entries.first { $0.name == "one" }!
        precondition(store.saveSource(for: oneEntry, input: "owner/repo"))
        store.toggleFavorite(one)
        store.libraryFilter = .favorites
        check(store.hasFilters, "Status scope alone must expose filter clearing")
        store.clearLibraryFilters()
        store.groupFilterID = a.id
        check(store.hasFilters, "Group alone must expose filter clearing")
        store.clearLibraryFilters()
        guard let repository = SourceRepository("owner/repo"),
              let selectedRoot = store.automaticRoots.first(where: { $0.agent == .codex })?.id else {
            fputs("FAIL: Library filter fixture requires a valid source and default Codex root\n", stderr)
            exit(1)
        }
        store.sourceFilterID = repository.id
        check(store.hasFilters, "Source alone must expose filter clearing")
        store.libraryFilter = .favorites
        store.agentFilter = .codex
        store.groupFilterID = a.id
        store.rootFilterID = selectedRoot
        store.linksOnly = true
        store.search = "one"
        check(store.filteredSkills.isEmpty && store.hasFilters, "All library filters must combine, including links")
        store.navigate(to: .skills)
        check(store.libraryFilter == .favorites && store.agentFilter == .codex
            && store.groupFilterID == a.id && store.rootFilterID == selectedRoot
            && store.sourceFilterID != nil && store.linksOnly && store.search == "one",
            "Clicking the current skills destination must preserve combined filters")
        store.linksOnly = false
        check(store.filteredSkills.map(\.id) == [one], "Combined filters must match the same installation")
        store.libraryFilter = .all
        check(store.agentFilter == .codex && store.groupFilterID == a.id
            && store.sourceFilterID == repository.id
            && store.rootFilterID == selectedRoot && store.search == "one", "Changing status must preserve the other filters")
        store.groupFilterID = b.id
        check(store.filteredSkills.isEmpty && store.libraryFilter == .all
            && store.agentFilter == .codex && store.rootFilterID == selectedRoot
            && store.sourceFilterID != nil && store.search == "one", "Changing group must preserve the other filters")
        store.selectedSkillID = "stale-selection"
        store.clearLibraryFilters()
        check(!store.hasFilters && store.libraryFilter == .all && store.groupFilterID == nil
            && store.sourceFilterID == nil && store.filteredSkills.count == 3 && store.selectedSkillID == nil,
            "Clearing library filters must clear every scope and stale selection")
        store.selectedSkillID = one
        store.clearLibraryFilters()
        check(store.selectedSkillID == one, "Clearing filters must preserve a valid selected skill")
        store.navigate(.favorites, agent: .codex, group: a.id)
        check(store.page == .library && store.filteredSkills.map(\.id) == [one]
            && store.agentFilter == .codex && store.groupFilterID == a.id, "Existing navigation must still open scoped library views")
        store.page = .groups
        check(!store.hasFilters && store.libraryFilter == .all && store.groupFilterID == nil,
            "Changing tasks must clear library scopes along with existing shared filters")
        store.selectedGroupID = a.id
        store.navigate(to: .skills)
        check(store.page == .groups && store.selectedGroupID == a.id,
            "Clicking the current skills destination must preserve the group section and selection")
        store.showLibrary(rootID: selectedRoot, sourceID: repository.id)
        check(store.page == .library && store.agentFilter == .codex
            && store.sourceFilterID != nil && store.filteredSkills.map(\.id) == [one],
            "Existing location and source navigation must remain supported")
        store.navigate(.favorites)
        precondition(store.filteredSkills.map(\.id) == [one])
        store.navigate()
        store.setGroupMode(.multiple)
        precondition(store.preferences.activeGroupIDs.isEmpty, "Creating a group does not activate it")
        await store.prepareGroupChange(a, enabled: true)
        precondition(store.mutationPreview == nil && store.preferences.activeGroupIDs == [a.id], "No file changes need no preview")
        await store.prepareGroupChange(b, enabled: true)
        precondition(store.preferences.activeGroupIDs == [a.id, b.id])
        await store.prepareGroupChange(a, enabled: false)
        precondition(store.mutationPreview?.installations.count == 1, "Overlap remains enabled for B")
        await store.applyPreview()
        precondition(store.skills.first { $0.id == one }?.isEnabled == false)
        precondition(store.skills.first { $0.id == two }?.isEnabled == true)
        precondition(store.skills.first { $0.id == three }?.isEnabled == true)
        precondition(store.journal.disabled.count == 1 && store.journal.pending == nil)
        let storedOne = store.skills.first { $0.id == one }!.installations[0]
        precondition(store.sourceRepository(for: storedOne) == SourceRepository("owner/repo"))
        precondition(store.sourceGroups.count == 1 && store.sourceGroups[0].count == 1)
        store.navigate(.off)
        precondition(store.filteredSkills.map(\.id) == [one])
        store.setGroupMode(.single)
        await store.prepareGroupChange(a, enabled: true)
        precondition(store.mutationPreview?.installations.count == 2)
        await store.applyPreview()
        precondition(store.skills.first { $0.id == one }?.isEnabled == true)
        precondition(store.skills.first { $0.id == two }?.isEnabled == true)
        precondition(store.skills.first { $0.id == three }?.isEnabled == false)
        precondition(Set(store.skills.map(\.id)) == Set([one, two, three]))
        store.runLocalReview()
        precondition(store.page == .history && store.reviews.count == 1)
        let restored = AppStore(defaults: defaults, home: home)
        await restored.rescan()
        precondition(restored.preferences.favorites.contains(one) && restored.groups.count == 2 && restored.reviews.count == 1)
        precondition(restored.reviews[0].snapshotID == restored.localReview.snapshotID)
        precondition(restored.profiles[0].note == "Preserved note" && defaults.data(forKey: "workProfiles") == originalData)
        let missingCodex = home.appendingPathComponent("missing-codex")
        precondition(restored.addRoot(url: missingCodex, agent: .codex, name: "Additional Codex"))
        await restored.rescan()
        precondition(restored.currentFindings.contains { $0.path == missingCodex.path }, "Missing additional Codex paths remain findings")
        await restored.removeRoot(restored.additionalRoots.first { $0.url == missingCodex }!)
        let invalid = Data("invalid".utf8)
        defaults.set(invalid, forKey: "libraryPreferences.v1")
        defaults.set(invalid, forKey: "review-history.v1")
        let corrupt = AppStore(defaults: defaults, home: home)
        await corrupt.rescan()
        precondition(corrupt.preferencesLoadFailed && corrupt.reviewsLoadFailed)
        precondition(!corrupt.saveGroup(SkillGroup(name: "Do not overwrite")))
        corrupt.runLocalReview()
        precondition(defaults.data(forKey: "libraryPreferences.v1") == invalid && defaults.data(forKey: "review-history.v1") == invalid)
        precondition(defaults.data(forKey: "workProfiles") == originalData)
        print("PASS: canonical library, idempotent legacy migration and preserved notes/missing references, group CRUD, favorites, overlapping multiple/single activation, disable/restore identity, local review history, corrupt state preserved")
    }

    @MainActor static func checkSkillLifecycle() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("SkillLifecycle-" + UUID().uuidString)
        let suite = "SkillLifecycle." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let source = home.appendingPathComponent("downloads/example")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        try "---\nname: example\ndescription: Lifecycle fixture\n---\nBody".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        let root = store.automaticRoots[0]
        guard let cancelled = await store.prepareInstallation(source: source, root: root) else { check(false, "Must prepare local installation"); return }
        check(store.mutationPreview == nil && store.skills.isEmpty, "Preparation must wait for the installer sheet to dismiss")
        store.mutationPreview = cancelled
        store.cancelPreview()
        check(!files.fileExists(atPath: cancelled.installations[0].source), "Cancelling installation must discard staging")
        guard let plan = await store.prepareInstallation(source: source, root: root, repository: SourceRepository("example/skills")) else { check(false); return }
        store.search = "does not match"
        store.mutationPreview = plan
        await store.applyPreview()
        check(store.skills.count == 1 && store.selectedSkill?.name == "example" && !store.hasFilters, "New installation must become selected and visible")
        check(store.sourceRepository(for: store.selectedSkill!.installations[0])?.name == "example/skills", "GitHub source must be connected after installation")
        let id = store.selectedSkill!.id
        await store.prepareRemoval(store.allInstallations)
        check(store.mutationPreview?.installations.first?.removesFromLibrary == true)
        store.cancelPreview()
        check(store.skills.count == 1, "Cancelling removal must leave installation untouched")
        await store.prepareRemoval(store.allInstallations)
        await store.applyPreview()
        check(store.skills.isEmpty && store.journal.disabled.first?.isRemoved == true, "Removal must hide the installation and preserve recovery data")
        let removal = store.journal.completed[0]
        await store.prepareUndo(removal)
        await store.applyPreview()
        check(store.skills.first?.id == id && store.skills.first?.isEnabled == true, "Undo removal must restore identity and state")
        print("PASS: reviewed local installation, cancellation cleanup, selection/filter reset, enabled removal and journal-backed restore")
    }

    @MainActor static func checkSkillsCLIBatchRemoval() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("CLIBatchState-" + UUID().uuidString).resolvingSymlinksInPath()
        let suite = "CLIBatchState." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        func createSkills() throws {
            for name in ["cli-example", "keyboard-demo", "zulu-demo"] {
                let folder = home.appendingPathComponent(".agents/skills/" + name)
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
                try "---\nname: \(name)\ndescription: Batch fixture\n---\nBody".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            }
        }
        try createSkills()
        let receipt = ["version": 3, "skills": Dictionary(uniqueKeysWithValues: ["cli-example", "keyboard-demo", "zulu-demo"].map { name in
            (name, ["source": name == "keyboard-demo" ? "fixture/keyboard" : "fixture/cli", "sourceUrl": "https://github.com/fixture/" + (name == "keyboard-demo" ? "keyboard" : "cli"), "sourceType": "github", "ref": "main",
                    "skillPath": "skills/" + name + "/SKILL.md", "skillFolderHash": String(repeating: "0", count: 40)])
        })] as [String: Any]
        try JSONSerialization.data(withJSONObject: receipt).write(to: home.appendingPathComponent(".agents/.skill-lock.json"))
        let bin = home.appendingPathComponent("bin"), executable = bin.appendingPathComponent("skills")
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo 1.7.4; exit 0; fi
        printf 'run\\n' >> "$HOME/runs"
        printf '%s\\n' "$@" > "$HOME/arguments"
        shift
        for name in "$@"; do
            [ "$name" = "--global" ] && break
            rm -rf -- "$HOME/.agents/skills/$name"
            [ -e "$HOME/fail" ] && exit 4
        done
        exit 0
        """.write(to: executable, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let service = SkillsCLIService(home: home, environment: [:], detector: AgentInstallationDetector(executableDirectories: [bin, URL(fileURLWithPath: "/bin"), URL(fileURLWithPath: "/usr/bin")], applicationDirectories: []))
        let store = AppStore(defaults: defaults, home: home, skillsCLIService: service, gitHubSkills: SkillUpdateFixture.service())
        await store.rescan(); store.setManagementMethod(.skillsCLI)
        let untouched = store.skills.first { $0.name == "keyboard-demo" }!
        await store.checkSkillUpdates([untouched])
        check(store.updateChecks[untouched.id]?.status == .available)
        let checkedAt = store.lastUpdatesChecked
        check(store.saveGroup(SkillGroup(name: "Batch", skillIDs: Set(store.skills.map(\.id)))))
        store.groupFilterID = store.groups[0].id
        store.sourceFilterID = SourceRepository("fixture/cli")!.id
        store.libraryFilter = .on; store.agentFilter = .codex
        store.rootFilterID = store.automaticRoots.first { $0.url.path.hasSuffix("/.agents/skills") }!.id
        store.search = "fixture"
        store.selectSkills(Set(store.skills.map(\.id)))
        check(store.selectedSkills.count == 2 && !store.selectedSkillIDs.contains(untouched.id), "Multi-selection must exclude skills hidden by current filters; visible=" + store.filteredSkills.map(\.name).joined(separator: ",") + "; sources=" + store.skills.map { $0.name + ":" + (store.sourceRepository(for: $0.installations[0])?.id ?? "nil") }.joined(separator: ","))
        await store.prepareSelectedSkillsRemoval()
        check(store.skillsCLIPreview?.removalNames == ["cli-example", "zulu-demo"], store.libraryMessage ?? "Batch review missing")
        check(store.skillsCLIPreview?.arguments == ["remove", "cli-example", "zulu-demo", "--global", "--yes"])
        store.cancelSkillsCLIChange()
        check(store.skills.count == 3 && store.selectedSkills.count == 2, "Cancel must preserve files, selection and filters")
        await store.prepareSelectedSkillsRemoval(); await store.applySkillsCLIChange()
        check(!store.skillsCLIFailed && store.skills.map(\.name) == ["keyboard-demo"], store.libraryMessage ?? "Batch delete failed")
        check(store.sourceFilterID == SourceRepository("fixture/cli")!.id && store.search == "fixture" && store.libraryFilter == .on
              && store.agentFilter == .codex && store.rootFilterID != nil && store.groupFilterID == store.groups[0].id,
              "Batch delete must preserve every active filter even when no matches remain")
        check(store.filteredSkills.isEmpty && store.selectedSkillIDs.isEmpty, "Filtered empty results must stay empty without hidden selections")
        check(store.updateChecks[untouched.id]?.status == .available && store.lastUpdatesChecked == checkedAt,
              "Deleting other skills must preserve unaffected update results")
        store.clearLibraryFilters(); store.libraryFilter = .updates
        check(store.filteredSkills.map(\.name) == ["keyboard-demo"], "Remaining update results must remain usable in the updates filter")
        try createSkills(); await store.rescan(); store.clearLibraryFilters()
        let first = store.filteredSkills.first { $0.name == "cli-example" }!
        store.selectedSkillID = first.id
        await store.prepareRemoval(first.installations, allAgents: true); await store.applySkillsCLIChange()
        check(store.selectedSkill?.name == "keyboard-demo", "Deleting a selected row must select the next visible row")
        try createSkills(); await store.rescan(); store.clearLibraryFilters()
        store.selectSkills(Set(store.skills.filter { $0.name != "keyboard-demo" }.map(\.id)))
        try Data().write(to: home.appendingPathComponent("fail"))
        await store.prepareSelectedSkillsRemoval(); await store.applySkillsCLIChange()
        check(store.skillsCLIFailed && store.skillsCLIPreview != nil && store.skills.contains { $0.name == "zulu-demo" }, "Partial CLI failure must remain visible and keep untouched skills")
        let runs = try Data(contentsOf: home.appendingPathComponent("runs"))
        await store.applySkillsCLIChange()
        check(try Data(contentsOf: home.appendingPathComponent("runs")) == runs, "Failed batch must never auto-retry")
        store.cancelSkillsCLIChange()
        print("PASS: filtered multi-selection, named CLI batch review/cancel/apply, empty-filter preservation, unaffected update results, partial failure without retry")
    }

    @MainActor static func checkSkillsCLIInstallation() async throws {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("SkillsCLIState-" + UUID().uuidString).resolvingSymlinksInPath()
        let suite = "SkillsCLIState." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
        let source = home.appendingPathComponent("source")
        let bin = home.appendingPathComponent("bin")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try "---\nname: cli-example\ndescription: CLI fixture\n---\nBody".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let executable = bin.appendingPathComponent("skills")
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo 1.7.4; exit 0; fi
        printf '%s\\n' "$@" > "$HOME/cli-arguments"
        if [ "$1" = "remove" ]; then
            rm -rf -- "$HOME/.agents/skills/cli-example"
            echo removed
            exit 0
        fi
        rm -rf -- "$HOME/.agents/skills/cli-example"
        mkdir -p "$HOME/.agents/skills/cli-example"
        cp -R "$AHM_FIXTURE_SOURCE/." "$HOME/.agents/skills/cli-example/"
        echo installed
        """.write(to: executable, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let service = SkillsCLIService(home: home, environment: ["AHM_FIXTURE_SOURCE": source.path],
            detector: AgentInstallationDetector(executableDirectories: [bin, URL(fileURLWithPath: "/bin"), URL(fileURLWithPath: "/usr/bin")], applicationDirectories: []))
        let store = AppStore(defaults: defaults, home: home, skillsCLIService: service, gitHubSkills: SkillUpdateFixture.service())
        await store.rescan()
        check(store.managementMethod == .direct && store.skillsCLIExecutable == executable)
        store.setManagementMethod(.skillsCLI)
        check(AppStore(defaults: defaults, home: home, skillsCLIService: service).managementMethod == .skillsCLI, "Install method must persist")
        guard let plan = await store.prepareSkillsCLIInstallation(source: source, agent: .codex, remoteSource: nil) else { check(false, store.libraryMessage ?? "CLI prepare failed"); return }
        store.presentSkillsCLIInstall(plan, download: nil)
        check(!store.metadataIsEditable && !store.canEditRoots && !store.canChangeFiles, "CLI review must lock other file changes")
        store.cancelSkillsCLIChange()
        check(store.skills.isEmpty && store.canEditRoots, "Cancel must not install")
        store.presentSkillsCLIInstall(plan, download: nil)
        await store.applySkillsCLIChange()
        check(!store.skillsCLIFailed && store.skillsCLIPreview == nil && store.selectedSkill?.name == "cli-example", store.libraryMessage ?? "CLI install failed")
        check(store.journal.completed.isEmpty, "External CLI install must not pretend to be an app-journal operation")
        await store.checkSkillUpdates()
        check(store.updateChecks.values.allSatisfy { $0.status == .unavailable }, "Missing receipt must not report latest or update availability")
        check(store.lastUpdatesChecked != nil && !store.isCheckingUpdates)
        let receipt = home.appendingPathComponent(".agents/.skill-lock.json")
        let receiptData = try JSONSerialization.data(withJSONObject: ["version": 3, "skills": ["cli-example": ["source": "fixture/cli", "sourceType": "github", "ref": "main", "skillPath": "skills/cli-example/SKILL.md", "skillFolderHash": String(repeating: "0", count: 40)]]])
        try receiptData.write(to: receipt)
        let installedDocument = home.appendingPathComponent(".agents/skills/cli-example/SKILL.md")
        let originalDocument = try Data(contentsOf: installedDocument)
        let arguments = try Data(contentsOf: home.appendingPathComponent("cli-arguments"))
        await store.checkSkillUpdates()
        check(store.availableUpdateCount == 1 && store.updateChecks[store.skills[0].id]?.status == .available)
        check(try Data(contentsOf: receipt) == receiptData && Data(contentsOf: installedDocument) == originalDocument,
              "Update checks must not change files or CLI receipts")
        check(try Data(contentsOf: home.appendingPathComponent("cli-arguments")) == arguments, "Read-only checks must never run skills check/update")
        let pinnedVersion = try JSONSerialization.data(withJSONObject: ["version": 3, "skills": ["cli-example": ["source": "fixture/cli", "sourceType": "github", "ref": String(repeating: "d", count: 40), "skillPath": "skills/cli-example/SKILL.md", "skillFolderHash": String(repeating: "0", count: 40)]]])
        try pinnedVersion.write(to: receipt)
        await store.checkSkillUpdates()
        check(store.updateChecks[store.skills[0].id]?.listing?.trackingReference == "main", "Resolve the actual default branch instead of passing HEAD to CLI clone")
        await store.prepareSkillUpdate(store.skills[0])
        check(store.skillsCLIPreview?.trackedReference == "main", "Pinned installations must update against the resolved branch")
        store.cancelSkillsCLIChange()
        let sameVersion = try JSONSerialization.data(withJSONObject: ["version": 3, "skills": ["cli-example": ["source": "fixture/cli", "sourceType": "github", "ref": "main", "skillPath": "skills/cli-example/SKILL.md", "skillFolderHash": String(repeating: "c", count: 40)]]])
        try sameVersion.write(to: receipt)
        await store.checkSkillUpdates()
        check(store.availableUpdateCount == 0 && store.updateChecks[store.skills[0].id]?.status == .modified,
              "Local changes alone must not be counted as an upstream update")
        try receiptData.write(to: receipt)
        await store.checkSkillUpdates()
        store.libraryFilter = .updates
        check(store.filteredSkills.count == 1, "Update filter must show available updates")
        let previousID = store.skills[0].id
        store.toggleFavorite(previousID)
        check(store.saveGroup(SkillGroup(name: "Update preservation", skillIDs: [previousID])))
        try SkillUpdateFixture.body("cli-example").write(to: source.appendingPathComponent("SKILL.md"))
        try Data([1,2,3]).write(to: source.appendingPathComponent("resource.bin"))
        await store.prepareSkillUpdate(store.skills[0])
        check(store.skillsCLIPreview?.operation == .update && store.skillsCLIPreview?.arguments.first == "add")
        let staged = store.skillsCLIPreview!.sourceFolder!
        store.cancelSkillsCLIChange()
        check(!files.fileExists(atPath: staged.path), "Cancelling update must clean the downloaded review")
        check(try Data(contentsOf: installedDocument) == originalDocument, "Cancelling update must preserve local edits")
        await store.prepareSkillUpdate(store.skills[0])
        await store.applySkillsCLIChange()
        check(try Data(contentsOf: installedDocument) == SkillUpdateFixture.body("cli-example"), store.libraryMessage ?? "CLI update failed")
        check(store.journal.completed.isEmpty && store.skillsCLIPreview == nil)
        check(store.preferences.favorites.contains(store.skills[0].id) && store.groups[0].skillIDs.contains(store.skills[0].id),
              "CLI replacement must preserve favorites and group membership")
        await store.checkSkillUpdates()
        check(store.availableUpdateCount == 0 && store.updateChecks[store.skills[0].id]?.status == .current,
              "All resource contents must compare equal after CLI update")
        let unavailableSource = try JSONSerialization.data(withJSONObject: ["version": 3, "skills": ["cli-example": ["source": "fixture/unavailable", "sourceType": "github", "ref": "main", "skillPath": "skills/cli-example/SKILL.md"]]])
        try unavailableSource.write(to: receipt)
        await store.checkSkillUpdates()
        check(store.availableUpdateCount == 0 && store.updateChecks[store.skills[0].id]?.status == .failed,
              "Offline or failed remote checks must never claim to be current")
        try receiptData.write(to: receipt)
        let beforeRemoval = store.allInstallations
        await store.prepareRemoval(beforeRemoval, allAgents: true)
        check(store.skillsCLIPreview?.operation == .remove && store.mutationPreview == nil, "CLI setting must route removal through CLI")
        store.cancelSkillsCLIChange()
        check(store.skills.count == 1, "Cancel CLI removal must preserve installed files")
        try files.removeItem(at: executable)
        store.refreshSkillsCLI()
        check(store.skillsCLIExecutable == nil && store.managementMethod == .skillsCLI, "Missing CLI must preserve the user's choice")
        let unavailable = await store.prepareSkillsCLIInstallation(source: source, agent: .codex, remoteSource: nil)
        check(unavailable == nil, "Missing CLI must not silently fall back to direct installation")
        await store.prepareRemoval(beforeRemoval, allAgents: true)
        check(store.mutationPreview == nil && store.skillsCLIPreview == nil, "Missing CLI must not fall back to app archive removal")
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo 1.7.4; exit 0; fi
        rm -rf -- "$HOME/.agents/skills/cli-example"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        store.refreshSkillsCLI()
        store.search = "cli-example"
        store.libraryFilter = .on
        store.sourceFilterID = SourceRepository("fixture/cli")!.id
        store.agentFilter = .codex
        let filteredRoot = store.automaticRoots.first { $0.url.path.hasSuffix("/.agents/skills") }!.id
        store.rootFilterID = filteredRoot
        store.linksOnly = true
        await store.prepareRemoval(beforeRemoval, allAgents: true)
        await store.applySkillsCLIChange()
        check(store.search == "cli-example" && store.libraryFilter == .on && store.sourceFilterID == SourceRepository("fixture/cli")!.id
              && store.agentFilter == .codex && store.rootFilterID == filteredRoot && store.linksOnly,
              "CLI removal must preserve search, source, scope, agent, location and link filters")
        check(store.skills.isEmpty && store.journal.completed.isEmpty, "CLI removal must execute CLI and leave no app archive journal")
        store.setManagementMethod(.direct)
        check(store.managementMethod == .direct)
        print("PASS: persisted CLI lifecycle tool, read-only remote/resource comparison, update/local-difference/current/offline states and filter, reviewed scoped update/cancel, metadata preservation, actual CLI deletion routing and missing-CLI fallback prevention")
    }

}
