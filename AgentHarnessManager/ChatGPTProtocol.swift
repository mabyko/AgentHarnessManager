import CryptoKit
import Foundation
import Security

enum ChatGPTRequestPhase: String {
    case codeExchange = "인증 코드 교환"
    case refresh = "토큰 갱신"
    case discovery = "인증 서버 확인"
    case signingKeys = "계정 서명 키 확인"
    case models = "모델 목록 조회"
    case test = "연결 테스트"
}

enum ChatGPTError: LocalizedError {
    case invalidAuthorization, invalidIdentity, invalidResponse, interrupted, denied, timedOut, busy
    case keychain(OSStatus)
    case service(Int, String?, String?)
    indirect case request(ChatGPTRequestPhase, ChatGPTError, String?)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorization: return "로그인 응답을 검증하지 못했습니다. 다시 연결하세요."
        case .invalidIdentity: return "ChatGPT 계정의 서명 또는 신원을 검증하지 못했습니다."
        case .invalidResponse: return "ChatGPT 응답 형식을 확인하지 못했습니다."
        case .interrupted: return "연결 테스트가 완료되기 전에 응답이 끊겼습니다."
        case .denied: return "ChatGPT 연결이 취소되었거나 권한이 허용되지 않았습니다."
        case .timedOut: return "로그인 대기 시간이 지났습니다. 다시 연결하세요."
        case .busy: return "다른 앱 인스턴스에서 ChatGPT 연결을 변경하고 있습니다. 잠시 후 다시 시도하세요."
        case .keychain(let status):
            if [errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed, errSecUserCanceled].contains(status) {
                return "키체인 접근 승인이 필요해 ChatGPT 연결을 중단했습니다 (\(status)). 앱 업데이트로 서명이 바뀐 경우 기존 항목에 접근하지 못할 수 있습니다. 기존 인증 정보는 보존했습니다."
            }
            return "키체인에 접근하지 못했습니다 (\(status)). 기존 인증 정보는 덮어쓰지 않았습니다."
        case .request(let phase, let failure, let parameter):
            return phase.rawValue + (parameter.map { " · 관련 항목: " + $0 } ?? "") + "\n" + (failure.errorDescription ?? "요청에 실패했습니다.")
        case .service(let status, let code, let requestID):
            let reason: String
            switch code {
            case "subscription_sharing_user_not_eligible": reason = "이 계정 또는 워크스페이스에서 ChatGPT 요금제를 사용할 수 없습니다."
            case "subscription_sharing_usage_limit_exceeded": reason = "사용 한도에 도달했습니다. ChatGPT 설정에서 사용량을 확인하세요."
            case "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused", "subscription_sharing_invalid_user": reason = "인증이 만료되었거나 해제되었습니다. 다시 연결하세요."
            case "invalid_client": reason = "앱의 OAuth 등록을 확인해야 합니다."
            case "invalid_request", "invalid_request_error": reason = "요청 형식 또는 필수 항목을 확인해야 합니다."
            case "invalid_target": reason = "요청한 리소스에 대한 인증을 확인해야 합니다."
            case "unauthorized_client", "unsupported_grant_type": reason = "앱 등록에서 허용된 인증 방식을 확인해야 합니다."
            default:
                switch status {
                case 401: reason = "ChatGPT 인증 또는 사용 권한을 확인하세요."
                case 403: reason = "계정·지역·워크스페이스 정책에 따라 요청이 허용되지 않았습니다."
                case 429: reason = "요청 또는 사용 한도에 도달했습니다. ChatGPT 설정에서 확인하세요."
                case 500...599: reason = "ChatGPT 서비스를 일시적으로 사용할 수 없습니다. 나중에 다시 시도하세요."
                default: reason = "ChatGPT 요청에 실패했습니다."
                }
            }
            // Only allow machine identifiers into diagnostics, never response bodies or token-bearing URLs.
            let safe = [code, requestID].compactMap { value -> String? in
                guard let value, value.count <= 160,
                      value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0) }) else { return nil }
                return value
            }
            return reason + " (HTTP \(status))" + (safe.isEmpty ? "" : " · " + safe.joined(separator: " · "))
        }
    }

    var invalidatesRefresh: Bool {
        if case .request(_, let failure, _) = self { return failure.invalidatesRefresh }
        guard case .service(_, let code, _) = self else { return false }
        return ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code ?? "")
    }

    static func httpFailure(status: Int, data: Data, requestID: String?, phase: ChatGPTRequestPhase) -> ChatGPTError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        // OAuth uses a string error; Responses commonly uses an object. Never display raw descriptions.
        let candidate = (object?["error"] as? String) ?? error?["code"] as? String ?? error?["type"] as? String ?? object?["code"] as? String
        let code = candidate.flatMap { value -> String? in
            value.range(of: "^[a-zA-Z][a-zA-Z0-9_]{0,99}$", options: .regularExpression) == nil ? nil : value
        }
        let allowed = ["client_id", "grant_type", "code", "code_verifier", "redirect_uri", "resource", "scope", "ext_agent_host_id", "nonce", "model", "input", "store", "stream"]
        let explicit = (error?["param"] as? String) ?? object?["param"] as? String
        var parameters: [String] = []
        if let explicit, allowed.contains(explicit) { parameters = [explicit] }
        else {
            let description = (object?["error_description"] as? String) ?? error?["message"] as? String ?? object?["detail"] as? String ?? ""
            // Extract only known parameter names, never the surrounding text, values, URLs, or credentials.
            parameters = allowed.filter { name in
                description.range(of: "(?<![a-zA-Z0-9_])" + name + "(?![a-zA-Z0-9_])", options: .regularExpression) != nil
            }
        }
        return .request(phase, .service(status, code, requestID), parameters.isEmpty ? nil : parameters.joined(separator: ", "))
    }
}

struct ChatGPTAccount: Codable, Identifiable {
    let clientID: String
    let subject: String
    var email: String?
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var nonce: String
    var scopes: [String]
    var expiresAt: Date
    var model: String?
    var welcomed = false

    var id: String { clientID }
    var signedIn: Bool { idToken != nil }
    var canUsePlan: Bool { signedIn && scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke") }
    var label: String { "\(email ?? "ChatGPT 계정") · \(clientID.suffix(8))" }

    mutating func clearTokens() {
        accessToken = nil; refreshToken = nil; idToken = nil
        scopes = []; expiresAt = .distantPast
    }
}

struct ChatGPTCredentials: Codable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var accounts: [ChatGPTAccount] = []
    var activeID: String?
    var pendingClientID: String?
}

struct ChatGPTTokenResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let id_token: String?
    let token_type: String?
    let expires_in: Double?
    let scope: String?

    func account(clientID: String, identity: ChatGPTIdentity, nonce: String, previous: ChatGPTAccount? = nil, now: Date = .now) throws -> ChatGPTAccount {
        let scopes = scope.map { $0.split(separator: " ").map(String.init) } ?? previous?.scopes ?? []
        let needsAccess = scopes.contains("chatgpt.tokens.use.direct")
        let lifetime = expires_in ?? 0
        guard (!needsAccess || (token_type?.lowercased() == "bearer" && access_token?.isEmpty == false && lifetime.isFinite && lifetime > 0 && lifetime <= 31_536_000)),
              previous == nil || (previous?.subject == identity.subject && previous?.clientID == clientID) else { throw ChatGPTError.invalidIdentity }
        // A refresh can omit scope and the ID token; retain only this registration's previous values.
        return ChatGPTAccount(clientID: clientID, subject: identity.subject, email: identity.email ?? previous?.email,
                              accessToken: access_token, refreshToken: refresh_token ?? previous?.refreshToken,
                              idToken: id_token ?? previous?.idToken, nonce: nonce,
                              scopes: scopes, expiresAt: now.addingTimeInterval(lifetime), model: previous?.model, welcomed: previous?.welcomed ?? false)
    }
}

struct ChatGPTIdentity {
    let subject: String
    let email: String?
}

struct ChatGPTModel: Decodable, Identifiable {
    let slug: String
    let display_name: String
    let visibility: String
    var id: String { slug }
}

struct ChatGPTAuthorization {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    let state: String
    let nonce: String
    let verifier: String
    let createdAt: Date

    init() throws {
        state = try Self.random(); nonce = try Self.random(); verifier = try Self.random(count: 64)
        createdAt = .now
    }

    var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }

    func url(redirect: URL, hostID: String, account: ChatGPTAccount?, consent: Bool, pendingClientID: String? = nil) -> URL {
        var items = ["client_id": account?.clientID ?? pendingClientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
                     "response_type": "code", "redirect_uri": redirect.absoluteString, "scope": Self.scopes,
                     "resource": Self.resource, "state": state, "nonce": nonce,
                     "code_challenge_method": "S256", "code_challenge": challenge]
        if let account {
            if let hint = account.idToken { items["id_token_hint"] = hint }
            if let email = account.email { items["login_hint"] = email }
        } else if pendingClientID == nil { items["agent_name_hint"] = "Agent Harness Manager" }
        if consent { items["prompt"] = "consent" }
        var url = URLComponents(string: Self.issuer + "/api/accounts/authorize")!
        url.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }

    func callback(_ url: URL, redirect: URL, account: ChatGPTAccount?, now: Date = .now, pendingClientID: String? = nil) throws -> (code: String, clientID: String) {
        guard now.timeIntervalSince(createdAt) < 600, now >= createdAt,
              url.scheme == redirect.scheme, url.host == "127.0.0.1", url.port == redirect.port,
              url.path == redirect.path, url.user == nil, url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state else { throw ChatGPTError.invalidAuthorization }
        if items.contains(where: { $0.name == "error" }) { throw ChatGPTError.denied }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              let client = items.first(where: { $0.name == "client_id" })?.value ?? account?.clientID ?? pendingClientID,
              !client.isEmpty, client != "dynamic_agent_client", client.count <= 256,
              client.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              account == nil || account?.clientID == client,
              pendingClientID == nil || pendingClientID == client else { throw ChatGPTError.invalidAuthorization }
        return (code, client)
    }

    private static func random(count: Int = 32) throws -> String {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw ChatGPTError.keychain(status) }
        return data.base64URL
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }
}

enum ChatGPTIdentityVerifier {
    static func verify(_ token: String, jwks: Data, clientID: String, nonce: String, requireNonce: Bool = true, now: Date = .now) throws -> ChatGPTIdentity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.utf8.count < 65_536,
              let headerData = Data(base64URL: String(parts[0])),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String,
              let keySet = try JSONSerialization.jsonObject(with: jwks) as? [String: Any],
              let keys = keySet["keys"] as? [[String: Any]] else { throw ChatGPTError.invalidIdentity }
        let matches = keys.filter { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }
        guard matches.count == 1, let jwk = matches.first,
              jwk["alg"] == nil || jwk["alg"] as? String == "RS256",
              jwk["use"] == nil || jwk["use"] as? String == "sig",
              let n = jwk["n"] as? String, let modulus = Data(base64URL: n),
              let e = jwk["e"] as? String, let exponent = Data(base64URL: e),
              modulus.count >= 256, modulus.count <= 1024, !exponent.isEmpty, exponent.count <= 8 else { throw ChatGPTError.invalidIdentity }
        let der = tagged(0x30, integer(modulus) + integer(exponent))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              claims["iss"] as? String == ChatGPTAuthorization.issuer,
              let sub = claims["sub"] as? String, !sub.isEmpty,
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970 - 5,
              let iat = claims["iat"] as? Double, iat <= now.timeIntervalSince1970 + 5,
              (claims["nonce"] as? String == nonce || (!requireNonce && claims["nonce"] == nil)) else { throw ChatGPTError.invalidIdentity }
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(clientID),
              audiences.count <= 1 || claims["azp"] as? String == clientID,
              claims["azp"] == nil || claims["azp"] as? String == clientID,
              (claims["nbf"] as? Double ?? 0) <= now.timeIntervalSince1970 + 5 else { throw ChatGPTError.invalidIdentity }
        return ChatGPTIdentity(subject: sub, email: claims["email"] as? String)
    }

    private static func integer(_ data: Data) -> Data {
        var bytes = Data(data.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = Data([0]) }
        if bytes[bytes.startIndex] & 0x80 != 0 { bytes.insert(0, at: bytes.startIndex) }
        return tagged(0x02, bytes)
    }

    private static func tagged(_ tag: UInt8, _ data: Data) -> Data {
        var size = data.count
        var length: [UInt8] = []
        repeat { length.insert(UInt8(size & 255), at: 0); size >>= 8 } while size > 0
        return Data([tag] + (data.count < 128 ? [UInt8(data.count)] : [0x80 | UInt8(length.count)] + length)) + data
    }
}

struct ChatGPTResponseStream {
    private(set) var completed = false
    private(set) var text = ""
    private var dataLines: [String] = []

    mutating func line(_ line: String) throws {
        if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        guard line.isEmpty, !dataLines.isEmpty else { return }
        let data = dataLines.joined(separator: "\n"); dataLines = []
        guard data != "[DONE]" else { return }
        guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = object["type"] as? String else { throw ChatGPTError.invalidResponse }
        switch type {
        case "response.output_text.delta":
            if let delta = object["delta"] as? String { text += String(delta.prefix(max(0, 500 - text.count))) }
        case "response.completed": completed = true
        case "error", "response.failed":
            let response = object["response"] as? [String: Any]
            let error = (response?["error"] as? [String: Any]) ?? object["error"] as? [String: Any] ?? object
            throw ChatGPTError.service(200, error["code"] as? String, nil)
        case "response.incomplete": throw ChatGPTError.interrupted
        default: break
        }
    }

    mutating func finish() throws -> String {
        try line("")
        guard completed else { throw ChatGPTError.interrupted }
        return text
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        self.init(base64Encoded: base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - base64URL.count % 4) % 4))
    }
}
