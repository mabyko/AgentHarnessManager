import AppKit
import SkillCore

@main
struct AppStateCheck {
    @MainActor static func main() async throws {
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
        print("PASS: profile create/edit/search/reload/delete, missing members preserved, invalid/corrupt state blocked, filters, fixed default paths, additional path edit/delete/reload, import profiles, reject missing members, preserve imported snapshots, no skill file changes")
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
        store.deleteGroup(legacy.id)
        await store.rescan()
        precondition(store.groups.isEmpty, "Deleted imported groups do not reappear")
        let one = store.skills.first { $0.name == "one" }!.id
        let two = store.skills.first { $0.name == "two" }!.id
        let three = store.skills.first { $0.name == "three" }!.id
        let a = SkillGroup(name: "A", skillIDs: [one, two])
        let b = SkillGroup(name: "B", skillIDs: [two, three])
        precondition(store.saveGroup(a) && store.saveGroup(b))
        precondition(!store.saveGroup(SkillGroup(name: "Forged", skillIDs: ["invalid"])))
        let oneEntry = store.entries.first { $0.name == "one" }!
        precondition(store.saveSource(for: oneEntry, input: "owner/repo"))
        store.toggleFavorite(one)
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

}
