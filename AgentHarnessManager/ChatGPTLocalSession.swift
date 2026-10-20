import Darwin
import Foundation
import Network
import Security

@MainActor
protocol ChatGPTCredentialStorage {
    func load() throws -> ChatGPTCredentials
    func save(_ credentials: ChatGPTCredentials) throws
    func lock() throws -> ChatGPTSessionLock
}

@MainActor
final class ChatGPTCredentialStore: ChatGPTCredentialStorage {
    private let service: String
    private let lockURL: URL

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "agent-harness-manager") {
        service = bundleID + ".chatgpt"
        lockURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID).appendingPathComponent("ChatGPT/session.lock")
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "oauth-registrations-v1"]
    }

    // Legacy login-keychain items ignore the Data Protection keychain's per-query UI controls.
    static func withoutInteraction<T>(_ action: () throws -> T) throws -> T {
        var previous = DarwinBoolean(false)
        let read = SecKeychainGetUserInteractionAllowed(&previous)
        guard read == errSecSuccess else { throw ChatGPTError.keychain(read) }
        let changed = SecKeychainSetUserInteractionAllowed(false)
        guard changed == errSecSuccess else { throw ChatGPTError.keychain(changed) }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        // Keep the process-wide policy scoped to synchronous main-actor work, including failures.
        return try action()
    }

    func load() throws -> ChatGPTCredentials {
        var request = query
        request[kSecReturnData] = true; request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = try Self.withoutInteraction { SecItemCopyMatching(request as CFDictionary, &result) }
        if status == errSecItemNotFound { return ChatGPTCredentials() }
        guard status == errSecSuccess else { throw ChatGPTError.keychain(status) }
        guard let data = result as? Data else { throw ChatGPTError.invalidResponse }
        let credentials = try JSONDecoder().decode(ChatGPTCredentials.self, from: data)
        guard credentials.hostID.hasPrefix("urn:uuid:"),
              Set(credentials.accounts.map(\.clientID)).count == credentials.accounts.count else { throw ChatGPTError.invalidResponse }
        return credentials
    }

    func save(_ credentials: ChatGPTCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try Self.withoutInteraction {
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
            if status == errSecItemNotFound {
                var request = query
                request[kSecValueData] = data
                let added = SecItemAdd(request as CFDictionary, nil)
                guard added == errSecSuccess else { throw ChatGPTError.keychain(added) }
            } else if status != errSecSuccess { throw ChatGPTError.keychain(status) }
        }
    }

    func lock() throws -> ChatGPTSessionLock {
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        return try ChatGPTSessionLock(url: lockURL)
    }
}

// Separate processes must not race the same rotating refresh token.
final class ChatGPTSessionLock {
    private let descriptor: Int32
    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ChatGPTError.busy }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor); throw ChatGPTError.busy
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

@MainActor
final class ChatGPTLoopback {
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var result: Result<URL, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    private(set) var redirect: URL?

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener?.port else { self.stop(ChatGPTError.invalidAuthorization); return }
                    let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
                    self.redirect = url
                    let continuation = self.ready; self.ready = nil
                    continuation?.resume(returning: url)
                case .failed: self.stop(ChatGPTError.invalidAuthorization)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(600)) } catch { return }
            self?.stop(ChatGPTError.timedOut)
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.start(queue: .main)
        }
    }

    func wait() async throws -> URL {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { callback = $0 }
    }

    func stop(_ error: Error = CancellationError()) {
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
        let ready = ready; self.ready = nil; ready?.resume(throwing: error)
        if result == nil { result = .failure(error) }
        let callback = callback; self.callback = nil
        if let result { callback?.resume(with: result) }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8, result == nil else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(10))
            connection?.cancel(); self?.connections.removeValue(forKey: id)
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                let bytes = buffer + (data ?? Data())
                guard bytes.count <= 16_384, error == nil else {
                    connection.cancel(); self.connections.removeValue(forKey: id); return
                }
                guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if complete { connection.cancel(); self.connections.removeValue(forKey: id) }
                    else { self.receive(connection, id: id, buffer: bytes) }
                    return
                }
                let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                let target = parts.count == 3 ? String(parts[1]) : ""
                let url = self.redirect.flatMap { URL(string: target, relativeTo: $0)?.absoluteURL }
                let valid = parts.first == "GET" && target.hasPrefix("/auth/callback?") && url?.path == "/auth/callback"
                // The HTTP response contains no callback parameters or credentials. OAuth validation follows in the client.
                let body = valid ? "<!doctype html><meta charset=utf-8><title>Agent Harness Manager</title><p>Return to Agent Harness Manager to see the sign-in result. You may close this tab.</p>" : "Not found"
                let response = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
                if valid, self.result == nil, let url {
                    self.result = .success(url)
                    self.listener?.cancel(); self.listener = nil
                    self.timeout?.cancel(); self.timeout = nil
                    let continuation = self.callback; self.callback = nil
                    continuation?.resume(returning: url)
                }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
                    connection.cancel()
                    Task { @MainActor in self?.connections.removeValue(forKey: id) }
                })
            }
        }
    }
}
