import Foundation

/// A local association with a repository, not a verification of its contents.
public struct SourceRepository: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: String { url.absoluteString }
    public var name: String {
        let path = url.path.dropFirst()
        return url.host == "github.com" ? String(path) : "\(url.host ?? "")/\(path)"
    }

    public init?(_ input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_048,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if text.hasPrefix("git@"), let colon = text.firstIndex(of: ":") {
            text = "https://" + text.dropFirst(4).prefix(upTo: colon) + "/" + text.suffix(from: text.index(after: colon))
        } else if !text.contains("://") { text = "https://github.com/" + text }
        guard var parts = URLComponents(string: text), parts.scheme == "https",
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasPrefix("/"), components.count >= 2,
              (host != "github.com" || components.count == 2),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                  $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-._~".unicodeScalars.contains($0) } }) else { return nil }
        parts.host = host
        parts.path = host == "github.com" ? path.lowercased() : path
        guard let url = parts.url else { return nil }
        self.url = url
    }
}

public struct InstallerSources: Sendable {
    public var repositories: [String: SourceRepository] = [:]
    public var message: String?
}
