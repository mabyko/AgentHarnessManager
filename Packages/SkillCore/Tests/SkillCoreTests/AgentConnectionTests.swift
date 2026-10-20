import Foundation
import XCTest
@testable import SkillCore

final class AgentConnectionTests: XCTestCase {
    func testReviewedInstallAndRemovalPreserveOtherSettingsAndBackUpAllTargets() async throws {
        let fixture = try ConnectionFixture(); defer { fixture.remove() }
        let installer = AgentConnectionInstaller(home: fixture.home, environment: fixture.environment)
        for target in [AgentConnectionTarget.codex, .claudeCode, .grokBuild] {
            let config = fixture.config(target)
            let original = Data("{\"keep\":\"untouched\",\"mcpServers\":{\"other\":{\"command\":\"other\"}}}".utf8)
            try original.write(to: config)
            let plan = try await installer.prepare(target: target, removing: false, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: target))
            XCTAssertEqual(try Data(contentsOf: config), original, "Preparing an install must not change configuration")
            XCTAssertFalse(plan.arguments.contains("login"))
            XCTAssertTrue(plan.arguments.contains("--"))
            if target != .codex { XCTAssertEqual(Array(plan.arguments.prefix(6)), ["mcp", "add", "--scope", "user", "--transport", "stdio"]) }
            let backup = try await installer.apply(plan, backupDirectory: fixture.home.appendingPathComponent("backups"))
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
            let permissions = try FileManager.default.attributesOfItem(atPath: backup!.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o600)
            let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
            XCTAssertEqual(installed["keep"] as? String, "untouched")
            XCTAssertNotNil((installed["mcpServers"] as? [String: Any])?["other"])
            do {
                _ = try await installer.prepare(target: target, removing: false, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: target))
                XCTFail("Repeated installation should require no overwrite")
            } catch AgentConnectionError.alreadyInstalled {}
            let removal = try await installer.prepare(target: target, removing: true, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: target))
            _ = try await installer.apply(removal, backupDirectory: fixture.home.appendingPathComponent("backups"))
            let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
            XCTAssertNil((removed["mcpServers"] as? [String: Any])?[AgentConnectionInstaller.serverName])
            XCTAssertNotNil((removed["mcpServers"] as? [String: Any])?["other"])
        }
    }

    func testForeignRegistrationAndChangesAfterPreviewAreNotOverwritten() async throws {
        let fixture = try ConnectionFixture(); defer { fixture.remove() }
        let installer = AgentConnectionInstaller(home: fixture.home, environment: fixture.environment)
        for target in [AgentConnectionTarget.codex, .claudeCode, .grokBuild] {
            let config = fixture.config(target)
            let foreign = Data("{\"mcpServers\":{\"agent-harness-manager\":{\"type\":\"stdio\",\"command\":\"/other/tool\",\"args\":[]}}}".utf8)
            try foreign.write(to: config)
            for removing in [false, true] {
                do {
                    _ = try await installer.prepare(target: target, removing: removing, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: target))
                    XCTFail("Foreign registration should be preserved")
                } catch AgentConnectionError.conflict {}
            }
            XCTAssertEqual(try Data(contentsOf: config), foreign)
            try Data("{}".utf8).write(to: config)
            let plan = try await installer.prepare(target: target, removing: false, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: target))
            let externalEdit = Data("{\"external\":true}".utf8)
            try externalEdit.write(to: config)
            do { _ = try await installer.apply(plan, backupDirectory: fixture.home.appendingPathComponent("backups")); XCTFail("Stale preview accepted") }
            catch AgentConnectionError.changed {}
            XCTAssertEqual(try Data(contentsOf: config), externalEdit)
        }
    }

    func testSymlinkAndMalformedConfigurationArePreserved() async throws {
        let fixture = try ConnectionFixture(); defer { fixture.remove() }
        let config = fixture.config(.claudeCode), outside = fixture.home.appendingPathComponent("outside.json")
        let data = Data("{}".utf8)
        try data.write(to: outside)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: outside)
        let installer = AgentConnectionInstaller(home: fixture.home, environment: fixture.environment)
        do {
            _ = try await installer.prepare(target: .claudeCode, removing: false, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: .claudeCode))
            XCTFail("Symlinked config accepted")
        } catch AgentConnectionError.invalidConfiguration {}
        XCTAssertEqual(try Data(contentsOf: outside), data)
        try FileManager.default.removeItem(at: config)
        try Data("invalid".utf8).write(to: config)
        do {
            _ = try await installer.prepare(target: .claudeCode, removing: false, helperURL: fixture.helper, domain: "management.tests", executableURL: fixture.executable(for: .claudeCode))
            XCTFail("Malformed config accepted")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: config), Data("invalid".utf8))
    }
}

private struct ConnectionFixture {
    let home: URL
    var helper: URL { home.appendingPathComponent("codex-cli") }
    func executable(for target: AgentConnectionTarget) -> URL { home.appendingPathComponent(target.executableName + "-cli") }
    var environment: [String: String] {
        ["PATH": "/usr/bin:/bin", "CODEX_HOME": home.appendingPathComponent("codex").path,
         "CLAUDE_CONFIG_DIR": home.appendingPathComponent("claude").path,
         "GROK_HOME": home.appendingPathComponent("grok").path]
    }
    init() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("System Python is unavailable") }
        home = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-connections-" + UUID().uuidString)
        for name in ["codex", "claude", "grok"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true) }
        let script = """
        #!/usr/bin/python3
        import json, os, pathlib, sys
        args = sys.argv[1:]
        assert args[0] == 'mcp' and args[1] in ('get', 'list', 'add', 'remove')
        target = pathlib.Path(sys.argv[0]).name.removesuffix('-cli')
        config = pathlib.Path(os.environ[{'claude':'CLAUDE_CONFIG_DIR','codex':'CODEX_HOME','grok':'GROK_HOME'}[target]]) / ('.claude.json' if target == 'claude' else 'config.toml')
        data = json.loads(config.read_text()) if config.exists() else {}
        servers = data.setdefault('mcpServers', {})
        if args[1] == 'list':
            print(json.dumps([dict(server, name=name, scope='user') for name, server in servers.items()]))
        elif args[1] == 'get':
            server = servers.get('agent-harness-manager')
            if server is None:
                print("Error: No MCP server named 'agent-harness-manager' found.", file=sys.stderr)
                sys.exit(1)
            print(json.dumps({'transport': server}))
        elif args[1] == 'add':
            index = args.index('--')
            assert args[index - 1] == 'agent-harness-manager'
            servers['agent-harness-manager'] = {'type': 'stdio', 'command': args[index + 1], 'args': args[index + 2:]}
            config.write_text(json.dumps(data))
        else:
            assert args[-1] == 'agent-harness-manager'
            servers.pop('agent-harness-manager', None)
            config.write_text(json.dumps(data))
        """
        for target in [AgentConnectionTarget.codex, .claudeCode, .grokBuild] {
            let executable = executable(for: target)
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
    }
    func config(_ target: AgentConnectionTarget) -> URL {
        home.appendingPathComponent(target == .codex ? "codex/config.toml" : target == .grokBuild ? "grok/config.toml" : "claude/.claude.json")
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
