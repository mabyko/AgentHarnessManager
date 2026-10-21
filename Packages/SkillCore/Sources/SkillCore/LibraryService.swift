import CryptoKit
import Darwin
import Foundation

public struct DirectoryIdentity: Codable, Hashable, Sendable {
    public let device: Int32
    public let inode: UInt64
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    func matches(_ info: stat) -> Bool { device == info.st_dev && inode == info.st_ino }
}

public struct StoredLink: Codable, Equatable, Sendable {
    public let text: String
    public let targetPath: String
    public let targetIdentity: DirectoryIdentity
}

public struct DisabledInstallation: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let originalPath: String
    public let currentPath: String
    public let location: DiscoveryRoot
    public let physicalParent: String
    public let parentIdentity: DirectoryIdentity
    public let physicalStorageParent: String
    public let storageParentIdentity: DirectoryIdentity
    public let identity: DirectoryIdentity
    public var link: StoredLink? = nil
    public var isRemoved: Bool? = nil
    public var readRoot: DiscoveryRoot { DiscoveryRoot(agent: location.agent, url: URL(fileURLWithPath: currentPath), label: location.label) }
    public var matchesCurrentItem: Bool {
        var info = stat()
        return lstat(currentPath, &info) == 0 && info.st_mode & S_IFMT == (link == nil ? S_IFDIR : S_IFLNK) && identity.matches(info)
    }
}

public enum InstallationOperation: String, Codable, Sendable {
    case install, remove, hide, unhide
    var reversed: Self {
        switch self { case .install: .remove; case .remove: .install; case .hide: .unhide; case .unhide: .hide }
    }
}

public struct Move: Codable, Identifiable, Equatable, Sendable {
    public let installation: DisabledInstallation
    public let enabled: Bool
    public let contentHash: String
    public var treeHash: String? = nil
    public var operation: InstallationOperation? = nil
    public var sourceRepository: String? = nil
    public var changesLocation: Bool { operation != .hide && operation != .unhide }
    public var removesFromLibrary: Bool { operation == .remove || operation == .hide }
    public var id: String { installation.id }
    public var source: String { enabled ? installation.currentPath : installation.originalPath }
    public var destination: String { enabled ? installation.originalPath : installation.currentPath }
}

public struct GroupSelectionChange: Codable, Equatable, Sendable {
    public let before: Set<UUID>
    public let after: Set<UUID>
    public let previousChangeID: UUID?
    public init(before: Set<UUID>, after: Set<UUID>, previousChangeID: UUID?) {
        self.before = before; self.after = after; self.previousChangeID = previousChangeID
    }
}

public struct GroupSelectionCommit: Codable, Sendable {
    public let id: UUID
    public let change: GroupSelectionChange
}

public struct MutationPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let installations: [Move]
    public let createdAt: Date?
    public var completedAt: Date?
    public let undoes: UUID?
    public let groupSelection: GroupSelectionChange?
    public init(id: UUID = UUID(), title: String, installations: [Move], undoes: UUID? = nil, groupSelection: GroupSelectionChange? = nil) {
        self.id = id; self.title = title; self.installations = installations; createdAt = .now
        self.undoes = undoes; self.groupSelection = groupSelection
    }
}

public struct LibraryJournal: Codable, Sendable {
    public var version = 1
    public var disabled: [DisabledInstallation] = []
    public var pending: MutationPlan?
    public var completed: [MutationPlan] = []
    public var groupSelection: GroupSelectionCommit?
    public init() {}

    /// History checks are cheap; filesystem checks still run before preview and again before applying.
    public func undoUnavailableReason(for id: UUID) -> String? {
        guard pending == nil else { return "중단된 변경을 먼저 복구해 주세요." }
        guard let index = completed.firstIndex(where: { $0.id == id }) else { return "완료 기록을 찾을 수 없습니다." }
        let original = completed[index]
        guard original.undoes == nil else { return "되돌리기 실행 기록은 다시 되돌릴 수 없습니다." }
        guard !completed.contains(where: { $0.undoes == id }) else { return "이미 되돌린 작업입니다." }
        guard original.installations.allSatisfy({ $0.treeHash != nil }) else { return "이전 형식의 기록에는 포함 파일 지문이 없어 되돌릴 수 없습니다." }
        let paths = Set(original.installations.map { $0.installation.originalPath })
        if completed.prefix(index).contains(where: { later in
            later.installations.contains { paths.contains($0.installation.originalPath) }
        }) { return "같은 설치 위치에 이후 변경이 있습니다. 이전 작업을 되돌릴 수 없습니다." }
        if original.groupSelection != nil, groupSelection?.id != original.id {
            return "이후 그룹 선택이 변경되어 이전 그룹 작업을 되돌릴 수 없습니다."
        }
        return nil
    }
}

/// Move independent directories or single-hop installation links out of the default discovery roots.
/// Shared source directories, nested/custom installations and provider-owned caches stay read-only.
public actor LibraryService {
    private let stateDirectory: URL
    public init(stateDirectory: URL) { self.stateDirectory = stateDirectory }

    public static func readOnlyReason(for item: SkillInstallation, allInstallations: [SkillInstallation], managedRoots: [DiscoveryRoot]) -> String? {
        guard managedRoots.contains(where: { $0.id == item.location.id }),
              URL(fileURLWithPath: item.originalPath).deletingLastPathComponent().path == item.location.url.path else {
            return "기본 경로 바로 아래의 설치만 전환할 수 있습니다. 추가·중첩 경로는 읽기 전용입니다."
        }
        let physicalRoot = LibraryCatalog.physicalPath(item.location.url.path) ?? item.location.url.path
        if (item.originalPath + "/" + physicalRoot).split(separator: "/").contains(where: { ["plugins", "cache", "marketplaces", ".system"].contains(String($0)) }) {
            return "제공자가 관리하는 캐시와 시스템 설치는 읽기 전용입니다."
        }
        if let error = item.readError { return "설치 원본을 확인할 수 없습니다: " + error }
        if !item.isSymbolicLink {
            let path = LibraryCatalog.physicalPath(item.originalPath) ?? item.originalPath
            if allInstallations.contains(where: { other in
                guard other.id != item.id, let target = other.resolvedPath else { return false }
                return target == path || target.hasPrefix(path + "/")
            }) { return "공유 원본은 유지합니다. 사용할 에이전트의 설치 링크를 전환하세요." }
        }
        return nil
    }

    private static func physicalEntryPath(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        return LibraryCatalog.physicalPath(url.deletingLastPathComponent().path).map { $0 + "/" + url.lastPathComponent }
    }

    private static func linkText(_ parent: Int32, _ name: String) throws -> String {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = buffer.withUnsafeMutableBytes { readlinkat(parent, name, $0.baseAddress, $0.count) }
        guard count > 0, count < buffer.count, let value = String(bytes: buffer.prefix(count), encoding: .utf8) else {
            throw failure("링크 대상 문자를 안전하게 읽을 수 없습니다.")
        }
        return value
    }

    private static func linkTargetPath(_ text: String, originalPath: String) -> String {
        text.hasPrefix("/") ? text : URL(fileURLWithPath: originalPath).deletingLastPathComponent().path + "/" + text
    }

    private static func openDirectLinkTarget(_ path: String) throws -> Int32 {
        do { return try openDirectory(path) }
        catch { throw failure("원본을 직접 가리키는 링크만 전환할 수 있습니다. 원본 경로의 다른 링크와 폴더 접근 권한을 확인해 주세요.") }
    }

    /// Follow only link metadata to detect incoming dependencies, including relative paths and ancestor links.
    private static func traversesLink(_ path: String, linkPath: String) throws -> Bool {
        var remaining = path.split(separator: "/").map(String.init), resolved: [String] = [], hops = 0
        while !remaining.isEmpty {
            let component = remaining.removeFirst()
            if component == "." { continue }
            if component == ".." { if !resolved.isEmpty { resolved.removeLast() }; continue }
            let current = "/" + (resolved + [component]).joined(separator: "/")
            if current == linkPath { return true }
            var info = stat()
            if lstat(current, &info) != 0 {
                guard errno == ENOENT || errno == ENOTDIR else { throw failure("링크 의존 경로를 확인할 수 없습니다.") }
                return false
            }
            if info.st_mode & S_IFMT == S_IFLNK {
                hops += 1
                guard hops <= 40 else { throw failure("순환 또는 다단계 링크의 영향을 확인할 수 없습니다.") }
                let text = try linkText(AT_FDCWD, current)
                if text.hasPrefix("/") { resolved = [] }
                remaining = text.split(separator: "/").map(String.init) + remaining
            } else { resolved.append(component) }
        }
        return false
    }

    private static func openLinkTarget(_ link: StoredLink, originalPath: String, roots: [DiscoveryRoot]) throws -> Int32 {
        let path = linkTargetPath(link.text, originalPath: originalPath)
        guard LibraryCatalog.physicalPath(path) == link.targetPath,
              roots.contains(where: { root in
                  guard let rootPath = LibraryCatalog.physicalPath(root.url.path) else { return false }
                  return link.targetPath == rootPath || link.targetPath.hasPrefix(rootPath + "/")
              }) else { throw failure("링크 원본이 없어졌거나 등록한 경로 밖으로 바뀌었습니다.") }
        // Reject target and ancestor symlinks; the supported installation link has exactly one hop.
        let fd = try openDirectLinkTarget(path)
        var info = stat()
        guard fstat(fd, &info) == 0, link.targetIdentity.matches(info), info.st_mode & S_IFMT == S_IFDIR else {
            close(fd); throw failure("링크 원본 폴더가 교체되었습니다. 기존 기록을 다른 원본에 연결하지 않습니다.")
        }
        return fd
    }

    public static func readStoredLinkDocument(_ saved: DisabledInstallation, roots: [DiscoveryRoot]) throws -> String {
        guard let link = saved.link, validPaths(saved, roots: roots), saved.matchesCurrentItem else {
            throw failure("보관한 설치 링크의 식별 정보를 확인할 수 없습니다.")
        }
        let storage = try openDirectory(saved.physicalStorageParent)
        defer { close(storage) }
        var info = stat(), item = stat()
        let name = URL(fileURLWithPath: saved.currentPath).lastPathComponent
        guard fstat(storage, &info) == 0, saved.storageParentIdentity.matches(info),
              fstatat(storage, name, &item, AT_SYMLINK_NOFOLLOW) == 0, saved.identity.matches(item),
              try linkText(storage, name) == link.text else { throw failure("보관한 링크가 교체되거나 바뀌었습니다.") }
        let target = try openLinkTarget(link, originalPath: saved.originalPath, roots: roots)
        defer { close(target) }
        let file = openat(target, "SKILL.md", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw failure("공유 원본의 SKILL.md를 읽을 수 없습니다.") }
        defer { close(file) }
        guard let text = String(data: try readRegular(file), encoding: .utf8) else { throw failure("공유 원본 문서가 UTF-8이 아닙니다.") }
        return text
    }

    private static func planLink(_ item: SkillInstallation, enabled: Bool, allInstallations: [SkillInstallation],
                                 managedRoots: [DiscoveryRoot], protectedRoots: [DiscoveryRoot]) throws -> Move {
        if let reason = readOnlyReason(for: item, allInstallations: allInstallations, managedRoots: managedRoots) { throw failure(reason) }
        let roots = managedRoots + protectedRoots
        guard let hash = item.contentHash, let physical = LibraryCatalog.physicalPath(item.location.url.path) else { throw failure("링크 원본과 설치 경로를 읽을 수 없습니다.") }
        let origin = physical + "/" + URL(fileURLWithPath: item.originalPath).lastPathComponent
        guard !allInstallations.contains(where: { $0.id != item.id && physicalEntryPath($0.originalPath) == origin }) else {
            throw failure("같은 설치 링크를 여러 등록 경로에서 읽습니다. 중복 경로를 먼저 해제해 주세요.")
        }
        let parent = try openDirectory(physical)
        defer { close(parent) }
        let destination = enabled ? item.currentPath : item.location.url.deletingLastPathComponent().appendingPathComponent(".ahm-disabled-" + UUID().uuidString).path
        guard let storagePath = LibraryCatalog.physicalPath(URL(fileURLWithPath: destination).deletingLastPathComponent().path) else { throw failure("링크 보관 경로를 열 수 없습니다.") }
        let storage = try openDirectory(storagePath)
        defer { close(storage) }
        let containing = item.isEnabled ? parent : storage
        let name = URL(fileURLWithPath: item.currentPath).lastPathComponent
        var parentInfo = stat(), storageInfo = stat(), info = stat()
        guard fstat(parent, &parentInfo) == 0, fstat(storage, &storageInfo) == 0, parentInfo.st_dev == storageInfo.st_dev,
              fstatat(containing, name, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_mode & S_IFMT == S_IFLNK else { throw failure("설치 링크나 보관 경로가 바뀌었습니다.") }
        let text = try linkText(containing, name)
        guard let targetPath = LibraryCatalog.physicalPath(linkTargetPath(text, originalPath: item.originalPath)),
              targetPath == item.resolvedPath else { throw failure("깨진 링크이거나 원본이 바뀌었습니다. 새로고침해 주세요.") }
        let target = try openDirectLinkTarget(linkTargetPath(text, originalPath: item.originalPath))
        defer { close(target) }
        var targetInfo = stat()
        guard fstat(target, &targetInfo) == 0 else { throw failure("링크 원본의 식별 정보를 읽을 수 없습니다.") }
        let link = StoredLink(text: text, targetPath: targetPath, targetIdentity: DirectoryIdentity(targetInfo))
        let approved = try openLinkTarget(link, originalPath: item.originalPath, roots: roots)
        defer { close(approved) }
        let document = try item.disabledRecord.map { try readStoredLinkDocument($0, roots: roots) }
            ?? SkillCatalog.readDocument(entry: item.entry, approvedRoots: roots)
        guard LibraryCatalog.digest(document) == hash else { throw failure("공유 원본 문서가 바뀌었습니다. 새로고침해 주세요.") }
        let saved = item.disabledRecord ?? DisabledInstallation(id: item.id, name: item.name, originalPath: item.originalPath,
            currentPath: destination, location: item.location, physicalParent: physical, parentIdentity: DirectoryIdentity(parentInfo),
            physicalStorageParent: storagePath, storageParentIdentity: DirectoryIdentity(storageInfo), identity: DirectoryIdentity(info), link: link)
        let move = Move(installation: saved, enabled: enabled, contentHash: hash, treeHash: try hashTree(approved))
        try validate(move, roots: roots, allowCompleted: false)
        return move
    }

    public static func plan(title: String, installations: [SkillInstallation], enabled: Bool,
                            allInstallations: [SkillInstallation], managedRoots: [DiscoveryRoot], protectedRoots: [DiscoveryRoot] = []) throws -> MutationPlan {
        var moves: [Move] = []
        var paths = Set<String>()
        for item in installations where item.isEnabled != enabled {
            if item.isSymbolicLink {
                let move = try planLink(item, enabled: enabled, allInstallations: allInstallations,
                                        managedRoots: managedRoots, protectedRoots: protectedRoots)
                guard paths.insert(item.originalPath).inserted else { continue }
                moves.append(move)
                continue
            }
            guard item.readError == nil, !item.isSymbolicLink, let hash = item.contentHash,
                  managedRoots.contains(where: { $0.id == item.location.id }),
                  URL(fileURLWithPath: item.originalPath).deletingLastPathComponent().path == item.location.url.path,
                  !item.originalPath.split(separator: "/").contains(where: { ["plugins", "cache", "marketplaces", ".system"].contains(String($0)) }),
                  !allInstallations.contains(where: { other in
                      guard other.id != item.id, let target = other.resolvedPath else { return false }
                      return target == item.originalPath || target.hasPrefix(item.originalPath + "/")
                  }) else {
                throw failure("‘\(item.name)’은 공유 링크·사용자 지정 경로·보호된 위치이거나 읽기 상태를 확인할 수 없어 전환할 수 없습니다.")
            }
            let sourcePath = LibraryCatalog.physicalPath(item.currentPath)
            guard !allInstallations.contains(where: { other in
                other.id != item.id && (LibraryCatalog.physicalPath(other.currentPath) == sourcePath
                    || other.originalPath.hasPrefix(item.originalPath + "/"))
            }), !protectedRoots.contains(where: { root in
                guard let rootPath = LibraryCatalog.physicalPath(root.url.path), let sourcePath else { return false }
                return rootPath == sourcePath || rootPath.hasPrefix(sourcePath + "/")
            }) else { throw failure("다른 설치 항목이나 등록 경로가 이 폴더를 공유하고 있어 읽기 전용으로 유지합니다.") }
            guard paths.insert(item.originalPath).inserted else { continue }
            guard let physical = LibraryCatalog.physicalPath(item.location.url.path) else { throw failure("등록 경로를 열 수 없습니다.") }
            guard !physical.split(separator: "/").contains(where: { ["plugins", "cache", "marketplaces", ".system"].contains(String($0)) }) else {
                throw failure("제공자가 관리하는 캐시와 시스템 경로는 읽기 전용입니다.")
            }
            let fd = try openDirectory(physical)
            defer { close(fd) }
            let destination = enabled ? item.currentPath : item.location.url.deletingLastPathComponent().appendingPathComponent(".ahm-disabled-" + UUID().uuidString).path
            guard let storagePath = LibraryCatalog.physicalPath(URL(fileURLWithPath: destination).deletingLastPathComponent().path) else { throw failure("보관 위치를 열 수 없습니다.") }
            let storageFD = try openDirectory(storagePath)
            defer { close(storageFD) }
            let itemParentFD = item.isEnabled ? fd : storageFD
            var parent = stat(), info = stat(), marker = stat(), storageInfo = stat()
            guard fstat(fd, &parent) == 0, fstat(storageFD, &storageInfo) == 0, parent.st_dev == storageInfo.st_dev,
                  fstatat(itemParentFD, URL(fileURLWithPath: item.currentPath).lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFDIR else { throw failure("설치 폴더가 바뀌었거나 보관 위치가 다른 볼륨에 있습니다.") }
            let directory = openat(itemParentFD, URL(fileURLWithPath: item.currentPath).lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw failure("설치 폴더에 접근할 수 없습니다.") }
            defer { close(directory) }
            guard fstatat(directory, "SKILL.md", &marker, AT_SYMLINK_NOFOLLOW) == 0, marker.st_mode & S_IFMT == S_IFREG else {
                throw failure("SKILL.md가 링크이거나 일반 파일이 아닙니다. 읽기 전용으로 유지합니다.")
            }
            let approved = managedRoots + (item.isEnabled ? [] : [DiscoveryRoot(agent: item.location.agent, url: URL(fileURLWithPath: item.currentPath), label: item.location.label)])
            guard LibraryCatalog.digest(try SkillCatalog.readDocument(entry: item.entry, approvedRoots: approved)) == hash else {
                throw failure("문서가 바뀌었습니다. 새로고침한 뒤 다시 시도해 주세요.")
            }
            let saved = item.disabledRecord ?? DisabledInstallation(id: item.id, name: item.name, originalPath: item.originalPath,
                currentPath: destination, location: item.location, physicalParent: physical,
                parentIdentity: DirectoryIdentity(parent), physicalStorageParent: storagePath,
                storageParentIdentity: DirectoryIdentity(storageInfo), identity: DirectoryIdentity(info))
            let move = Move(installation: saved, enabled: enabled, contentHash: hash, treeHash: try hashTree(directory))
            try validate(move, roots: managedRoots, allowCompleted: false)
            moves.append(move)
        }
        let plan = MutationPlan(title: title, installations: moves)
        let roots = Dictionary((managedRoots + protectedRoots).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).map(\.value)
        try checkReaders(plan, roots: roots, disabled: allInstallations.compactMap(\.disabledRecord))
        return plan
    }

    public static func planRemoval(installations: [SkillInstallation], allInstallations: [SkillInstallation],
                                   managedRoots: [DiscoveryRoot], protectedRoots: [DiscoveryRoot]) throws -> MutationPlan {
        var moves: [Move] = []
        for item in installations {
            if let reason = readOnlyReason(for: item, allInstallations: allInstallations, managedRoots: managedRoots) {
                throw failure(reason)
            }
            if item.isEnabled {
                let plan = try plan(title: "제거", installations: [item], enabled: false,
                                    allInstallations: allInstallations, managedRoots: managedRoots, protectedRoots: protectedRoots)
                moves += plan.installations.map {
                    var move = $0; move.operation = .remove; return move
                }
            } else {
                let plan = try plan(title: "제거", installations: [item], enabled: true,
                                    allInstallations: allInstallations, managedRoots: managedRoots, protectedRoots: protectedRoots)
                moves += plan.installations.map {
                    Move(installation: $0.installation, enabled: false, contentHash: $0.contentHash,
                         treeHash: $0.treeHash, operation: .hide)
                }
            }
        }
        return MutationPlan(title: "스킬 제거 · \(installations.count)개 설치 위치", installations: moves)
    }

    /// Copy a user-selected skill to private staging; the journal performs the final atomic installation.
    public static func planInstallation(source: URL, root: DiscoveryRoot, managedRoots: [DiscoveryRoot]) throws -> MutationPlan {
        guard managedRoots.contains(root), source.isFileURL else { throw failure("기본 설치 위치와 로컬 스킬 폴더를 선택하세요.") }
        guard !root.url.path.split(separator: "/").contains(where: { ["plugins", "cache", "marketplaces", ".system"].contains(String($0)) }) else {
            throw failure("제공자가 관리하는 캐시와 시스템 경로에는 설치할 수 없습니다.")
        }
        let name = source.lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), name.utf8.count <= 200 else {
            throw failure("스킬 폴더 이름을 확인하세요. 숨김 폴더는 설치할 수 없습니다.")
        }
        let input = try openDirectory(source.path)
        defer { close(input) }
        let hash = try hashDocument(input), tree = try hashTree(input)
        let sourcePath = source.resolvingSymlinksInPath().path
        let storagePath = root.url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard storagePath != sourcePath, !storagePath.hasPrefix(sourcePath + "/") else {
            throw failure("원본 폴더 안에는 설치 준비 위치를 만들 수 없습니다. 별도의 스킬 폴더를 선택하세요.")
        }
        let parent = try openDirectory(root.url.path, create: true)
        defer { close(parent) }
        var marker = stat(), parentInfo = stat(), storageInfo = stat(), childInfo = stat()
        guard fstatat(parent, "SKILL.md", &marker, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw failure("설치 위치 자체가 스킬 폴더입니다. 다른 위치를 선택하세요.")
        }
        guard fstatat(parent, name, &marker, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw failure("같은 이름의 설치가 이미 있습니다. 기존 파일은 덮어쓰지 않습니다.")
        }
        let storageURL = root.url.deletingLastPathComponent()
        let storage = try openDirectory(storageURL.path)
        defer { close(storage) }
        let stageName = ".ahm-disabled-" + UUID().uuidString
        guard mkdirat(storage, stageName, 0o700) == 0 else { throw failure("설치 준비 폴더를 만들 수 없습니다.") }
        let stageURL = storageURL.appendingPathComponent(stageName)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: stageURL) } }
        let output = openat(storage, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard output >= 0 else { throw failure("설치 준비 폴더를 열 수 없습니다.") }
        defer { close(output) }
        var entries = 0, bytes = 0
        try copySkill(input, to: output, depth: 0, entries: &entries, bytes: &bytes)
        guard try hashTree(input) == tree, try hashTree(output) == tree,
              fstat(parent, &parentInfo) == 0, fstat(storage, &storageInfo) == 0, fstat(output, &childInfo) == 0,
              let physical = LibraryCatalog.physicalPath(root.url.path),
              let physicalStorage = LibraryCatalog.physicalPath(storageURL.path) else {
            throw failure("복사 중 원본이나 설치 위치가 변경되었습니다. 다시 시도하세요.")
        }
        let original = root.url.appendingPathComponent(name).path
        let saved = DisabledInstallation(id: LibraryCatalog.digest(UUID().uuidString), name: name, originalPath: original,
            currentPath: stageURL.path, location: root, physicalParent: physical, parentIdentity: DirectoryIdentity(parentInfo),
            physicalStorageParent: physicalStorage, storageParentIdentity: DirectoryIdentity(storageInfo), identity: DirectoryIdentity(childInfo))
        let move = Move(installation: saved, enabled: true, contentHash: hash, treeHash: tree, operation: .install)
        try validate(move, roots: managedRoots, allowCompleted: false)
        guard fsync(storage) == 0 else { throw failure("설치 준비 위치를 디스크에 기록하지 못했습니다.") }
        retained = true
        return MutationPlan(title: "스킬 설치 · " + name, installations: [move])
    }

    public static func discardInstallation(_ plan: MutationPlan) {
        guard plan.undoes == nil else { return }
        for move in plan.installations where move.operation == .install && move.enabled
            && validPaths(move.installation, roots: [move.installation.location]) && move.installation.matchesCurrentItem {
            try? FileManager.default.removeItem(atPath: move.installation.currentPath)
        }
    }

    private static func copySkill(_ source: Int32, to destination: Int32, depth: Int, entries: inout Int, bytes: inout Int) throws {
        guard depth <= 32 else { throw failure("스킬 폴더가 32단계를 넘습니다.") }
        var sourceInfo = stat()
        guard fstat(source, &sourceInfo) == 0 else { throw failure("원본 폴더를 읽을 수 없습니다.") }
        let listing = openat(source, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard listing >= 0, let stream = fdopendir(listing) else { throw failure("원본 목록을 읽을 수 없습니다.") }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw failure("원본 목록을 끝까지 읽을 수 없습니다.") }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                raw.firstIndex(of: 0).flatMap { String(bytes: raw.prefix($0), encoding: .utf8) }
            }
            guard let name else { throw failure("파일 이름이 UTF-8이 아닙니다.") }
            if name == "." || name == ".." { continue }
            entries += 1
            guard entries <= 10_000 else { throw failure("스킬 항목이 10,000개를 넘습니다.") }
            var info = stat()
            guard fstatat(source, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("원본 항목이 변경되었습니다.") }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = openat(source, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw failure("원본 폴더를 열 수 없습니다.") }
                defer { close(child) }
                guard mkdirat(destination, name, 0o700) == 0 else { throw failure("하위 폴더를 만들 수 없습니다.") }
                let output = openat(destination, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard output >= 0 else { throw failure("하위 폴더를 열 수 없습니다.") }
                defer { close(output) }
                try copySkill(child, to: output, depth: depth + 1, entries: &entries, bytes: &bytes)
            case S_IFREG:
                guard info.st_size >= 0, info.st_size <= 64 * 1_024 * 1_024 - bytes else { throw failure("스킬이 64 MiB 한도를 넘습니다.") }
                bytes += Int(info.st_size)
                let file = openat(source, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard file >= 0 else { throw failure("원본 파일을 열 수 없습니다.") }
                defer { close(file) }
                var opened = stat()
                guard fstat(file, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG,
                      opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else { throw failure("원본 파일이 교체되었습니다.") }
                let output = openat(destination, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard output >= 0 else { throw failure("설치 파일을 만들 수 없습니다.") }
                defer { close(output) }
                var buffer = [UInt8](repeating: 0, count: 16_384), total = 0
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw failure("원본 파일 읽기에 실패했습니다.") }
                    if count == 0 { break }
                    total += count
                    guard total <= info.st_size else { throw failure("원본 파일이 변경되었습니다.") }
                    try buffer.withUnsafeBytes { raw in
                        var offset = 0
                        while offset < count {
                            let written = Darwin.write(output, raw.baseAddress!.advanced(by: offset), count - offset)
                            if written < 0 && errno == EINTR { continue }
                            guard written > 0 else { throw failure("설치 파일 저장에 실패했습니다.") }
                            offset += written
                        }
                    }
                }
                guard total == info.st_size, fchmod(output, info.st_mode & 0o777) == 0, fsync(output) == 0 else { throw failure("설치 파일을 확인할 수 없습니다.") }
            default: throw failure("로컬 설치는 일반 파일과 폴더만 지원합니다. 심볼릭 링크와 특수 파일은 제외해 주세요.")
            }
        }
        guard fchmod(destination, sourceInfo.st_mode & 0o777) == 0, fsync(destination) == 0 else { throw failure("설치 폴더를 저장할 수 없습니다.") }
    }

    public func load(roots: [DiscoveryRoot]) throws -> LibraryJournal {
        try locked { directory in
            let journal = try readJournal(directory)
            try validateJournal(journal, roots: roots)
            return observedJournal(journal)
        }
    }

    public func apply(_ plan: MutationPlan, roots: [DiscoveryRoot]) throws {
        try locked { directory in
            var journal = try readJournal(directory)
            try validateJournal(journal, roots: roots)
            guard journal.pending == nil else { throw Self.failure("중단된 변경이 있습니다. 먼저 복구를 완료해 주세요.") }
            guard Set(plan.installations.map(\.id)).count == plan.installations.count,
                  Set(plan.installations.map { $0.installation.originalPath }).count == plan.installations.count else {
                throw Self.failure("변경 계획에 중복 설치 위치가 있습니다. 다시 검토해 주세요.")
            }
            guard !journal.completed.contains(where: { $0.id == plan.id }) else { throw Self.failure("이미 적용한 변경 계획입니다.") }
            if let id = plan.undoes {
                let expected = try Self.undoPlan(id: id, journal: journal)
                guard plan.installations == expected.installations, plan.groupSelection == expected.groupSelection else {
                    throw Self.failure("되돌리기 계획이 바뀌었습니다. 다시 검토해 주세요.")
                }
            }
            if let change = plan.groupSelection {
                guard change.previousChangeID == journal.groupSelection?.id,
                      journal.groupSelection == nil || journal.groupSelection?.change.after == change.before else {
                    throw Self.failure("그룹 선택이 다른 실행에서 변경되었습니다. 새로고침한 뒤 다시 검토해 주세요.")
                }
            }
            guard !plan.installations.isEmpty || plan.groupSelection != nil else { return }
            for move in plan.installations {
                if !move.changesLocation {
                    guard journal.disabled.contains(where: { $0.id == move.id && $0.identity == move.installation.identity }),
                          !move.enabled else { throw Self.failure("보관 항목이 변경되었습니다. 다시 검토해 주세요.") }
                }
                try Self.validate(move, roots: roots, allowCompleted: !move.changesLocation)
            }
            try Self.checkReaders(plan, roots: roots, disabled: journal.disabled)
            if plan.installations.contains(where: { $0.operation != nil }) { journal.version = 3 }
            else if journal.version < 2, plan.installations.contains(where: { $0.installation.link != nil }) { journal.version = 2 }
            journal.pending = plan
            try writeJournal(journal, directory: directory)
            try finish(&journal, directory: directory, roots: roots)
        }
    }

    public func planUndo(id: UUID, roots: [DiscoveryRoot]) throws -> MutationPlan {
        try locked { directory in
            let journal = try readJournal(directory)
            try validateJournal(journal, roots: roots)
            let plan = try Self.undoPlan(id: id, journal: journal)
            for move in plan.installations { try Self.validate(move, roots: roots, allowCompleted: !move.changesLocation) }
            try Self.checkReaders(plan, roots: roots, disabled: journal.disabled)
            return plan
        }
    }

    private static func undoPlan(id: UUID, journal: LibraryJournal) throws -> MutationPlan {
        if let reason = journal.undoUnavailableReason(for: id) { throw failure(reason) }
        guard let original = journal.completed.first(where: { $0.id == id }) else { throw failure("완료 기록을 찾을 수 없습니다.") }
        let moves = original.installations.reversed().map {
            Move(installation: $0.installation, enabled: $0.changesLocation ? !$0.enabled : $0.enabled, contentHash: $0.contentHash, treeHash: $0.treeHash, operation: $0.operation?.reversed, sourceRepository: $0.sourceRepository)
        }
        let selection = original.groupSelection.map {
            GroupSelectionChange(before: $0.after, after: $0.before, previousChangeID: journal.groupSelection?.id)
        }
        return MutationPlan(title: original.title + " · 되돌리기", installations: moves, undoes: id, groupSelection: selection)
    }

    public func recover(roots: [DiscoveryRoot]) throws {
        try locked { directory in
            var journal = try readJournal(directory)
            try validateJournal(journal, roots: roots)
            guard journal.pending != nil else { return }
            try finish(&journal, directory: directory, roots: roots)
        }
    }

    private func finish(_ journal: inout LibraryJournal, directory: Int32, roots: [DiscoveryRoot]) throws {
        guard let plan = journal.pending else { return }
        // Revalidate the entire remainder before resuming any operation. Existing files are never overwritten.
        for move in plan.installations { try Self.validate(move, roots: roots, allowCompleted: true) }
        try Self.checkReaders(plan, roots: roots, disabled: journal.disabled)
        for move in plan.installations where move.changesLocation {
            let fd = try Self.openDirectory(move.installation.physicalParent)
            defer { close(fd) }
            let storage = try Self.openDirectory(move.installation.physicalStorageParent)
            defer { close(storage) }
            let sourceFD = move.enabled ? storage : fd
            let destinationFD = move.enabled ? fd : storage
            let source = URL(fileURLWithPath: move.source).lastPathComponent
            let destination = URL(fileURLWithPath: move.destination).lastPathComponent
            var info = stat()
            if fstatat(sourceFD, source, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                try Self.validate(move, roots: roots, allowCompleted: false)
                guard renameatx_np(sourceFD, source, destinationFD, destination, UInt32(RENAME_EXCL)) == 0 else {
                    throw Self.failure("설치 항목을 이동하지 못했습니다. 변경 기록을 보존했습니다. 충돌을 해결한 뒤 복구를 다시 시도해 주세요.")
                }
                guard fsync(fd) == 0, fsync(storage) == 0 else { throw Self.failure("폴더 변경을 디스크에 기록하지 못했습니다. 복구가 필요합니다.") }
            }
            try Self.validate(move, roots: roots, allowCompleted: true)
        }
        for move in plan.installations {
            journal.disabled.removeAll { $0.id == move.id }
            if !move.enabled {
                var saved = move.installation
                saved.isRemoved = move.removesFromLibrary
                journal.disabled.append(saved)
            }
        }
        var completed = plan
        completed.completedAt = .now
        journal.completed.insert(completed, at: 0)
        journal.completed = Array(journal.completed.prefix(100))
        if let change = plan.groupSelection { journal.groupSelection = GroupSelectionCommit(id: plan.id, change: change) }
        journal.pending = nil
        try writeJournal(journal, directory: directory)
    }

    private func observedJournal(_ original: LibraryJournal) -> LibraryJournal {
        var result = original
        for move in original.pending?.installations ?? [] {
            var info = stat()
            let saved = move.installation
            if lstat(saved.currentPath, &info) == 0 && saved.identity.matches(info) {
                result.disabled.removeAll { $0.id == saved.id }
                var observed = saved
                observed.isRemoved = move.removesFromLibrary
                result.disabled.append(observed)
            } else if lstat(saved.originalPath, &info) == 0 && saved.identity.matches(info) {
                result.disabled.removeAll { $0.id == saved.id }
            }
        }
        return result
    }

    private func validateJournal(_ journal: LibraryJournal, roots: [DiscoveryRoot]) throws {
        guard [1, 2, 3].contains(journal.version), Set(journal.disabled.map(\.id)).count == journal.disabled.count,
              Set(journal.completed.map(\.id)).count == journal.completed.count,
              journal.pending.map({ Set($0.installations.map(\.id)).count == $0.installations.count }) ?? true else {
            throw Self.failure("변경 기록 형식을 확인할 수 없습니다. 기존 데이터를 보존하고 파일 변경을 잠갔습니다.")
        }
        for saved in journal.disabled + (journal.pending?.installations.map(\.installation) ?? []) {
            guard Self.validPaths(saved, roots: roots) else { throw Self.failure("변경 기록의 경로를 확인할 수 없습니다. 원래 경로를 등록한 뒤 다시 시도해 주세요.") }
        }
    }

    private static func checkReaders(_ plan: MutationPlan, roots: [DiscoveryRoot], disabled: [DisabledInstallation]) throws {
        guard plan.installations.contains(where: { $0.changesLocation && (!$0.enabled || $0.installation.link != nil) }) else { return }
        let snapshot = SkillCatalog.scan(roots: roots)
        guard snapshot.roots.allSatisfy({ $0.status == .available || $0.status == .missing }) else {
            throw failure("공유 링크에 미치는 영향을 확인할 수 없습니다. 경로 문제를 해결한 뒤 다시 시도해 주세요.")
        }
        for move in plan.installations where move.changesLocation && (!move.enabled || move.installation.link != nil) {
            let source = (move.enabled ? move.installation.physicalStorageParent : move.installation.physicalParent)
                + "/" + URL(fileURLWithPath: move.source).lastPathComponent
            if move.installation.link != nil {
                let readers = snapshot.entries.filter { $0.isSymbolicLink && physicalEntryPath($0.url.path) != source }
                if try readers.contains(where: { try traversesLink($0.url.path, linkPath: source) })
                    || roots.contains(where: { (try? traversesLink($0.url.path, linkPath: source)) != false }) {
                    throw failure("다른 설치 항목이나 등록 경로가 이 링크를 거쳐 원본을 읽습니다. 의존 링크를 먼저 정리해 주세요.")
                }
                continue
            }
            if roots.contains(where: { root in
                guard let path = LibraryCatalog.physicalPath(root.url.path) else { return false }
                return path == source || path.hasPrefix(source + "/")
            }) || snapshot.entries.contains(where: { entry in
                guard entry.url.path != move.installation.originalPath else { return false }
                let target = entry.resolvedURL?.path ?? LibraryCatalog.physicalPath(entry.url.path)
                return target == source || target?.hasPrefix(source + "/") == true
            }) || disabled.contains(where: { saved in
                guard let target = saved.link?.targetPath else { return false }
                return target == source || target.hasPrefix(source + "/")
            }) { throw failure("이 스킬을 가리키는 공유 링크가 있습니다. 원본을 읽기 전용으로 유지합니다.") }
        }
    }

    private static func validPaths(_ saved: DisabledInstallation, roots: [DiscoveryRoot]) -> Bool {
        let original = URL(fileURLWithPath: saved.originalPath)
        let current = URL(fileURLWithPath: saved.currentPath)
        let name = current.lastPathComponent
        return roots.contains(where: { $0.id == saved.location.id })
            && original.standardizedFileURL.path == saved.originalPath && current.standardizedFileURL.path == saved.currentPath
            && original.deletingLastPathComponent().path == saved.location.url.path
            && current.deletingLastPathComponent() == original.deletingLastPathComponent().deletingLastPathComponent()
            && !original.lastPathComponent.hasPrefix(".ahm-disabled-")
            && name.hasPrefix(".ahm-disabled-") && UUID(uuidString: String(name.dropFirst(".ahm-disabled-".count))) != nil
    }

    private static func validate(_ move: Move, roots: [DiscoveryRoot], allowCompleted: Bool) throws {
        let saved = move.installation
        if let operation = move.operation {
            guard move.enabled == (operation == .install) else { throw failure("설치 작업의 방향을 확인할 수 없습니다.") }
        }
        guard validPaths(saved, roots: roots), LibraryCatalog.physicalPath(saved.location.url.path) == saved.physicalParent,
              LibraryCatalog.physicalPath(URL(fileURLWithPath: saved.currentPath).deletingLastPathComponent().path) == saved.physicalStorageParent else {
            throw failure("등록 경로가 바뀌었습니다. 변경을 멈췄습니다.")
        }
        let fd = try openDirectory(saved.physicalParent)
        defer { close(fd) }
        let storage = try openDirectory(saved.physicalStorageParent)
        defer { close(storage) }
        let sourceFD = move.enabled ? storage : fd
        let destinationFD = move.enabled ? fd : storage
        var parent = stat(), storageInfo = stat(), source = stat(), destination = stat()
        guard fstat(fd, &parent) == 0, saved.parentIdentity.matches(parent),
              fstat(storage, &storageInfo) == 0, saved.storageParentIdentity.matches(storageInfo), parent.st_dev == storageInfo.st_dev else { throw failure("설치 폴더의 부모가 교체되었습니다. 변경을 멈췄습니다.") }
        let from = URL(fileURLWithPath: move.source).lastPathComponent
        let to = URL(fileURLWithPath: move.destination).lastPathComponent
        let fromResult = fstatat(sourceFD, from, &source, AT_SYMLINK_NOFOLLOW)
        let fromError = errno
        let toResult = fstatat(destinationFD, to, &destination, AT_SYMLINK_NOFOLLOW)
        let toError = errno
        let name: String
        let containingFD: Int32
        let kind = saved.link == nil ? S_IFDIR : S_IFLNK
        if fromResult == 0 && toResult != 0 && toError == ENOENT && saved.identity.matches(source) && source.st_mode & S_IFMT == kind { name = from; containingFD = sourceFD }
        else if allowCompleted && fromResult != 0 && fromError == ENOENT && toResult == 0 && saved.identity.matches(destination) && destination.st_mode & S_IFMT == kind { name = to; containingFD = destinationFD }
        else { throw failure("출발·도착 위치가 바뀌었거나 기존 폴더와 충돌합니다. 파일을 덮어쓰지 않고 중단했습니다.") }
        if let link = saved.link {
            guard try linkText(containingFD, name) == link.text else { throw failure("링크 대상 문자가 바뀌었습니다. 변경을 멈췄습니다.") }
            let target = try openLinkTarget(link, originalPath: saved.originalPath, roots: roots)
            defer { close(target) }
            guard try hashDocument(target) == move.contentHash, let hash = move.treeHash, try hashTree(target) == hash else {
                throw failure("공유 원본의 내용이 검토 또는 실행 후 바뀌었습니다. 새 계획을 검토해 주세요.")
            }
            return
        }
        let child = openat(containingFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw failure("설치 폴더를 다시 열 수 없습니다.") }
        defer { close(child) }
        var opened = stat()
        guard fstat(child, &opened) == 0, saved.identity.matches(opened), try hashDocument(child) == move.contentHash else {
            throw failure("검토 후 설치 항목이나 SKILL.md가 바뀌었습니다. 변경을 멈췄습니다.")
        }
        if let expected = move.treeHash, try hashTree(child) != expected {
            throw failure("검토 또는 실행 후 포함 파일이 바뀌었습니다. 변경을 멈췄습니다.")
        }
    }

    private static func hashDocument(_ directory: Int32) throws -> String {
        let file = openat(directory, "SKILL.md", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw failure("SKILL.md를 안전하게 읽을 수 없습니다.") }
        defer { close(file) }
        let data = try readRegular(file)
        guard let text = String(data: data, encoding: .utf8) else { throw failure("SKILL.md가 UTF-8 문서가 아닙니다.") }
        return LibraryCatalog.digest(text)
    }

    /// Hash link text without following it. Bound work and reject special files rather than reading them.
    private static func hashTree(_ directory: Int32) throws -> String {
        var hasher = SHA256(), entries = 0, bytes = 0
        func frame(_ value: String) {
            let data = Data(value.utf8)
            hasher.update(data: Data("\(data.count):".utf8)); hasher.update(data: data)
        }
        func unchanged(_ before: stat, _ after: stat) -> Bool {
            before.st_dev == after.st_dev && before.st_ino == after.st_ino && before.st_mode == after.st_mode
                && before.st_size == after.st_size
                && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        }
        func visit(_ fd: Int32, depth: Int) throws {
            guard depth <= 32 else { throw failure("포함 폴더가 32단계를 넘어 안전하게 변경할 수 없습니다.") }
            var before = stat(), after = stat()
            guard fstat(fd, &before) == 0 else { throw failure("포함 폴더를 확인할 수 없습니다.") }
            // A new descriptor gives each traversal an independent directory offset.
            let listing = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard listing >= 0 else { throw failure("포함 파일 목록을 열 수 없습니다.") }
            guard let stream = fdopendir(listing) else { close(listing); throw failure("포함 파일 목록을 읽을 수 없습니다.") }
            defer { closedir(stream) }
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw failure("포함 파일 목록을 끝까지 읽을 수 없습니다.") }
                    break
                }
                guard let name = withUnsafeBytes(of: entry.pointee.d_name, { raw in
                    raw.firstIndex(of: 0).flatMap { String(bytes: raw.prefix($0), encoding: .utf8) }
                }) else { throw failure("포함 파일 이름을 UTF-8로 확인할 수 없습니다.") }
                if name == "." || name == ".." { continue }
                entries += 1
                guard entries <= 10_000 else { throw failure("포함 항목이 10,000개를 넘어 안전하게 변경할 수 없습니다.") }
                names.append(name)
            }
            frame("directory:\(before.st_mode)")
            for name in names.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                var info = stat(), observed = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("포함 파일이 검사 중 바뀌었습니다.") }
                frame(name); frame("\(info.st_mode)")
                switch info.st_mode & S_IFMT {
                case S_IFDIR:
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw failure("포함 폴더를 안전하게 열 수 없습니다.") }
                    defer { close(child) }
                    guard fstat(child, &observed) == 0, unchanged(info, observed) else { throw failure("포함 폴더가 교체되었습니다.") }
                    try visit(child, depth: depth + 1)
                case S_IFREG:
                    guard info.st_size >= 0, info.st_size <= 64 * 1_024 * 1_024 - bytes else { throw failure("포함 파일이 64 MiB 한도를 넘어 안전하게 변경할 수 없습니다.") }
                    bytes += Int(info.st_size)
                    let file = openat(fd, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                    guard file >= 0 else { throw failure("포함 파일을 안전하게 읽을 수 없습니다.") }
                    defer { close(file) }
                    guard fstat(file, &observed) == 0, unchanged(info, observed) else { throw failure("포함 파일이 교체되었습니다.") }
                    var digest = SHA256(), buffer = [UInt8](repeating: 0, count: 16_384), readCount = 0
                    while true {
                        let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
                        if count < 0 && errno == EINTR { continue }
                        guard count >= 0 else { throw failure("포함 파일을 끝까지 읽을 수 없습니다.") }
                        if count == 0 { break }
                        readCount += count
                        guard readCount <= info.st_size else { throw failure("포함 파일이 검사 중 바뀌었습니다.") }
                        digest.update(data: Data(buffer.prefix(count)))
                    }
                    guard readCount == info.st_size, fstat(file, &observed) == 0, unchanged(info, observed) else { throw failure("포함 파일이 검사 중 바뀌었습니다.") }
                    frame(digest.finalize().map { String(format: "%02x", $0) }.joined())
                case S_IFLNK:
                    var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
                    let count = buffer.withUnsafeMutableBytes { readlinkat(fd, name, $0.baseAddress, $0.count) }
                    guard count >= 0, count < buffer.count else { throw failure("포함 링크를 확인할 수 없습니다.") }
                    frame(Data(buffer.prefix(count)).base64EncodedString())
                default: throw failure("일반 파일·폴더·링크 외의 포함 항목은 안전하게 변경할 수 없습니다.")
                }
                guard fstatat(fd, name, &observed, AT_SYMLINK_NOFOLLOW) == 0, unchanged(info, observed) else { throw failure("포함 항목이 검사 중 바뀌었습니다.") }
            }
            guard fstat(fd, &after) == 0, unchanged(before, after) else { throw failure("포함 폴더가 검사 중 바뀌었습니다.") }
            frame("end")
        }
        try visit(directory, depth: 0)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func locked<T>(_ body: (Int32) throws -> T) throws -> T {
        let directory = try Self.openDirectory(stateDirectory.path, create: true)
        defer { close(directory) }
        let lock = openat(directory, "library.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Self.failure("변경 기록의 잠금 파일을 열 수 없습니다.") }
        defer { close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Self.failure("다른 앱이 변경 기록을 사용 중이거나 잠금 파일을 확인할 수 없습니다.") }
        defer { _ = flock(lock, LOCK_UN) }
        return try body(directory)
    }

    private func readJournal(_ directory: Int32) throws -> LibraryJournal {
        let fd = openat(directory, "library-journal.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return LibraryJournal() }
        guard fd >= 0 else { throw Self.failure("변경 기록을 읽을 수 없습니다. 파일 변경을 잠갔습니다.") }
        defer { close(fd) }
        do { return try JSONDecoder().decode(LibraryJournal.self, from: Self.readRegular(fd)) }
        catch { throw Self.failure("변경 기록이 손상되었거나 읽을 수 없습니다. 기존 데이터를 보존하고 파일 변경을 잠갔습니다.") }
    }

    private func writeJournal(_ journal: LibraryJournal, directory: Int32) throws {
        let data = try JSONEncoder().encode(journal)
        guard data.count <= 2 * 1_024 * 1_024 else { throw Self.failure("변경 기록이 2 MiB 한도를 넘습니다.") }
        let name = ".journal-" + UUID().uuidString
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.failure("변경 기록을 저장할 수 없습니다.") }
        defer { close(fd); _ = unlinkat(directory, name, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Self.failure("변경 기록을 쓸 수 없습니다.") }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(directory, name, directory, "library-journal.json") == 0, fsync(directory) == 0 else {
            throw Self.failure("변경 기록을 디스크에 저장하지 못했습니다.")
        }
    }

    private static func readRegular(_ fd: Int32) throws -> Data {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 2 * 1_024 * 1_024 else { throw failure("일반 파일 또는 2 MiB 읽기 한도를 확인할 수 없습니다.") }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let length = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if length < 0 && errno == EINTR { continue }
            guard length >= 0 else { throw failure("파일을 읽을 수 없습니다.") }
            if length == 0 { return data }
            guard data.count + length <= 2 * 1_024 * 1_024 else { throw failure("2 MiB 읽기 한도를 넘습니다.") }
            data.append(contentsOf: buffer.prefix(length))
        }
    }

    private static func openDirectory(_ input: String, create: Bool = false) throws -> Int32 {
        var path = input
        // Foundation abbreviates these system aliases; other symlink components remain forbidden.
        for alias in ["/var", "/tmp", "/etc"] where input == alias || input.hasPrefix(alias + "/") {
            guard let physical = LibraryCatalog.physicalPath(alias) else { throw failure("시스템 경로를 확인할 수 없습니다.") }
            path = physical + input.dropFirst(alias.count)
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw failure("폴더를 열 수 없습니다.") }
        for component in path.split(separator: "/") {
            let name = String(component)
            var next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0 && errno == ENOENT && create {
                guard mkdirat(fd, name, 0o700) == 0 || errno == EEXIST else { close(fd); throw failure("기록 폴더를 만들 수 없습니다.") }
                next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            close(fd)
            guard next >= 0 else { throw failure("폴더가 링크이거나 접근할 수 없습니다: \(path) (\(name))") }
            fd = next
        }
        return fd
    }

    private static func failure(_ message: String) -> CatalogReadError { .inaccessible(message) }
}
