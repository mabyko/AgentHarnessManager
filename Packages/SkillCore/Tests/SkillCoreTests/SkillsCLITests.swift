import Foundation
import XCTest
@testable import SkillCore

final class SkillsCLITests: XCTestCase {
    private struct Fixture {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("CLI Test " + UUID().uuidString).resolvingSymlinksInPath()
        let source: URL
        let executable: URL
        let service: SkillsCLIService
        init(name: String = "Example Skill", version: String = "1.7.4", status: Int = 0) throws {
            source = home.appendingPathComponent("source folder")
            executable = home.appendingPathComponent("bin/skills")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: CLI fixture\n---\nBody".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then echo '\(version)'; exit 0; fi
            printf '%s\\n' "$@" > "$HOME/arguments"
            printf '%s\\n' "$DISABLE_TELEMETRY:$DO_NOT_TRACK" > "$HOME/telemetry"
            target="$HOME/.agents/skills/$AHM_TARGET"
            if [ "$1" = "remove" ]; then
                rm -rf -- "$target" "$HOME/.claude/skills/$AHM_TARGET"
                printf '%s' '{"version":3,"skills":{}}' > "$HOME/.agents/.skill-lock.json"
                echo 'fixture CLI removal'
                exit \(status)
            fi
            if [ "$5" = "claude-code" ]; then
                target="$HOME/.claude/skills/$AHM_TARGET"
            fi
            mkdir -p "$target"
            cp "$AHM_FIXTURE_SOURCE/SKILL.md" "$target/SKILL.md"
            echo 'fixture CLI output'
            exit \(status)
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let detector = AgentInstallationDetector(executableDirectories: [executable.deletingLastPathComponent(), URL(fileURLWithPath: "/usr/bin"), URL(fileURLWithPath: "/bin")], applicationDirectories: [])
            service = SkillsCLIService(home: home, environment: ["AHM_FIXTURE_SOURCE": source.path, "AHM_TARGET": SkillsCLIService.directoryName(name)], detector: detector)
        }
        func plan(agent: SkillAgent = .codex) throws -> SkillsCLIPlan { try service.prepare(folder: source, agent: agent, executable: executable) }
        func remove() { try? FileManager.default.removeItem(at: home) }
    }

    func testDetectionCommandArgumentsAndAgentTarget() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertEqual(f.service.detect(), f.executable)
        let plan = try f.plan(agent: .claudeCode)
        XCTAssertEqual(plan.arguments, ["add", f.source.path, "--global", "--agent", "claude-code", "--skill", "Example Skill", "--yes"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("arguments").path))
        XCTAssertTrue(try f.service.apply(plan).contains("fixture CLI output"))
        XCTAssertEqual(try String(contentsOf: f.home.appendingPathComponent("telemetry"), encoding: .utf8), "1:1\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.home.appendingPathComponent(".claude/skills/example-skill/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent(".agents/skills/example-skill").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.appendingPathComponent("SKILL.md").path))
        XCTAssertThrowsError(try f.plan(agent: .claudeCode))
    }

    func testMissingOverrideDoesNotSilentlyUseAnotherExecutable() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertNil(f.service.detect(preferred: f.home.appendingPathComponent("missing")))
        XCTAssertNotNil(f.service.detect())
    }

    func testReviewRevalidatesSourceExecutableReceiptAndDestination() throws {
        for change in ["source", "executable", "receipt", "destination"] {
            let f = try Fixture(); defer { f.remove() }
            let plan = try f.plan()
            switch change {
            case "source": try Data([1]).write(to: f.source.appendingPathComponent("new-resource"))
            case "executable": try "\n# changed\n".write(to: f.executable, atomically: true, encoding: .utf8)
            case "receipt":
                let file = f.home.appendingPathComponent(".agents/.skill-lock.json")
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{\"version\":3,\"skills\":{}}".utf8).write(to: file)
            default: try FileManager.default.createDirectory(atPath: plan.expectedPaths[0], withIntermediateDirectories: true)
            }
            XCTAssertThrowsError(try f.service.apply(plan), change)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("arguments").path), change)
        }
    }

    func testShellMetacharactersRemainLiteralArguments() throws {
        let sentinel = FileManager.default.temporaryDirectory.appendingPathComponent("CLIInjection-" + UUID().uuidString)
        defer { if FileManager.default.fileExists(atPath: sentinel.path) { try? FileManager.default.removeItem(at: sentinel) } }
        let name = "Example $(touch " + sentinel.path + ")"
        let f = try Fixture(name: name); defer { f.remove() }
        let plan = try f.plan()
        _ = try f.service.apply(plan)
        let args = try String(contentsOf: f.home.appendingPathComponent("arguments"), encoding: .utf8)
        XCTAssertTrue(args.contains(name))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testFailuresAreReportedWithoutRemovingPartialCLIChanges() throws {
        let f = try Fixture(status: 4); defer { f.remove() }
        let plan = try f.plan()
        XCTAssertThrowsError(try f.service.apply(plan)) { XCTAssertTrue($0.localizedDescription.contains("일부 변경")) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.expectedPaths[0] + "/SKILL.md"))
        XCTAssertThrowsError(try f.service.apply(plan))
    }

    func testUnsupportedVersionAndUnsafeReceiptAreBlocked() throws {
        let old = try Fixture(version: "1.6.0"); defer { old.remove() }
        XCTAssertThrowsError(try old.plan())
        let f = try Fixture(); defer { f.remove() }
        let file = f.home.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: f.source.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try f.plan())
    }

    private func installed(_ f: Fixture) -> [SkillInstallation] {
        let roots = ManagementConfiguration.defaultRoots(home: f.home)
        return LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: roots), roots: roots).flatMap(\.installations)
    }

    private func receipt(_ f: Fixture, ref: String = "main", sourceType: String = "github") throws {
        let file = f.home.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let value: [String: Any] = ["version": 3, "skills": ["Example Skill": ["source": "owner/repo", "sourceType": sourceType,
            "sourceUrl": "https://github.com/owner/repo", "ref": ref, "skillPath": "skills/example/SKILL.md", "skillFolderHash": String(repeating: "a", count: 40)]]]
        try JSONSerialization.data(withJSONObject: value).write(to: file)
    }

    func testScopedRemovalUsesCLIAndGlobalRemovalNamesOnlyOneSkill() throws {
        for agent in [SkillAgent.claudeCode, .codex] {
            let f = try Fixture(); defer { f.remove() }
            _ = try f.service.apply(f.plan(agent: agent)); try receipt(f)
            let items = installed(f)
            let plan = try f.service.prepareRemoval(installations: items, allInstallations: items, executable: f.executable, allAgents: agent == .codex)
            XCTAssertEqual(plan.operation, .remove)
            XCTAssertEqual(plan.arguments, agent == .codex ? ["remove", "Example Skill", "--global", "--yes"]
                           : ["remove", "Example Skill", "--global", "--agent", "claude-code", "--yes"])
            XCTAssertFalse(plan.arguments.contains("--all"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: items[0].originalPath))
            XCTAssertTrue(try f.service.apply(plan).contains("fixture CLI removal"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: items[0].originalPath))
            XCTAssertTrue(try f.service.receiptEntries().isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.appendingPathComponent("SKILL.md").path))
        }
    }

    func testMaintenanceRevalidatesFilesAndProtectsSharedReaders() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.service.apply(f.plan()); try receipt(f)
        var items = installed(f)
        let plan = try f.service.prepareRemoval(installations: items, allInstallations: items, executable: f.executable, allAgents: true)
        try FileManager.default.removeItem(at: f.home.appendingPathComponent("arguments"))
        try Data([1]).write(to: URL(fileURLWithPath: items[0].originalPath).appendingPathComponent("local-edit"))
        XCTAssertThrowsError(try f.service.apply(plan))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("arguments").path))
        let linked = f.home.appendingPathComponent(".claude/skills/example-skill")
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: URL(fileURLWithPath: items[0].originalPath))
        items = installed(f)
        XCTAssertThrowsError(try f.service.prepareRemoval(installations: [items.first { !$0.isSymbolicLink }!], allInstallations: items, executable: f.executable))
        XCTAssertNoThrow(try f.service.prepareRemoval(installations: items, allInstallations: items, executable: f.executable, allAgents: true))
    }

    func testUpdateSourceRequiresReceiptAndExplicitlyTracksPinnedCommits() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.service.apply(f.plan())
        let items = installed(f)
        XCTAssertThrowsError(try f.service.updateSource(for: items))
        try receipt(f)
        XCTAssertEqual(try f.service.updateSource(for: items).reference, "main")
        try receipt(f, ref: String(repeating: "b", count: 40))
        let pinned = try f.service.updateSource(for: items)
        XCTAssertTrue(pinned.pinnedCommit); XCTAssertNil(pinned.reference)
        try receipt(f, sourceType: "local")
        XCTAssertThrowsError(try f.service.updateSource(for: items))
    }

    func testUpdateUsesScopedCLIReinstallAndChecksAllResources() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.service.apply(f.plan(agent: .claudeCode)); try receipt(f)
        let items = installed(f), source = try f.service.updateSource(for: installed(f))
        let remote = URL(string: "https://github.com/owner/repo/tree/" + String(repeating: "b", count: 40) + "/skills/example")!
        let body = "---\nname: Example Skill\ndescription: Updated\n---\nNew body"
        try body.write(to: f.source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let plan = try f.service.prepareUpdate(folder: f.source, installations: items, source: source, remoteSource: remote, executable: f.executable)
        XCTAssertEqual(plan.operation, .update)
        XCTAssertEqual(plan.arguments, ["add", "https://github.com/owner/repo/tree/main/skills/example", "--global", "--agent", "claude-code", "--skill", "Example Skill", "--yes"])
        XCTAssertEqual(plan.reviewedCommit, String(repeating: "b", count: 40))
        XCTAssertEqual(plan.trackedReference, "main")
        _ = try f.service.apply(plan)
        XCTAssertEqual(try String(contentsOfFile: items[0].originalPath + "/SKILL.md", encoding: .utf8), body)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.home.appendingPathComponent(".agents/skills/example-skill").path))
        try Data([1]).write(to: f.source.appendingPathComponent("new-resource"))
        let incomplete = try f.service.prepareUpdate(folder: f.source, installations: installed(f), source: source, remoteSource: remote, executable: f.executable)
        XCTAssertThrowsError(try f.service.apply(incomplete)) { XCTAssertTrue($0.localizedDescription.contains("포함 파일")) }
    }

    func testReadOnlyContentComparisonIncludesResourcesAndLocalEdits() throws {
        let f = try Fixture(); defer { f.remove() }
        try Data([1,2,3]).write(to: f.source.appendingPathComponent("resource.bin"))
        let hashes = try GitHubSkillService.contentHashes(folder: f.source)
        XCTAssertEqual(hashes.keys.sorted(), ["SKILL.md", "resource.bin"])
        XCTAssertEqual(try GitHubSkillService.contentHashes(folder: f.source), hashes)
        let tree = hashes.map { path, sha -> [String: Any] in ["path": "skills/example/" + path, "type": "blob", "mode": "100644", "sha": sha, "size": 1] }
        let data = try JSONSerialization.data(withJSONObject: ["tree": tree, "truncated": false])
        let listing = try GitHubSkillService.parse(data, repository: SourceRepository("https://github.com/owner/repo")!)
        XCTAssertTrue(try GitHubSkillService.contentMatches(folder: f.source, skill: listing.skills[0], listing: listing))
        try Data([4]).write(to: f.source.appendingPathComponent("resource.bin"))
        XCTAssertFalse(try GitHubSkillService.contentMatches(folder: f.source, skill: listing.skills[0], listing: listing))
        try FileManager.default.createSymbolicLink(at: f.source.appendingPathComponent("link"), withDestinationURL: f.source.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try GitHubSkillService.contentMatches(folder: f.source, skill: listing.skills[0], listing: listing))
    }

    func testXDGReceiptAndRedirectedParents() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.service.apply(f.plan()); try receipt(f)
        let state = f.home.appendingPathComponent("state/skills")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: f.home.appendingPathComponent(".agents/.skill-lock.json"), to: state.appendingPathComponent(".skill-lock.json"))
        let detector = AgentInstallationDetector(executableDirectories: [f.executable.deletingLastPathComponent()], applicationDirectories: [])
        let xdg = SkillsCLIService(home: f.home, environment: ["XDG_STATE_HOME": state.deletingLastPathComponent().path], detector: detector)
        XCTAssertEqual(try xdg.updateSource(for: installed(f)).reference, "main")
        let redirect = f.home.appendingPathComponent("redirect")
        try FileManager.default.createSymbolicLink(at: redirect, withDestinationURL: state.deletingLastPathComponent())
        let unsafe = SkillsCLIService(home: f.home, environment: ["XDG_STATE_HOME": redirect.path], detector: detector)
        XCTAssertThrowsError(try unsafe.updateSource(for: installed(f)))
    }
}
