import CryptoKit
import Foundation
import SkillCore

/// Offline GitHub responses for native and app-state lifecycle checks.
final class SkillUpdateFixture: URLProtocol, @unchecked Sendable {
    static func body(_ name: String) -> Data { Data("---\nname: \(name)\ndescription: Updated fixture\n---\nReviewed new version.\n".utf8) }
    static func sha(_ data: Data) -> String {
        var framed = Data("blob \(data.count)\0".utf8); framed.append(data)
        return Insecure.SHA1.hash(data: framed).map { String(format: "%02x", $0) }.joined()
    }
    static func service() -> GitHubSkillService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkillUpdateFixture.self]
        return GitHubSkillService(session: URLSession(configuration: configuration))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!, name = request.url!.path.contains("/fixture/keyboard/") ? "keyboard-demo" : "cli-example"
        if url.path.contains("/fixture/unavailable") {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let document = Self.body(name), resource = Data([1, 2, 3])
        let payload: Data
        if !url.path.contains("/commits/") && !url.path.contains("/git/") { payload = Data("{\"default_branch\":\"main\"}".utf8) }
        else if url.path.contains("/commits/") { payload = Data("{\"sha\":\"\(String(repeating: "a", count: 40))\"}".utf8) }
        else if url.path.contains("/git/trees/") {
            var items: [[String: Any]] = [("SKILL.md", document), ("resource.bin", resource)].map { file, data in
                ["path": "skills/\(name)/" + file, "mode": "100644", "type": "blob", "sha": Self.sha(data), "size": data.count]
            }
            items.append(["path": "skills/\(name)", "mode": "040000", "type": "tree", "sha": String(repeating: "c", count: 40)])
            payload = try! JSONSerialization.data(withJSONObject: ["tree": items, "truncated": false, "sha": String(repeating: "b", count: 40)])
        } else if url.lastPathComponent == Self.sha(document) { payload = document }
        else { payload = resource }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
