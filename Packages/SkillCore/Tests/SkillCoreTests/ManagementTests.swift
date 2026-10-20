import Foundation
import XCTest
@testable import SkillCore

final class ManagementTests: XCTestCase {
    func testGrokNativeRootCanBeScannedSwitchedAndRestoredWithoutChangingOtherAgents() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let grok = fixture.home.appendingPathComponent(".grok/skills/grok-example/SKILL.md")
        try FileManager.default.createDirectory(at: grok.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.body.write(to: grok, atomically: true, encoding: .utf8)
        let before = try await fixture.snapshot()
        let item = try XCTUnwrap(before.installations.first { $0.location.agent == .grokBuild })
        XCTAssertEqual(before.configuration.managedRoots.count, 10)
        let off = try before.plan(installationIDs: [item.id], enabled: false, title: "Grok only")
        try await fixture.library.apply(off, roots: fixture.configuration.roots)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.document.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: grok.path))
        let stored = try await fixture.snapshot()
        let on = try stored.plan(installationIDs: [item.id], enabled: true, title: "Restore Grok")
        try await fixture.library.apply(on, roots: fixture.configuration.roots)
        XCTAssertEqual(try String(contentsOf: grok, encoding: .utf8), fixture.body)
        let restored = try await fixture.snapshot()
        XCTAssertEqual(restored.installations.first { $0.location.agent == .grokBuild }?.id, item.id)
    }

    func testNewNativeRootsSwitchIndependentlyAndCompatibilityDoesNotDuplicateInstallations() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let roots = fixture.configuration.managedRoots
        XCTAssertEqual(roots[0].id, "codex:" + fixture.home.appendingPathComponent(".agents/skills").path)
        XCTAssertEqual(ManagementConfiguration.readers(of: roots[0], defaultRoots: roots), [.codex, .grokBuild, .opencode, .pi, .devin, .cursor])
        XCTAssertEqual(ManagementConfiguration.readers(of: roots[1], defaultRoots: roots), [.claudeCode, .grokBuild, .opencode])
        let custom = DiscoveryRoot(agent: .codex, url: fixture.home.appendingPathComponent("custom"), label: "Custom")
        XCTAssertEqual(ManagementConfiguration.readers(of: custom, defaultRoots: roots), [.codex])
        let initial = try await fixture.snapshot()
        XCTAssertEqual(initial.installations.count, 1)
        XCTAssertFalse(initial.review.findings.contains { $0.id.hasPrefix("root:") }, "Absent optional agents are not broken installations")
        for (index, root) in roots.dropFirst(3).enumerated() {
            let document = root.url.appendingPathComponent("new-\(index)/SKILL.md")
            try FileManager.default.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fixture.body.write(to: document, atomically: true, encoding: .utf8)
            let before = try await fixture.snapshot()
            let item = try XCTUnwrap(before.installations.first { $0.originalPath == document.deletingLastPathComponent().path })
            let off = try before.plan(installationIDs: [item.id], enabled: false, title: "New agent only")
            try await fixture.library.apply(off, roots: roots)
            XCTAssertFalse(FileManager.default.fileExists(atPath: document.path))
            XCTAssertEqual(try String(contentsOf: fixture.document, encoding: .utf8), fixture.body)
            let disabled = try await fixture.snapshot()
            let on = try disabled.plan(installationIDs: [item.id], enabled: true, title: "Restore")
            try await fixture.library.apply(on, roots: roots)
            XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), fixture.body)
            let restored = try await fixture.snapshot()
            XCTAssertEqual(restored.installations.first { $0.id == item.id }?.location.id, root.id)
        }
        let final = try await fixture.snapshot()
        XCTAssertEqual(final.installations.count, 8)
    }

    func testRequestRoundTripRebuildsPlanAndRequiresSeparateApply() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let snapshot = try await fixture.snapshot()
        let request = try fixture.request(snapshot)
        let queue = AgentRequestStore(stateDirectory: fixture.configuration.stateDirectory)
        try await queue.submit(request)
        let requests = try await queue.list()
        XCTAssertEqual(requests.map(\.id), [request.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.document.path), "Submitting an intent must not move skills")
        let plan = try requests[0].validatedPlan(snapshot: snapshot)
        XCTAssertEqual(plan.id, request.id)
        XCTAssertNotEqual(plan.installations[0].destination, request.moves[0].destination, "Never trust serialized destination paths")
        try await fixture.library.apply(plan, roots: fixture.configuration.roots)
        let applied = try await fixture.snapshot()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.document.path))
        XCTAssertEqual(applied.journal.completed.first?.id, request.id)
        XCTAssertThrowsError(try request.validatedPlan(snapshot: applied))
        let restore = try applied.plan(installationIDs: [applied.installations[0].id], enabled: true, title: "Restore")
        try await fixture.library.apply(restore, roots: fixture.configuration.roots)
        XCTAssertEqual(try String(contentsOf: fixture.document, encoding: .utf8), fixture.body)
        try await queue.remove(request.id)
        let empty = try await queue.list()
        XCTAssertTrue(empty.isEmpty)
    }

    func testStaleDocumentResourcesExpiryAndUnknownIDsAreRejected() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let request = try fixture.request(before)
        XCTAssertThrowsError(try request.validatedPlan(snapshot: before, now: .now.addingTimeInterval(86_500)))
        XCTAssertThrowsError(try before.plan(installationIDs: ["forged"], enabled: false, title: "Invalid"))
        XCTAssertThrowsError(try before.plan(installationIDs: [before.installations[0].id, before.installations[0].id], enabled: false, title: "Duplicate"))
        let resource = fixture.document.deletingLastPathComponent().appendingPathComponent("data.txt")
        try "New resource".write(to: resource, atomically: true, encoding: .utf8)
        let changedResources = try await fixture.snapshot()
        XCTAssertEqual(before.fingerprint, changedResources.fingerprint, "SKILL.md alone is insufficient to detect resource changes")
        XCTAssertThrowsError(try request.validatedPlan(snapshot: changedResources))
        try (fixture.body + "Changed\n").write(to: fixture.document, atomically: true, encoding: .utf8)
        let changedDocument = try await fixture.snapshot()
        XCTAssertNotEqual(before.fingerprint, changedDocument.fingerprint)
        XCTAssertThrowsError(try request.validatedPlan(snapshot: changedDocument))
    }

    func testCorruptAndSymlinkedQueueEntriesArePreservedAndRejected() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let snapshot = try await fixture.snapshot(), queue = AgentRequestStore(stateDirectory: fixture.configuration.stateDirectory)
        let request = try fixture.request(snapshot)
        try await queue.submit(request)
        do { try await queue.submit(request); XCTFail("Duplicate request overwrote the original") } catch {}
        let file = fixture.configuration.stateDirectory.appendingPathComponent("AgentRequests/\(request.id.uuidString).json")
        let data = try Data(contentsOf: file)
        try Data("invalid".utf8).write(to: file)
        do { _ = try await queue.list(); XCTFail("Corrupt request accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), Data("invalid".utf8))
        try FileManager.default.removeItem(at: file)
        let outside = fixture.home.appendingPathComponent("outside.json")
        try data.write(to: outside)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        do { _ = try await queue.list(); XCTFail("Symlinked request accepted") } catch {}
        do { try await queue.remove(request.id); XCTFail("Symlinked request deleted") } catch {}
        XCTAssertEqual(try Data(contentsOf: outside), data)
    }

    func testMalformedMetadataFailsClosedAndFingerprintIsStableAcrossSetOrder() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        XCTAssertThrowsError(try ManagementConfiguration.decodePreferences(Data("invalid".utf8)))
        let remote = DiscoveryRoot(agent: .custom, url: URL(string: "https://example.com")!, label: "Remote")
        XCTAssertThrowsError(try ManagementConfiguration.decodeRoots(JSONEncoder().encode([remote]), home: fixture.home))
        XCTAssertThrowsError(try ManagementConfiguration(home: fixture.home, domain: "../other", preferencesData: nil, rootsData: nil))
        var preferences = AppPreferences()
        let group = SkillGroup(name: "Group", skillIDs: ["b", "a"])
        preferences.groups = [group]; preferences.activeGroupIDs = [group.id]
        let firstConfig = try ManagementConfiguration(home: fixture.home, domain: "management.tests",
            preferencesData: JSONEncoder().encode(preferences), rootsData: nil)
        let first = try await ManagementService.snapshot(configuration: firstConfig)
        preferences.groups[0].skillIDs = ["a", "b"]
        let secondConfig = try ManagementConfiguration(home: fixture.home, domain: "management.tests",
            preferencesData: JSONEncoder().encode(preferences), rootsData: nil)
        let second = try await ManagementService.snapshot(configuration: secondConfig)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        preferences.groups[0].name = "Changed"
        let changedConfig = try ManagementConfiguration(home: fixture.home, domain: "management.tests",
            preferencesData: JSONEncoder().encode(preferences), rootsData: nil)
        let changed = try await ManagementService.snapshot(configuration: changedConfig)
        XCTAssertNotEqual(first.fingerprint, changed.fingerprint)
    }

    func testCustomRootCannotBeChangedAndPendingRecoveryBlocksPlanning() async throws {
        let fixture = try ManagementFixture(); defer { fixture.remove() }
        let directory = fixture.home.appendingPathComponent("custom/example")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.body.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let custom = DiscoveryRoot(agent: .custom, url: directory.deletingLastPathComponent(), label: "Custom")
        let config = try ManagementConfiguration(home: fixture.home, domain: "management.tests", preferencesData: nil,
            rootsData: JSONEncoder().encode([custom]))
        let snapshot = try await ManagementService.snapshot(configuration: config)
        let item = try XCTUnwrap(snapshot.installations.first { $0.location.agent == .custom })
        XCTAssertThrowsError(try snapshot.plan(installationIDs: [item.id], enabled: false, title: "Unsafe"))
        var journal = snapshot.journal
        journal.pending = MutationPlan(title: "Pending recovery", installations: [])
        let pending = ManagementSnapshot(configuration: config, journal: journal, skills: snapshot.skills, observations: snapshot.observations)
        XCTAssertThrowsError(try pending.plan(installationIDs: [item.id], enabled: false, title: "Busy"))
    }
}

private struct ManagementFixture {
    let home: URL
    let configuration: ManagementConfiguration
    let document: URL
    let body = "---\nname: sample\ndescription: Synthetic management check\n---\nHello\n"
    var library: LibraryService { LibraryService(stateDirectory: configuration.stateDirectory.appendingPathComponent("Library")) }
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-management-" + UUID().uuidString).resolvingSymlinksInPath()
        document = home.appendingPathComponent(".agents/skills/sample/SKILL.md")
        try FileManager.default.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: document, atomically: true, encoding: .utf8)
        configuration = try ManagementConfiguration(home: home, domain: "management.tests", preferencesData: nil, rootsData: nil)
    }
    func snapshot() async throws -> ManagementSnapshot { try await ManagementService.snapshot(configuration: configuration) }
    func request(_ snapshot: ManagementSnapshot) throws -> AgentChangeRequest {
        let ids = snapshot.installations.filter { $0.location.agent == .codex }.map(\.id)
        return AgentChangeRequest(snapshot: snapshot, plan: try snapshot.plan(installationIDs: ids, enabled: false, title: "Synthetic request"), installationIDs: ids, enabled: false)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
