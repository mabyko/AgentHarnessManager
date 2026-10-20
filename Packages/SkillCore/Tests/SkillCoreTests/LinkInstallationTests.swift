import Darwin
import Foundation
import XCTest
@testable import SkillCore

final class LinkInstallationTests: XCTestCase {
    func testRelativeLinkArchiveKeepsSourceOtherReaderAndCanonicalIdentity() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let before = f.library()
        let sourceID = try XCTUnwrap(before.first).id
        let item = try f.item(f.codexLink)
        let plan = try f.plan([item], enabled: false)
        // Moving this relative link beside the root makes its text point at a decoy. Never follow it there.
        let decoy = f.codex.url.deletingLastPathComponent().appendingPathComponent("source")
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        try "decoy".write(to: decoy.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try await f.service.apply(plan, roots: f.roots)
        let journal = try await f.service.load(roots: f.roots)
        XCTAssertEqual(journal.version, 2)
        let saved = try XCTUnwrap(journal.disabled.first)
        XCTAssertTrue(saved.matchesCurrentItem)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: saved.currentPath), "source")
        XCTAssertEqual(try LibraryService.readStoredLinkDocument(saved, roots: f.roots), f.body)
        let after = f.library(disabled: journal.disabled)
        XCTAssertEqual(after.map(\.id), [sourceID])
        XCTAssertEqual(after[0].installations.count, 3)
        let off = try XCTUnwrap(after[0].installations.first { $0.id == item.id })
        XCTAssertTrue(off.isSymbolicLink)
        XCTAssertFalse(off.isEnabled)
        XCTAssertEqual(try LibraryCatalog.readDocument(installation: off, roots: f.roots), f.body)
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent("SKILL.md"), encoding: .utf8), f.body)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.claudeLink.path), "../../.agents/skills/source")
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent("resource.bin")), Data([0, 255, 42]))
        XCTAssertEqual(after[0].activationInstallations.count, 2)
        XCTAssertTrue(after[0].activationInstallations.allSatisfy(\.isSymbolicLink))
    }

    func testLinkRestoreAndUndoPreserveExactTextAndInode() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let item = try f.item(f.claudeLink)
        let disable = try f.plan([item], enabled: false)
        try await f.service.apply(disable, roots: f.roots)
        let undoDisable = try await f.service.planUndo(id: disable.id, roots: f.roots)
        try await f.service.apply(undoDisable, roots: f.roots)
        XCTAssertEqual(try f.item(f.claudeLink).id, item.id)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.claudeLink.path), "../../.agents/skills/source")
        try await f.service.apply(f.plan([f.item(f.claudeLink)], enabled: false), roots: f.roots)
        let disabled = try await f.service.load(roots: f.roots)
        let off = try f.item(f.claudeLink, disabled: disabled.disabled)
        let restore = try f.plan([off], enabled: true, disabled: disabled.disabled)
        try await f.service.apply(restore, roots: f.roots)
        let undoRestore = try await f.service.planUndo(id: restore.id, roots: f.roots)
        try await f.service.apply(undoRestore, roots: f.roots)
        let final = try await f.service.load(roots: f.roots)
        XCTAssertEqual(final.disabled.count, 1)
        XCTAssertEqual(final.disabled[0].id, item.id)
        XCTAssertEqual(final.disabled[0].currentPath, disabled.disabled[0].currentPath)
        XCTAssertTrue(final.disabled[0].matchesCurrentItem)
    }

    func testSourceEditBlocksStalePreviewAndUndoButFreshRestoreCanBeReviewed() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let item = try f.item(f.claudeLink)
        let plan = try f.plan([item], enabled: false)
        let resource = f.source.appendingPathComponent("resource.bin")
        try Data([7]).write(to: resource)
        await fails { try await f.service.apply(plan, roots: f.roots) }
        let fresh = try f.plan([f.item(f.claudeLink)], enabled: false)
        try await f.service.apply(fresh, roots: f.roots)
        try Data([8]).write(to: resource)
        await fails { _ = try await f.service.planUndo(id: fresh.id, roots: f.roots) }
        let journal = try await f.service.load(roots: f.roots)
        let off = try f.item(f.claudeLink, disabled: journal.disabled)
        let restore = try f.plan([off], enabled: true, disabled: journal.disabled)
        try await f.service.apply(restore, roots: f.roots)
        XCTAssertEqual(try Data(contentsOf: resource), Data([8]))
        XCTAssertTrue(try f.item(f.claudeLink).isEnabled)
    }

    func testReplacementSourceStaysVisibleAsUnreadableAndCannotBeAdopted() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let item = try f.item(f.claudeLink)
        try await f.service.apply(f.plan([item], enabled: false), roots: f.roots)
        let journal = try await f.service.load(roots: f.roots)
        try FileManager.default.moveItem(at: f.source, to: f.base.appendingPathComponent("held-source"))
        try FileManager.default.createDirectory(at: f.source, withIntermediateDirectories: true)
        try f.body.write(to: f.source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let off = try f.item(f.claudeLink, disabled: journal.disabled)
        XCTAssertNotNil(off.readError)
        XCTAssertThrowsError(try f.plan([off], enabled: true, disabled: journal.disabled))
        XCTAssertTrue(journal.disabled[0].matchesCurrentItem)
        XCTAssertEqual(try String(contentsOf: f.source.appendingPathComponent("SKILL.md"), encoding: .utf8), f.body)
    }

    func testLinkReplacementAndDestinationCollisionNeverOverwrite() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let item = try f.item(f.claudeLink)
        let plan = try f.plan([item], enabled: false)
        let destination = plan.installations[0].destination
        try Data([99]).write(to: URL(fileURLWithPath: destination))
        await fails { try await f.service.apply(plan, roots: f.roots) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), Data([99]))
        try FileManager.default.removeItem(atPath: destination)
        let held = f.base.appendingPathComponent("held-link")
        try FileManager.default.moveItem(at: f.claudeLink, to: held)
        try FileManager.default.createSymbolicLink(at: f.claudeLink, withDestinationURL: f.source)
        await fails { try await f.service.apply(plan, roots: f.roots) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.claudeLink.path), f.source.path)
        XCTAssertNotEqual(try f.item(f.claudeLink).id, item.id)
    }

    func testIncomingIndirectReaderBlocksPreviewAndApply() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let item = try f.item(f.claudeLink)
        let plan = try f.plan([item], enabled: false)
        let dependent = f.codex.url.appendingPathComponent("indirect")
        try FileManager.default.createSymbolicLink(at: dependent, withDestinationURL: f.claudeLink)
        XCTAssertThrowsError(try f.plan([f.item(f.claudeLink)], enabled: false))
        await fails { try await f.service.apply(plan, roots: f.roots) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.claudeLink.path))
        XCTAssertEqual(try String(contentsOf: dependent.appendingPathComponent("SKILL.md"), encoding: .utf8), f.body)
    }

    func testNewReaderOfArchivedAbsoluteLinkBlocksRestore() async throws {
        let f = try Fixture()
        defer { f.remove() }
        try FileManager.default.removeItem(at: f.claudeLink)
        try FileManager.default.createSymbolicLink(at: f.claudeLink, withDestinationURL: f.source)
        try await f.service.apply(f.plan([f.item(f.claudeLink)], enabled: false), roots: f.roots)
        let journal = try await f.service.load(roots: f.roots)
        let off = try f.item(f.claudeLink, disabled: journal.disabled)
        let restore = try f.plan([off], enabled: true, disabled: journal.disabled)
        let reader = f.codex.url.appendingPathComponent("archive-reader")
        try FileManager.default.createSymbolicLink(atPath: reader.path, withDestinationPath: journal.disabled[0].currentPath)
        XCTAssertThrowsError(try f.plan([off], enabled: true, disabled: journal.disabled))
        await fails { try await f.service.apply(restore, roots: f.roots) }
        XCTAssertEqual(try String(contentsOf: reader.appendingPathComponent("SKILL.md"), encoding: .utf8), f.body)
        XCTAssertTrue(journal.disabled[0].matchesCurrentItem)
    }

    func testRegisteredRootDependingOnLinkBlocksItsMove() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let plan = try f.plan([f.item(f.claudeLink)], enabled: false)
        let root = DiscoveryRoot(agent: .custom, url: f.claudeLink, label: "Dependent root")
        await fails { try await f.service.apply(plan, roots: f.roots + [root]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.claudeLink.path))
    }

    func testBrokenExternalAndMultiHopLinksRemainReadOnly() throws {
        let f = try Fixture()
        defer { f.remove() }
        let broken = f.claude.url.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
        XCTAssertNotNil(try f.item(broken).readError)
        XCTAssertThrowsError(try f.plan([f.item(broken)], enabled: false))
        try FileManager.default.removeItem(at: broken)
        let outside = f.base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try f.body.write(to: outside.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let external = f.claude.url.appendingPathComponent("external")
        try FileManager.default.createSymbolicLink(at: external, withDestinationURL: outside)
        XCTAssertNotNil(try f.item(external).readError)
        XCTAssertThrowsError(try f.plan([f.item(external)], enabled: false))
        try FileManager.default.removeItem(at: external)
        let chain = f.claude.url.appendingPathComponent("chain")
        try FileManager.default.createSymbolicLink(at: chain, withDestinationURL: f.codexLink)
        XCTAssertThrowsError(try f.plan([f.item(chain)], enabled: false))
    }

    func testLinkBatchAndInverseRecoverAfterPartialMoves() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let plan = try f.plan(f.library()[0].activationInstallations, enabled: false)
        XCTAssertEqual(plan.installations.count, 2)
        var journal = try await f.service.load(roots: f.roots)
        journal.version = 2; journal.pending = plan
        try JSONEncoder().encode(journal).write(to: f.state.appendingPathComponent("library-journal.json"))
        let first = plan.installations[0]
        try FileManager.default.moveItem(atPath: first.source, toPath: first.destination)
        let observed = try await f.service.load(roots: f.roots)
        XCTAssertEqual(observed.disabled.count, 1)
        let restarted = LibraryService(stateDirectory: f.state)
        try await restarted.recover(roots: f.roots)
        journal = try await restarted.load(roots: f.roots)
        XCTAssertEqual(journal.disabled.count, 2)
        XCTAssertEqual(f.library(disabled: journal.disabled)[0].activationInstallations.filter(\.isEnabled).count, 0)
        let undo = try await restarted.planUndo(id: plan.id, roots: f.roots)
        journal.pending = undo
        try JSONEncoder().encode(journal).write(to: f.state.appendingPathComponent("library-journal.json"))
        try FileManager.default.moveItem(atPath: undo.installations[0].source, toPath: undo.installations[0].destination)
        try await restarted.recover(roots: f.roots)
        let final = try await restarted.load(roots: f.roots)
        XCTAssertTrue(final.disabled.isEmpty)
        XCTAssertEqual(final.completed[0].undoes, plan.id)
        XCTAssertEqual(f.library()[0].installations.count, 3)
    }

    func testSharedSourceStaysProtectedWithOnlyArchivedReaders() async throws {
        let f = try Fixture()
        defer { f.remove() }
        try await f.service.apply(f.plan(f.library()[0].activationInstallations, enabled: false), roots: f.roots)
        let journal = try await f.service.load(roots: f.roots)
        let source = try f.item(f.source, disabled: journal.disabled)
        XCTAssertNotNil(LibraryService.readOnlyReason(for: source, allInstallations: f.library(disabled: journal.disabled).flatMap(\.installations), managedRoots: f.roots))
        XCTAssertThrowsError(try f.plan([source], enabled: false, disabled: journal.disabled))
        // Even a caller omitting archived readers cannot move the source past the durable journal check.
        await fails {
            let incomplete = try LibraryService.plan(title: "Source", installations: [source], enabled: false, allInstallations: [source], managedRoots: f.roots)
            try await f.service.apply(incomplete, roots: f.roots)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
    }

    func testNestedAndCustomInstallationLinksStayReadOnly() throws {
        let f = try Fixture()
        defer { f.remove() }
        let nested = f.claude.url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let link = nested.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.source)
        XCTAssertThrowsError(try f.plan([f.item(link)], enabled: false))
        let root = DiscoveryRoot(agent: .custom, url: nested, label: "Custom")
        let roots = f.roots + [root]
        let library = LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: roots), roots: roots)
        let custom = try XCTUnwrap(library.flatMap(\.installations).first { $0.location.id == root.id })
        XCTAssertThrowsError(try LibraryService.plan(title: "Custom", installations: [custom], enabled: false,
            allInstallations: library.flatMap(\.installations), managedRoots: f.roots, protectedRoots: roots))
    }

    private func fails(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected rejection", file: file, line: line) } catch {}
    }

    private struct Fixture {
        let base: URL, source: URL, codexLink: URL, claudeLink: URL, state: URL
        let codex: DiscoveryRoot, claude: DiscoveryRoot
        let service: LibraryService
        let body = "---\nname: shared\ndescription: Shared source\n---\nOriginal content\n"
        var roots: [DiscoveryRoot] { [codex, claude] }
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LinkInstallationTests-\(UUID().uuidString)")
            codex = DiscoveryRoot(agent: .codex, url: base.appendingPathComponent(".agents/skills"), label: "Codex")
            claude = DiscoveryRoot(agent: .claudeCode, url: base.appendingPathComponent(".claude/skills"), label: "Claude")
            source = codex.url.appendingPathComponent("source")
            codexLink = codex.url.appendingPathComponent("codex-link")
            claudeLink = claude.url.appendingPathComponent("claude-link")
            state = base.appendingPathComponent("state")
            service = LibraryService(stateDirectory: state)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: claude.url, withIntermediateDirectories: true)
            try body.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try Data([0, 255, 42]).write(to: source.appendingPathComponent("resource.bin"))
            try FileManager.default.createSymbolicLink(atPath: codexLink.path, withDestinationPath: "source")
            try FileManager.default.createSymbolicLink(atPath: claudeLink.path, withDestinationPath: "../../.agents/skills/source")
        }
        func library(disabled: [DisabledInstallation] = []) -> [CanonicalSkill] {
            LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: roots), roots: roots, disabled: disabled)
        }
        func item(_ path: URL, disabled: [DisabledInstallation] = []) throws -> SkillInstallation {
            try XCTUnwrap(library(disabled: disabled).flatMap(\.installations).first { $0.originalPath == path.path })
        }
        func plan(_ items: [SkillInstallation], enabled: Bool, disabled: [DisabledInstallation] = []) throws -> MutationPlan {
            try LibraryService.plan(title: "Link switch", installations: items, enabled: enabled,
                allInstallations: library(disabled: disabled).flatMap(\.installations), managedRoots: roots)
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }
}
