import Foundation

/// The app and command-line frontends read the same metadata and journal.
public struct ManagementConfiguration: Sendable {
    public static let releaseDomain = "forked.agentskillmanager.local"
    public static let preferencesKey = "libraryPreferences.v1"
    public static let rootsKey = "additionalSkillRoots"
    public let home: URL
    public let domain: String
    public let preferences: AppPreferences
    public let roots: [DiscoveryRoot]
    public var managedRoots: [DiscoveryRoot] { Self.defaultRoots(home: home) }
    public var stateDirectory: URL { home.appendingPathComponent("Library/Application Support/\(domain)") }

    public static func defaultRoots(home: URL) -> [DiscoveryRoot] {
        [DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "Codex · 사용자 스킬"),
         DiscoveryRoot(agent: .claudeCode, url: home.appendingPathComponent(".claude/skills"), label: "Claude Code · 사용자 스킬"),
         DiscoveryRoot(agent: .grokBuild, url: home.appendingPathComponent(".grok/skills"), label: "Grok Build · 사용자 스킬"),
         DiscoveryRoot(agent: .antigravity, url: home.appendingPathComponent(".gemini/config/skills"), label: "Antigravity · 앱 / IDE"),
         DiscoveryRoot(agent: .antigravity, url: home.appendingPathComponent(".gemini/antigravity-cli/skills"), label: "Antigravity · CLI"),
         DiscoveryRoot(agent: .antigravity, url: home.appendingPathComponent(".gemini/antigravity/skills"), label: "Antigravity · 이전 IDE 경로"),
         DiscoveryRoot(agent: .opencode, url: home.appendingPathComponent(".config/opencode/skills"), label: "OpenCode · 사용자 스킬"),
         DiscoveryRoot(agent: .pi, url: home.appendingPathComponent(".pi/agent/skills"), label: "Pi · 사용자 스킬"),
         DiscoveryRoot(agent: .devin, url: home.appendingPathComponent(".config/devin/skills"), label: "Devin CLI · 사용자 스킬"),
         DiscoveryRoot(agent: .cursor, url: home.appendingPathComponent(".cursor/skills"), label: "Cursor · 사용자 스킬")]
    }

    /// Compatibility readers share one installation; the stored root ID and journal remain unchanged.
    public static func readers(of root: DiscoveryRoot, defaultRoots: [DiscoveryRoot]) -> [SkillAgent] {
        guard defaultRoots.contains(where: { $0.id == root.id }) else { return [root.agent] }
        switch root.agent {
        case .codex: return [.codex, .grokBuild, .opencode, .pi, .devin, .cursor]
        case .claudeCode: return [.claudeCode, .grokBuild, .opencode]
        default: return [root.agent]
        }
    }

    public static func decodePreferences(_ data: Data?) throws -> AppPreferences {
        guard let data else { return AppPreferences() }
        let value = try JSONDecoder().decode(AppPreferences.self, from: data)
        guard value.version == 1, Set(value.groups.map(\.id)).count == value.groups.count,
              value.groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              value.activeGroupIDs.isSubset(of: Set(value.groups.map(\.id))) else { throw ManagementError.invalidSettings }
        return value
    }

    public static func decodeRoots(_ data: Data?, home: URL) throws -> [DiscoveryRoot] {
        var roots = defaultRoots(home: home)
        if let data {
            for root in try JSONDecoder().decode([DiscoveryRoot].self, from: data) {
                guard root.url.isFileURL, root.url.path.hasPrefix("/") else { throw ManagementError.invalidSettings }
                if !roots.contains(where: { $0.id == root.id }) { roots.append(root) }
            }
        }
        return roots
    }

    public init(home: URL, domain: String, preferencesData: Data?, rootsData: Data?) throws {
        guard domain.range(of: "^[a-zA-Z0-9][a-zA-Z0-9.-]{0,199}$", options: .regularExpression) != nil else {
            throw ManagementError.invalidSettings
        }
        self.home = home.resolvingSymlinksInPath(); self.domain = domain
        preferences = try Self.decodePreferences(preferencesData)
        roots = try Self.decodeRoots(rootsData, home: self.home)
    }
}

public enum ManagementError: LocalizedError {
    case invalidSettings, invalidRequest, staleRequest, pendingRecovery, unknownInstallation, queueFull
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "앱 설정을 안전하게 읽을 수 없습니다. 앱에서 설정을 확인하세요."
        case .invalidRequest: "에이전트 요청 형식 또는 저장 위치를 확인할 수 없습니다."
        case .staleRequest: "요청 후 파일·설정이 바뀌었거나 요청이 만료되었습니다. 새 요청을 만들어 주세요."
        case .pendingRecovery: "중단된 파일 변경을 앱에서 먼저 복구하세요."
        case .unknownInstallation: "현재 목록에 없는 설치 항목입니다. 목록을 다시 조회하세요."
        case .queueFull: "에이전트 요청이 100건입니다. 앱에서 기존 요청을 정리하세요."
        }
    }
}

public struct ManagementSnapshot: Sendable {
    public let configuration: ManagementConfiguration
    public let journal: LibraryJournal
    public let skills: [CanonicalSkill]
    public let observations: [RootObservation]
    public init(configuration: ManagementConfiguration, journal: LibraryJournal, skills: [CanonicalSkill], observations: [RootObservation]) {
        self.configuration = configuration; self.journal = journal; self.skills = skills; self.observations = observations
    }
    public var installations: [SkillInstallation] { skills.flatMap(\.installations) }
    public var review: ReviewRecord {
        ReviewRecord(skills: skills, roots: observations.filter { observation in
            observation.status != .missing || !configuration.managedRoots.contains { $0.id == observation.id }
        })
    }
    public var fingerprint: String {
        let preferences = configuration.preferences
        let groups = preferences.groups.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.name)|\($0.skillIDs.sorted().joined(separator: ","))"
        }.joined(separator: "\n")
        return LibraryCatalog.digest(review.snapshotID + "\n" + configuration.roots.map(\.id).sorted().joined(separator: "\n")
            + "\n" + groups + "\n" + preferences.activeGroupIDs.map(\.uuidString).sorted().joined(separator: ",")
            + "\n" + preferences.groupSelectionMode.rawValue + "\n" + journal.completed.map { $0.id.uuidString }.joined(separator: ","))
    }

    public func plan(installationIDs: [String], enabled: Bool, title: String, id: UUID = UUID()) throws -> MutationPlan {
        guard journal.pending == nil else { throw ManagementError.pendingRecovery }
        let ids = Set(installationIDs)
        guard !ids.isEmpty, ids.count <= 100, ids.count == installationIDs.count,
              !title.isEmpty, title.count <= 160 else { throw ManagementError.invalidRequest }
        let items = installations.filter { ids.contains($0.id) }
        guard items.count == ids.count else { throw ManagementError.unknownInstallation }
        let plan = try LibraryService.plan(title: title, installations: items, enabled: enabled,
            allInstallations: installations, managedRoots: configuration.managedRoots, protectedRoots: configuration.roots)
        return MutationPlan(id: id, title: title, installations: plan.installations)
    }
}

public enum ManagementService {
    public static func snapshot(configuration: ManagementConfiguration) async throws -> ManagementSnapshot {
        let journal = try await LibraryService(stateDirectory: configuration.stateDirectory.appendingPathComponent("Library"))
            .load(roots: configuration.managedRoots)
        let catalog = SkillCatalog.scan(roots: configuration.roots)
        return ManagementSnapshot(configuration: configuration, journal: journal,
            skills: LibraryCatalog.build(snapshot: catalog, roots: configuration.roots, disabled: journal.disabled),
            observations: catalog.roots)
    }
}
