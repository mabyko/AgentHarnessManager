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
        let body = "---\nname: check\ndescription: Temporary check\n---\nRead only\n"
        for path in [".agents/skills/codex-check", ".claude/skills/claude-check", "manual/custom-check", "replacement/replacement-check"] {
            let directory = home.appendingPathComponent(path)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try body.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let store = AppStore(defaults: defaults, home: home)
        await store.rescan()
        precondition(store.page == .profiles && store.entries.count == 2)
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
        precondition(restored.page == .profiles && restored.selectedProfile?.id == profileID)
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
        precondition(restored.registeredRoots.count == 2)
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
        print("PASS: profile create/edit/search/reload/delete, missing members preserved, invalid/corrupt state blocked, filters, fixed default paths, additional path edit/delete/reload, import profiles, reject missing members, preserve imported snapshots, no skill file changes")
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
        precondition(store.rootFilterID == nil && store.availableRoots.count == 3)
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

}
