import AppKit
import Foundation
import Observation

@MainActor @Observable
final class ChatGPTConnection {
    private(set) var accounts: [ChatGPTAccount] = []
    private(set) var activeID: String?
    private(set) var models: [ChatGPTModel] = []
    private(set) var isBusy = false
    private(set) var isSigningIn = false
    private(set) var message: String?
    private(set) var needsReconnect = false
    var showWelcome = false
    @ObservationIgnored private let vault: any ChatGPTCredentialStorage
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let openBrowser: @MainActor (URL) -> Bool
    @ObservationIgnored private var credentials = ChatGPTCredentials()
    @ObservationIgnored private var loopback: ChatGPTLoopback?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var loaded = false

    init(vault: any ChatGPTCredentialStorage = ChatGPTCredentialStore(), session: URLSession? = nil,
         openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.vault = vault
        self.openBrowser = openBrowser
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config, delegate: ChatGPTNoRedirects(), delegateQueue: nil)
    }

    var active: ChatGPTAccount? { accounts.first { $0.id == activeID } }
    var selectedModel: String { active?.model ?? "" }
    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!

    func load() {
        guard !loaded else { return }
        do { try reload(); loaded = true } catch { report(error) }
    }

    func connect(newAccount: Bool = false, consent: Bool = false) {
        perform {
            self.isSigningIn = true
            defer { self.isSigningIn = false; self.loopback?.stop(); self.loopback = nil }
            try self.reload()
            let previous = newAccount ? nil : self.active
            let pendingClientID = previous == nil ? self.credentials.pendingClientID : nil
            // Persist the host ID before starting the first browser registration.
            try self.save()
            let transaction = try ChatGPTAuthorization()
            let server = ChatGPTLoopback(); self.loopback = server
            let redirect = try await server.start()
            guard self.openBrowser(transaction.url(redirect: redirect, hostID: self.credentials.hostID, account: previous, consent: consent, pendingClientID: pendingClientID)) else {
                throw ChatGPTError.invalidAuthorization
            }
            let callback = try await server.wait()
            try Task.checkCancellation()
            let authorization = try transaction.callback(callback, redirect: redirect, account: previous, pendingClientID: pendingClientID)
            if previous == nil {
                // Retain an issued registration after exchange failure without trusting its identity or tokens.
                self.credentials.pendingClientID = authorization.clientID
                try self.save()
            }
            let tokens: ChatGPTTokenResponse = try await self.postToken([
                "grant_type": "authorization_code", "client_id": authorization.clientID,
                "code": authorization.code, "code_verifier": transaction.verifier,
                "redirect_uri": redirect.absoluteString, "resource": ChatGPTAuthorization.resource
            ])
            guard let idToken = tokens.id_token else { throw ChatGPTError.invalidIdentity }
            let identity = try await self.identity(idToken, clientID: authorization.clientID, nonce: transaction.nonce)
            let known = self.credentials.accounts.first { $0.id == authorization.clientID }
            let account = try tokens.account(clientID: authorization.clientID, identity: identity, nonce: transaction.nonce, previous: previous ?? known)
            try Task.checkCancellation()
            try self.store(account, activate: true)
            self.needsReconnect = false
            self.message = account.canUsePlan ? "ChatGPT에 연결했습니다." : "로그인했습니다. AI 요청을 보내려면 ChatGPT 요금제 사용 권한을 허용하세요."
            if account.canUsePlan {
                defer { self.showWelcome = !account.welcomed }
                try await self.fetchModels()
            }
        }
    }

    func cancelSignIn() {
        guard isSigningIn else { return }
        operation?.cancel(); loopback?.stop()
    }

    func chooseAccount(_ id: String) {
        perform {
            try self.reload()
            guard self.credentials.accounts.contains(where: { $0.id == id }) else { throw ChatGPTError.invalidAuthorization }
            self.credentials.activeID = id; try self.save()
            self.models = []; self.needsReconnect = false
            self.message = "계정을 선택했습니다. 모델을 새로고침하거나 다시 연결하세요."
        }
    }

    func chooseModel(_ model: String) {
        perform {
            try self.reload()
            guard var account = self.active, self.models.contains(where: { $0.id == model }) else { throw ChatGPTError.invalidResponse }
            account.model = model; try self.store(account)
        }
    }

    func refreshModels() { perform { try self.reload(); try await self.fetchModels(); self.message = "사용 가능한 모델을 확인했습니다." } }

    func acknowledgeWelcome() {
        showWelcome = false
        perform {
            try self.reload()
            guard var account = self.active else { return }
            account.welcomed = true; try self.store(account)
        }
    }

    func testConnection() {
        perform {
            try self.reload()
            let token = try await self.accessToken()
            guard let model = self.active?.model, !model.isEmpty else { throw ChatGPTError.invalidResponse }
            var request = URLRequest(url: URL(string: ChatGPTAuthorization.resource + "/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "store": false, "stream": true,
                "input": [["role": "user", "content": "Reply with exactly OK. This is a connection test."]]])
            let (bytes, response) = try await self.session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatGPTError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes { data.append(byte); if data.count >= 65_536 { break } }
                throw self.serviceError(http, data: data, phase: .test)
            }
            var stream = ChatGPTResponseStream(), count = 0, line = Data()
            // AsyncBytes.lines omits empty lines; SSE needs those event delimiters.
            for try await byte in bytes {
                try Task.checkCancellation()
                count += 1
                guard count < 2_097_152 else { throw ChatGPTError.invalidResponse }
                if byte == 10 {
                    if line.last == 13 { line.removeLast() }
                    guard let text = String(data: line, encoding: .utf8) else { throw ChatGPTError.invalidResponse }
                    try stream.line(text); line.removeAll(keepingCapacity: true)
                } else { line.append(byte) }
                if stream.completed { break }
            }
            if !line.isEmpty {
                guard let text = String(data: line, encoding: .utf8) else { throw ChatGPTError.invalidResponse }
                try stream.line(text)
            }
            let text = try stream.finish()
            self.message = "연결 테스트를 완료했습니다." + (text.isEmpty ? "" : " 응답: \(text)")
        }
    }

    func signOut() {
        perform {
            try self.reload()
            guard var account = self.active else { return }
            var revoked = account.refreshToken == nil
            if let refresh = account.refreshToken {
                do {
                    let config = try await self.discovery()
                    guard let endpoint = config["revocation_endpoint"] as? String, self.trustedAuthURL(endpoint) else { throw ChatGPTError.invalidResponse }
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = ChatGPTAuthorization.form(["token": refresh, "token_type_hint": "refresh_token", "client_id": account.clientID])
                    // One bounded retry for infrastructure failures; local sign-out still completes offline.
                    for attempt in 0..<2 {
                        let (_, response) = try await self.session.data(for: request)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if status == 200 { revoked = true; break }
                        if status < 500 || attempt == 1 { break }
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch { revoked = false }
            }
            account.clearTokens(); try self.store(account)
            self.models = []; self.needsReconnect = false
            self.message = revoked ? "연결을 해제했습니다. 계정 등록 정보는 다음 로그인을 위해 보관합니다." : "이 기기에서 연결을 해제했습니다. 원격 세션 해제는 확인하지 못했으므로 ChatGPT 설정에서도 앱 접근을 해제하세요."
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; message = nil
        operation = Task {
            defer { isBusy = false; operation = nil }
            do {
                let lock = try vault.lock()
                defer { withExtendedLifetime(lock) {} }
                try await action()
            } catch is CancellationError { message = "연결을 취소했습니다." }
            catch { if Task.isCancelled { message = "연결을 취소했습니다." } else { report(error) } }
        }
    }

    private func report(_ error: Error) {
        // Foundation networking errors can include URLs. Never expose them or arbitrary server text.
        message = (error as? ChatGPTError)?.errorDescription ?? "네트워크 또는 저장소에 접근하지 못했습니다. 연결 상태를 확인하고 다시 시도하세요."
    }

    private func reload() throws {
        credentials = try vault.load()
        publish()
    }

    private func save() throws { try vault.save(credentials); publish() }
    private func publish() {
        if activeID != credentials.activeID { models = [] }
        accounts = credentials.accounts; activeID = credentials.activeID
    }

    private func store(_ account: ChatGPTAccount, activate: Bool = false) throws {
        var updated = credentials
        if let index = updated.accounts.firstIndex(where: { $0.id == account.id }) { updated.accounts[index] = account }
        else { updated.accounts.append(account) }
        if activate {
            updated.activeID = account.id
            if updated.pendingClientID == account.id { updated.pendingClientID = nil }
        }
        try vault.save(updated)
        credentials = updated; publish()
    }

    private func accessToken() async throws -> String {
        guard let account = active, account.canUsePlan, let token = account.accessToken else { throw ChatGPTError.denied }
        if account.expiresAt.timeIntervalSinceNow > 60 { return token }
        guard let refresh = account.refreshToken else { needsReconnect = true; throw ChatGPTError.denied }
        do {
            let tokens: ChatGPTTokenResponse = try await postToken(["grant_type": "refresh_token", "client_id": account.clientID,
                                                                  "refresh_token": refresh, "resource": ChatGPTAuthorization.resource])
            let verified: ChatGPTIdentity
            if let id = tokens.id_token { verified = try await identity(id, clientID: account.clientID, nonce: account.nonce, requireNonce: false) }
            else { verified = ChatGPTIdentity(subject: account.subject, email: account.email) }
            let renewed = try tokens.account(clientID: account.clientID, identity: verified, nonce: account.nonce, previous: account)
            try store(renewed)
            guard renewed.canUsePlan else { throw ChatGPTError.denied }
            guard let access = renewed.accessToken else { throw ChatGPTError.denied }
            return access
        } catch {
            if let failure = error as? ChatGPTError, failure.invalidatesRefresh {
                var invalid = account; invalid.clearTokens(); try store(invalid); needsReconnect = true
            }
            throw error
        }
    }

    private func fetchModels() async throws {
        let token = try await accessToken()
        var request = URLRequest(url: URL(string: ChatGPTAuthorization.resource + "/models")!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let data = try await data(request, phase: .models)
        struct Catalog: Decodable { let models: [ChatGPTModel] }
        let available = try JSONDecoder().decode(Catalog.self, from: data).models.filter { $0.visibility == "list" }
        guard Set(available.map(\.id)).count == available.count else { throw ChatGPTError.invalidResponse }
        models = available
        guard var account = active else { throw ChatGPTError.invalidAuthorization }
        if !available.contains(where: { $0.id == account.model }) { account.model = available.first?.id; try store(account) }
        if available.isEmpty { message = "현재 계정에서 사용할 수 있는 모델이 없습니다." }
    }

    private func identity(_ token: String, clientID: String, nonce: String, requireNonce: Bool = true) async throws -> ChatGPTIdentity {
        let config = try await discovery()
        guard let endpoint = config["jwks_uri"] as? String, trustedAuthURL(endpoint) else { throw ChatGPTError.invalidIdentity }
        let keys = try await data(URLRequest(url: URL(string: endpoint)!), phase: .signingKeys)
        return try ChatGPTIdentityVerifier.verify(token, jwks: keys, clientID: clientID, nonce: nonce, requireNonce: requireNonce)
    }

    private func discovery() async throws -> [String: Any] {
        let data = try await data(URLRequest(url: URL(string: ChatGPTAuthorization.issuer + "/.well-known/openid-configuration")!), phase: .discovery)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["issuer"] as? String == ChatGPTAuthorization.issuer else { throw ChatGPTError.invalidIdentity }
        return result
    }

    private func trustedAuthURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" && url.host == "auth.openai.com" && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    private func postToken<T: Decodable>(_ fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: ChatGPTAuthorization.issuer + "/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ChatGPTAuthorization.form(fields)
        return try JSONDecoder().decode(T.self, from: await data(request, phase: fields["grant_type"] == "refresh_token" ? .refresh : .codeExchange))
    }

    private func data(_ request: URLRequest, phase: ChatGPTRequestPhase) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2_097_152 else { throw ChatGPTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw serviceError(http, data: data, phase: phase) }
        return data
    }

    private func serviceError(_ response: HTTPURLResponse, data: Data, phase: ChatGPTRequestPhase) -> ChatGPTError {
        .httpFailure(status: response.statusCode, data: data,
                     requestID: response.value(forHTTPHeaderField: "x-request-id") ?? response.value(forHTTPHeaderField: "openai-request-id"), phase: phase)
    }
}

private final class ChatGPTNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
