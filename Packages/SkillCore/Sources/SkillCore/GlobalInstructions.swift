import CryptoKit
import Darwin
import Foundation

public struct InstructionDocument: Identifiable, Sendable {
    public let agent: SkillAgent
    public let url: URL
    public let role: String
    public let resolvedURL: URL
    public let data: Data?
    public let issue: String?
    public let revision: String
    let permissions: mode_t
    public var id: String { agent.rawValue + ":" + url.path }
    public var isLink: Bool { url != resolvedURL }
    public var text: String { Self.decode(data) ?? "" }
    public var status: String { issue == nil ? (data == nil ? "파일 없음" : "파일 찾음") : "읽기 제한" }
    public var digest: String { GlobalInstructionService.digest(data) }
    public var isWritable: Bool { issue == nil && permissions & 0o222 != 0 }

    static func decode(_ data: Data?) -> String? {
        guard var data else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        return String(data: data, encoding: .utf8)
    }
}

public struct InstructionBackup: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let documentURL: URL
    public let targetURL: URL
    public let savedDigest: String
    let version: Int
    let previousData: Data?
    let previousPermissions: mode_t
    public var wasCreation: Bool { previousData == nil }
}

public struct InstructionChangePlan: Identifiable, Sendable {
    public let id = UUID()
    public let document: InstructionDocument
    public let replacementData: Data?
    public let affectedAgents: [SkillAgent]
    public let restoring: Bool
    public var before: String { document.text }
    public var after: String { InstructionDocument.decode(replacementData) ?? "" }
    let permissions: mode_t
    let catalogRevision: [String: String]
}

public enum InstructionError: Error, LocalizedError {
    case unsupported, invalidPath, invalidFile, changed, noChanges, backupUnavailable, busy
    public var errorDescription: String? {
        switch self {
        case .unsupported: "이 에이전트의 전역 지침 파일 관리는 아직 지원하지 않습니다."
        case .invalidPath: "지침 경로를 확인할 수 없습니다. 디렉터리 링크나 사용자 영역 밖의 공유 원본은 편집하지 않습니다."
        case .invalidFile: "2 MiB 이하의 UTF-8 일반 파일만 지원합니다. 하드 링크·특수 파일·읽기 전용 파일은 수정하지 않습니다."
        case .changed: "확인 후 지침 파일이나 우선순위 파일이 바뀌었습니다. 초안을 보존했습니다. 새로고침 후 다시 비교하세요."
        case .noChanges: "저장할 변경이 없습니다."
        case .backupUnavailable: "백업을 확인할 수 없거나 저장 이후 원본이 바뀌어 복원할 수 없습니다."
        case .busy: "다른 지침 저장 작업이 진행 중입니다. 잠시 후 다시 시도하세요."
        }
    }
}

public struct GlobalInstructionService: Sendable {
    public static let supportedAgents: [SkillAgent] = [.codex, .claudeCode, .grokBuild, .antigravity, .opencode, .pi]
    public static let limit = 2 * 1_024 * 1_024
    private let home: URL
    private let environment: [String: String]
    private let backupDirectory: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment, backupDirectory: URL) {
        self.home = home.resolvingSymlinksInPath()
        self.environment = environment
        self.backupDirectory = backupDirectory.standardizedFileURL
    }

    public func scan() throws -> [InstructionDocument] {
        try definitions().map { agent, url, role in
            do { return try inspect(agent: agent, url: url, role: role) }
            catch {
                return InstructionDocument(agent: agent, url: url, role: role, resolvedURL: url, data: nil,
                    issue: error.localizedDescription, revision: "unreadable", permissions: 0)
            }
        }
    }

    public func prepare(_ document: InstructionDocument, text: String) throws -> InstructionChangePlan {
        var data = Data(text.utf8)
        if let original = document.data, let raw = String(data: original, encoding: .utf8),
           raw.contains("\r\n"), !raw.replacingOccurrences(of: "\r\n", with: "").contains("\n") {
            data = Data(text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n").utf8)
        }
        if document.data?.starts(with: [0xEF, 0xBB, 0xBF]) == true { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
        guard data.count <= Self.limit else { throw InstructionError.invalidFile }
        guard document.data != data else { throw InstructionError.noChanges }
        return try plan(document, replacement: data, permissions: document.permissions, restoring: false)
    }

    public func backups(for document: InstructionDocument) throws -> [InstructionBackup] {
        guard let fd = try MCPConfigurationFile.directory(backupDirectory, create: false) else { return [] }
        defer { close(fd) }
        let names = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
        guard names.count <= 1_000 else { throw InstructionError.backupUnavailable }
        return try names.compactMap { name -> InstructionBackup? in
            guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))) else { return nil }
            let record = try backup(id)
            return record.targetURL == document.resolvedURL ? record : nil
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func prepareRestore(_ document: InstructionDocument, backupID: UUID) throws -> InstructionChangePlan {
        let record = try backup(backupID)
        guard record.targetURL == document.resolvedURL, record.savedDigest == document.digest,
              record.previousData != document.data else { throw InstructionError.backupUnavailable }
        return try plan(document, replacement: record.previousData, permissions: record.previousPermissions, restoring: true)
    }

    @discardableResult
    public func apply(_ plan: InstructionChangePlan) throws -> InstructionBackup {
        guard let fd = try MCPConfigurationFile.directory(backupDirectory, create: true) else { throw InstructionError.invalidPath }
        defer { close(fd) }
        let lock = openat(fd, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw InstructionError.invalidPath }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw InstructionError.busy }
        defer { flock(lock, LOCK_UN) }
        let current = try scan()
        guard revisions(current) == plan.catalogRevision,
              let document = current.first(where: { $0.id == plan.document.id }), document.issue == nil else { throw InstructionError.changed }
        let record = InstructionBackup(id: UUID(), createdAt: Date(), documentURL: document.url,
            targetURL: document.resolvedURL, savedDigest: Self.digest(plan.replacementData), version: 1,
            previousData: document.data, previousPermissions: document.permissions)
        try MCPConfigurationFile.write(try JSONEncoder().encode(record),
            to: backupDirectory.appendingPathComponent(record.id.uuidString + ".json"), replacing: nil)
        guard revisions(try scan()) == plan.catalogRevision else { throw InstructionError.changed }
        if let data = plan.replacementData {
            try MCPConfigurationFile.write(data, to: document.resolvedURL, replacing: document.data, permissions: plan.permissions)
        } else {
            guard let parent = try MCPConfigurationFile.directory(document.resolvedURL.deletingLastPathComponent(), create: false) else { throw InstructionError.changed }
            defer { close(parent) }
            guard try MCPConfigurationFile.read(document.resolvedURL, limit: Self.limit) == document.data else { throw InstructionError.changed }
            guard unlinkat(parent, document.resolvedURL.lastPathComponent, 0) == 0, fsync(parent) == 0 else { throw InstructionError.invalidFile }
        }
        return record
    }

    private func plan(_ original: InstructionDocument, replacement: Data?, permissions: mode_t, restoring: Bool) throws -> InstructionChangePlan {
        let current = try scan()
        guard let document = current.first(where: { $0.id == original.id }), document.issue == nil,
              document.revision == original.revision else { throw InstructionError.changed }
        guard document.permissions & 0o222 != 0 else { throw InstructionError.invalidFile }
        let readers = Self.supportedAgents.filter { agent in
            current.contains { $0.agent == agent && $0.resolvedURL == document.resolvedURL }
        }
        return InstructionChangePlan(document: document, replacementData: replacement, affectedAgents: readers,
            restoring: restoring, permissions: permissions, catalogRevision: revisions(current))
    }

    private func definitions() throws -> [(SkillAgent, URL, String)] {
        let codex = try directory("CODEX_HOME", fallback: home.appendingPathComponent(".codex"))
        let claude = try directory("CLAUDE_CONFIG_DIR", fallback: home.appendingPathComponent(".claude"))
        let pi = try directory("PI_CODING_AGENT_DIR", fallback: home.appendingPathComponent(".pi/agent"))
        let config = try directory("XDG_CONFIG_HOME", fallback: home.appendingPathComponent(".config"))
        return [(.codex, codex.appendingPathComponent("AGENTS.override.md"), "우선 지침"),
                (.codex, codex.appendingPathComponent("AGENTS.md"), "기본 지침"),
                (.claudeCode, claude.appendingPathComponent("CLAUDE.md"), "사용자 지침"),
                (.grokBuild, home.appendingPathComponent(".grok/AGENTS.md"), "기본 지침"),
                (.grokBuild, home.appendingPathComponent(".grok/CLAUDE.md"), "호환 지침"),
                (.grokBuild, home.appendingPathComponent(".grok/CLAUDE.local.md"), "개인 호환 지침"),
                (.grokBuild, home.appendingPathComponent(".grok/AGENT.md"), "호환 지침"),
                (.antigravity, home.appendingPathComponent(".gemini/GEMINI.md"), "전역 지침"),
                (.antigravity, home.appendingPathComponent(".gemini/AGENTS.md"), "전역 지침"),
                (.opencode, config.appendingPathComponent("opencode/AGENTS.md"), "기본 지침"),
                (.opencode, home.appendingPathComponent(".claude/CLAUDE.md"), "Claude 호환 지침"),
                (.pi, pi.appendingPathComponent("AGENTS.override.md"), "우선 지침"),
                (.pi, pi.appendingPathComponent("AGENTS.md"), "기본 지침"),
                (.pi, pi.appendingPathComponent("CLAUDE.md"), "호환 지침")]
    }

    private func directory(_ key: String, fallback: URL) throws -> URL {
        guard let value = environment[key], !value.isEmpty else { return fallback }
        let path = value.hasPrefix("~/") ? home.path + String(value.dropFirst()) : value
        guard path.hasPrefix("/"), !path.contains("\0") else { throw InstructionError.invalidPath }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func inspect(agent: SkillAgent, url: URL, role: String) throws -> InstructionDocument {
        let missing = InstructionDocument(agent: agent, url: url, role: role, resolvedURL: url, data: nil,
            issue: nil, revision: "missing", permissions: 0o600)
        guard let parent = try MCPConfigurationFile.directory(url.deletingLastPathComponent(), create: false) else { return missing }
        defer { close(parent) }
        var entry = stat()
        if fstatat(parent, url.lastPathComponent, &entry, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return missing }
            throw InstructionError.invalidFile
        }
        var resolved = url
        if entry.st_mode & S_IFMT == S_IFLNK {
            var bytes = [UInt8](repeating: 0, count: 4_097)
            let count = readlinkat(parent, url.lastPathComponent, &bytes, 4_096)
            guard count > 0, count < 4_096, let link = String(bytes: bytes.prefix(count), encoding: .utf8) else { throw InstructionError.invalidPath }
            resolved = URL(fileURLWithPath: link, relativeTo: url.deletingLastPathComponent()).standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(home.path + "/"), resolved.pathExtension.lowercased() == "md" else { throw InstructionError.invalidPath }
        }
        guard let data = try MCPConfigurationFile.read(resolved, limit: Self.limit), InstructionDocument.decode(data) != nil else { throw InstructionError.invalidFile }
        var target = stat()
        guard lstat(resolved.path, &target) == 0, target.st_mode & S_IFMT == S_IFREG, target.st_nlink == 1 else { throw InstructionError.invalidFile }
        let revision = resolved.path + ":" + identity(entry) + ":" + identity(target) + ":" + Self.digest(data)
        return InstructionDocument(agent: agent, url: url, role: role, resolvedURL: resolved, data: data,
            issue: nil, revision: revision, permissions: target.st_mode & 0o777)
    }

    private func backup(_ id: UUID) throws -> InstructionBackup {
        guard let data = try MCPConfigurationFile.read(backupDirectory.appendingPathComponent(id.uuidString + ".json")),
              let record = try? JSONDecoder().decode(InstructionBackup.self, from: data), record.id == id, record.version == 1,
              record.previousData.map({ $0.count <= Self.limit && InstructionDocument.decode($0) != nil }) ?? true else { throw InstructionError.backupUnavailable }
        return record
    }

    private func revisions(_ documents: [InstructionDocument]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.revision) })
    }
    private func identity(_ value: stat) -> String {
        "\(value.st_dev):\(value.st_ino):\(value.st_mode):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
    static func digest(_ data: Data?) -> String {
        data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing"
    }
}
