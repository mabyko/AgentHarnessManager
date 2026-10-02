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
        print("PASS: profile create/edit/search/reload/delete, missing members preserved, invalid/corrupt state blocked, filters, fixed default paths, additional path edit/delete/reload, no skill file changes")
    }
}
