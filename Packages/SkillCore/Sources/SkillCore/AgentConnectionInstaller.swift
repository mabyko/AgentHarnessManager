import CoreFoundation
import Darwin
import Foundation

public enum AgentConnectionTarget: String, CaseIterable, Sendable, Identifiable {
    case codex, claudeCode, grokBuild, antigravity, opencode, pi, devin, cursor
    public var id: String { rawValue }
    public var name: String {
        SkillAgent(rawValue: rawValue)!.displayName
    }
    public var executableName: String {
        switch self {
        case .codex: "codex"; case .claudeCode: "claude"; case .grokBuild: "grok"
        case .antigravity: "agy"; case .opencode: "opencode"; case .pi: "pi"; case .devin: "devin"; case .cursor: "cursor"
        }
    }
}

public enum AgentConnectionStatus: String, Sendable {
    case notRegistered, registered, disabled
    public var label: String {
        switch self {
        case .notRegistered: "등록 안 됨"
        case .registered: "등록됨 · 실행 확인 필요"
        case .disabled: "등록됨 · 비활성"
        }
    }
}

public struct AgentConnectionPlan: Identifiable, Sendable {
    public let id = UUID()
    public let target: AgentConnectionTarget
    public let removing: Bool
    public let configurationURL: URL
    public let executableURL: URL
    public let arguments: [String]
    public let helperURL: URL
    public let helperArguments: [String]
    fileprivate let originalData: Data?
    fileprivate let replacementData: Data?
    public var editsConfiguration: Bool { target.editsConfiguration }
    fileprivate let environment: [String: String]
    public var displayCommand: String {
        if editsConfiguration {
            if removing { return target.configurationKey + "." + AgentConnectionInstaller.serverName + " 제거" }
            let object = [target.configurationKey: [AgentConnectionInstaller.serverName: target.entry(helper: helperURL, arguments: helperArguments)]]
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        return ([executableURL.path] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }
}

public enum AgentConnectionError: LocalizedError {
    case unavailable, conflict, changed, alreadyInstalled, notInstalled, commandFailed, invalidConfiguration, ambiguousConfiguration
    public var errorDescription: String? {
        switch self {
        case .unavailable: "에이전트 CLI 또는 앱의 관리 도구를 찾을 수 없습니다. CLI 설치 또는 앱 설치 상태를 확인하세요."
        case .conflict: "같은 이름의 다른 MCP 등록이 있습니다. 기존 설정은 변경하지 않았습니다."
        case .changed: "검토한 뒤 설정이 바뀌었습니다. 다시 설치 내용을 확인하세요."
        case .alreadyInstalled: "이 앱의 MCP 연결이 이미 등록되어 있습니다. 에이전트에서 MCP 상태를 확인하세요."
        case .notInstalled: "이 앱의 MCP 연결이 등록되어 있지 않습니다."
        case .commandFailed: "MCP 설정 변경에 실패했습니다. 백업을 보존했습니다. 에이전트에서 등록 상태를 확인하세요."
        case .invalidConfiguration: "에이전트 설정 형식 또는 경로를 확인할 수 없습니다. 기존 설정은 보존했습니다."
        case .ambiguousConfiguration: "사용 가능한 설정 파일이 여러 개입니다. 에이전트에서 사용할 설정 경로를 정리한 뒤 다시 시도하세요. 기존 파일은 변경하지 않았습니다."
        }
    }
}

/// Config-only commands, never inference/login commands. Not exposed to agents as an MCP tool.
public actor AgentConnectionInstaller {
    public static let serverName = "agent-harness-manager"
    private let home: URL
    private let environment: [String: String]
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home; self.environment = environment
    }

    public func prepare(target: AgentConnectionTarget, removing: Bool, helperURL: URL, domain: String,
                        executableURL: URL? = nil) throws -> AgentConnectionPlan {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw AgentConnectionError.unavailable }
        let executable: URL
        if target.editsConfiguration { executable = helperURL }
        else {
            guard let found = executableURL ?? findExecutable(target.executableName) else { throw AgentConnectionError.unavailable }
            executable = found
        }
        let (config, env) = try configuration(target)
        let original = try configurationData(config)
        let helperArguments = ["--domain", domain, "mcp"]
        let existing = try registration(target: target, config: original, executable: executable, environment: env)
        if let existing {
            guard existing.command == helperURL.path, existing.arguments == helperArguments else { throw AgentConnectionError.conflict }
            guard removing else { throw AgentConnectionError.alreadyInstalled }
        } else if removing { throw AgentConnectionError.notInstalled }
        let arguments: [String]
        let replacement: Data?
        if target.editsConfiguration {
            arguments = []
            replacement = try MCPConfiguration(original, comments: target == .opencode)
                .replacing(in: target.configurationKey, named: Self.serverName,
                           with: removing ? nil : target.entry(helper: helperURL, arguments: helperArguments))
        } else if removing {
            replacement = nil
            arguments = ["mcp", "remove"] + (target == .codex ? [] : ["--scope", "user"]) + [Self.serverName]
        } else {
            replacement = nil
            arguments = ["mcp", "add"] + (target == .codex ? [] : ["--scope", "user", "--transport", "stdio"])
                + [Self.serverName, "--", helperURL.path] + helperArguments
        }
        return AgentConnectionPlan(target: target, removing: removing, configurationURL: config, executableURL: executable,
            arguments: arguments, helperURL: helperURL, helperArguments: helperArguments, originalData: original, replacementData: replacement, environment: env)
    }

    public func apply(_ plan: AgentConnectionPlan, backupDirectory: URL) throws -> URL? {
        guard try configuration(plan.target).0 == plan.configurationURL else { throw AgentConnectionError.changed }
        guard try configurationData(plan.configurationURL) == plan.originalData else { throw AgentConnectionError.changed }
        var backup: URL?
        if let data = plan.originalData {
            let folder = backupDirectory.appendingPathComponent(plan.id.uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = folder.appendingPathComponent(plan.configurationURL.lastPathComponent)
            try data.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            backup = url
        }
        guard try configurationData(plan.configurationURL) == plan.originalData else { throw AgentConnectionError.changed }
        if let replacement = plan.replacementData {
            try MCPConfigurationFile.write(replacement, to: plan.configurationURL, replacing: plan.originalData)
        } else {
            let result = try run(plan.executableURL, arguments: plan.arguments, environment: plan.environment)
            guard result.status == 0 else { throw AgentConnectionError.commandFailed }
        }
        let actual = try registration(target: plan.target, config: configurationData(plan.configurationURL),
            executable: plan.executableURL, environment: plan.environment)
        if plan.removing {
            guard actual == nil else { throw AgentConnectionError.commandFailed }
        } else {
            guard actual?.command == plan.helperURL.path, actual?.arguments == plan.helperArguments else { throw AgentConnectionError.commandFailed }
        }
        return backup
    }

    public func status(target: AgentConnectionTarget, helperURL: URL, domain: String, executableURL: URL? = nil) throws -> AgentConnectionStatus {
        let (config, env) = try configuration(target)
        let executable: URL
        if target.editsConfiguration { executable = helperURL }
        else {
            guard let found = executableURL ?? findExecutable(target.executableName) else { throw AgentConnectionError.unavailable }
            executable = found
        }
        guard let value = try registration(target: target, config: configurationData(config), executable: executable, environment: env) else { return .notRegistered }
        guard value.command == helperURL.path, value.arguments == ["--domain", domain, "mcp"] else { throw AgentConnectionError.conflict }
        return value.enabled ? .registered : .disabled
    }

    private func configuration(_ target: AgentConnectionTarget) throws -> (URL, [String: String]) {
        var env = environment
        let config: URL
        switch target {
        case .codex:
            let root = try configuredDirectory("CODEX_HOME", fallback: home.appendingPathComponent(".codex"))
            config = root.appendingPathComponent("config.toml"); env["CODEX_HOME"] = root.path
        case .grokBuild:
            let root = try configuredDirectory("GROK_HOME", fallback: home.appendingPathComponent(".grok"))
            config = root.appendingPathComponent("config.toml"); env["GROK_HOME"] = root.path
        case .claudeCode:
            if environment["CLAUDE_CONFIG_DIR"] != nil {
                let root = try configuredDirectory("CLAUDE_CONFIG_DIR", fallback: home)
                config = root.appendingPathComponent(".claude.json"); env["CLAUDE_CONFIG_DIR"] = root.path
            } else { config = home.appendingPathComponent(".claude.json") }
        case .cursor: config = home.appendingPathComponent(".cursor/mcp.json")
        case .pi:
            config = try configuredDirectory("PI_CODING_AGENT_DIR", fallback: home.appendingPathComponent(".pi/agent")).appendingPathComponent("mcp.json")
        case .antigravity:
            config = try existingConfiguration([".gemini/config/mcp_config.json", ".gemini/antigravity/mcp_config.json"].map { home.appendingPathComponent($0) })
        case .opencode:
            if let path = environment["OPENCODE_CONFIG"] {
                guard path.hasPrefix("/") else { throw AgentConnectionError.invalidConfiguration }
                config = URL(fileURLWithPath: path)
            } else {
                let root = try configuredDirectory("XDG_CONFIG_HOME", fallback: home.appendingPathComponent(".config")).appendingPathComponent("opencode")
                config = try existingConfiguration(["opencode.json", "opencode.jsonc"].map { root.appendingPathComponent($0) })
            }
        case .devin:
            let root = try configuredDirectory("XDG_CONFIG_HOME", fallback: home.appendingPathComponent(".config")).appendingPathComponent("devin")
            let current = root.appendingPathComponent("mcp_config.json"), legacy = root.appendingPathComponent("config.json")
            if try configurationData(current) == nil, let data = try configurationData(legacy),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["mcpServers"] != nil { config = legacy }
            else { config = current }
        }
        return (config, env)
    }

    private func existingConfiguration(_ candidates: [URL]) throws -> URL {
        let existing = try candidates.filter { try configurationData($0) != nil }
        guard existing.count <= 1 else { throw AgentConnectionError.ambiguousConfiguration }
        return existing.first ?? candidates[0]
    }

    private func configuredDirectory(_ key: String, fallback: URL) throws -> URL {
        guard let path = environment[key] else { return fallback }
        guard path.hasPrefix("/") else { throw AgentConnectionError.invalidConfiguration }
        return URL(fileURLWithPath: path)
    }

    private func findExecutable(_ name: String) -> URL? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".grok/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func configurationData(_ url: URL) throws -> Data? { try MCPConfigurationFile.read(url) }

    private struct Registration { let command: String; let arguments: [String]; var enabled = true }
    private func registration(target: AgentConnectionTarget, config: Data?, executable: URL,
                              environment: [String: String]) throws -> Registration? {
        if target.editsConfiguration {
            guard let server = try MCPConfiguration(config, comments: target == .opencode).server(in: target.configurationKey, named: Self.serverName) else { return nil }
            let command: String, arguments: [String]
            let allowed: Set<String>
            if target == .opencode {
                allowed = ["type", "command", "environment", "cwd", "enabled", "disabled"]
                guard server["type"] as? String == "local", let invocation = server["command"] as? [String], let executable = invocation.first,
                      server["environment"] == nil || (server["environment"] as? [String: String])?.isEmpty == true else { throw AgentConnectionError.conflict }
                command = executable; arguments = Array(invocation.dropFirst())
            } else {
                allowed = ["type", "command", "args", "env", "cwd", "enabled", "disabled"]
                guard server["type"] == nil || server["type"] as? String == "stdio",
                      let executable = server["command"] as? String, let args = server["args"] as? [String],
                      server["env"] == nil || (server["env"] as? [String: String])?.isEmpty == true else { throw AgentConnectionError.conflict }
                command = executable; arguments = args
            }
            guard Set(server.keys).isSubset(of: allowed), server["cwd"] == nil || server["cwd"] is NSNull else { throw AgentConnectionError.conflict }
            for key in ["enabled", "disabled"] {
                if let flag = server[key] {
                    guard let number = flag as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AgentConnectionError.invalidConfiguration }
                }
            }
            return Registration(command: command, arguments: arguments, enabled: server["enabled"] as? Bool != false && server["disabled"] as? Bool != true)
        }
        if target == .grokBuild {
            let result = try run(executable, arguments: ["mcp", "list", "--json"], environment: environment)
            guard result.status == 0, let servers = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] else {
                throw AgentConnectionError.invalidConfiguration
            }
            let matches = servers.filter { $0["name"] as? String == Self.serverName }
            guard !matches.isEmpty else { return nil }
            guard matches.count == 1, let server = matches.first, server["scope"] as? String == "user",
                  let command = server["command"] as? String, let args = server["args"] as? [String],
                  server["env"] == nil || (server["env"] as? [String: String])?.isEmpty == true,
                  server["cwd"] == nil || server["cwd"] is NSNull else { throw AgentConnectionError.conflict }
            return Registration(command: command, arguments: args, enabled: server["enabled"] as? Bool != false)
        }
        if target == .claudeCode {
            guard let config else { return nil }
            guard let object = try JSONSerialization.jsonObject(with: config) as? [String: Any],
                  object["mcpServers"] == nil || object["mcpServers"] is [String: Any] else { throw AgentConnectionError.invalidConfiguration }
            guard let value = (object["mcpServers"] as? [String: Any])?[Self.serverName] else { return nil }
            guard let server = value as? [String: Any], server["type"] as? String == "stdio",
                  let command = server["command"] as? String, let args = server["args"] as? [String],
                  server["env"] == nil || (server["env"] as? [String: String])?.isEmpty == true,
                  server["cwd"] == nil || server["cwd"] is NSNull else { throw AgentConnectionError.conflict }
            return Registration(command: command, arguments: args)
        }
        let result = try run(executable, arguments: ["mcp", "get", Self.serverName, "--json"], environment: environment)
        if result.status != 0 {
            guard String(decoding: result.data, as: UTF8.self).contains("No MCP server named '\(Self.serverName)' found") else {
                throw AgentConnectionError.invalidConfiguration
            }
            return nil
        }
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let transport = object["transport"] as? [String: Any], transport["type"] as? String == "stdio",
              let command = transport["command"] as? String, let args = transport["args"] as? [String],
              transport["env"] == nil || transport["env"] is NSNull || (transport["env"] as? [String: String])?.isEmpty == true,
              transport["cwd"] == nil || transport["cwd"] is NSNull else { throw AgentConnectionError.conflict }
        return Registration(command: command, arguments: args, enabled: object["enabled"] as? Bool != false)
    }

    private func run(_ executable: URL, arguments: [String], environment: [String: String]) throws -> (status: Int32, data: Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-config-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("output")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outputURL); defer { try? output.close() }
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = folder; process.environment = environment
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let stop = Date().addingTimeInterval(1)
            while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw AgentConnectionError.commandFailed
        }
        process.waitUntilExit()
        let data = try Data(contentsOf: outputURL)
        guard data.count <= 2_097_152 else { throw AgentConnectionError.commandFailed }
        return (process.terminationStatus, data)
    }
}

private extension AgentConnectionTarget {
    var editsConfiguration: Bool { ![Self.codex, .claudeCode, .grokBuild].contains(self) }
    var configurationKey: String { self == .opencode ? "mcp" : "mcpServers" }
    func entry(helper: URL, arguments: [String]) -> [String: Any] {
        self == .opencode ? ["type": "local", "command": [helper.path] + arguments] : ["command": helper.path, "args": arguments]
    }
}
