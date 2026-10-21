import CryptoKit
import Foundation

public struct GitHubSkillCandidate: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public var id: String { path }
}

public struct GitHubSkillListing: Sendable {
    public let repository: SourceRepository
    public let skills: [GitHubSkillCandidate]
    public let reference: String?
    public let trackingReference: String?
    let treeHash: String?
    let files: [GitHubTreeItem]

    public func folderHash(for skill: GitHubSkillCandidate) -> String? {
        skill.path.isEmpty ? treeHash : files.first { $0.type == "tree" && $0.path == skill.path }?.sha
    }
}

struct GitHubTreeItem: Decodable, Sendable {
    let path: String
    let mode: String
    let type: String
    let sha: String
    let size: Int?
}

public struct GitHubSkillDownload: Sendable {
    public let folder: URL
    let container: URL
    public func discard() { try? FileManager.default.removeItem(at: container) }
}

/// Fetch immutable Git blobs without running Git, repository hooks, or downloaded scripts.
public struct GitHubSkillService: Sendable {
    private let session: URLSession

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    public init(session: URLSession? = nil) { self.session = session ?? Self.sharedSession }

    public func list(repository input: String, reference: String? = nil) async throws -> GitHubSkillListing {
        guard let repository = SourceRepository(input), repository.url.host == "github.com" else {
            throw Self.failure("공개 GitHub 저장소의 루트 주소를 입력하세요. 예: https://github.com/owner/repo")
        }
        struct Commit: Decodable { let sha: String }
        let ref: String
        if reference == nil || reference == "HEAD" {
            struct Repository: Decodable { let default_branch: String }
            ref = try JSONDecoder().decode(Repository.self, from: await fetch(endpoint(repository, path: ""), limit: 2 * 1_024 * 1_024)).default_branch
        } else { ref = reference! }
        guard !ref.isEmpty, ref.count <= 200, !ref.hasPrefix("/"), !ref.contains(".."),
              !ref.contains("?"), !ref.contains("#"), !ref.contains("\\"),
              !ref.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Self.failure("업데이트 기준 브랜치·태그를 확인하세요.") }
        let encoded = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%?#")))!
        let commit = try JSONDecoder().decode(Commit.self, from: await fetch(endpoint(repository, path: "commits/" + encoded), limit: 8 * 1_024 * 1_024))
        guard Self.validSHA(commit.sha) else { throw Self.failure("GitHub 버전 정보를 확인할 수 없습니다.") }
        let url = endpoint(repository, path: "git/trees/" + commit.sha + "?recursive=1")
        let data = try await fetch(url, limit: 8 * 1_024 * 1_024)
        return try Self.parse(data, repository: repository, reference: commit.sha, trackingReference: ref)
    }

    static func parse(_ data: Data, repository: SourceRepository, reference: String? = nil, trackingReference: String? = nil) throws -> GitHubSkillListing {
        struct Tree: Decodable { let tree: [GitHubTreeItem]; let truncated: Bool; let sha: String? }
        let response = try JSONDecoder().decode(Tree.self, from: data)
        guard !response.truncated, response.tree.count <= 100_000 else {
            throw failure("저장소가 너무 커 전체 목록을 확인할 수 없습니다. 스킬만 담은 작은 저장소를 사용하세요.")
        }
        guard Set(response.tree.map(\.path)).count == response.tree.count,
              response.tree.allSatisfy({ safePath($0.path) && validSHA($0.sha) }) else {
            throw failure("저장소의 경로 또는 파일 식별 정보를 확인할 수 없습니다.")
        }
        let skills = response.tree.filter {
            $0.type == "blob" && ["100644", "100755"].contains($0.mode)
                && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md"))
        }.map { item in
            let directory = item.path == "SKILL.md" ? "" : String(item.path.dropLast("/SKILL.md".count))
            let name = directory.isEmpty ? repository.url.lastPathComponent : URL(fileURLWithPath: directory).lastPathComponent
            return GitHubSkillCandidate(path: directory, name: name)
        }.filter { !$0.name.hasPrefix(".") }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !skills.isEmpty else { throw failure("이 저장소에서 설치 가능한 SKILL.md를 찾지 못했습니다.") }
        guard skills.count <= 1_000 else { throw failure("스킬이 1,000개를 넘습니다. 더 작은 저장소를 선택하세요.") }
        return GitHubSkillListing(repository: repository, skills: skills, reference: reference, trackingReference: trackingReference, treeHash: response.sha, files: response.tree)
    }

    public static func contentMatches(folder: URL, skill: GitHubSkillCandidate, listing: GitHubSkillListing) throws -> Bool {
        let prefix = skill.path.isEmpty ? "" : skill.path + "/"
        let remote = listing.files.filter { $0.path.hasPrefix(prefix) && $0.type != "tree" }
        guard remote.allSatisfy({ $0.type == "blob" && ["100644", "100755"].contains($0.mode) }), remote.count <= 10_000 else {
            throw failure("원격 스킬에 지원하지 않는 링크·항목이 있습니다.")
        }
        let expected = Dictionary(uniqueKeysWithValues: remote.map { (String($0.path.dropFirst(prefix.count)), $0.sha) })
        return try contentHashes(folder: folder) == expected
    }

    public static func contentHashes(folder: URL) throws -> [String: String] {
        let before = try LibraryService.fingerprintDirectory(folder)
        guard let rootPath = LibraryCatalog.physicalPath(folder.path) else { throw failure("설치 폴더 경로를 확인할 수 없습니다.") }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            throw failure("설치 파일을 비교할 수 없습니다.")
        }
        var observed: [String: String] = [:], bytes = 0, count = 0
        for case let file as URL in enumerator {
            count += 1
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard count <= 10_000, info.isSymbolicLink != true else { throw failure("설치 파일에 링크 또는 너무 많은 항목이 있습니다.") }
            if info.isDirectory == true { continue }
            guard info.isRegularFile == true, let size = info.fileSize, size <= 64 * 1_024 * 1_024 - bytes else { throw failure("설치 파일의 형식·크기를 확인하세요.") }
            bytes += size
            let data = try Data(contentsOf: file)
            guard data.count == size else { throw failure("비교 중 설치 파일이 바뀌었습니다.") }
            var framed = Data("blob \(data.count)\0".utf8); framed.append(data)
            guard let physical = LibraryCatalog.physicalPath(file.path), physical.hasPrefix(rootPath + "/") else { throw failure("설치 폴더 밖의 파일은 비교할 수 없습니다.") }
            let relative = String(physical.dropFirst(rootPath.count + 1))
            observed[relative] = Insecure.SHA1.hash(data: framed).map { String(format: "%02x", $0) }.joined()
        }
        guard try LibraryService.fingerprintDirectory(folder) == before else { throw failure("비교 중 설치 파일이 바뀌었습니다.") }
        return observed
    }

    public func download(_ skill: GitHubSkillCandidate, from listing: GitHubSkillListing) async throws -> GitHubSkillDownload {
        guard listing.skills.contains(skill) else { throw Self.failure("목록에서 스킬을 다시 선택하세요.") }
        let prefix = skill.path.isEmpty ? "" : skill.path + "/"
        let items = listing.files.filter { $0.path.hasPrefix(prefix) }
        var total = 0
        guard items.count <= 10_000 else { throw Self.failure("스킬 항목이 10,000개를 넘습니다.") }
        for item in items {
            let relative = String(item.path.dropFirst(prefix.count))
            guard Self.safePath(relative), relative.split(separator: "/").count <= 33 else { throw Self.failure("스킬 경로가 너무 깊거나 올바르지 않습니다.") }
            if item.type == "tree", item.mode == "040000" { continue }
            guard item.type == "blob", ["100644", "100755"].contains(item.mode), let size = item.size,
                  size >= 0, size <= 64 * 1_024 * 1_024 - total else {
                throw Self.failure("설치는 64 MiB 이하의 일반 파일·폴더만 지원합니다. 링크·서브모듈·특수 항목은 설치할 수 없습니다.")
            }
            if relative == "SKILL.md", size > 2 * 1_024 * 1_024 { throw Self.failure("SKILL.md가 2 MiB 읽기 한도를 넘습니다.") }
            total += size
        }
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-github-" + UUID().uuidString)
        let folder = container.appendingPathComponent(skill.name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: container) } }
        for item in items where item.type == "blob" {
            try Task.checkCancellation()
            let data = try await fetch(endpoint(listing.repository, path: "git/blobs/" + item.sha), limit: item.size ?? 0, raw: true)
            var framed = Data("blob \(data.count)\0".utf8)
            framed.append(data)
            let sha = Insecure.SHA1.hash(data: framed).map { String(format: "%02x", $0) }.joined()
            guard data.count == item.size, sha == item.sha else { throw Self.failure("다운로드한 파일이 조회 시점의 원본과 다릅니다. 다시 불러오세요.") }
            let file = folder.appendingPathComponent(String(item.path.dropFirst(prefix.count)))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: item.mode == "100755" ? 0o700 : 0o600], ofItemAtPath: file.path)
        }
        try Task.checkCancellation()
        retained = true
        return GitHubSkillDownload(folder: folder, container: container)
    }

    private func endpoint(_ repository: SourceRepository, path: String) -> URL {
        URL(string: "https://api.github.com/repos/" + repository.name + (path.isEmpty ? "" : "/" + path))!
    }

    private func fetch(_ url: URL, limit: Int, raw: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AgentHarnessManager", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https", http.url?.host == "api.github.com" else {
            throw Self.failure("GitHub 응답 주소를 확인할 수 없습니다.")
        }
        if http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0") {
            throw Self.failure("GitHub 조회 한도에 도달했습니다. 잠시 후 다시 시도하거나 저장소를 내려받아 로컬 폴더로 설치하세요.")
        }
        guard http.statusCode == 200 else {
            throw Self.failure(http.statusCode == 404 ? "저장소나 파일을 찾지 못했습니다. 공개 저장소 주소인지 확인하세요." : "GitHub 요청에 실패했습니다 (HTTP \(http.statusCode)). 잠시 후 다시 시도하세요.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else { throw Self.failure("GitHub 응답이 파일 크기 한도를 넘습니다.") }
        return try Data(contentsOf: file)
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" && $0.utf8.count <= 200
            }
    }
    private static func validSHA(_ sha: String) -> Bool { sha.count == 40 && sha.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private static func failure(_ message: String) -> CatalogReadError { .inaccessible(message) }
}
