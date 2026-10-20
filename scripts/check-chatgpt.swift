import CryptoKit
import Foundation
import Security
import Synchronization

private final class MockChatGPT: URLProtocol, @unchecked Sendable {
    struct BrowserFixture: Sendable {
        let authorization: URL
        let idToken: String
        let jwks: Data
    }
    static let mode = Mutex("success")
    static let requests = Mutex<[URLRequest]>([])
    static let browser = Mutex<BrowserFixture?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let mode = Self.mode.withLock { $0 }
        let path = request.url!.path
        var status = 200
        let body: String
        switch path {
        case "/api/accounts/oauth/token":
            if mode == "browser400" { status = 400; body = "{\"error\":\"invalid_request\",\"error_description\":\"Synthetic private details: check resource\"}" }
            else if mode == "browser", let fixture = Self.browser.withLock({ $0 }) {
                let payload: Data
                if let bytes = request.httpBody { payload = bytes }
                else {
                    let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                    var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
                    payload = bytes
                }
                var form = URLComponents()
                form.percentEncodedQuery = String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
                let fields = Dictionary(uniqueKeysWithValues: form.queryItems!.map { ($0.name, $0.value ?? "") })
                let query = URLComponents(url: fixture.authorization, resolvingAgainstBaseURL: false)!.queryItems!
                let authorization = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
                let valid = fields["grant_type"] == "authorization_code" && fields["client_id"] == "oaiapp_browser"
                    && fields["code"] == "synthetic+authorization/code="
                    && fields["redirect_uri"] == authorization["redirect_uri"]
                    && fields["resource"] == "https://api.openai.com/v1"
                    && fields["code_verifier"].map { Data(SHA256.hash(data: Data($0.utf8))).base64URL } == authorization["code_challenge"]
                    && request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
                if valid {
                    body = String(decoding: try! JSONSerialization.data(withJSONObject: ["access_token": "fixture-browser-access", "refresh_token": "fixture-browser-refresh", "id_token": fixture.idToken, "token_type": "Bearer", "expires_in": 3600, "scope": ChatGPTAuthorization.scopes]), as: UTF8.self)
                } else { status = 400; body = "{\"error\":\"invalid_grant\"}" }
            }
            else if mode == "oauth400" { status = 400; body = "{\"error\":\"invalid_request\",\"error_description\":\"Synthetic private code and callback URL must not be displayed\"}" }
            else if mode == "revoked-flat" { status = 400; body = "{\"error\":\"invalid_grant\"}" }
            else if mode == "revoked" { status = 401; body = "{\"error\":{\"code\":\"invalid_grant\"}}" }
            else if mode == "offline" { status = 503; body = "{\"detail\":\"synthetic private diagnostic\"}" }
            else { body = "{\"access_token\":\"fixture-renewed\",\"refresh_token\":\"fixture-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}" }
        case "/v1/models":
            body = "{\"models\":[{\"slug\":\"fixture-model\",\"display_name\":\"Fixture\",\"visibility\":\"list\"},{\"slug\":\"hidden\",\"display_name\":\"Hidden\",\"visibility\":\"hidden\"}]}"
        case "/v1/responses":
            body = mode == "limit" ? "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n" : "data: {\"type\":\"response.output_text.delta\",\"delta\":\"OK\"}\n\ndata: {\"type\":\"response.completed\"}\n\n"
        case "/.well-known/openid-configuration":
            body = "{\"issuer\":\"https://auth.openai.com\",\"revocation_endpoint\":\"https://auth.openai.com/revoke\",\"jwks_uri\":\"https://auth.openai.com/.well-known/jwks.json\"}"
        case "/.well-known/jwks.json": body = String(decoding: Self.browser.withLock { $0!.jwks }, as: UTF8.self)
        case "/revoke": body = ""
        default: status = 404; body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": path == "/v1/responses" ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor private final class MemoryCredentials: ChatGPTCredentialStorage {
    var value: ChatGPTCredentials
    var loadError: ChatGPTError?
    var saves = 0
    let lockURL: URL
    init(_ value: ChatGPTCredentials, lockURL: URL) { self.value = value; self.lockURL = lockURL }
    func load() throws -> ChatGPTCredentials {
        if let loadError { throw loadError }
        return value
    }
    func save(_ credentials: ChatGPTCredentials) throws { saves += 1; value = credentials }
    func lock() throws -> ChatGPTSessionLock { try ChatGPTSessionLock(url: lockURL) }
}

@main
struct ChatGPTCheck {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Invalid authentication was accepted") } catch {}
    }

    @MainActor static func main() async throws {
        func interactionAllowed() -> Bool {
            var allowed = DarwinBoolean(false)
            precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
            return allowed.boolValue
        }
        let originalInteraction = interactionAllowed()
        try ChatGPTCredentialStore.withoutInteraction {
            precondition(!interactionAllowed(), "Keychain operations may unexpectedly display a password dialog")
            try ChatGPTCredentialStore.withoutInteraction { precondition(!interactionAllowed()) }
            precondition(!interactionAllowed(), "Nested access restored interaction too early")
        }
        precondition(interactionAllowed() == originalInteraction)
        rejects {
            try ChatGPTCredentialStore.withoutInteraction {
                precondition(!interactionAllowed())
                throw ChatGPTError.keychain(errSecInteractionNotAllowed)
            }
        }
        precondition(interactionAllowed() == originalInteraction, "Failed access changed the process UI policy")

        let tx = try ChatGPTAuthorization(), other = try ChatGPTAuthorization()
        precondition(tx.state != other.state && tx.verifier != other.verifier && tx.nonce != other.nonce)
        precondition(tx.verifier.count >= 43 && tx.challenge == Data(SHA256.hash(data: Data(tx.verifier.utf8))).base64URL)
        let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let authorize = tx.url(redirect: redirect, hostID: "urn:uuid:fixture", account: nil, consent: false)
        let query = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.contains { $0.name == "client_id" && $0.value == "dynamic_agent_client" })
        precondition(query.contains { $0.name == "agent_name_hint" && $0.value == "Agent Harness Manager" })
        precondition(!query.contains { $0.name == "client_secret" })
        let retryQuery = URLComponents(url: tx.url(redirect: redirect, hostID: "urn:uuid:fixture", account: nil, consent: false, pendingClientID: "oaiapp_pending"), resolvingAgainstBaseURL: false)!.queryItems!
        precondition(retryQuery.contains { $0.name == "client_id" && $0.value == "oaiapp_pending" })
        precondition(!retryQuery.contains { $0.name == "agent_name_hint" })
        let callback = URL(string: redirect.absoluteString + "?state=\(tx.state)&code=fixture&client_id=oaiapp_fixture")!
        let validCallback = try tx.callback(callback, redirect: redirect, account: nil)
        precondition(validCallback.clientID == "oaiapp_fixture")
        rejects { _ = try tx.callback(callback, redirect: redirect, account: nil, pendingClientID: "oaiapp_other") }
        for suffix in ["?state=wrong&code=x&client_id=oaiapp_fixture", "?state=\(tx.state)&code=x", "?state=\(tx.state)&state=\(tx.state)&code=x&client_id=oaiapp_fixture", "?state=\(tx.state)&error=access_denied"] {
            rejects { _ = try tx.callback(URL(string: redirect.absoluteString + suffix)!, redirect: redirect, account: nil) }
        }
        rejects { _ = try tx.callback(callback, redirect: redirect, account: nil, now: tx.createdAt.addingTimeInterval(601)) }
        rejects { _ = try tx.callback(URL(string: callback.absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))!, redirect: redirect, account: nil) }

        let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(key)!
        let rawKey = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var cursor = 0
        func element() -> Data {
            cursor += 1
            var length = Int(rawKey[cursor]); cursor += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f; length = 0
                for _ in 0..<count { length = (length << 8) | Int(rawKey[cursor]); cursor += 1 }
            }
            let bytes = Data(rawKey[cursor..<(cursor + length)]); cursor += length; return bytes
        }
        // Skip only the enclosing sequence header, then read its two ASN.1 integers.
        cursor = rawKey[1] & 0x80 == 0 ? 2 : 2 + Int(rawKey[1] & 0x7f)
        let modulus = Data(element().drop(while: { $0 == 0 })), exponent = element()
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kty": "RSA", "kid": "fixture", "alg": "RS256", "n": modulus.base64URL, "e": exponent.base64URL]]])
        let now = Date()
        let claims: [String: Any] = ["iss": ChatGPTAuthorization.issuer, "sub": "fixture-subject", "aud": "oaiapp_fixture", "exp": now.timeIntervalSince1970 + 600, "iat": now.timeIntervalSince1970, "nonce": tx.nonce, "email": "fixture@example.invalid"]
        func signed(_ claims: [String: Any], algorithm: String = "RS256") throws -> String {
            let header = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "kid": "fixture"]).base64URL
            let payload = try JSONSerialization.data(withJSONObject: claims).base64URL
            let message = header + "." + payload
            let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(message.utf8) as CFData, nil)! as Data
            return message + "." + signature.base64URL
        }
        let token = try signed(claims)
        let identity = try ChatGPTIdentityVerifier.verify(token, jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce, now: now)
        precondition(identity.subject == "fixture-subject")
        for (name, value) in [("iss", "https://example.invalid" as Any), ("aud", "other" as Any), ("nonce", "other" as Any), ("exp", now.timeIntervalSince1970 - 60 as Any), ("iat", now.timeIntervalSince1970 + 60 as Any), ("sub", "" as Any)] {
            var changed = claims; changed[name] = value
            rejects { _ = try ChatGPTIdentityVerifier.verify(signed(changed), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce, now: now) }
        }
        rejects { _ = try ChatGPTIdentityVerifier.verify(signed(claims, algorithm: "none"), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce) }
        rejects { _ = try ChatGPTIdentityVerifier.verify(token + "x", jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce) }
        var withoutNonce = claims; withoutNonce.removeValue(forKey: "nonce")
        rejects { _ = try ChatGPTIdentityVerifier.verify(signed(withoutNonce), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce) }
        _ = try ChatGPTIdentityVerifier.verify(signed(withoutNonce), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce, requireNonce: false)
        var multipleAudiences = claims; multipleAudiences["aud"] = ["oaiapp_fixture", "other"]
        rejects { _ = try ChatGPTIdentityVerifier.verify(signed(multipleAudiences), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce) }
        multipleAudiences["azp"] = "oaiapp_fixture"
        _ = try ChatGPTIdentityVerifier.verify(signed(multipleAudiences), jwks: jwks, clientID: "oaiapp_fixture", nonce: tx.nonce)

        let initial = ChatGPTTokenResponse(access_token: "fixture-access", refresh_token: "fixture-refresh", id_token: token, token_type: "Bearer", expires_in: 3600, scope: ChatGPTAuthorization.scopes)
        var account = try initial.account(clientID: "oaiapp_fixture", identity: identity, nonce: tx.nonce)
        precondition(account.canUsePlan)
        let returning = URLComponents(url: tx.url(redirect: redirect, hostID: "urn:uuid:fixture", account: account, consent: false), resolvingAgainstBaseURL: false)!.queryItems!
        precondition(returning.contains { $0.name == "client_id" && $0.value == account.clientID })
        precondition(!returning.contains { $0.name == "agent_name_hint" || $0.name == "prompt" })
        rejects { _ = try tx.callback(URL(string: redirect.absoluteString + "?state=\(tx.state)&code=x&client_id=oaiapp_other")!, redirect: redirect, account: account) }
        let renewed = ChatGPTTokenResponse(access_token: "fixture-renewed", refresh_token: "fixture-rotated", id_token: nil, token_type: "Bearer", expires_in: 3600, scope: nil)
        let rotated = try renewed.account(clientID: account.id, identity: identity, nonce: tx.nonce, previous: account)
        precondition(rotated.refreshToken == "fixture-rotated" && rotated.idToken == token && rotated.canUsePlan)
        rejects { _ = try renewed.account(clientID: account.id, identity: ChatGPTIdentity(subject: "other", email: nil), nonce: tx.nonce, previous: account) }
        let identityOnly = ChatGPTTokenResponse(access_token: nil, refresh_token: nil, id_token: token, token_type: nil, expires_in: nil, scope: "openid email profile")
        let deniedPlan = try identityOnly.account(clientID: account.id, identity: identity, nonce: tx.nonce)
        precondition(deniedPlan.signedIn && !deniedPlan.canUsePlan)
        account.clearTokens()
        precondition(!account.signedIn && account.refreshToken == nil && account.id == "oaiapp_fixture")

        var stream = ChatGPTResponseStream()
        try stream.line("data: {\"type\":\"response.output_text.delta\",\"delta\":\"OK\"}"); try stream.line("")
        rejects { _ = try stream.finish() }
        try stream.line("data: {\"type\":\"response.completed\"}"); try stream.line("")
        let completedText = try stream.finish()
        precondition(completedText == "OK")
        for event in ["{\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}", "{\"type\":\"response.incomplete\"}"] {
            rejects { var failed = ChatGPTResponseStream(); try failed.line("data: " + event); try failed.line("") }
        }

        let lockFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-auth-\(UUID())")
        try FileManager.default.createDirectory(at: lockFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lockFolder) }
        var lock: ChatGPTSessionLock? = try ChatGPTSessionLock(url: lockFolder.appendingPathComponent("lock"))
        rejects { _ = try ChatGPTSessionLock(url: lockFolder.appendingPathComponent("lock")) }
        withExtendedLifetime(lock) {}; lock = nil
        _ = try ChatGPTSessionLock(url: lockFolder.appendingPathComponent("lock"))

        let server = ChatGPTLoopback()
        let address = try await server.start()
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let local = URLSession(configuration: config)
        let (_, notFound) = try await local.data(from: address.deletingLastPathComponent().appendingPathComponent("favicon.ico"))
        precondition((notFound as? HTTPURLResponse)?.statusCode == 404)
        let incoming = URL(string: address.absoluteString + "?code=synthetic-secret&state=fixture&client_id=oaiapp_fixture")!
        async let request = local.data(from: incoming)
        let received = try await server.wait()
        precondition(received == incoming)
        let (body, response) = try await request
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        precondition(!String(decoding: body, as: UTF8.self).contains("synthetic-secret"))
        server.stop()
        let cancelled = ChatGPTLoopback()
        _ = try await cancelled.start(); cancelled.stop()
        do { _ = try await cancelled.wait(); preconditionFailure("Cancelled listener returned successfully") } catch is CancellationError {}

        let dangerous = ChatGPTError.service(403, "credential?token=secret", "https://example.invalid/token").errorDescription!
        precondition(!dangerous.contains("secret") && !dangerous.contains("example.invalid"))
        let unsafeBody = Data("{\"error\":\"https://example.invalid/private-token\",\"error_description\":\"code_verifier=synthetic-secret at http://127.0.0.1:1455/auth/callback?code=private\"}".utf8)
        let sanitized = ChatGPTError.httpFailure(status: 400, data: unsafeBody, requestID: "fixture-request-id", phase: .codeExchange).errorDescription!
        precondition(sanitized.contains("code_verifier") && sanitized.contains("fixture-request-id"))
        precondition(!sanitized.contains("synthetic-secret") && !sanitized.contains("127.0.0.1") && !sanitized.contains("example.invalid"))

        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockChatGPT.self]
        let mockSession = URLSession(configuration: mockConfig)
        var expired = try initial.account(clientID: "oaiapp_fixture", identity: identity, nonce: tx.nonce)
        expired.expiresAt = .distantPast
        let memory = MemoryCredentials(ChatGPTCredentials(accounts: [expired], activeID: expired.id), lockURL: lockFolder.appendingPathComponent("controller-lock"))
        let connection = ChatGPTConnection(vault: memory, session: mockSession)
        connection.load()
        func waitForOperation() async throws {
            let deadline = Date().addingTimeInterval(5)
            while connection.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!connection.isBusy, "Mock connection timed out")
        }
        MockChatGPT.mode.withLock { $0 = "oauth400" }
        connection.refreshModels(); try await waitForOperation()
        precondition(connection.message?.contains("invalid_request") == true, "OAuth HTTP 400 lost the server error code: " + (connection.message ?? "No diagnostic"))
        precondition(connection.message?.contains("Synthetic private") == false)
        precondition(connection.message?.contains("토큰 갱신") == true)
        MockChatGPT.mode.withLock { $0 = "success" }
        connection.refreshModels(); try await waitForOperation()
        precondition(connection.models.map(\.id) == ["fixture-model"] && connection.selectedModel == "fixture-model")
        precondition(memory.value.accounts[0].refreshToken == "fixture-rotated")
        let calls = MockChatGPT.requests.withLock { $0 }
        precondition(calls.first?.url?.path == "/api/accounts/oauth/token")
        precondition(calls.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-renewed")
        connection.testConnection(); try await waitForOperation()
        precondition(connection.message?.contains("응답: OK") == true, connection.message ?? "No message")
        let inference = MockChatGPT.requests.withLock { $0.last! }
        let requestData: Data
        if let body = inference.httpBody { requestData = body }
        else {
            let stream = inference.httpBodyStream!; stream.open(); defer { stream.close() }
            var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
            requestData = body
        }
        let payload = try JSONSerialization.jsonObject(with: requestData) as! [String: Any]
        precondition(payload["store"] as? Bool == false && payload["stream"] as? Bool == true && payload["model"] as? String == "fixture-model")
        precondition((payload["input"] as? [[String: String]])?.first?["content"] == "Reply with exactly OK. This is a connection test.")
        MockChatGPT.mode.withLock { $0 = "limit" }
        connection.testConnection(); try await waitForOperation()
        precondition(connection.message?.contains("사용 한도") == true && memory.value.accounts[0].refreshToken != nil)
        memory.value.accounts[0].expiresAt = .distantPast
        MockChatGPT.mode.withLock { $0 = "offline" }
        connection.refreshModels(); try await waitForOperation()
        precondition(memory.value.accounts[0].refreshToken == "fixture-rotated")
        for mode in ["revoked", "revoked-flat"] {
            memory.value.accounts[0] = expired
            MockChatGPT.mode.withLock { $0 = mode }
            connection.refreshModels(); try await waitForOperation()
            precondition(memory.value.accounts[0].refreshToken == nil && memory.value.accounts[0].id == "oaiapp_fixture" && connection.needsReconnect)
        }
        memory.value.accounts[0] = try initial.account(clientID: "oaiapp_fixture", identity: identity, nonce: tx.nonce)
        MockChatGPT.mode.withLock { $0 = "success" }
        connection.signOut(); try await waitForOperation()
        precondition(memory.value.accounts[0].idToken == nil && memory.value.accounts.count == 1)
        precondition(MockChatGPT.requests.withLock { $0.last?.url?.path } == "/revoke")
        let secondAccount = try identityOnly.account(clientID: "oaiapp_other", identity: identity, nonce: tx.nonce)
        memory.value.accounts.append(secondAccount)
        connection.chooseAccount(secondAccount.id); try await waitForOperation()
        precondition(connection.activeID == secondAccount.id && connection.models.isEmpty && !connection.active!.canUsePlan)
        let requestCount = MockChatGPT.requests.withLock { $0.count }
        connection.refreshModels(); try await waitForOperation()
        precondition(MockChatGPT.requests.withLock { $0.count } == requestCount)
        precondition(memory.value.accounts.count == 2 && memory.value.accounts[0].id != memory.value.accounts[1].id)

        let browserVault = MemoryCredentials(ChatGPTCredentials(), lockURL: lockFolder.appendingPathComponent("browser-lock"))
        var callbackTask: Task<Void, Error>?
        var registrations: [String] = []
        let browserConnection = ChatGPTConnection(vault: browserVault, session: mockSession) { url in
            let fields = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            registrations.append(fields["client_id"]!)
            var browserClaims = claims
            browserClaims["nonce"] = fields["nonce"]!
            browserClaims["aud"] = "oaiapp_browser"
            MockChatGPT.browser.withLock { $0 = .init(authorization: url, idToken: try! signed(browserClaims), jwks: jwks) }
            var callback = URLComponents(string: fields["redirect_uri"]!)!
            callback.queryItems = [URLQueryItem(name: "state", value: fields["state"]!), URLQueryItem(name: "code", value: "synthetic+authorization/code=")]
            if fields["client_id"] == "dynamic_agent_client" { callback.queryItems!.append(URLQueryItem(name: "client_id", value: "oaiapp_browser")) }
            callbackTask = Task {
                let (_, response) = try await local.data(from: callback.url!)
                precondition((response as? HTTPURLResponse)?.statusCode == 200)
            }
            return true
        }
        func waitForBrowser() async throws {
            let deadline = Date().addingTimeInterval(5)
            while browserConnection.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!browserConnection.isBusy, "Mock browser sign-in timed out")
            try await callbackTask?.value
        }
        MockChatGPT.mode.withLock { $0 = "browser400" }
        browserConnection.connect(); try await waitForBrowser()
        precondition(browserConnection.message?.contains("인증 코드 교환") == true && browserConnection.message?.contains("invalid_request") == true)
        precondition(browserConnection.message?.contains("resource") == true && browserConnection.message?.contains("Synthetic private") == false)
        precondition(browserVault.value.pendingClientID == "oaiapp_browser" && browserVault.value.accounts.isEmpty)
        MockChatGPT.mode.withLock { $0 = "browser" }
        browserConnection.connect(); try await waitForBrowser()
        precondition(browserConnection.active?.canUsePlan == true, browserConnection.message ?? "Sign-in failed")
        precondition(browserConnection.models.map(\.id) == ["fixture-model"] && browserVault.value.pendingClientID == nil)
        precondition(registrations == ["dynamic_agent_client", "oaiapp_browser"])
        let savedHost = browserVault.value.hostID
        let savedToken = browserVault.value.accounts[0].accessToken
        let saveCount = browserVault.saves
        let blockedRequestCount = MockChatGPT.requests.withLock { $0.count }
        for status in [errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed, errSecUserCanceled] {
            browserVault.loadError = .keychain(status)
            browserConnection.load()
            precondition(browserConnection.message?.contains("기존 인증 정보는 보존") == true)
            browserConnection.connect(); try await waitForBrowser()
            precondition(browserConnection.message?.contains("키체인 접근 승인") == true)
            precondition(browserVault.value.hostID == savedHost && browserVault.value.accounts[0].accessToken == savedToken)
            precondition(browserVault.saves == saveCount && registrations.count == 2)
            precondition(MockChatGPT.requests.withLock { $0.count } == blockedRequestCount)
        }
        print("ChatGPT checks passed: noninteractive Keychain scope/restoration and blocked-access preservation, full browser/callback/code-exchange/signature/model flow, OAuth HTTP 400 diagnostics and redaction, retained-registration retry, PKCE, account/scope isolation, rotating refresh, flat/nested terminal errors, SSE/limits, fixed test payload, revocation, process lock and loopback cancellation. No real credentials or external AI requests used.")
    }
}
