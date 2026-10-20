import Darwin
import Foundation

public struct AgentChangeRequest: Codable, Identifiable, Sendable {
    public let version: Int
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let installationIDs: [String]
    public let enabled: Bool
    public let snapshotID: String
    public let moves: [Move]

    public init(snapshot: ManagementSnapshot, plan: MutationPlan, installationIDs: [String], enabled: Bool) {
        version = 1; id = plan.id; title = plan.title; createdAt = .now
        self.installationIDs = installationIDs; self.enabled = enabled
        snapshotID = snapshot.fingerprint; moves = plan.installations
    }

    public func validatedPlan(snapshot: ManagementSnapshot, now: Date = .now) throws -> MutationPlan {
        try validateShape()
        guard version == 1, createdAt <= now.addingTimeInterval(60), now.timeIntervalSince(createdAt) <= 86_400,
              snapshotID == snapshot.fingerprint else { throw ManagementError.staleRequest }
        // The serialized moves are evidence only. Rebuild all paths and permissions from current app state.
        let rebuilt = try snapshot.plan(installationIDs: installationIDs, enabled: enabled, title: title, id: id)
        guard rebuilt.installations.count == moves.count,
              zip(rebuilt.installations.sorted { $0.id < $1.id }, moves.sorted { $0.id < $1.id }).allSatisfy({ current, old in
                  current.id == old.id && current.enabled == old.enabled && current.contentHash == old.contentHash
                      && current.treeHash == old.treeHash && current.installation.originalPath == old.installation.originalPath
              }) else { throw ManagementError.staleRequest }
        return rebuilt
    }

    fileprivate func validateShape() throws {
        guard version == 1, !title.isEmpty, title.count <= 160,
              !installationIDs.isEmpty, installationIDs.count <= 100,
              Set(installationIDs).count == installationIDs.count,
              !moves.isEmpty, moves.count <= 100, Set(moves.map(\.id)).count == moves.count else { throw ManagementError.invalidRequest }
    }
}

/// Local, bounded intent queue. Requests grant no authority to apply file changes.
public actor AgentRequestStore {
    private let directory: URL
    public init(stateDirectory: URL) { directory = stateDirectory.appendingPathComponent("AgentRequests") }

    private func withDirectory<T>(_ action: (Int32) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ManagementError.invalidRequest }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ManagementError.invalidRequest }
        let lock = openat(fd, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw ManagementError.invalidRequest }
        defer { close(lock) }
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == getuid(), flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw ManagementError.invalidRequest }
        defer { flock(lock, LOCK_UN) }
        return try action(fd)
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
    }

    private func read(_ id: UUID, fd: Int32) throws -> AgentChangeRequest {
        let file = openat(fd, id.uuidString + ".json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw ManagementError.invalidRequest }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == getuid(), info.st_size > 0, info.st_size <= 1_048_576 else { throw ManagementError.invalidRequest }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(file, &bytes, bytes.count)
            guard count >= 0 else { throw ManagementError.invalidRequest }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
            guard data.count <= 1_048_576 else { throw ManagementError.invalidRequest }
        }
        let request = try JSONDecoder().decode(AgentChangeRequest.self, from: data)
        guard request.id == id else { throw ManagementError.invalidRequest }
        try request.validateShape()
        return request
    }

    public func list() throws -> [AgentChangeRequest] {
        try withDirectory { fd in
            let names = try names()
            guard names.count <= 100 else { throw ManagementError.queueFull }
            return try names.map { name in
                guard let id = UUID(uuidString: String(name.dropLast(5))), name == id.uuidString + ".json" else { throw ManagementError.invalidRequest }
                return try read(id, fd: fd)
            }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func submit(_ request: AgentChangeRequest) throws {
        try request.validateShape()
        let data = try JSONEncoder().encode(request)
        guard data.count <= 1_048_576, !request.moves.isEmpty else { throw ManagementError.invalidRequest }
        try withDirectory { fd in
            guard try names().count < 100 else { throw ManagementError.queueFull }
            let name = request.id.uuidString + ".json"
            let temporary = "." + UUID().uuidString + ".tmp"
            let file = openat(fd, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard file >= 0 else { throw ManagementError.invalidRequest }
            defer { close(file); unlinkat(fd, temporary, 0) }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    guard count > 0 else { throw ManagementError.invalidRequest }
                    offset += count
                }
            }
            guard fsync(file) == 0 else { throw ManagementError.invalidRequest }
            guard renameatx_np(fd, temporary, fd, name, UInt32(RENAME_EXCL)) == 0, fsync(fd) == 0 else { throw ManagementError.invalidRequest }
        }
    }

    public func remove(_ id: UUID) throws {
        try withDirectory { fd in
            _ = try read(id, fd: fd)
            guard unlinkat(fd, id.uuidString + ".json", 0) == 0 else { throw ManagementError.invalidRequest }
        }
    }
}
