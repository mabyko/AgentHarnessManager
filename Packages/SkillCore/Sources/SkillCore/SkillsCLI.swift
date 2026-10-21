import CryptoKit
import Darwin
import Foundation

public enum SkillManagementMethod: String, CaseIterable, Sendable {
    case direct, skillsCLI
    public var title: String { self == .direct ? "앱 직접 관리" : "skills CLI" }
}

public enum SkillsCLIOperation: Sendable {
    case install, remove, update
    public var title: String { switch self { case .install: "설치"; case .remove: "삭제"; case .update: "업데이트" } }
}

public struct SkillsCLIPlan: Identifiable, Sendable {
    public let id = UUID()
    public let executable: URL
    public let arguments: [String]
    public let name: String
    public let agent: SkillAgent
    public let checkedPaths: [String]
    public let expectedPaths: [String]
    public let roots: [DiscoveryRoot]
    public let sourceFolder: URL?
    public let sourceHash: String?
    let executableHash: String
    let receiptHash: String?
    let documentHash: String?
    public internal(set) var operation: SkillsCLIOperation = .install
    public internal(set) var scopeNote: String = ""
    public internal(set) var reviewedCommit: String?
    public internal(set) var trackedReference: String?
    public internal(set) var updateRepository: SourceRepository?
    public internal(set) var legacyLinkCleanup: [String] = []
    var pathStates: [String: String] = [:]
    var expectedContents: [String: String] = [:]
    public var command: String {
        ([executable.path] + SkillsCLIService.launcherArguments(for: executable) + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }
}

public struct SkillsCLIService: Sendable {
    let home: URL
    let environment: [String: String]
    let detector: AgentInstallationDetector

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                detector: AgentInstallationDetector? = nil) {
        self.home = home.resolvingSymlinksInPath()
        self.environment = environment
        self.detector = detector ?? AgentInstallationDetector(home: home, environment: environment)
    }

    public func detect(preferred: URL? = nil) -> URL? {
        if let preferred { return isExecutable(preferred) ? preferred : nil }
        return ["bunx", "npx", "skills"].lazy.compactMap { detector.findExecutable($0) }.first(where: isExecutable)
    }

    static func launcherArguments(for executable: URL) -> [String] {
        switch executable.lastPathComponent { case "bunx": ["skills"]; case "npx": ["--yes", "skills"]; default: [] }
    }

    public func prepare(folder: URL, agent: SkillAgent, executable: URL, remoteSource: URL? = nil) throws -> SkillsCLIPlan {
        try prepare(folder: folder, agents: [agent], executable: executable, remoteSource: remoteSource)
    }

    public func prepare(folder: URL, agents selected: [SkillAgent], executable: URL, remoteSource: URL? = nil) throws -> SkillsCLIPlan {
        let agents = Array(Set(selected)).sorted { $0.rawValue < $1.rawValue }
        guard let agent = agents.first, !agents.contains(.custom), let binaryHash = executableHash(executable) else { throw failure("skills CLI 실행 파일을 다시 확인하세요.") }
        try validateVersion(executable)
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
        let targets = try agents.map(installRoot)
        let roots = [canonicalRoot()] + targets
        let defaults = ManagementConfiguration.defaultRoots(home: home)
        let checked = Set((roots + defaults.filter { agents.contains($0.agent) }).map { $0.url.appendingPathComponent(name).path }).sorted()
        for path in checked { try validateVacant(path) }
        var plan = SkillsCLIPlan(executable: executable, arguments: ["add", source, "--global", "--agent"] + agents.map(agentID) + ["--skill", skill.name, "--yes"],
            name: skill.name, agent: agent, checkedPaths: checked,
            expectedPaths: Set(targets.map { $0.url.appendingPathComponent(name).path }).sorted(), roots: roots,
            sourceFolder: folder, sourceHash: sourceHash, executableHash: binaryHash, receiptHash: try receiptHash(), documentHash: documentHash)
        plan.scopeNote = "사용자 전역 설치 · " + agents.map(\.displayName).joined(separator: ", ") + "\n복사·공유 링크 구성은 skills CLI의 기본 규칙을 따릅니다."
        return plan
    }

    public func apply(_ plan: SkillsCLIPlan) throws -> String {
        guard executableHash(plan.executable) == plan.executableHash,
              try receiptHash() == plan.receiptHash else { throw failure("검토 후 CLI·원본·설치 기록이 바뀌었습니다. 다시 검토하세요.") }
        if let folder = plan.sourceFolder {
            guard try LibraryService.fingerprintDirectory(folder) == plan.sourceHash else { throw failure("검토 후 원본이 바뀌었습니다. 다시 검토하세요.") }
        }
        if plan.operation == .install { for path in plan.checkedPaths { try validateVacant(path) } }
        else {
            for (path, expected) in plan.pathStates where try pathState(path) != expected {
                throw failure("검토 후 설치 경로가 바뀌었습니다. 다시 검토하세요: " + path)
            }
        }
        let output = try run(plan.executable, arguments: plan.arguments, timeout: 180)
        if plan.operation == .remove {
            for path in plan.legacyLinkCleanup where try pathState(path) != "missing" {
                guard let expected = plan.pathStates[path], try pathState(path) == expected else {
                    throw failure("CLI 삭제 후 이전 설치 링크가 바뀌어 그대로 두었습니다: " + path)
                }
                guard unlink(path) == 0 else { throw failure("CLI 삭제 후 이전 설치 링크 정리에 실패했습니다: " + path) }
            }
            for path in plan.expectedPaths where try pathState(path) != "missing" {
                throw failure("CLI 실행 후에도 삭제 대상이 남아 있습니다. 일부 변경이 있을 수 있으니 새로고침 후 확인하세요.")
            }
            return output
        }
        for path in plan.expectedPaths {
            let root = DiscoveryRoot(agent: plan.agent, url: URL(fileURLWithPath: path), label: "CLI 설치 결과")
            let scan = SkillCatalog.scan(roots: [root], additionalApprovedRoots: plan.roots)
            guard let entry = scan.entries.first,
                  LibraryCatalog.digest(try SkillCatalog.readDocument(entry: entry, approvedRoots: [root] + plan.roots)) == plan.documentHash else {
                throw failure("CLI 실행은 끝났지만 예상한 설치 내용을 확인하지 못했습니다. 일부 변경이 있을 수 있으니 새로고침 후 확인하세요.")
            }
            if !plan.expectedContents.isEmpty {
                let installed = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                guard try GitHubSkillService.contentHashes(folder: installed) == plan.expectedContents else {
                    throw failure("CLI 실행 후 포함 파일이 검토한 업데이트와 다릅니다. 일부 변경이 있을 수 있으니 설치 위치를 확인하세요.")
                }
            }
        }
        return output
    }

    static func directoryName(_ name: String) -> String {
        let safe = name.lowercased().replacingOccurrences(of: "[^a-z0-9._]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return safe.isEmpty ? "unnamed-skill" : String(safe.prefix(255))
    }

    func base(_ key: String, fallback: String) throws -> URL {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return home.appendingPathComponent(fallback) }
        guard value.hasPrefix("/") else { throw failure("\(key)의 절대 경로를 확인하세요.") }
        return URL(fileURLWithPath: value)
    }

    private func isExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])).map {
            $0.isRegularFile == true && ($0.fileSize ?? Int.max) <= 256 * 1_024 * 1_024 && FileManager.default.isExecutableFile(atPath: resolved.path)
        } ?? false
    }

    func executableHash(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        guard isExecutable(url), let data = try? Data(contentsOf: resolved, options: .mappedIfSafe) else { return nil }
        return resolved.path + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func validateVacant(_ path: String) throws {
        try validateParents(path)
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT else { throw failure("설치 경로 접근 상태를 확인할 수 없습니다.") }
            return
        }
        throw failure("기존 설치와 충돌합니다: \(path). CLI로 덮어쓰지 않습니다.")
    }

    var receiptURL: URL {
        get throws {
            if let value = environment["XDG_STATE_HOME"], !value.isEmpty {
                guard value.hasPrefix("/") else { throw failure("XDG_STATE_HOME의 절대 경로를 확인하세요.") }
                return URL(fileURLWithPath: value).appendingPathComponent("skills/.skill-lock.json")
            }
            return home.appendingPathComponent(".agents/.skill-lock.json")
        }
    }

    func receiptHash() throws -> String? {
        let file = try receiptURL
        try validateParents(file.path)
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

    func validateVersion(_ executable: URL) throws {
        let version = try run(executable, arguments: ["--version"], timeout: 60)
        let line = version.split(whereSeparator: \.isNewline).last { $0.range(of: "^v?[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil } ?? ""
        let pieces = line.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 3, pieces[0] == 1, pieces[1] > 7 || (pieces[1] == 7 && pieces[2] >= 4) else {
            throw failure("이 연동은 skills CLI 1.7.4 이상의 1.x 버전이 필요합니다. CLI를 업데이트한 뒤 다시 확인하세요.")
        }
    }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-skills-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("output")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: log); defer { try? output.close() }
        let process = Process(); process.executableURL = executable; process.arguments = Self.launcherArguments(for: executable) + arguments
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

    func failure(_ message: String) -> CatalogReadError { .inaccessible(message) }
}
