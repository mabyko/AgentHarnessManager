import Darwin
import Foundation

/// Edits only one MCP member, preserving comments and unrelated configuration bytes.
struct MCPConfiguration {
    private struct Token { let range: Range<Int>; let byte: UInt8 }
    private struct Member { let key: String; let start: Int; let value: Int; let end: Int; let comma: Int? }
    private let data: Data
    private let tokens: [Token]
    private let object: [String: Any]

    init(_ data: Data?, comments: Bool) throws {
        self.data = data ?? Data("{}\n".utf8)
        guard let object = try JSONSerialization.jsonObject(with: self.data, options: comments ? [.json5Allowed] : []) as? [String: Any] else {
            throw AgentConnectionError.invalidConfiguration
        }
        self.object = object
        let bytes = Array(self.data)
        var tokens: [Token] = [], index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if [9, 10, 13, 32].contains(byte) { index += 1; continue }
            if comments, byte == 47, index + 1 < bytes.count {
                if bytes[index + 1] == 47 {
                    index += 2
                    while index < bytes.count && bytes[index] != 10 { index += 1 }
                    continue
                }
                if bytes[index + 1] == 42 {
                    index += 2
                    while index + 1 < bytes.count && !(bytes[index] == 42 && bytes[index + 1] == 47) { index += 1 }
                    guard index + 1 < bytes.count else { throw AgentConnectionError.invalidConfiguration }
                    index += 2; continue
                }
            }
            let start = index
            index += 1
            if byte == 34 {
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { index += 1; break }
                    index += 1
                }
            } else if ![123, 125, 91, 93, 58, 44].contains(byte) {
                while index < bytes.count && ![9, 10, 13, 32, 123, 125, 91, 93, 58, 44, 47].contains(bytes[index]) { index += 1 }
            }
            guard index <= bytes.count, tokens.count < 500_000 else { throw AgentConnectionError.invalidConfiguration }
            tokens.append(Token(range: start..<index, byte: byte))
        }
        self.tokens = tokens
        _ = try members(at: 0)
    }

    func server(in key: String, named name: String) throws -> [String: Any]? {
        guard let value = object[key] else { return nil }
        guard let servers = value as? [String: Any], let map = try members(at: 0).first(where: { $0.key == key }) else {
            throw AgentConnectionError.invalidConfiguration
        }
        let entries = try members(at: map.value)
        guard let value = servers[name] else { return nil }
        guard let server = value as? [String: Any], let entry = entries.first(where: { $0.key == name }) else {
            throw AgentConnectionError.conflict
        }
        _ = try members(at: entry.value)
        return server
    }

    func replacing(in key: String, named name: String, with server: [String: Any]?) throws -> Data {
        let root = try members(at: 0)
        var result = data
        if let map = root.first(where: { $0.key == key }) {
            let entries = try members(at: map.value)
            if let entry = entries.first(where: { $0.key == name }) {
                guard server == nil else { throw AgentConnectionError.conflict }
                if let comma = entry.comma {
                    result.removeSubrange(tokens[entry.start].range.lowerBound..<tokens[comma].range.upperBound)
                } else {
                    result.removeSubrange(tokens[entry.start].range.lowerBound..<tokens[entry.end].range.upperBound)
                    if let position = entries.firstIndex(where: { $0.key == name }), position > 0, let comma = entries[position - 1].comma {
                        result.removeSubrange(tokens[comma].range)
                    }
                }
            } else if let server {
                let value = try JSONSerialization.data(withJSONObject: [name: server], options: [.sortedKeys, .withoutEscapingSlashes])
                let member = value.dropFirst().dropLast()
                result.insert(contentsOf: Data("\n  ".utf8) + member + Data((entries.isEmpty ? "\n" : ",\n").utf8), at: tokens[map.value].range.upperBound)
            }
        } else if let server {
            let value = try JSONSerialization.data(withJSONObject: [key: [name: server]], options: [.sortedKeys, .withoutEscapingSlashes])
            result.insert(contentsOf: Data("\n  ".utf8) + value.dropFirst().dropLast() + Data((root.isEmpty ? "\n" : ",\n").utf8), at: tokens[0].range.upperBound)
        }
        _ = try MCPConfiguration(result, comments: true)
        return result
    }

    private func members(at start: Int) throws -> [Member] {
        guard tokens.indices.contains(start), tokens[start].byte == 123 else { throw AgentConnectionError.invalidConfiguration }
        var result: [Member] = [], seen = Set<String>(), index = start + 1
        while index < tokens.count && tokens[index].byte != 125 {
            let keyIndex = index
            guard tokens[index].byte == 34,
                  let key = try JSONSerialization.jsonObject(with: data.subdata(in: tokens[index].range), options: .fragmentsAllowed) as? String,
                  seen.insert(key).inserted, index + 2 < tokens.count, tokens[index + 1].byte == 58 else {
                throw AgentConnectionError.invalidConfiguration
            }
            index += 2
            let value = index
            var depth = 0
            repeat {
                guard index < tokens.count else { throw AgentConnectionError.invalidConfiguration }
                let byte = tokens[index].byte
                if byte == 123 || byte == 91 { depth += 1 }
                if byte == 125 || byte == 93 { depth -= 1 }
                guard depth >= 0 && depth <= 64 else { throw AgentConnectionError.invalidConfiguration }
                index += 1
            } while depth > 0
            let end = index - 1
            let comma = index < tokens.count && tokens[index].byte == 44 ? index : nil
            result.append(Member(key: key, start: keyIndex, value: value, end: end, comma: comma))
            if comma != nil { index += 1 }
            else { break }
        }
        guard index < tokens.count, tokens[index].byte == 125 else { throw AgentConnectionError.invalidConfiguration }
        return result
    }
}

/// Anchored no-follow I/O prevents configuration symlinks from escaping the reviewed path.
enum MCPConfigurationFile {
    static func directory(_ url: URL, create: Bool) throws -> Int32? {
        var path = url.standardizedFileURL.path
        for alias in ["/var/", "/tmp/"] where path.hasPrefix(alias) { path = "/private" + path }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw AgentConnectionError.invalidConfiguration }
        do {
            for component in path.split(separator: "/").map(String.init) {
                var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                if next < 0 && errno == ENOENT && create {
                    guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw AgentConnectionError.invalidConfiguration }
                    next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                }
                if next < 0 && errno == ENOENT && !create { close(descriptor); return nil }
                guard next >= 0 else { throw AgentConnectionError.invalidConfiguration }
                close(descriptor); descriptor = next
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }

    private static func read(_ name: String, directory: Int32, limit: Int = 8_388_608) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0 && errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw AgentConnectionError.invalidConfiguration }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= limit,
              let data = try file.read(upToCount: limit + 1), data.count == info.st_size else { throw AgentConnectionError.invalidConfiguration }
        return data
    }

    static func read(_ url: URL, limit: Int = 8_388_608) throws -> Data? {
        guard let descriptor = try directory(url.deletingLastPathComponent(), create: false) else { return nil }
        defer { close(descriptor) }
        return try read(url.lastPathComponent, directory: descriptor, limit: limit)
    }

    static func write(_ data: Data, to url: URL, replacing original: Data?, permissions: mode_t = 0o600) throws {
        guard let descriptor = try directory(url.deletingLastPathComponent(), create: true) else { throw AgentConnectionError.invalidConfiguration }
        defer { close(descriptor) }
        let temporary = ".ahm-mcp-" + UUID().uuidString
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw AgentConnectionError.invalidConfiguration }
        defer { close(file); unlinkat(descriptor, temporary, 0) }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fchmod(file, permissions & 0o777) == 0, fsync(file) == 0 else { throw AgentConnectionError.commandFailed }
        guard try read(url.lastPathComponent, directory: descriptor) == original else { throw AgentConnectionError.changed }
        guard renameatx_np(descriptor, temporary, descriptor, url.lastPathComponent, original == nil ? UInt32(RENAME_EXCL) : 0) == 0,
              fsync(descriptor) == 0 else { throw AgentConnectionError.commandFailed }
    }
}
