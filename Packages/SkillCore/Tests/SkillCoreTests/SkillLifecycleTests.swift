import Darwin
import Foundation
import XCTest
@testable import SkillCore

final class SkillLifecycleTests: XCTestCase {
    private struct Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root: DiscoveryRoot
        let source: URL
        let service: LibraryService
        init() throws {
            root = DiscoveryRoot(agent: .codex, url: base.appendingPathComponent("agent/skills"), label: "Codex")
            source = base.appendingPathComponent("downloads/example")
            service = LibraryService(stateDirectory: base.appendingPathComponent("state"))
            try FileManager.default.createDirectory(at: source.appendingPathComponent("resources"), withIntermediateDirectories: true)
            try "---\nname: example\ndescription: Example skill\n---\nBody".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try Data([0, 1, 255]).write(to: source.appendingPathComponent("resources/data.bin"))
        }
        func installPlan() throws -> MutationPlan {
            try LibraryService.planInstallation(source: source, root: root, managedRoots: [root])
        }
        func library(_ journal: LibraryJournal = LibraryJournal()) -> [CanonicalSkill] {
            LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: [root]), roots: [root], disabled: journal.disabled)
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }

    func testInstallCopyCancelConflictAndUndo() async throws {
        let f = try Fixture(); defer { f.remove() }
        let cancelled = try f.installPlan()
        XCTAssertTrue(f.library().isEmpty)
        LibraryService.discardInstallation(cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.installations[0].source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
        let plan = try f.installPlan()
        try await f.service.apply(plan, roots: [f.root])
        XCTAssertEqual(f.library().count, 1)
        XCTAssertEqual(try Data(contentsOf: f.root.url.appendingPathComponent("example/resources/data.bin")), Data([0, 1, 255]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertThrowsError(try f.installPlan())
        let journal = try await f.service.load(roots: [f.root])
        XCTAssertEqual(journal.version, 3)
        let undo = try await f.service.planUndo(id: plan.id, roots: [f.root])
        try await f.service.apply(undo, roots: [f.root])
        let undone = try await f.service.load(roots: [f.root])
        XCTAssertTrue(f.library(undone).isEmpty)
        XCTAssertEqual(undone.disabled.first?.isRemoved, true)
    }

    func testChangedStagingAndDestinationCollisionAreRejected() async throws {
        let f = try Fixture(); defer { f.remove() }
        let plan = try f.installPlan()
        let destination = URL(fileURLWithPath: plan.installations[0].destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do { try await f.service.apply(plan, roots: [f.root]); XCTFail("Must reject a destination collision") } catch {}
        try FileManager.default.removeItem(at: destination)
        try "changed".write(to: URL(fileURLWithPath: plan.installations[0].source).appendingPathComponent("resources/data.bin"), atomically: true, encoding: .utf8)
        do { try await f.service.apply(plan, roots: [f.root]); XCTFail("Must revalidate staged resources") } catch {}
        XCTAssertTrue(f.library().isEmpty)
        LibraryService.discardInstallation(plan)
    }

    func testRemoveEnabledAndDisabledThenRestorePreviousState() async throws {
        for initiallyEnabled in [true, false] {
            let f = try Fixture(); defer { f.remove() }
            let install = try f.installPlan()
            try await f.service.apply(install, roots: [f.root])
            var journal = try await f.service.load(roots: [f.root])
            if !initiallyEnabled {
                let items = f.library().flatMap(\.installations)
                let off = try LibraryService.plan(title: "Off", installations: items, enabled: false, allInstallations: items, managedRoots: [f.root])
                try await f.service.apply(off, roots: [f.root])
                journal = try await f.service.load(roots: [f.root])
            }
            let items = f.library(journal).flatMap(\.installations)
            let removal = try LibraryService.planRemoval(installations: items, allInstallations: items, managedRoots: [f.root], protectedRoots: [f.root])
            XCTAssertEqual(removal.installations[0].changesLocation, initiallyEnabled)
            try await f.service.apply(removal, roots: [f.root])
            let removed = try await f.service.load(roots: [f.root])
            XCTAssertTrue(f.library(removed).isEmpty)
            XCTAssertTrue(try XCTUnwrap(removed.disabled.first).matchesCurrentItem)
            let undo = try await f.service.planUndo(id: removal.id, roots: [f.root])
            try await f.service.apply(undo, roots: [f.root])
            let restored = try await f.service.load(roots: [f.root])
            XCTAssertEqual(f.library(restored).first?.isEnabled, initiallyEnabled)
            XCTAssertEqual(f.library(restored).first?.id, "skill:" + items[0].id)
        }
    }

    func testRemovalProtectsSharedSourcesAndPreservesLinkTarget() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.apply(f.installPlan(), roots: [f.root])
        let original = f.root.url.appendingPathComponent("example")
        try FileManager.default.createSymbolicLink(at: f.root.url.appendingPathComponent("alias"), withDestinationURL: original)
        let items = f.library().flatMap(\.installations)
        XCTAssertThrowsError(try LibraryService.planRemoval(installations: items, allInstallations: items, managedRoots: [f.root], protectedRoots: [f.root]))
        let plan = try LibraryService.planRemoval(installations: items.filter(\.isSymbolicLink), allInstallations: items, managedRoots: [f.root], protectedRoots: [f.root])
        try await f.service.apply(plan, roots: [f.root])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.appendingPathComponent("SKILL.md").path))
        let removed = try await f.service.load(roots: [f.root])
        XCTAssertEqual(f.library(removed).flatMap(\.installations).count, 1)
        try await f.service.apply(f.service.planUndo(id: plan.id, roots: [f.root]), roots: [f.root])
        XCTAssertEqual(f.library().flatMap(\.installations).count, 2)
    }

    func testInstallRejectsSymlinksSpecialFilesAndUnmanagedRoots() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertThrowsError(try LibraryService.planInstallation(source: f.source, root: f.root, managedRoots: []))
        try FileManager.default.createSymbolicLink(at: f.source.appendingPathComponent("external"), withDestinationURL: f.base)
        XCTAssertThrowsError(try f.installPlan())
        try FileManager.default.removeItem(at: f.source.appendingPathComponent("external"))
        XCTAssertEqual(mkfifo(f.source.appendingPathComponent("pipe").path, 0o600), 0)
        XCTAssertThrowsError(try f.installPlan())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.root.url.deletingLastPathComponent().path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".ahm-disabled-") })
    }

    func testInterruptedInstallAndRemovalRecoverWithoutLosingArchive() async throws {
        let f = try Fixture(); defer { f.remove() }
        let install = try f.installPlan()
        var journal = try await f.service.load(roots: [f.root])
        let journalURL = f.base.appendingPathComponent("state/library-journal.json")
        journal.version = 3
        journal.pending = install
        try JSONEncoder().encode(journal).write(to: journalURL)
        try FileManager.default.moveItem(atPath: install.installations[0].source, toPath: install.installations[0].destination)
        try await f.service.recover(roots: [f.root])
        journal = try await f.service.load(roots: [f.root])
        XCTAssertNil(journal.pending)
        XCTAssertEqual(f.library(journal).count, 1)
        let items = f.library(journal).flatMap(\.installations)
        let removal = try LibraryService.planRemoval(installations: items, allInstallations: items, managedRoots: [f.root], protectedRoots: [f.root])
        journal.pending = removal
        try JSONEncoder().encode(journal).write(to: journalURL)
        try FileManager.default.moveItem(atPath: removal.installations[0].source, toPath: removal.installations[0].destination)
        let observed = try await f.service.load(roots: [f.root])
        XCTAssertTrue(f.library(observed).isEmpty)
        try await f.service.recover(roots: [f.root])
        let removed = try await f.service.load(roots: [f.root])
        XCTAssertNil(removed.pending)
        XCTAssertEqual(removed.disabled.first?.isRemoved, true)
        XCTAssertTrue(try XCTUnwrap(removed.disabled.first).matchesCurrentItem)
    }
}
