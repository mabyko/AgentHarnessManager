import Darwin
import XCTest
@testable import SkillCore

final class GlobalInstructionTests: XCTestCase {
    func testDiscoveryIsReadOnlyAndIncludesSupportedCandidatesAndEnvironment() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let documents = try f.service.scan()
        XCTAssertEqual(Set(documents.map(\.agent)), Set(GlobalInstructionService.supportedAgents))
        XCTAssertFalse(documents.contains { [.cursor, .devin, .custom].contains($0.agent) })
        XCTAssertTrue(documents.allSatisfy { $0.data == nil && $0.issue == nil })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.home.path), [])
        let alternate = GlobalInstructionService(home: f.home, environment: ["CODEX_HOME": f.home.appendingPathComponent("profile").path,
            "PI_CODING_AGENT_DIR": "~/pi-profile", "XDG_CONFIG_HOME": "~/config"], backupDirectory: f.backups)
        XCTAssertTrue(try alternate.scan().contains { $0.url == f.home.appendingPathComponent("profile/AGENTS.override.md") })
        XCTAssertTrue(try alternate.scan().contains { $0.url == f.home.appendingPathComponent("pi-profile/AGENTS.md") })
        XCTAssertTrue(try alternate.scan().contains { $0.url == f.home.appendingPathComponent("config/opencode/AGENTS.md") })
    }

    func testPreviewThenCreateAndRestoreCreationWithoutOverwriting() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let document = try f.document(.codex)
        let plan = try f.service.prepare(document, text: "# Rules\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.backups.path))
        let saved = try f.service.apply(plan)
        XCTAssertEqual(try Data(contentsOf: document.url), Data("# Rules\n".utf8))
        XCTAssertTrue(saved.wasCreation)
        XCTAssertEqual(try f.service.backups(for: f.document(.codex)).count, 1)
        let restore = try f.service.prepareRestore(f.document(.codex), backupID: saved.id)
        XCTAssertNil(restore.replacementData)
        let undoRecord = try f.service.apply(restore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.url.path))
        try f.service.apply(f.service.prepareRestore(f.document(.codex), backupID: undoRecord.id))
        XCTAssertEqual(try Data(contentsOf: document.url), Data("# Rules\n".utf8))
        var info = stat(); XCTAssertEqual(stat(f.backups.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o700)
    }

    func testExactBackupAndEncodingAndPermissionsSurviveEditAndRestore() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let url = f.home.appendingPathComponent(".claude/CLAUDE.md")
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# 지침\r\n기존 내용\r\n".utf8)
        try f.write(original, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let document = try f.document(.claudeCode, name: "CLAUDE.md")
        XCTAssertEqual(document.text, "# 지침\r\n기존 내용\r\n")
        let record = try f.service.apply(f.service.prepare(document, text: "# 지침\n수정 내용\n"))
        XCTAssertEqual(try Data(contentsOf: url), Data([0xEF, 0xBB, 0xBF]) + Data("# 지침\r\n수정 내용\r\n".utf8))
        var info = stat(); XCTAssertEqual(stat(url.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o640)
        try f.service.apply(f.service.prepareRestore(f.document(.claudeCode, name: "CLAUDE.md"), backupID: record.id))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(stat(url.path, &info), 0); XCTAssertEqual(info.st_mode & 0o777, 0o640)
    }

    func testExternalChangesAndNewPriorityFilesBlockSaving() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let url = f.home.appendingPathComponent(".codex/AGENTS.md")
        try f.write(Data("old".utf8), to: url)
        let plan = try f.service.prepare(f.document(.codex), text: "draft")
        try Data("external".utf8).write(to: url)
        XCTAssertThrowsError(try f.service.apply(plan))
        XCTAssertEqual(try Data(contentsOf: url), Data("external".utf8))
        let next = try f.service.prepare(f.document(.codex), text: "draft")
        try f.write(Data("priority".utf8), to: url.deletingLastPathComponent().appendingPathComponent("AGENTS.override.md"))
        XCTAssertThrowsError(try f.service.apply(next))
        XCTAssertEqual(try Data(contentsOf: url), Data("external".utf8))
        let missing = try f.document(.pi)
        let creation = try f.service.prepare(missing, text: "new")
        try f.write(Data("appeared".utf8), to: missing.url)
        XCTAssertThrowsError(try f.service.apply(creation))
        XCTAssertEqual(try Data(contentsOf: missing.url), Data("appeared".utf8))
    }

    func testSharedSymlinkSourceIsEditedWithoutReplacingLinksAndRetargetIsRejected() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let source = f.home.appendingPathComponent(".claude/CLAUDE.md")
        try f.write(Data("old".utf8), to: source)
        let link = f.home.appendingPathComponent(".codex/AGENTS.md")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../.claude/CLAUDE.md")
        let document = try f.document(.codex)
        XCTAssertTrue(document.isLink)
        let plan = try f.service.prepare(document, text: "shared")
        XCTAssertEqual(Set(plan.affectedAgents), Set([.codex, .claudeCode, .opencode]))
        try f.service.apply(plan)
        XCTAssertEqual(try Data(contentsOf: source), Data("shared".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "../.claude/CLAUDE.md")
        let stale = try f.service.prepare(f.document(.codex), text: "another")
        let other = f.home.appendingPathComponent("other.md"); try Data("shared".utf8).write(to: other)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertThrowsError(try f.service.apply(stale))
        XCTAssertEqual(try Data(contentsOf: source), Data("shared".utf8))
        XCTAssertEqual(try Data(contentsOf: other), Data("shared".utf8))
    }

    func testOutsideLinksLinkedParentsSpecialAndOversizedFilesAreBlocked() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let outside = f.home.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("sentinel".utf8).write(to: outside)
        let url = f.home.appendingPathComponent(".codex/AGENTS.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        XCTAssertNotNil(try f.document(.codex).issue)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        XCTAssertNotNil(try f.document(.codex).issue)
        try FileManager.default.removeItem(at: url)
        try Data(repeating: 65, count: GlobalInstructionService.limit + 1).write(to: url)
        XCTAssertNotNil(try f.document(.codex).issue)
        try Data([0xFF, 0xFE]).write(to: url)
        XCTAssertNotNil(try f.document(.codex).issue)
        let parent = f.home.appendingPathComponent(".pi")
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: url.deletingLastPathComponent())
        XCTAssertNotNil(try f.document(.pi).issue)
        XCTAssertEqual(try Data(contentsOf: outside), Data("sentinel".utf8))
    }

    func testRestoreRejectsChangedFileAndCorruptBackup() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let document = try f.document(.codex)
        let record = try f.service.apply(f.service.prepare(document, text: "saved"))
        try Data("changed".utf8).write(to: document.url)
        XCTAssertThrowsError(try f.service.prepareRestore(f.document(.codex), backupID: record.id))
        try Data("broken".utf8).write(to: f.backups.appendingPathComponent(record.id.uuidString + ".json"))
        XCTAssertThrowsError(try f.service.backups(for: f.document(.codex)))
        XCTAssertEqual(try Data(contentsOf: document.url), Data("changed".utf8))
    }

    func testReadOnlyAndHardLinksAreNeverReplaced() throws {
        let f = try InstructionFixture(); defer { f.remove() }
        let document = try f.document(.codex)
        try f.write(Data("read only".utf8), to: document.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: document.url.path)
        XCTAssertThrowsError(try f.service.prepare(f.document(.codex), text: "new"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: document.url.path)
        let link = f.home.appendingPathComponent("hard.md")
        try FileManager.default.linkItem(at: document.url, to: link)
        XCTAssertNotNil(try f.document(.codex).issue)
        XCTAssertEqual(try Data(contentsOf: link), Data("read only".utf8))
    }
}

private struct InstructionFixture {
    let home: URL
    var backups: URL { home.appendingPathComponent("state/InstructionBackups") }
    var service: GlobalInstructionService { GlobalInstructionService(home: home, environment: [:], backupDirectory: backups) }
    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-instructions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        home = root.resolvingSymlinksInPath()
    }
    func document(_ agent: SkillAgent, name: String = "AGENTS.md") throws -> InstructionDocument {
        try XCTUnwrap(service.scan().first { $0.agent == agent && $0.url.lastPathComponent == name })
    }
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
