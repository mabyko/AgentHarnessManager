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
        func plan(agent: SkillAgent = .codex) throws -> SkillsCLIInstallPlan { try service.prepare(folder: source, agent: agent, executable: executable) }
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
}
