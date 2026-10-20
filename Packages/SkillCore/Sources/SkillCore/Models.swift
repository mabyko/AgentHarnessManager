import Foundation

public enum SkillAgent: String, CaseIterable, Sendable, Codable {
    case codex, claudeCode, grokBuild, antigravity, opencode, pi, devin, cursor, custom

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .grokBuild: "Grok Build"
        case .antigravity: "Antigravity"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .devin: "Devin CLI"
        case .cursor: "Cursor"
        case .custom: "다른 에이전트"
        }
    }
}

public struct DiscoveryRoot: Identifiable, Hashable, Sendable, Codable {
    public let agent: SkillAgent
    public let url: URL
    public let label: String
    public var id: String { "\(agent.rawValue):\(url.standardizedFileURL.path)" }

    public init(agent: SkillAgent, url: URL, label: String) {
        self.agent = agent
        self.url = url.standardizedFileURL
        self.label = label
    }
}

public enum RootStatus: String, Sendable {
    case available, missing, blocked, partial
}

public struct RootObservation: Identifiable, Sendable {
    public let root: DiscoveryRoot
    public let status: RootStatus
    public let message: String?
    public var id: String { root.id }

    public init(root: DiscoveryRoot, status: RootStatus, message: String? = nil) {
        self.root = root
        self.status = status
        self.message = message
    }
}

public struct SkillEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let rootID: String
    public let agent: SkillAgent
    public let name: String
    public let url: URL
    public let isSymbolicLink: Bool
    public let resolvedURL: URL?
    public let problem: String?

    public init(id: String, rootID: String, agent: SkillAgent, name: String, url: URL,
                isSymbolicLink: Bool, resolvedURL: URL?, problem: String? = nil) {
        self.id = id
        self.rootID = rootID
        self.agent = agent
        self.name = name
        self.url = url
        self.isSymbolicLink = isSymbolicLink
        self.resolvedURL = resolvedURL
        self.problem = problem
    }
}

public struct CatalogSnapshot: Sendable {
    public let entries: [SkillEntry]
    public let roots: [RootObservation]

    public init(entries: [SkillEntry], roots: [RootObservation]) {
        self.entries = entries
        self.roots = roots
    }
}
