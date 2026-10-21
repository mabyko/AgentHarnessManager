import CryptoKit
import Foundation
import XCTest
@testable import SkillCore

final class GitHubSkillTests: XCTestCase {
    private let repository = SourceRepository("example/skills")!
    private func tree(_ entries: [[String: Any]], truncated: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tree": entries, "truncated": truncated])
    }
    private func item(_ path: String, data: Data = Data(), mode: String = "100644") -> [String: Any] {
        var framed = Data("blob \(data.count)\0".utf8); framed.append(data)
        return ["path": path, "mode": mode, "type": "blob", "size": data.count,
                "sha": Insecure.SHA1.hash(data: framed).map { String(format: "%02x", $0) }.joined()]
    }

    func testFindsRootAndNestedSkillsAndRejectsIncompleteOrUnsafeTrees() throws {
        let data = try tree([item("SKILL.md"), item("skills/example/SKILL.md"), item("docs/guide.md")])
        let listing = try GitHubSkillService.parse(data, repository: repository)
        XCTAssertEqual(listing.skills.map(\.path), ["", "skills/example"])
        XCTAssertEqual(listing.skills.map(\.name), ["skills", "example"])
        for path in ["../escape/SKILL.md", "/absolute/SKILL.md", "a//b/SKILL.md", "a\\b/SKILL.md", "a/.git/SKILL.md"] {
            XCTAssertThrowsError(try GitHubSkillService.parse(tree([item(path)]), repository: repository))
        }
        XCTAssertThrowsError(try GitHubSkillService.parse(tree([item("SKILL.md")], truncated: true), repository: repository))
        XCTAssertThrowsError(try GitHubSkillService.parse(tree([item("README.md")]), repository: repository))
        XCTAssertThrowsError(try GitHubSkillService.parse(tree([item("SKILL.md"), item("SKILL.md")]), repository: repository))
    }

    func testDownloadRejectsLinksAndOversizeBeforeNetworking() async throws {
        for resource in [item("example/link", mode: "120000"),
                         ["path": "example/large.bin", "mode": "100644", "type": "blob", "sha": String(repeating: "a", count: 40), "size": 65 * 1_024 * 1_024]] {
            let listing = try GitHubSkillService.parse(tree([item("example/SKILL.md"), resource]), repository: repository)
            do { _ = try await GitHubSkillService().download(listing.skills[0], from: listing); XCTFail("Must reject unsafe resource") }
            catch { XCTAssertTrue(error.localizedDescription.contains("64 MiB")) }
        }
    }

    func testInvalidRepositoryURLsNeverReachNetwork() async throws {
        for input in ["https://example.com/owner/repo", "https://github.com/owner/repo/tree/main", "https://token@github.com/owner/repo", "file:///tmp/repo"] {
            do { _ = try await GitHubSkillService().list(repository: input); XCTFail("Must reject invalid URL") }
            catch { XCTAssertTrue(error.localizedDescription.contains("공개 GitHub")) }
        }
    }
}
