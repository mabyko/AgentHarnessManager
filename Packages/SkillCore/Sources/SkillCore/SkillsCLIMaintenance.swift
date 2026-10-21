import Darwin
import Foundation

public struct SkillUpdateSource: Sendable {
    public let name: String
    public let repository: SourceRepository
    public let skillPath: String
    public let reference: String?
    public let pinnedCommit: Bool
    public let installedFolderHash: String?
    let receiptHash: String
}

extension SkillsCLIService {
    func canonicalRoot() -> DiscoveryRoot {
        DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "skills CLI · 공유 스킬")
    }

    func agentID(_ agent: SkillAgent) -> String {
        switch agent { case .claudeCode: "claude-code"; case .grokBuild: "grok"; default: agent.rawValue }
    }

    func installRoot(_ agent: SkillAgent) throws -> DiscoveryRoot {
        let url: URL
        switch agent {
        case .claudeCode: url = try base("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent("skills")
        case .grokBuild: url = try base("GROK_HOME", fallback: ".grok").appendingPathComponent("skills")
        case .devin: url = try base("XDG_CONFIG_HOME", fallback: ".config").appendingPathComponent("devin/skills")
        case .custom: throw failure("사용자 지정 경로는 skills CLI로 관리할 수 없습니다.")
        default: return canonicalRoot()
        }
        return DiscoveryRoot(agent: agent, url: url, label: agent.displayName + " · skills CLI")
    }

    // remove also cleans native legacy paths, even for agents that now use .agents/skills.
    func removalRoots(_ agent: SkillAgent) throws -> [DiscoveryRoot] {
        var roots = [try installRoot(agent), canonicalRoot()]
        let native: URL?
        switch agent {
        case .antigravity: native = home.appendingPathComponent(".gemini/antigravity/skills")
        case .opencode: native = try base("XDG_CONFIG_HOME", fallback: ".config").appendingPathComponent("opencode/skills")
        case .cursor: native = home.appendingPathComponent(".cursor/skills")
        default: native = nil
        }
        if let native { roots.append(DiscoveryRoot(agent: agent, url: native, label: agent.displayName + " · 이전 경로")) }
        return roots
    }

    func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.contains("*"), !name.contains("/"), !name.contains("\\"), name.count <= 200,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw failure("단일 스킬의 이름을 확인하세요. 옵션·전체 선택·저장소 단위 삭제는 허용하지 않습니다.")
        }
    }

    func validateParents(_ path: String) throws {
        var normalized = path
        for alias in ["/tmp", "/var", "/etc"] where path.hasPrefix(alias + "/") {
            guard let physical = LibraryCatalog.physicalPath(alias) else { throw failure("시스템 경로를 확인할 수 없습니다.") }
            normalized = physical + path.dropFirst(alias.count)
        }
        var current = "", info = stat()
        for part in normalized.split(separator: "/").dropLast() {
            current += "/" + part
            if lstat(current, &info) != 0 {
                guard errno == ENOENT else { throw failure("설치 경로에 접근할 수 없습니다.") }
                return
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw failure("설치 경로의 부모에 링크 또는 일반 폴더가 아닌 항목이 있습니다: " + current) }
        }
    }

    func pathState(_ path: String) throws -> String {
        try validateParents(path)
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT else { throw failure("설치 경로를 확인할 수 없습니다.") }
            return "missing"
        }
        let identity = "\(info.st_dev):\(info.st_ino):\(info.st_mode):"
        if info.st_mode & S_IFMT == S_IFDIR { return identity + (try LibraryService.fingerprintDirectory(URL(fileURLWithPath: path))) }
        if info.st_mode & S_IFMT == S_IFLNK {
            return identity + (try FileManager.default.destinationOfSymbolicLink(atPath: path))
        }
        throw failure("설치 대상은 일반 폴더 또는 설치 링크여야 합니다: " + path)
    }

    func receiptEntries() throws -> [String: [String: Any]] {
        guard try receiptHash() != nil else { return [:] }
        let data = try Data(contentsOf: receiptURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = json["skills"] as? [String: [String: Any]] else { throw failure("설치 기록의 스킬 항목을 확인할 수 없습니다.") }
        return skills
    }

    func matchingName(_ folderName: String, entries: [String: [String: Any]]) throws -> String {
        let matches = entries.keys.filter { Self.directoryName($0) == folderName }
        guard matches.count <= 1 else { throw failure("같은 설치 이름을 사용하는 기록이 여러 개입니다. CLI 설치 기록을 확인하세요.") }
        let name = matches.first ?? folderName
        try validateName(name)
        guard Self.directoryName(name) == folderName else { throw failure("CLI 설치 이름과 경로가 다릅니다.") }
        return name
    }

    func validateInstallation(_ item: SkillInstallation, removal: Bool) throws -> SkillAgent {
        guard item.isEnabled, item.problems.isEmpty else { throw failure("꺼져 있거나 읽을 수 없는 설치는 먼저 복원·확인한 뒤 CLI로 관리하세요.") }
        let name = URL(fileURLWithPath: item.originalPath).lastPathComponent
        let agent = item.location.agent
        let roots = removal ? try removalRoots(agent) : [try installRoot(agent)]
        guard roots.contains(where: { $0.url.appendingPathComponent(name).path == item.originalPath }) else {
            throw failure("이 위치는 skills CLI의 사용자 전역 관리 경로가 아닙니다. 설정에서 관리 도구를 확인하세요.")
        }
        _ = try pathState(item.originalPath)
        if item.isSymbolicLink {
            guard let target = item.resolvedPath,
                  LibraryCatalog.physicalPath(target) == LibraryCatalog.physicalPath(canonicalRoot().url.appendingPathComponent(name).path) else {
                throw failure("CLI의 공유 원본을 가리키는 단일 설치 링크만 관리할 수 있습니다.")
            }
        }
        return agent
    }

    public func prepareRemoval(installations: [SkillInstallation], allInstallations: [SkillInstallation], executable: URL, allAgents: Bool = false) throws -> SkillsCLIPlan {
        guard !installations.isEmpty, let binaryHash = executableHash(executable) else { throw failure("삭제할 설치와 skills CLI를 확인하세요.") }
        try validateVersion(executable)
        let names = Set(installations.map { URL(fileURLWithPath: $0.originalPath).lastPathComponent })
        guard names.count == 1, let folderName = names.first else { throw failure("서로 다른 설치 이름은 하나씩 삭제하세요.") }
        let name = try matchingName(folderName, entries: receiptEntries())
        let agents = try Set(installations.map { try validateInstallation($0, removal: true) }).sorted { $0.rawValue < $1.rawValue }
        let scopedAgents = allAgents ? SkillAgent.allCases.filter { $0 != .custom } : agents
        let roots = try scopedAgents.flatMap(removalRoots)
        let paths = Set(roots.map { $0.url.appendingPathComponent(folderName).path }).sorted()
        let canonical = canonicalRoot().url.appendingPathComponent(folderName).path
        let selected = Set(installations.map(\.originalPath))
        let canonicalPhysical = LibraryCatalog.physicalPath(canonical)
        guard !allInstallations.contains(where: { item in
            canonicalPhysical != nil && item.isSymbolicLink && !selected.contains(item.originalPath)
                && !(allAgents && paths.contains(item.originalPath))
                && item.resolvedPath.flatMap(LibraryCatalog.physicalPath) == canonicalPhysical
        }) else { throw failure("다른 설치 링크도 이 공유 원본을 사용합니다. 스킬 전체의 CLI 삭제에서 함께 검토하세요.") }
        var states: [String: String] = [:]
        for path in paths { states[path] = try pathState(path) }
        let expected = installations.map(\.originalPath).filter { allAgents || $0 != canonical }
        guard !expected.isEmpty else { throw failure("이 공유 설치는 에이전트 하나에서만 삭제할 수 없습니다. 스킬 전체의 CLI 삭제에서 검토하세요.") }
        var plan = SkillsCLIPlan(executable: executable,
            arguments: ["remove", name, "--global"] + (allAgents ? [] : ["--agent"] + agents.map(agentID)) + ["--yes"],
            name: name, agent: agents[0], checkedPaths: paths, expectedPaths: expected, roots: roots,
            sourceFolder: nil, sourceHash: nil, executableHash: binaryHash, receiptHash: try receiptHash(), documentHash: nil)
        plan.operation = .remove; plan.pathStates = states
        plan.scopeNote = "대상 에이전트: " + (allAgents ? "CLI가 인식하는 모든 에이전트(현재 목록 밖의 동명 설치 포함)" : agents.map(\.displayName).joined(separator: ", "))
            + ". CLI가 해당 설치·이전 경로를 영구 삭제하고, 사용 여부에 따라 공유 원본과 설치 기록도 정리합니다. 앱의 보관·자동 되돌리기는 제공하지 않습니다."
        return plan
    }

    public func updateSource(for installations: [SkillInstallation]) throws -> SkillUpdateSource {
        guard let first = installations.first else { throw failure("설치 위치가 없습니다.") }
        for item in installations { _ = try validateInstallation(item, removal: false) }
        let folder = URL(fileURLWithPath: first.originalPath).lastPathComponent
        guard installations.allSatisfy({ URL(fileURLWithPath: $0.originalPath).lastPathComponent == folder }) else { throw failure("설치 이름이 서로 다릅니다.") }
        let entries = try receiptEntries(), name = try matchingName(folder, entries: entries)
        guard let record = entries[name], record["sourceType"] as? String == "github",
              let source = record["source"] as? String,
              let repository = SourceRepository("https://github.com/" + source), repository.url.host == "github.com",
              let path = record["skillPath"] as? String,
              path == "SKILL.md" || path.hasSuffix("/SKILL.md"),
              !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let hash = try receiptHash() else { throw failure("공개 GitHub의 skills CLI 설치 기록과 스킬 경로가 필요합니다. 로컬·미확인 출처는 자동 업데이트할 수 없습니다.") }
        let ref = record["ref"] as? String
        let pinned = ref?.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil
        return SkillUpdateSource(name: name, repository: repository, skillPath: path, reference: pinned ? nil : ref, pinnedCommit: pinned,
                                 installedFolderHash: record["skillFolderHash"] as? String, receiptHash: hash)
    }

    public func prepareUpdate(folder: URL, installations: [SkillInstallation], source: SkillUpdateSource,
                              remoteSource: URL, executable: URL, trackingReference: String? = nil) throws -> SkillsCLIPlan {
        guard let binaryHash = executableHash(executable), !installations.isEmpty,
              try receiptHash() == source.receiptHash else { throw failure("CLI 또는 설치 기록이 바뀌었습니다. 업데이트를 다시 확인하세요.") }
        try validateVersion(executable)
        let current = try updateSource(for: installations)
        guard current.name == source.name, current.repository == source.repository, current.skillPath == source.skillPath else { throw failure("업데이트 출처가 바뀌었습니다.") }
        let hash = try LibraryService.fingerprintDirectory(folder)
        let input = DiscoveryRoot(agent: .custom, url: folder, label: "업데이트 원본")
        let catalog = LibraryCatalog.build(snapshot: SkillCatalog.scan(roots: [input]), roots: [input])
        guard catalog.count == 1, let skill = catalog.first, skill.name == source.name, !skill.hasProblems,
              let documentHash = skill.installations.first?.contentHash else { throw failure("업데이트의 스킬 이름·문서를 확인하세요.") }
        let agents = try Set(installations.map { try validateInstallation($0, removal: false) }).sorted { $0.rawValue < $1.rawValue }
        let roots = [canonicalRoot()] + (try agents.map(installRoot))
        let paths = Set(roots.map { $0.url.appendingPathComponent(Self.directoryName(source.name)).path }).sorted()
        var states: [String: String] = [:]
        for path in paths { states[path] = try pathState(path) }
        guard remoteSource.scheme == "https", remoteSource.host == "github.com", remoteSource.user == nil, remoteSource.password == nil,
              remoteSource.query == nil, remoteSource.fragment == nil else { throw failure("업데이트 주소를 확인하세요.") }
        let parts = remoteSource.pathComponents
        guard parts.count >= 5, parts[3] == "tree", parts[4].range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else {
            throw failure("검토한 업데이트 커밋을 확인하세요.")
        }
        guard let reference = source.reference == nil || source.reference == "HEAD" ? trackingReference : source.reference else {
            throw failure("저장소의 실제 기본 브랜치를 다시 확인하세요.")
        }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%?#"))
        guard let encoded = reference.addingPercentEncoding(withAllowedCharacters: allowed), !reference.isEmpty else { throw failure("업데이트 기준을 확인하세요.") }
        var components = URLComponents(url: remoteSource, resolvingAgainstBaseURL: false)!
        let encodedParts = components.percentEncodedPath.split(separator: "/").map(String.init)
        components.percentEncodedPath = "/" + (Array(encodedParts.prefix(3)) + [encoded] + Array(encodedParts.dropFirst(4))).joined(separator: "/")
        guard let trackedURL = components.url else { throw failure("업데이트 주소를 확인하세요.") }
        var plan = SkillsCLIPlan(executable: executable,
            arguments: ["add", trackedURL.absoluteString, "--global", "--agent"] + agents.map(agentID) + ["--skill", source.name, "--yes"],
            name: source.name, agent: agents[0], checkedPaths: paths, expectedPaths: installations.map(\.originalPath), roots: roots,
            sourceFolder: folder, sourceHash: hash, executableHash: binaryHash, receiptHash: source.receiptHash, documentHash: documentHash)
        plan.operation = .update; plan.pathStates = states
        plan.reviewedCommit = parts[4]; plan.trackedReference = reference; plan.updateRepository = source.repository
        plan.expectedContents = try GitHubSkillService.contentHashes(folder: folder)
        plan.scopeNote = "CLI add로 선택한 에이전트에 검토한 버전을 다시 설치합니다. skills update는 에이전트 범위를 지정할 수 없어 사용하지 않습니다. 기존 파일과 로컬 수정은 덮어쓰며 앱 자동 되돌리기를 제공하지 않습니다."
            + " 공유 원본이 바뀌면 그 원본을 읽는 다른 에이전트에도 적용됩니다."
            + " 기준(\(reference))을 유지하고 실행 직전 검토한 커밋인지 다시 확인합니다. 실행 중 원격이 바뀌면 완료 검증에 실패할 수 있습니다."
            + (source.pinnedCommit ? " 고정된 커밋에서 최신 기본 브랜치 버전으로 이동합니다." : "")
        return plan
    }
}
