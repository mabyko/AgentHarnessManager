import CryptoKit
import Darwin
import Foundation

public enum SkillInstallMethod: String, CaseIterable, Sendable {
    case direct, skillsCLI
    public var title: String { self == .direct ? "앱 직접 설치" : "skills CLI" }
}

public struct SkillsCLIInstallPlan: Identifiable, Sendable {
    public let id = UUID()
    public let executable: URL
    public let arguments: [String]
    public let name: String
    public let agent: SkillAgent
    public let checkedPaths: [String]
    public let expectedPaths: [String]
    public let roots: [DiscoveryRoot]
    public let sourceFolder: URL
    public let sourceHash: String
    let executableHash: String
    let receiptHash: String?
    let documentHash: String
    public var command: String {
        ([executable.path] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }
}

public struct SkillsCLIService: Sendable {
    private let home: URL
    private let environment: [String: String]
    private let detector: AgentInstallationDetector

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                detector: AgentInstallationDetector? = nil) {
        self.home = home.resolvingSymlinksInPath()
        self.environment = environment
        self.detector = detector ?? AgentInstallationDetector(home: home, environment: environment)
    }

    public func detect(preferred: URL? = nil) -> URL? {
        if let preferred { return executableHash(preferred) == nil ? nil : preferred }
        if let executable = detector.findExecutable("skills") { return executable }
        guard home == FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath() else { return nil }
        var packages = [FileManager.default.temporaryDirectory.appendingPathComponent("bunx-\(getuid())-skills@latest/node_modules/skills")]
        let npm = home.appendingPathComponent(".npm/_npx")
        let entries = (try? FileManager.default.contentsOfDirectory(at: npm, includingPropertiesForKeys: nil)) ?? []
        packages += entries.sorted { $0.path < $1.path }.prefix(100).map { $0.appendingPathComponent("node_modules/skills") }
        return packages.lazy.compactMap { package -> URL? in
            let metadata = package.appendingPathComponent("package.json")
            guard let size = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_024 * 1_024,
                  let data = try? Data(contentsOf: metadata), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == "skills" else { return nil }
            let executable = package.appendingPathComponent("bin/cli.mjs")
            return executableHash(executable) == nil ? nil : executable
        }.first
    }

    public func prepare(folder: URL, agent: SkillAgent, executable: URL, remoteSource: URL? = nil) throws -> SkillsCLIInstallPlan {
        guard agent != .custom, let binaryHash = executableHash(executable) else { throw failure("skills CLI 실행 파일을 다시 확인하세요.") }
        let version = try run(executable, arguments: ["--version"], timeout: 10)
        let pieces = version.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 3, pieces[0] == 1, pieces[1] > 7 || (pieces[1] == 7 && pieces[2] >= 4) else {
            throw failure("이 연동은 skills CLI 1.7.4 이상의 1.x 버전이 필요합니다. CLI를 업데이트한 뒤 다시 확인하세요.")
        }
        let sourceHash = try LibraryService.fingerprintDirectory(folder)
        let root = DiscoveryRoot(agent: .custom, url: folder, label: "설치 원본")
        let skills = LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: [root]), roots: [root])
        guard skills.count == 1, let skill = skills.first, let item = skill.installations.first,
              item.originalPath == folder.path, item.problems.isEmpty, let documentHash = item.contentHash,
              !skill.name.hasPrefix("-"), !skill.name.contains("*"), skill.name.count <= 200,
              !skill.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw failure("CLI가 선택할 단일 스킬의 name·description과 SKILL.md를 확인하세요.")
        }
        if let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let file as URL in files where try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw failure("설치 원본에 심볼릭 링크가 있습니다. 일반 파일·폴더로 준비하세요.")
            }
        } else { throw failure("설치 원본을 확인할 수 없습니다.") }
        let source: String
        if let remoteSource {
            guard let parts = URLComponents(url: remoteSource, resolvingAgainstBaseURL: false), parts.scheme == "https",
                  parts.host == "github.com", parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
                throw failure("공개 GitHub 설치 주소를 확인하세요.")
            }
            source = remoteSource.absoluteString
        } else { source = folder.path }
        let name = Self.directoryName(skill.name)
        let canonical = DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "skills CLI · 공유 스킬")
        let defaults = ManagementConfiguration.defaultRoots(home: home)
        let agentID: String
        switch agent { case .claudeCode: agentID = "claude-code"; case .grokBuild: agentID = "grok"; default: agentID = agent.rawValue }
        let specific: DiscoveryRoot?
        switch agent {
        case .claudeCode:
            specific = DiscoveryRoot(agent: agent, url: try base("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent("skills"), label: "Claude Code · skills CLI")
        case .grokBuild:
            specific = DiscoveryRoot(agent: agent, url: try base("GROK_HOME", fallback: ".grok").appendingPathComponent("skills"), label: "Grok Build · skills CLI")
        case .devin:
            specific = DiscoveryRoot(agent: agent, url: try base("XDG_CONFIG_HOME", fallback: ".config").appendingPathComponent("devin/skills"), label: "Devin CLI · skills CLI")
        default: specific = nil
        }
        let roots = [canonical] + (specific.map { [$0] } ?? [])
        let checked = Set((roots + defaults.filter { $0.agent == agent }).map { $0.url.appendingPathComponent(name).path }).sorted()
        for path in checked { try validateVacant(path) }
        return SkillsCLIInstallPlan(executable: executable, arguments: ["add", source, "--global", "--agent", agentID, "--skill", skill.name, "--yes"],
            name: skill.name, agent: agent, checkedPaths: checked, expectedPaths: [(specific ?? canonical).url.appendingPathComponent(name).path], roots: roots,
            sourceFolder: folder, sourceHash: sourceHash, executableHash: binaryHash, receiptHash: try receiptHash(), documentHash: documentHash)
    }

    public func apply(_ plan: SkillsCLIInstallPlan) throws -> String {
        guard executableHash(plan.executable) == plan.executableHash,
              try LibraryService.fingerprintDirectory(plan.sourceFolder) == plan.sourceHash,
              try receiptHash() == plan.receiptHash else { throw failure("검토 후 CLI·원본·설치 기록이 바뀌었습니다. 다시 검토하세요.") }
        for path in plan.checkedPaths { try validateVacant(path) }
        let output = try run(plan.executable, arguments: plan.arguments, timeout: 180)
        for path in plan.expectedPaths {
            let root = DiscoveryRoot(agent: plan.agent, url: URL(fileURLWithPath: path), label: "CLI 설치 결과")
            let scan = SkillCatalog.scan(roots: [root], additionalApprovedRoots: plan.roots)
            guard let entry = scan.entries.first,
                  LibraryCatalog.digest(try SkillCatalog.readDocument(entry: entry, approvedRoots: [root] + plan.roots)) == plan.documentHash else {
                throw failure("CLI 실행은 끝났지만 예상한 설치 내용을 확인하지 못했습니다. 일부 변경이 있을 수 있으니 새로고침 후 확인하세요.")
            }
        }
        return output
    }

    static func directoryName(_ name: String) -> String {
        let safe = name.lowercased().replacingOccurrences(of: "[^a-z0-9._]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return safe.isEmpty ? "unnamed-skill" : String(safe.prefix(255))
    }

    private func base(_ key: String, fallback: String) throws -> URL {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return home.appendingPathComponent(fallback) }
        guard value.hasPrefix("/") else { throw failure("\(key)의 절대 경로를 확인하세요.") }
        return URL(fileURLWithPath: value)
    }

    private func executableHash(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        guard let info = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), info.isRegularFile == true,
              (info.fileSize ?? Int.max) <= 64 * 1_024 * 1_024, FileManager.default.isExecutableFile(atPath: resolved.path),
              let data = try? Data(contentsOf: resolved) else { return nil }
        return resolved.path + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validateVacant(_ path: String) throws {
        var normalized = path
        for alias in ["/tmp", "/var", "/etc"] where path == alias || path.hasPrefix(alias + "/") {
            guard let physical = LibraryCatalog.physicalPath(alias) else { throw failure("시스템 경로를 확인할 수 없습니다.") }
            normalized = physical + path.dropFirst(alias.count)
        }
        var current = "", info = stat()
        let components = normalized.split(separator: "/")
        for (index, part) in components.enumerated() {
            current += "/" + part
            if lstat(current, &info) != 0 {
                guard errno == ENOENT else { throw failure("설치 경로 접근 상태를 확인할 수 없습니다.") }
                return
            }
            guard index != components.count - 1 else { throw failure("기존 설치와 충돌합니다: \(path). CLI로 덮어쓰지 않습니다.") }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw failure("설치 경로에 링크 또는 일반 폴더가 아닌 항목이 있습니다: \(current)") }
        }
    }

    private func receiptHash() throws -> String? {
        let file = home.appendingPathComponent(".agents/.skill-lock.json")
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw failure("skills CLI 설치 기록을 확인할 수 없습니다.") }
            return nil
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= 2 * 1_024 * 1_024 else { throw failure("skills CLI 설치 기록은 2 MiB 이하 일반 파일이어야 합니다.") }
        let data = try Data(contentsOf: file)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["version"] as? Int == 3,
              json["skills"] is [String: Any] else { throw failure("skills CLI 설치 기록의 형식을 확인할 수 없습니다. 기존 기록은 보존합니다.") }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-skills-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("output")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: log); defer { try? output.close() }
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        var env = environment
        env["HOME"] = home.path; env["PATH"] = detector.executableSearchPath
        env["DISABLE_TELEMETRY"] = "1"; env["DO_NOT_TRACK"] = "1"; env["CI"] = "1"; env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env; process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var exceeded = false
        while process.isRunning && Date() < deadline {
            if ((try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 2 * 1_024 * 1_024 { exceeded = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            let group = getpgid(process.processIdentifier)
            if group == process.processIdentifier && group != getpgrp() { Darwin.kill(-group, SIGTERM) }
            else { process.terminate() }
            let stop = Date().addingTimeInterval(1)
            while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                if group == process.processIdentifier && group != getpgrp() { Darwin.kill(-group, SIGKILL) }
                else { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            throw failure(exceeded ? "CLI 출력이 한도를 넘었습니다. 일부 변경이 있을 수 있으니 설치 위치를 확인하세요." : "CLI 실행 시간이 초과됐습니다. 일부 변경이 있을 수 있으니 설치 위치를 확인하세요.")
        }
        process.waitUntilExit()
        let data = try Data(contentsOf: log)
        guard data.count <= 2 * 1_024 * 1_024 else { throw failure("CLI 출력이 한도를 넘었습니다.") }
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        guard process.terminationStatus == 0 else { throw failure("skills CLI 실행 실패 (\(process.terminationStatus)). 일부 변경이 있을 수 있습니다.\n" + String(text.suffix(4_000))) }
        return text
    }

    private func failure(_ message: String) -> CatalogReadError { .inaccessible(message) }
}
