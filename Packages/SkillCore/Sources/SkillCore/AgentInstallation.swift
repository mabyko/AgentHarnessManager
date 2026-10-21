import Foundation

public struct AgentInstallation: Equatable, Sendable {
    public let executableURL: URL?
    public let applicationURL: URL?

    public var isInstalled: Bool { executableURL != nil || applicationURL != nil }
    public var label: String {
        if executableURL != nil { return "CLI 설치 감지됨" }
        if applicationURL != nil { return "앱 설치 감지됨" }
        return "미설치 · 감지되지 않음"
    }

    public func canInstallConnection(for target: AgentConnectionTarget) -> Bool {
        isInstalled && (!target.requiresCLIForConnection || executableURL != nil)
    }
}

/// Checks local files only. A found executable is not a login, version, or live-tool check.
public struct AgentInstallationDetector: Sendable {
    private let executableDirectories: [URL]
    private let applicationDirectories: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [".local/bin", ".grok/bin", ".opencode/bin", ".bun/bin", ".npm-global/bin", ".local/share/mise/shims", ".volta/bin"]
                .map { home.appendingPathComponent($0).path }
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        self.init(executableDirectories: paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) },
                  applicationDirectories: [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")])
    }

    public init(executableDirectories: [URL], applicationDirectories: [URL]) {
        self.executableDirectories = executableDirectories.filter { $0.path.hasPrefix("/") }
        self.applicationDirectories = applicationDirectories
    }

    public func scan() -> [AgentConnectionTarget: AgentInstallation] {
        Dictionary(uniqueKeysWithValues: AgentConnectionTarget.allCases.map { target in
            let names = target == .antigravity ? ["agy", "antigravity"]
                : target == .cursor ? ["cursor", "cursor-agent"] : [target.executableName]
            let executable = names.lazy.compactMap { findExecutable($0) }.first
            let application = applicationNames(for: target).lazy.flatMap { name in
                applicationDirectories.map { $0.appendingPathComponent(name + ".app") }
            }.first { url in
                guard let bundle = Bundle(url: url),
                      bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                      let executable = bundle.executableURL else { return false }
                return isExecutableFile(executable)
            }
            return (target, AgentInstallation(executableURL: executable, applicationURL: application))
        })
    }

    func findExecutable(_ name: String) -> URL? {
        executableDirectories.lazy.map { $0.appendingPathComponent(name) }.first { isExecutableFile($0) }
    }

    var executableSearchPath: String { executableDirectories.map(\.path).joined(separator: ":") }

    private func isExecutableFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            && FileManager.default.isExecutableFile(atPath: resolved.path)
    }

    private func applicationNames(for target: AgentConnectionTarget) -> [String] {
        switch target {
        case .codex: ["Codex"]
        case .antigravity: ["Antigravity"]
        case .opencode: ["OpenCode"]
        case .cursor: ["Cursor"]
        default: []
        }
    }
}
