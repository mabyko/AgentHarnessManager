import Darwin
import Foundation
import XCTest
@testable import SkillCore

final class SkillCatalogTests: XCTestCase {
    func testCopiesAndSharedLinksKeepTheirOwnIdentityWithoutChangingFiles() throws {
        try withTemporaryDirectory { base in
            let first = base.appendingPathComponent("codex")
            let second = base.appendingPathComponent("claude")
            let source = try makeSkill("same-name", under: first)
            _ = try makeSkill("same-name", under: second)
            let linked = first.appendingPathComponent("shared-link")
            try FileManager.default.createSymbolicLink(atPath: linked.path, withDestinationPath: "same-name")
            let roots = [root(first), root(second, agent: .claudeCode)]
            let before = try Data(contentsOf: source.appendingPathComponent("SKILL.md"))
            let snapshot = SkillCatalog.scan(roots: roots)
            let copies = snapshot.entries.filter { $0.name == "same-name" }
            XCTAssertEqual(copies.count, 2)
            XCTAssertEqual(Set(copies.map(\.id)).count, 2)
            let reference = try entry(at: linked, in: snapshot)
            XCTAssertTrue(reference.isSymbolicLink)
            XCTAssertEqual(reference.resolvedURL?.standardizedFileURL.path, source.standardizedFileURL.path)
            XCTAssertNotEqual(reference.id, try entry(at: source, in: snapshot).id)
            XCTAssertEqual(try SkillCatalog.readDocument(entry: reference, approvedRoots: roots), String(decoding: before, as: UTF8.self))
            XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("SKILL.md")), before)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path), "same-name")
            XCTAssertEqual(snapshot.roots.map(\.status), [.available, .available])
        }
    }

    func testExternalAndBrokenLinksAreVisibleButCannotReadOutsideApprovedRoots() throws {
        try withTemporaryDirectory { base in
            let approved = base.appendingPathComponent("approved")
            let external = try makeSkill("outside", under: base.appendingPathComponent("private"))
            try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
            let externalLink = approved.appendingPathComponent("external")
            try FileManager.default.createSymbolicLink(at: externalLink, withDestinationURL: external)
            let broken = approved.appendingPathComponent("broken")
            try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
            let documentLink = approved.appendingPathComponent("document-link")
            try FileManager.default.createDirectory(at: documentLink, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: documentLink.appendingPathComponent("SKILL.md"), withDestinationURL: external.appendingPathComponent("SKILL.md"))
            let roots = [root(approved)]
            let snapshot = SkillCatalog.scan(roots: roots)
            for location in [externalLink, broken, documentLink] {
                let observed = try entry(at: location, in: snapshot)
                XCTAssertNotNil(observed.problem)
                XCTAssertThrowsError(try SkillCatalog.readDocument(entry: observed, approvedRoots: roots))
            }
            XCTAssertEqual(snapshot.roots.first?.status, .partial)
            XCTAssertEqual(try String(contentsOf: external.appendingPathComponent("SKILL.md"), encoding: .utf8), document)
            let approvedExternal = roots + [root(external.deletingLastPathComponent())]
            let nowReadable = try entry(at: externalLink, in: SkillCatalog.scan(roots: approvedExternal))
            XCTAssertEqual(try SkillCatalog.readDocument(entry: nowReadable, approvedRoots: approvedExternal), document)
        }
    }

    func testMissingAndBlockedRootsDoNotDiscardHealthyResults() throws {
        try withTemporaryDirectory { base in
            let healthy = base.appendingPathComponent("healthy")
            let skill = try makeSkill("valid", under: healthy)
            let missing = base.appendingPathComponent("missing")
            let blocked = base.appendingPathComponent("not-a-directory")
            try Data("regular file".utf8).write(to: blocked)
            let roots = [root(healthy), root(missing), root(blocked)]
            let snapshot = SkillCatalog.scan(roots: roots)
            XCTAssertEqual(snapshot.roots.map(\.status), [.available, .missing, .blocked])
            XCTAssertEqual(snapshot.entries.count, 1)
            XCTAssertEqual(try SkillCatalog.readDocument(entry: entry(at: skill, in: snapshot), approvedRoots: roots), document)
            let singleSkillRoot = [root(skill)]
            let singleSnapshot = SkillCatalog.scan(roots: singleSkillRoot)
            XCTAssertEqual(try SkillCatalog.readDocument(entry: entry(at: skill, in: singleSnapshot), approvedRoots: singleSkillRoot), document)
        }
    }

    func testBoundedRegularUTF8ReadsRejectSpecialFilesAndChangedParents() throws {
        try withTemporaryDirectory { base in
            let approved = base.appendingPathComponent("approved")
            let valid = try makeSkill("valid", under: approved)
            let huge = try makeSkill("huge", under: approved)
            try Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1).write(to: huge.appendingPathComponent("SKILL.md"))
            let invalid = try makeSkill("invalid-utf8", under: approved)
            try Data([0xFF, 0xFE]).write(to: invalid.appendingPathComponent("SKILL.md"))
            let fifo = approved.appendingPathComponent("fifo")
            try FileManager.default.createDirectory(at: fifo, withIntermediateDirectories: true)
            XCTAssertEqual(mkfifo(fifo.appendingPathComponent("SKILL.md").path, 0o600), 0)
            let roots = [root(approved)]
            let snapshot = SkillCatalog.scan(roots: roots)
            for location in [huge, invalid, fifo] {
                XCTAssertThrowsError(try SkillCatalog.readDocument(entry: entry(at: location, in: snapshot), approvedRoots: roots))
            }
            let original = try entry(at: valid, in: snapshot)
            let held = base.appendingPathComponent("held-original")
            try FileManager.default.moveItem(at: approved, to: held)
            let replacement = base.appendingPathComponent("replacement")
            _ = try makeSkill("valid", under: replacement)
            try FileManager.default.createSymbolicLink(at: approved, withDestinationURL: replacement)
            XCTAssertThrowsError(try SkillCatalog.readDocument(entry: original, approvedRoots: roots))
            XCTAssertEqual(try String(contentsOf: held.appendingPathComponent("valid/SKILL.md"), encoding: .utf8), document)
        }
    }

    func testInstallerReceiptIsOptionalBoundedAndDoesNotFollowMetadataLinks() throws {
        try withTemporaryDirectory { home in
            let source = try makeSkill("example", under: home.appendingPathComponent(".agents/skills"))
            let roots = [root(source.deletingLastPathComponent())]
            let entries = SkillCatalog.scan(roots: roots).entries
            let lock = home.appendingPathComponent(".agents/.skill-lock.json")
            XCTAssertTrue(SkillCatalog.installerSources(entries: entries, home: home).repositories.isEmpty)
            let valid = Data(#"{"version":3,"skills":{"example":{"sourceType":"github","sourceUrl":"https://github.com/owner/repo.git"}}}"#.utf8)
            try valid.write(to: lock)
            XCTAssertEqual(SkillCatalog.installerSources(entries: entries, home: home).repositories[entries[0].id]?.name, "owner/repo")
            for invalid in [Data("invalid JSON".utf8), Data([0xFF]), Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1), Data(#"{"version":4,"skills":{}}"#.utf8)] {
                try invalid.write(to: lock)
                let result = SkillCatalog.installerSources(entries: entries, home: home)
                XCTAssertTrue(result.repositories.isEmpty)
                XCTAssertNotNil(result.message)
            }
            try FileManager.default.removeItem(at: lock)
            let outside = home.appendingPathComponent("external-lock")
            try valid.write(to: outside)
            try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: outside)
            XCTAssertNotNil(SkillCatalog.installerSources(entries: entries, home: home).message)
            try FileManager.default.removeItem(at: lock)
            XCTAssertEqual(mkfifo(lock.path, 0o600), 0)
            XCTAssertNotNil(SkillCatalog.installerSources(entries: entries, home: home).message)
            try FileManager.default.removeItem(at: lock)
            try valid.write(to: lock)
            let held = home.appendingPathComponent("held")
            try FileManager.default.moveItem(at: home.appendingPathComponent(".agents"), to: held)
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".agents"), withDestinationURL: held)
            XCTAssertNotNil(SkillCatalog.installerSources(entries: entries, home: home).message)
            XCTAssertEqual(try Data(contentsOf: outside), valid)
        }
    }

    private let document = "---\nname: example\ndescription: Read-only fixture\n---\n# Example\n안녕하세요\n"

    private func root(_ url: URL, agent: SkillAgent = .codex) -> DiscoveryRoot {
        DiscoveryRoot(agent: agent, url: url, label: url.lastPathComponent)
    }

    private func entry(at url: URL, in snapshot: CatalogSnapshot) throws -> SkillEntry {
        try XCTUnwrap(snapshot.entries.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }, "Missing entry at \(url.path)")
    }

    @discardableResult
    private func makeSkill(_ name: String, under parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(document.utf8).write(to: directory.appendingPathComponent("SKILL.md"))
        return directory
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SkillCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
