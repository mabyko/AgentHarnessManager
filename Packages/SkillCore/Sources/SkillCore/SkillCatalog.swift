import Foundation
import Darwin

public enum CatalogReadError: LocalizedError {
    case inaccessible(String)

    public var errorDescription: String? {
        switch self { case .inaccessible(let message): message }
    }
}

public enum SkillCatalog {
    private static let documentLimit = 2 * 1_024 * 1_024
    private static let candidateLimit = 10_000
    private static let depthLimit = 8

    public static func scan(roots: [DiscoveryRoot]) -> CatalogSnapshot {
        let approved = roots.compactMap { try? OpenRoot($0) }
        defer { approved.forEach { close($0.fd) } }
        var entries: [SkillEntry] = []
        var observations: [RootObservation] = []

        for root in roots {
            guard let opened = approved.first(where: { $0.root.id == root.id }) else {
                var info = stat()
                let result = fstatat(AT_FDCWD, root.url.path, &info, 0)
                let missing = result != 0 && (errno == ENOENT || errno == ENOTDIR)
                observations.append(RootObservation(root: root, status: missing ? .missing : .blocked,
                    message: missing ? "등록 위치가 없습니다." : "등록 위치를 열 수 없습니다."))
                continue
            }
            var count = 0
            var visited: Set<String> = []
            var issues: [String] = []

            func appendEntry(_ url: URL, info: stat, linked: Bool, resolved: URL?, problem: String?) {
                entries.append(SkillEntry(id: identity(root: root, url: url, info: info, anchor: opened), rootID: root.id,
                    agent: root.agent, name: url.lastPathComponent, url: url,
                    isSymbolicLink: linked, resolvedURL: resolved, problem: problem))
                if let problem { issues.append(problem) }
            }

            func visit(fd: Int32, physicalPath: String, displayedURL: URL, depth: Int) {
                guard count < candidateLimit else { issues.append("후보 10,000개 탐색 한도에 도달했습니다."); return }
                var marker = stat()
                let markerResult = fstatat(fd, "SKILL.md", &marker, AT_SYMLINK_NOFOLLOW)
                if markerResult == 0 {
                    var directoryInfo = stat()
                    guard fstat(fd, &directoryInfo) == 0 else { issues.append("폴더 식별 정보를 읽을 수 없습니다."); return }
                    var problem: String?
                    if isType(marker, S_IFLNK) {
                        do {
                            let filePath = try canonical(physicalPath + "/SKILL.md")
                            let file = try secureOpen(filePath, approved: approved, directory: false)
                            defer { close(file) }
                            var fileInfo = stat()
                            guard fstat(file, &fileInfo) == 0, isType(fileInfo, S_IFREG) else {
                                throw CatalogReadError.inaccessible("SKILL.md가 일반 파일이 아닙니다.")
                            }
                        } catch { problem = error.localizedDescription }
                    } else if !isType(marker, S_IFREG) {
                        problem = "SKILL.md가 일반 파일이 아닙니다."
                    }
                    appendEntry(displayedURL, info: directoryInfo, linked: false, resolved: nil, problem: problem)
                    return
                }
                if errno != ENOENT {
                    issues.append("SKILL.md 접근 상태를 확인할 수 없습니다.")
                    return
                }
                var info = stat()
                guard fstat(fd, &info) == 0 else { issues.append("폴더 식별 정보를 읽을 수 없습니다."); return }
                let key = "\(info.st_dev):\(info.st_ino)"
                guard visited.insert(key).inserted else { issues.append("순환 또는 중복 탐색 경로를 건너뛰었습니다."); return }
                let listingFD = dup(fd)
                guard listingFD >= 0 else { issues.append("폴더 목록을 읽을 수 없습니다."); return }
                guard let directory = fdopendir(listingFD) else {
                    close(listingFD)
                    issues.append("폴더 목록을 읽을 수 없습니다.")
                    return
                }
                defer { closedir(directory) }
                var names: [String] = []
                errno = 0
                while let item = readdir(directory) {
                    let name = withUnsafePointer(to: item.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                    }
                    if name != "." && name != ".." { names.append(name) }
                    if names.count > candidateLimit { issues.append("후보 10,000개 탐색 한도에 도달했습니다."); break }
                    errno = 0
                }
                if errno != 0 { issues.append("폴더 목록을 모두 읽지 못했습니다.") }
                for name in names.sorted() {
                    guard count < candidateLimit else { issues.append("후보 10,000개 탐색 한도에 도달했습니다."); break }
                    count += 1
                    var childInfo = stat()
                    guard fstatat(fd, name, &childInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
                        issues.append("항목을 확인할 수 없습니다: \(name)"); continue
                    }
                    let childURL = displayedURL.appendingPathComponent(name)
                    let childPath = physicalPath + "/" + name
                    if isType(childInfo, S_IFLNK) {
                        do {
                            let target = try canonical(childPath)
                            let childFD = try secureOpen(target, approved: approved, directory: true)
                            defer { close(childFD) }
                            var skillInfo = stat()
                            if fstatat(childFD, "SKILL.md", &skillInfo, AT_SYMLINK_NOFOLLOW) == 0 {
                                var problem: String?
                                do {
                                    let document = try secureOpen(try canonical(target + "/SKILL.md"), approved: approved, directory: false)
                                    defer { close(document) }
                                    var documentInfo = stat()
                                    guard fstat(document, &documentInfo) == 0, isType(documentInfo, S_IFREG) else {
                                        throw CatalogReadError.inaccessible("SKILL.md가 일반 파일이 아닙니다.")
                                    }
                                } catch { problem = error.localizedDescription }
                                appendEntry(childURL, info: childInfo, linked: true, resolved: URL(fileURLWithPath: target), problem: problem)
                            } else if depth < depthLimit {
                                visit(fd: childFD, physicalPath: target, displayedURL: childURL, depth: depth + 1)
                            } else { issues.append("탐색 깊이 8 한도에 도달했습니다.") }
                        } catch {
                            // File symlinks are not installed skill directories.
                            let savedError = error
                            if let target = try? canonical(childPath), let file = try? secureOpen(target, approved: approved, directory: false) {
                                var targetInfo = stat()
                                let regular = fstat(file, &targetInfo) == 0 && isType(targetInfo, S_IFREG)
                                close(file)
                                if regular { continue }
                            }
                            appendEntry(childURL, info: childInfo, linked: true, resolved: nil, problem: savedError.localizedDescription)
                        }
                    } else if isType(childInfo, S_IFDIR) {
                        guard depth < depthLimit else { issues.append("탐색 깊이 8 한도에 도달했습니다."); continue }
                        let childFD = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        guard childFD >= 0 else { issues.append("폴더를 열 수 없습니다: \(name)"); continue }
                        defer { close(childFD) }
                        var currentInfo = stat()
                        guard fstat(childFD, &currentInfo) == 0, sameIdentity(childInfo, currentInfo) else {
                            issues.append("탐색 중 폴더가 바뀌었습니다: \(name)"); continue
                        }
                        visit(fd: childFD, physicalPath: childPath, displayedURL: childURL, depth: depth + 1)
                    }
                }
            }

            visit(fd: opened.fd, physicalPath: opened.path, displayedURL: root.url, depth: 0)
            observations.append(RootObservation(root: root, status: issues.isEmpty ? .available : .partial,
                message: issues.first))
        }
        return CatalogSnapshot(entries: entries.sorted { $0.url.path < $1.url.path }, roots: observations)
    }

    public static func readDocument(entry: SkillEntry, approvedRoots: [DiscoveryRoot]) throws -> String {
        guard let registered = approvedRoots.first(where: { $0.id == entry.rootID }),
              contains(root: registered.url.path, path: entry.url.standardizedFileURL.path) else {
            throw CatalogReadError.inaccessible("설치 위치가 등록된 범위에 없습니다.")
        }
        let approved = approvedRoots.compactMap { try? OpenRoot($0) }
        defer { approved.forEach { close($0.fd) } }
        guard let anchor = approved.first(where: { $0.root.id == registered.id }) else {
            throw CatalogReadError.inaccessible("등록 위치를 열 수 없습니다.")
        }
        var observed = stat()
        if entry.url.standardizedFileURL.path == registered.url.path {
            guard fstat(anchor.fd, &observed) == 0 else {
                throw CatalogReadError.inaccessible("설치 위치를 확인할 수 없습니다.")
            }
        } else {
            let parent = try canonical(entry.url.deletingLastPathComponent().path)
            let parentFD = try secureOpen(parent, approved: approved, directory: true)
            defer { close(parentFD) }
            guard fstatat(parentFD, entry.url.lastPathComponent, &observed, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw CatalogReadError.inaccessible("설치 항목을 확인할 수 없습니다.")
            }
        }
        guard identity(root: registered, url: entry.url, info: observed, anchor: anchor) == entry.id else {
            throw CatalogReadError.inaccessible("설치 항목이 바뀌었습니다. 다시 검사해 주세요.")
        }
        let entryPath = try canonical(entry.url.path)
        let entryFD = try secureOpen(entryPath, approved: approved, directory: true)
        defer { close(entryFD) }
        var directoryInfo = stat()
        guard fstat(entryFD, &directoryInfo) == 0,
              entry.isSymbolicLink || sameIdentity(observed, directoryInfo) else {
            throw CatalogReadError.inaccessible("설치 폴더가 바뀌었습니다. 다시 검사해 주세요.")
        }
        var marker = stat()
        guard fstatat(entryFD, "SKILL.md", &marker, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CatalogReadError.inaccessible("SKILL.md에 접근할 수 없습니다.")
        }
        let file: Int32
        if isType(marker, S_IFLNK) {
            file = try secureOpen(try canonical(entryPath + "/SKILL.md"), approved: approved, directory: false)
        } else {
            file = openat(entryFD, "SKILL.md", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard file >= 0 else { throw CatalogReadError.inaccessible("SKILL.md에 접근할 수 없습니다.") }
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, isType(info, S_IFREG) else {
            throw CatalogReadError.inaccessible("SKILL.md가 일반 파일이 아닙니다.")
        }
        guard info.st_size <= documentLimit else { throw CatalogReadError.inaccessible("SKILL.md가 2 MiB 읽기 한도를 넘습니다.") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let length = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if length == 0 { break }
            if length < 0 {
                if errno == EINTR { continue }
                throw CatalogReadError.inaccessible("SKILL.md를 읽을 수 없습니다.")
            }
            guard data.count + length <= documentLimit else { throw CatalogReadError.inaccessible("SKILL.md가 2 MiB 읽기 한도를 넘습니다.") }
            data.append(contentsOf: buffer.prefix(length))
        }
        guard let document = String(data: data, encoding: .utf8) else {
            throw CatalogReadError.inaccessible("SKILL.md가 올바른 UTF-8 문서가 아닙니다.")
        }
        return document
    }

    private struct OpenRoot {
        let root: DiscoveryRoot
        let path: String
        let fd: Int32

        init(_ root: DiscoveryRoot) throws {
            self.root = root
            path = try canonical(root.url.path)
            fd = try openAbsoluteDirectory(path)
        }
    }

    private static func canonical(_ path: String) throws -> String {
        guard let resolved = realpath(path, nil) else {
            throw CatalogReadError.inaccessible("경로가 없거나 링크 원본에 접근할 수 없습니다.")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func contains(root: String, path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private static func openAbsoluteDirectory(_ path: String) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw CatalogReadError.inaccessible("등록 위치를 열 수 없습니다.") }
        for component in path.split(separator: "/") {
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw CatalogReadError.inaccessible("등록 위치가 바뀌었거나 접근할 수 없습니다.") }
            fd = next
        }
        return fd
    }

    private static func secureOpen(_ path: String, approved: [OpenRoot], directory: Bool) throws -> Int32 {
        guard let root = approved.filter({ contains(root: $0.path, path: path) }).max(by: { $0.path.count < $1.path.count }) else {
            throw CatalogReadError.inaccessible("링크 원본이 승인된 위치 밖에 있습니다.")
        }
        let components = path.dropFirst(root.path.count).split(separator: "/").map(String.init)
        var fd = dup(root.fd)
        guard fd >= 0 else { throw CatalogReadError.inaccessible("파일 접근 핸들을 열 수 없습니다.") }
        for (index, component) in components.enumerated() {
            let finalFile = index == components.count - 1 && !directory
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (finalFile ? O_NONBLOCK : O_DIRECTORY)
            let next = openat(fd, component, flags)
            close(fd)
            guard next >= 0 else { throw CatalogReadError.inaccessible("경로가 바뀌었거나 파일에 접근할 수 없습니다.") }
            fd = next
        }
        return fd
    }

    private static func isType(_ info: stat, _ type: mode_t) -> Bool { info.st_mode & S_IFMT == type }
    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool { lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino }
    private static func identity(root: DiscoveryRoot, url: URL, info: stat, anchor: OpenRoot) -> String {
        var rootInfo = stat()
        _ = fstat(anchor.fd, &rootInfo)
        return "\(root.id)|\(anchor.path):\(rootInfo.st_dev):\(rootInfo.st_ino)|\(url.standardizedFileURL.path)|\(info.st_dev):\(info.st_ino)"
    }
}
