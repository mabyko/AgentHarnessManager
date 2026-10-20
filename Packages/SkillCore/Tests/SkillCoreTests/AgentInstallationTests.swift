import Foundation
import XCTest
@testable import SkillCore

final class AgentInstallationTests: XCTestCase {
    func testSkillFoldersDoNotImplyAnInstalledAgent() throws {
        let fixture = try InstallationFixture(); defer { fixture.remove() }
        for path in [".agents/skills", ".claude/skills", ".grok/skills", ".cursor"] {
            try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let detected = fixture.detector.scan()
        XCTAssertEqual(detected.count, 8)
        XCTAssertTrue(detected.values.allSatisfy { !$0.isInstalled })
    }

    func testExecutablesAndSymlinksAreDetectedWithoutRunningThem() throws {
        let fixture = try InstallationFixture(); defer { fixture.remove() }
        let executable = try fixture.executable("codex")
        try FileManager.default.createSymbolicLink(at: fixture.bin.appendingPathComponent("claude"), withDestinationURL: executable)
        try fixture.executable("antigravity")
        try fixture.executable("cursor-agent")
        try Data("not executable".utf8).write(to: fixture.bin.appendingPathComponent("pi"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.bin.appendingPathComponent("pi").path)
        try FileManager.default.createDirectory(at: fixture.bin.appendingPathComponent("devin"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: fixture.bin.appendingPathComponent("grok"), withDestinationURL: fixture.root.appendingPathComponent("missing"))
        let detected = fixture.detector.scan()
        for target in [AgentConnectionTarget.codex, .claudeCode, .antigravity, .cursor] {
            XCTAssertTrue(try XCTUnwrap(detected[target]).isInstalled)
        }
        for target in [AgentConnectionTarget.pi, .devin, .grokBuild] {
            XCTAssertFalse(try XCTUnwrap(detected[target]).isInstalled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.marker.path), "Installation checks must never execute an agent")
    }

    func testValidAppBundlesAreDistinctFromCLIReadinessAndStaleBundles() throws {
        let fixture = try InstallationFixture(); defer { fixture.remove() }
        let codex = try fixture.application("Codex")
        try fixture.application("Cursor")
        try FileManager.default.createDirectory(at: fixture.apps.appendingPathComponent("Antigravity.app"), withIntermediateDirectories: true)
        var detected = fixture.detector.scan()
        let appOnly = try XCTUnwrap(detected[.codex])
        XCTAssertTrue(appOnly.isInstalled)
        XCTAssertNil(appOnly.executableURL)
        XCTAssertFalse(appOnly.canInstallConnection(for: .codex), "CLI-managed registrations still require a CLI")
        XCTAssertTrue(try XCTUnwrap(detected[.cursor]).canInstallConnection(for: .cursor))
        XCTAssertFalse(try XCTUnwrap(detected[.antigravity]).isInstalled)
        try FileManager.default.removeItem(at: codex.appendingPathComponent("Contents/MacOS/test-agent"))
        detected = fixture.detector.scan()
        XCTAssertFalse(try XCTUnwrap(detected[.codex]).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.marker.path))
    }

    func testAbsolutePATHOrderAndUserFallbackDirectories() throws {
        let fixture = try InstallationFixture(); defer { fixture.remove() }
        try fixture.executable("codex")
        let local = fixture.root.appendingPathComponent(".opencode/bin")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let openCode = local.appendingPathComponent("opencode")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: openCode)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: openCode.path)
        let detector = AgentInstallationDetector(home: fixture.root, environment: ["PATH": "relative::" + fixture.bin.path])
        XCTAssertEqual(detector.findExecutable("codex"), fixture.bin.appendingPathComponent("codex"))
        XCTAssertEqual(detector.findExecutable("opencode"), openCode)
    }
}

private struct InstallationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-installation-" + UUID().uuidString)
    var bin: URL { root.appendingPathComponent("bin") }
    var apps: URL { root.appendingPathComponent("Applications") }
    var marker: URL { root.appendingPathComponent("agent-was-executed") }
    var detector: AgentInstallationDetector { AgentInstallationDetector(executableDirectories: [bin], applicationDirectories: [apps]) }

    init() throws {
        for path in [bin, apps] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
    }
    @discardableResult func executable(_ name: String) throws -> URL {
        let url = bin.appendingPathComponent(name)
        try Data(("#!/bin/sh\ntouch '" + marker.path + "'\nexit 99\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    @discardableResult func application(_ name: String) throws -> URL {
        let url = apps.appendingPathComponent(name + ".app")
        let executable = url.appendingPathComponent("Contents/MacOS/test-agent")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleExecutable": "test-agent",
                                   "CFBundleIdentifier": "tests.agent." + UUID().uuidString]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
