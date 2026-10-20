import Darwin
import Foundation
import XCTest
@testable import SkillCore

final class LibraryTests: XCTestCase {
    func testMetadataSharedTargetsAndIndependentCopies() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let one = try fixture.skill("one")
        let copy = try fixture.skill("copy", body: "---\nname: shared\ndescription: >-\n  A folded\n  description\n---\nOther resources\n")
        try FileManager.default.createSymbolicLink(at: fixture.root.url.appendingPathComponent("alias"), withDestinationURL: one)
        let skills = fixture.library()
        XCTAssertEqual(skills.count, 2)
        let shared = try XCTUnwrap(skills.first { $0.installations.count == 2 })
        XCTAssertEqual(shared.name, "shared")
        XCTAssertEqual(Set(shared.installations.map(\.originalPath)), Set([one.path, fixture.root.url.appendingPathComponent("alias").path]))
        XCTAssertEqual(skills.first { $0.installations.first?.originalPath == copy.path }?.summary, "A folded description")
        XCTAssertNotEqual(skills[0].id, skills[1].id)
        XCTAssertThrowsError(try LibraryService.plan(title: "Shared", installations: shared.installations, enabled: false, allInstallations: skills.flatMap(\.installations), managedRoots: [fixture.root]))
        try "No frontmatter".write(to: copy.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let review = ReviewRecord(skills: fixture.library(), roots: [])
        XCTAssertEqual(review.findings.count, 1)
        XCTAssertNotNil(review.findings.first?.contentHash)
        XCTAssertNotEqual(review.snapshotID, ReviewRecord(skills: skills, roots: []).snapshotID)
    }

    func testDisableReloadAndRestoreKeepIdentityAndContents() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("example")
        let resource = original.appendingPathComponent("data.bin")
        let bytes = Data([0, 1, 254, 255])
        try bytes.write(to: resource)
        let before = fixture.library()
        let plan = try fixture.plan(before)
        try await fixture.service.apply(plan, roots: [fixture.root])
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(SkillCatalog.scan(roots: [fixture.root]).entries.isEmpty)
        let saved = try await LibraryService(stateDirectory: fixture.state).load(roots: [fixture.root])
        XCTAssertNil(saved.pending)
        XCTAssertEqual(saved.disabled.count, 1)
        let off = fixture.library(disabled: saved.disabled)
        XCTAssertEqual(before.map(\.id), off.map(\.id))
        XCTAssertFalse(try XCTUnwrap(off.first).isEnabled)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: saved.disabled[0].currentPath).appendingPathComponent("data.bin")), bytes)
        let on = try LibraryService.plan(title: "Restore", installations: off.flatMap(\.installations), enabled: true, allInstallations: off.flatMap(\.installations), managedRoots: [fixture.root])
        try await fixture.service.apply(on, roots: [fixture.root])
        let restored = try await fixture.service.load(roots: [fixture.root])
        XCTAssertTrue(restored.disabled.isEmpty)
        XCTAssertEqual(fixture.library().map(\.id), before.map(\.id))
        XCTAssertEqual(try Data(contentsOf: resource), bytes)
    }

    func testPreviewRejectsChangedDocumentCollisionAndParentReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("example")
        let plan = try fixture.plan(fixture.library())
        let destination = URL(fileURLWithPath: plan.installations[0].destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        try FileManager.default.removeItem(at: destination)
        try "Changed".write(to: original.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        let newPlan = try fixture.plan(fixture.library())
        let held = fixture.base.appendingPathComponent("held")
        try FileManager.default.moveItem(at: fixture.root.url, to: held)
        try FileManager.default.createDirectory(at: fixture.root.url, withIntermediateDirectories: true)
        await assertThrows { try await fixture.service.apply(newPlan, roots: [fixture.root]) }
        XCTAssertEqual(try String(contentsOf: held.appendingPathComponent("example/SKILL.md"), encoding: .utf8), "Changed")
    }

    func testPendingRecoveryResumesPartiallyMovedBatchAndNeverOverwrites() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one"); _ = try fixture.skill("two")
        let before = fixture.library()
        let plan = try fixture.plan(before)
        let initial = try await fixture.service.load(roots: [fixture.root])
        XCTAssertNil(initial.pending)
        var journal = initial; journal.pending = plan
        try JSONEncoder().encode(journal).write(to: fixture.state.appendingPathComponent("library-journal.json"))
        let first = plan.installations[0]
        try FileManager.default.moveItem(atPath: first.source, toPath: first.destination)
        let loaded = try await fixture.service.load(roots: [fixture.root])
        XCTAssertNotNil(loaded.pending)
        XCTAssertEqual(loaded.disabled.count, 1)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        try await fixture.service.recover(roots: [fixture.root])
        let recovered = try await fixture.service.load(roots: [fixture.root])
        XCTAssertNil(recovered.pending)
        XCTAssertEqual(recovered.disabled.count, 2)
        XCTAssertEqual(fixture.library(disabled: recovered.disabled).map(\.id).sorted(), before.map(\.id).sorted())
        try await fixture.service.recover(roots: [fixture.root])
        let on = try LibraryService.plan(title: "Restore", installations: fixture.library(disabled: recovered.disabled).flatMap(\.installations), enabled: true, allInstallations: [], managedRoots: [fixture.root])
        let conflict = URL(fileURLWithPath: on.installations[0].destination)
        try FileManager.default.createDirectory(at: conflict, withIntermediateDirectories: false)
        try "Keep me".write(to: conflict.appendingPathComponent("untouched"), atomically: true, encoding: .utf8)
        await assertThrows { try await fixture.service.apply(on, roots: [fixture.root]) }
        XCTAssertEqual(try String(contentsOf: conflict.appendingPathComponent("untouched"), encoding: .utf8), "Keep me")
        let untouched = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(untouched.disabled.count, 2)
    }

    func testCorruptJournalAndSymlinkMetadataArePreserved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one")
        let plan = try fixture.plan(fixture.library())
        _ = try await fixture.service.load(roots: [fixture.root])
        let path = fixture.state.appendingPathComponent("library-journal.json")
        let invalid = Data("invalid".utf8)
        try invalid.write(to: path)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        XCTAssertEqual(try Data(contentsOf: path), invalid)
        try FileManager.default.removeItem(at: path)
        let external = fixture.base.appendingPathComponent("outside")
        try invalid.write(to: external)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: external)
        await assertThrows { _ = try await fixture.service.load(roots: [fixture.root]) }
        XCTAssertEqual(try Data(contentsOf: external), invalid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.installations[0].source))
    }

    func testReaderAddedAfterPreviewBlocksMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        let plan = try fixture.plan(fixture.library())
        try FileManager.default.createSymbolicLink(at: fixture.root.url.appendingPathComponent("new-reader"), withDestinationURL: original)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testDisabledItemDoesNotAdoptReplacementRoot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one")
        try await fixture.service.apply(fixture.plan(fixture.library()), roots: [fixture.root])
        let saved = try await fixture.service.load(roots: [fixture.root])
        let off = fixture.library(disabled: saved.disabled)
        try FileManager.default.moveItem(at: fixture.root.url, to: fixture.base.appendingPathComponent("held-root"))
        try FileManager.default.createDirectory(at: fixture.root.url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LibraryService.plan(title: "Restore", installations: off.flatMap(\.installations), enabled: true,
            allInstallations: off.flatMap(\.installations), managedRoots: [fixture.root]))
        XCTAssertTrue(saved.disabled[0].matchesCurrentItem)
    }

    func testSymlinkedStateDirectoryIsNotFollowed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.base.appendingPathComponent("outside-state")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: fixture.state, withDestinationURL: outside)
        await assertThrows { _ = try await fixture.service.load(roots: [fixture.root]) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testNestedRegisteredRootsAndMultipleReadersAreReadOnly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        let contents = original.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
        let protected = DiscoveryRoot(agent: .custom, url: contents, label: "Nested")
        XCTAssertThrowsError(try LibraryService.plan(title: "Disable", installations: fixture.library().flatMap(\.installations), enabled: false,
            allInstallations: fixture.library().flatMap(\.installations), managedRoots: [fixture.root], protectedRoots: [protected]))
        let secondURL = fixture.base.appendingPathComponent("shared-root")
        try FileManager.default.createSymbolicLink(at: secondURL, withDestinationURL: fixture.root.url)
        let second = DiscoveryRoot(agent: .claudeCode, url: secondURL, label: "Claude")
        let roots = [fixture.root, second]
        let library = LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: roots), roots: roots)
        XCTAssertThrowsError(try LibraryService.plan(title: "Disable", installations: library.flatMap(\.installations), enabled: false,
            allInstallations: library.flatMap(\.installations), managedRoots: roots))
    }

    func testUndoRestoresBinaryResourcesAndRecordsBothOperations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        let resource = original.appendingPathComponent("resource.bin")
        let bytes = Data([0, 255, 64, 128])
        try bytes.write(to: resource)
        let plan = try fixture.plan(fixture.library())
        XCTAssertNotNil(plan.installations[0].treeHash)
        try await fixture.service.apply(plan, roots: [fixture.root])
        let undo = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root])
        XCTAssertEqual(undo.undoes, plan.id)
        XCTAssertEqual(undo.installations[0].source, plan.installations[0].destination)
        try await fixture.service.apply(undo, roots: [fixture.root])
        let journal = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(journal.completed.map(\.id), [undo.id, plan.id])
        XCTAssertNotNil(journal.completed[0].completedAt)
        XCTAssertTrue(journal.disabled.isEmpty)
        XCTAssertEqual(try Data(contentsOf: resource), bytes)
        XCTAssertNotNil(journal.undoUnavailableReason(for: plan.id))
        await assertThrows { _ = try await fixture.service.planUndo(id: undo.id, roots: [fixture.root]) }
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
    }

    func testUndoEnableUsesRecordedStorageAndRejectsNewReaders() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        try await fixture.service.apply(fixture.plan(fixture.library()), roots: [fixture.root])
        let disabled = try await fixture.service.load(roots: [fixture.root])
        let items = fixture.library(disabled: disabled.disabled).flatMap(\.installations)
        let restore = try LibraryService.plan(title: "Restore", installations: items, enabled: true, allInstallations: items, managedRoots: [fixture.root])
        try await fixture.service.apply(restore, roots: [fixture.root])
        let undo = try await fixture.service.planUndo(id: restore.id, roots: [fixture.root])
        let link = fixture.root.url.appendingPathComponent("reader")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        await assertThrows { try await fixture.service.apply(undo, roots: [fixture.root]) }
        try FileManager.default.removeItem(at: link)
        try await fixture.service.apply(undo, roots: [fixture.root])
        let journal = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(journal.disabled[0].currentPath, disabled.disabled[0].currentPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testUndoRejectsResourceEditsAfterCompletionAndAfterPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        try "before".write(to: original.appendingPathComponent("resource"), atomically: true, encoding: .utf8)
        let plan = try fixture.plan(fixture.library())
        try await fixture.service.apply(plan, roots: [fixture.root])
        let undo = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root])
        let resource = URL(fileURLWithPath: plan.installations[0].destination).appendingPathComponent("resource")
        try "edited".write(to: resource, atomically: true, encoding: .utf8)
        await assertThrows { _ = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root]) }
        await assertThrows { try await fixture.service.apply(undo, roots: [fixture.root]) }
        XCTAssertEqual(try String(contentsOf: resource, encoding: .utf8), "edited")
        let journal = try await fixture.service.load(roots: [fixture.root])
        XCTAssertNil(journal.pending)
        XCTAssertEqual(journal.completed.count, 1)
    }

    func testUndoAllowsUnrelatedLaterChangesButBlocksOverlappingHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one"); _ = try fixture.skill("two")
        let skills = fixture.library()
        let one = try fixture.plan(skills.filter { $0.installations[0].originalPath.hasSuffix("/one") })
        let two = try fixture.plan(skills.filter { $0.installations[0].originalPath.hasSuffix("/two") })
        try await fixture.service.apply(one, roots: [fixture.root])
        let preview = try await fixture.service.planUndo(id: one.id, roots: [fixture.root])
        try await fixture.service.apply(two, roots: [fixture.root])
        try await fixture.service.apply(preview, roots: [fixture.root])
        let later = try fixture.plan(fixture.library())
        try await fixture.service.apply(later, roots: [fixture.root])
        await assertThrows { _ = try await fixture.service.planUndo(id: one.id, roots: [fixture.root]) }
        await assertThrows { try await fixture.service.apply(preview, roots: [fixture.root]) }
    }

    func testUndoCollisionAndPartialUndoRecoveryNeverOverwrite() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one"); _ = try fixture.skill("two")
        let plan = try fixture.plan(fixture.library())
        try await fixture.service.apply(plan, roots: [fixture.root])
        let undo = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root])
        let conflict = URL(fileURLWithPath: undo.installations[0].destination)
        try FileManager.default.createDirectory(at: conflict, withIntermediateDirectories: false)
        try "keep".write(to: conflict.appendingPathComponent("sentinel"), atomically: true, encoding: .utf8)
        await assertThrows { try await fixture.service.apply(undo, roots: [fixture.root]) }
        XCTAssertEqual(try String(contentsOf: conflict.appendingPathComponent("sentinel"), encoding: .utf8), "keep")
        try FileManager.default.removeItem(at: conflict)
        var journal = try await fixture.service.load(roots: [fixture.root])
        journal.pending = undo
        try JSONEncoder().encode(journal).write(to: fixture.state.appendingPathComponent("library-journal.json"))
        let first = undo.installations[0]
        try FileManager.default.moveItem(atPath: first.source, toPath: first.destination)
        let reloaded = LibraryService(stateDirectory: fixture.state)
        try await reloaded.recover(roots: [fixture.root])
        let result = try await reloaded.load(roots: [fixture.root])
        XCTAssertNil(result.pending)
        XCTAssertTrue(result.disabled.isEmpty)
        XCTAssertEqual(result.completed.first?.undoes, plan.id)
        XCTAssertEqual(fixture.library().count, 2)
    }

    func testGroupSelectionIsJournaledForRecoveryAndMetadataOnlyUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = UUID()
        let selection = GroupSelectionChange(before: [], after: [id], previousChangeID: nil)
        let plan = MutationPlan(title: "Select group", installations: [], groupSelection: selection)
        try await fixture.service.apply(plan, roots: [fixture.root])
        let stale = MutationPlan(title: "Stale group", installations: [], groupSelection: selection)
        await assertThrows { try await fixture.service.apply(stale, roots: [fixture.root]) }
        let saved = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(saved.groupSelection?.id, plan.id)
        XCTAssertEqual(saved.groupSelection?.change.after, [id])
        let undo = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root])
        try await fixture.service.apply(undo, roots: [fixture.root])
        let restored = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(restored.groupSelection?.change.after, [])
        XCTAssertEqual(restored.completed.count, 2)
    }

    func testLegacyJournalRemainsReadableButCannotUndoWithoutTreeHash() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.skill("one")
        let plan = try fixture.plan(fixture.library())
        try await fixture.service.apply(plan, roots: [fixture.root])
        let path = fixture.state.appendingPathComponent("library-journal.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var records = try XCTUnwrap(json["completed"] as? [[String: Any]])
        for field in ["createdAt", "completedAt", "undoes", "groupSelection"] { records[0].removeValue(forKey: field) }
        var moves = try XCTUnwrap(records[0]["installations"] as? [[String: Any]])
        moves[0].removeValue(forKey: "treeHash"); records[0]["installations"] = moves
        json["completed"] = records; json.removeValue(forKey: "groupSelection")
        try JSONSerialization.data(withJSONObject: json).write(to: path)
        let legacy = try await fixture.service.load(roots: [fixture.root])
        XCTAssertEqual(legacy.completed[0].id, plan.id)
        XCTAssertNil(legacy.completed[0].createdAt)
        XCTAssertNotNil(legacy.undoUnavailableReason(for: plan.id))
        await assertThrows { _ = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root]) }
    }

    func testTreeFingerprintRejectsRenamesModesSpecialFilesAndOversizedContent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        let resource = original.appendingPathComponent("resource")
        try Data([1]).write(to: resource)
        let plan = try fixture.plan(fixture.library())
        let renamed = original.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: resource, to: renamed)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        try FileManager.default.moveItem(at: renamed, to: resource)
        var info = stat()
        XCTAssertEqual(lstat(resource.path, &info), 0)
        XCTAssertEqual(chmod(resource.path, info.st_mode ^ mode_t(0o100)), 0)
        await assertThrows { try await fixture.service.apply(plan, roots: [fixture.root]) }
        XCTAssertEqual(chmod(resource.path, info.st_mode), 0)
        let pipe = original.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try fixture.plan(fixture.library()))
        try FileManager.default.removeItem(at: pipe)
        let file = try FileHandle(forWritingTo: resource)
        try file.truncate(atOffset: 64 * 1_024 * 1_024 + 1)
        try file.close()
        XCTAssertThrowsError(try fixture.plan(fixture.library()))
    }

    func testTreeFingerprintTracksLinkTextWithoutReadingLinkTargets() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.skill("one")
        let external = fixture.base.appendingPathComponent("external")
        try Data([42]).write(to: external)
        let link = original.appendingPathComponent("linked-resource")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let plan = try fixture.plan(fixture.library())
        // External targets are not part of the moved tree and are never opened by its fingerprint.
        try Data([43]).write(to: external)
        try await fixture.service.apply(plan, roots: [fixture.root])
        let stored = URL(fileURLWithPath: plan.installations[0].destination)
        let movedLink = stored.appendingPathComponent("linked-resource")
        try FileManager.default.removeItem(at: movedLink)
        try FileManager.default.createSymbolicLink(atPath: movedLink.path, withDestinationPath: "different-target")
        await assertThrows { _ = try await fixture.service.planUndo(id: plan.id, roots: [fixture.root]) }
        XCTAssertEqual(try Data(contentsOf: external), Data([43]))
    }

    private func assertThrows(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected failure", file: file, line: line) } catch {}
    }

    private struct Fixture {
        let base: URL
        let root: DiscoveryRoot
        let state: URL
        let service: LibraryService
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LibraryTests-\(UUID().uuidString)")
            root = DiscoveryRoot(agent: .codex, url: base.appendingPathComponent(".agents/skills"), label: "Codex")
            state = base.appendingPathComponent("state")
            service = LibraryService(stateDirectory: state)
            try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        }
        func skill(_ name: String, body: String = "---\nname: shared\ndescription: A shared skill\n---\nRead only\n") throws -> URL {
            let url = root.url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try body.write(to: url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            return url
        }
        func library(disabled: [DisabledInstallation] = []) -> [CanonicalSkill] {
            LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: [root]), roots: [root], disabled: disabled)
        }
        func plan(_ skills: [CanonicalSkill]) throws -> MutationPlan {
            try LibraryService.plan(title: "Disable", installations: skills.flatMap(\.installations), enabled: false, allInstallations: skills.flatMap(\.installations), managedRoots: [root])
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }
}
