import CryptoKit
import Darwin
import Foundation

public struct DirectoryIdentity: Codable, Hashable, Sendable {
    public let device: Int32
    public let inode: UInt64
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    func matches(_ info: stat) -> Bool { device == info.st_dev && inode == info.st_ino }
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
    public var readRoot: DiscoveryRoot { DiscoveryRoot(agent: location.agent, url: URL(fileURLWithPath: currentPath), label: location.label) }
    public var matchesCurrentItem: Bool {
        var info = stat()
        return lstat(currentPath, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && identity.matches(info)
    }
}

public struct Move: Codable, Identifiable, Equatable, Sendable {
    public let installation: DisabledInstallation
    public let enabled: Bool
    public let contentHash: String
    public var treeHash: String? = nil
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
    public init(title: String, installations: [Move], undoes: UUID? = nil, groupSelection: GroupSelectionChange? = nil) {
        id = UUID(); self.title = title; self.installations = installations; createdAt = .now
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

/// Only independent, direct child directories in the two default skill roots can be moved outside discovery roots.
/// Links, nested skills, custom roots and provider-owned caches stay read-only.
public actor LibraryService {
    private let stateDirectory: URL
    public init(stateDirectory: URL) { self.stateDirectory = stateDirectory }

    public static func plan(title: String, installations: [SkillInstallation], enabled: Bool,
                            allInstallations: [SkillInstallation], managedRoots: [DiscoveryRoot], protectedRoots: [DiscoveryRoot] = []) throws -> MutationPlan {
        var moves: [Move] = []
        var paths = Set<String>()
        for item in installations where item.isEnabled != enabled {
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
        return MutationPlan(title: title, installations: moves)
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
            for move in plan.installations { try Self.validate(move, roots: roots, allowCompleted: false) }
            try Self.checkReaders(plan, roots: roots)
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
            for move in plan.installations { try Self.validate(move, roots: roots, allowCompleted: false) }
            try Self.checkReaders(plan, roots: roots)
            return plan
        }
    }

    private static func undoPlan(id: UUID, journal: LibraryJournal) throws -> MutationPlan {
        if let reason = journal.undoUnavailableReason(for: id) { throw failure(reason) }
        guard let original = journal.completed.first(where: { $0.id == id }) else { throw failure("완료 기록을 찾을 수 없습니다.") }
        let moves = original.installations.reversed().map {
            Move(installation: $0.installation, enabled: !$0.enabled, contentHash: $0.contentHash, treeHash: $0.treeHash)
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
        try Self.checkReaders(plan, roots: roots)
        for move in plan.installations {
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
                    throw Self.failure("폴더를 이동하지 못했습니다. 변경 기록을 보존했습니다. 충돌을 해결한 뒤 복구를 다시 시도해 주세요.")
                }
                guard fsync(fd) == 0, fsync(storage) == 0 else { throw Self.failure("폴더 변경을 디스크에 기록하지 못했습니다. 복구가 필요합니다.") }
            }
            try Self.validate(move, roots: roots, allowCompleted: true)
        }
        for move in plan.installations {
            journal.disabled.removeAll { $0.id == move.id }
            if !move.enabled { journal.disabled.append(move.installation) }
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
                result.disabled.removeAll { $0.id == saved.id }; result.disabled.append(saved)
            } else if lstat(saved.originalPath, &info) == 0 && saved.identity.matches(info) {
                result.disabled.removeAll { $0.id == saved.id }
            }
        }
        return result
    }

    private func validateJournal(_ journal: LibraryJournal, roots: [DiscoveryRoot]) throws {
        guard journal.version == 1, Set(journal.disabled.map(\.id)).count == journal.disabled.count,
              Set(journal.completed.map(\.id)).count == journal.completed.count,
              journal.pending.map({ Set($0.installations.map(\.id)).count == $0.installations.count }) ?? true else {
            throw Self.failure("변경 기록 형식을 확인할 수 없습니다. 기존 데이터를 보존하고 파일 변경을 잠갔습니다.")
        }
        for saved in journal.disabled + (journal.pending?.installations.map(\.installation) ?? []) {
            guard Self.validPaths(saved, roots: roots) else { throw Self.failure("변경 기록의 경로를 확인할 수 없습니다. 원래 경로를 등록한 뒤 다시 시도해 주세요.") }
        }
    }

    private static func checkReaders(_ plan: MutationPlan, roots: [DiscoveryRoot]) throws {
        guard plan.installations.contains(where: { !$0.enabled }) else { return }
        let snapshot = SkillCatalog.scan(roots: roots)
        guard snapshot.roots.allSatisfy({ $0.status == .available || $0.status == .missing }) else {
            throw failure("공유 링크에 미치는 영향을 확인할 수 없습니다. 경로 문제를 해결한 뒤 다시 시도해 주세요.")
        }
        for move in plan.installations where !move.enabled {
            let source = move.installation.physicalParent + "/" + URL(fileURLWithPath: move.installation.originalPath).lastPathComponent
            if roots.contains(where: { root in
                guard let path = LibraryCatalog.physicalPath(root.url.path) else { return false }
                return path == source || path.hasPrefix(source + "/")
            }) || snapshot.entries.contains(where: { entry in
                guard entry.url.path != move.installation.originalPath else { return false }
                let target = entry.resolvedURL?.path ?? LibraryCatalog.physicalPath(entry.url.path)
                return target == source || target?.hasPrefix(source + "/") == true
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
        if fromResult == 0 && toResult != 0 && toError == ENOENT && saved.identity.matches(source) && source.st_mode & S_IFMT == S_IFDIR { name = from; containingFD = sourceFD }
        else if allowCompleted && fromResult != 0 && fromError == ENOENT && toResult == 0 && saved.identity.matches(destination) && destination.st_mode & S_IFMT == S_IFDIR { name = to; containingFD = destinationFD }
        else { throw failure("출발·도착 위치가 바뀌었거나 기존 폴더와 충돌합니다. 파일을 덮어쓰지 않고 중단했습니다.") }
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
