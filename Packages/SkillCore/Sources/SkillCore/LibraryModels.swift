import CryptoKit
import Darwin
import Foundation

public struct SkillInstallation: Identifiable, Sendable {
    public let id: String
    public let disabledRecord: DisabledInstallation?
    public let entry: SkillEntry
    public let originalPath: String
    public let currentPath: String
    public let resolvedPath: String?
    public let location: DiscoveryRoot
    public let isEnabled: Bool
    public var isSymbolicLink: Bool { entry.isSymbolicLink }
    public let contentHash: String?
    public let document: String?
    public let name: String
    public let summary: String
    public let metadataErrors: [String]
    public let readError: String?
    public var problems: [String] { metadataErrors + [readError].compactMap { $0 } }
}

public struct CanonicalSkill: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let installations: [SkillInstallation]
    public var summary: String { installations.first(where: { !$0.summary.isEmpty })?.summary ?? "설명 없음" }
    public var isEnabled: Bool { installations.contains(where: \.isEnabled) }
    public var hasProblems: Bool { installations.contains { !$0.problems.isEmpty } }
    public var hasVariants: Bool {
        Set(installations.compactMap(\.contentHash)).count > 1
    }
    /// Shared source directories stay in place; group and whole-skill actions switch their installation links.
    public var activationInstallations: [SkillInstallation] {
        let targets = Set(installations.filter(\.isSymbolicLink).compactMap(\.resolvedPath))
        return installations.filter { $0.isSymbolicLink || !targets.contains(LibraryCatalog.physicalPath($0.originalPath) ?? $0.originalPath) }
    }
}

public struct SkillGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var skillIDs: Set<String>

    public init(id: UUID = UUID(), name: String = "", symbol: String = "folder", skillIDs: Set<String> = []) {
        self.id = id; self.name = name; self.symbol = symbol; self.skillIDs = skillIDs
    }
}

public enum GroupSelectionMode: String, CaseIterable, Codable, Sendable {
    case single, multiple
}

public struct GroupActivationPlan: Sendable {
    public let activeGroupIDs: Set<UUID>
    public let enabling: Set<String>
    public let disabling: Set<String>

    public init(groups: [SkillGroup], currentActiveGroupIDs: Set<UUID>, mode: GroupSelectionMode, groupID: UUID, enabled: Bool) {
        if enabled { activeGroupIDs = mode == .single ? [groupID] : currentActiveGroupIDs.union([groupID]) }
        else { activeGroupIDs = currentActiveGroupIDs.subtracting([groupID]) }
        let targetIDs = activeGroupIDs
        let keepOn = groups.filter { targetIDs.contains($0.id) }.reduce(into: Set<String>()) { $0.formUnion($1.skillIDs) }
        enabling = keepOn
        if enabled && mode == .single {
            disabling = groups.reduce(into: Set<String>()) { $0.formUnion($1.skillIDs) }.subtracting(keepOn)
        } else {
            disabling = enabled ? [] : (groups.first { $0.id == groupID }?.skillIDs ?? []).subtracting(keepOn)
        }
    }
}

public struct AppPreferences: Codable, Sendable {
    public var version = 1
    public var favorites: Set<String> = []
    public var groups: [SkillGroup] = []
    public var groupSelectionMode: GroupSelectionMode = .multiple
    public var activeGroupIDs: Set<UUID> = []
    public var lastAppliedGroupChangeID: UUID?
    // Preserve the legacy records in UserDefaults; this mapping makes migration repeatable.
    public var importedProfileIDs: Set<UUID> = []
    public init() {}
}

public struct ReviewFinding: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let skillID: String?
    public let title: String
    public let evidence: String
    public let path: String
    public let contentHash: String?
}

public struct ReviewRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let provider: String
    public let snapshotID: String
    public let skillCount: Int
    public let findings: [ReviewFinding]
    public let versions: [String: String]

    public init(skills: [CanonicalSkill], roots: [RootObservation]) {
        id = UUID(); date = .now; provider = "로컬 검사"
        skillCount = skills.count
        let currentVersions = Dictionary(uniqueKeysWithValues: skills.flatMap(\.installations).map {
            ($0.id, LibraryCatalog.digest("\($0.currentPath)|\($0.isEnabled)|\($0.contentHash ?? "unreadable")|\($0.problems)"))
        })
        versions = currentVersions
        snapshotID = LibraryCatalog.digest(currentVersions.keys.sorted().map { "\($0):\(currentVersions[$0]!)" }.joined(separator: "\n") + roots.map { "\($0.id):\($0.status):\($0.message ?? "")" }.joined(separator: "\n"))
        var found = skills.flatMap { skill in
            skill.installations.flatMap { installation in
                installation.problems.enumerated().map { index, problem in
                    ReviewFinding(id: "\(installation.id):\(index)", skillID: skill.id, title: installation.readError == problem ? "문서를 읽을 수 없음" : "메타데이터 확인 필요", evidence: problem, path: installation.originalPath, contentHash: installation.contentHash)
                }
            }
        }
        found += roots.filter { $0.status == .blocked || $0.status == .partial || $0.status == .missing }.map {
            ReviewFinding(id: "root:\($0.id)", skillID: nil, title: "설치 경로 확인 필요", evidence: $0.message ?? "경로를 확인할 수 없습니다.", path: $0.root.url.path, contentHash: nil)
        }
        findings = found
    }
}

public enum LibraryCatalog {
    public static func physicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    public static func build(snapshot: CatalogSnapshot, roots: [DiscoveryRoot], disabled: [DisabledInstallation] = []) -> [CanonicalSkill] {
        var installations: [SkillInstallation] = []
        for entry in snapshot.entries {
            guard let location = roots.first(where: { $0.id == entry.rootID }) else { continue }
            installations.append(installation(entry: entry, location: location, roots: roots))
        }
        for saved in disabled {
            if let link = saved.link {
                guard saved.matchesCurrentItem else { continue }
                let entry = SkillEntry(id: "stored-link:" + saved.id, rootID: saved.location.id, agent: saved.location.agent,
                    name: saved.name, url: URL(fileURLWithPath: saved.currentPath), isSymbolicLink: true,
                    resolvedURL: URL(fileURLWithPath: link.targetPath))
                installations.append(installation(entry: entry, location: saved.location, roots: roots, saved: saved))
                continue
            }
            // Only a matching physical item can inherit a saved installation identity.
            let scan = SkillCatalog.scan(roots: [saved.readRoot], additionalApprovedRoots: roots)
            guard let entry = scan.entries.first(where: { $0.url.path == saved.currentPath && $0.rootID == saved.readRoot.id }),
                  saved.matchesCurrentItem else { continue }
            installations.append(installation(entry: entry, location: saved.location, roots: roots + [saved.readRoot], saved: saved))
        }
        // Group actual shared targets, not names or matching SKILL.md text (resources can differ).
        let byOriginalPath = Dictionary(installations.filter { !$0.isSymbolicLink }.map { (physicalPath($0.originalPath) ?? $0.originalPath, $0.id) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: installations) { item in
            if item.isSymbolicLink, item.readError == nil, let path = item.resolvedPath, let targetID = byOriginalPath[path] { return targetID }
            return item.id
        }
        return grouped.map { key, values in
            CanonicalSkill(id: "skill:" + key, name: values.first(where: { !$0.isSymbolicLink })?.name ?? values[0].name,
                           installations: values.sorted { $0.isSymbolicLink == $1.isSymbolicLink ? $0.originalPath < $1.originalPath : !$0.isSymbolicLink })
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func readDocument(installation: SkillInstallation, roots: [DiscoveryRoot]) throws -> String {
        if let saved = installation.disabledRecord, saved.link != nil { return try LibraryService.readStoredLinkDocument(saved, roots: roots) }
        let approved = roots + (installation.disabledRecord.map { [$0.readRoot] } ?? [])
        return try SkillCatalog.readDocument(entry: installation.entry, approvedRoots: approved)
    }

    private static func installation(entry: SkillEntry, location: DiscoveryRoot, roots: [DiscoveryRoot], saved: DisabledInstallation? = nil) -> SkillInstallation {
        var document: String?
        var readError = entry.problem
        do {
            if let saved, saved.link != nil { document = try LibraryService.readStoredLinkDocument(saved, roots: roots) }
            else { document = try SkillCatalog.readDocument(entry: entry, approvedRoots: roots) }
        }
        catch { readError = error.localizedDescription }
        let metadata = metadata(document, fallback: saved?.name ?? entry.name)
        return SkillInstallation(id: saved?.id ?? digest(entry.id), disabledRecord: saved, entry: entry,
            originalPath: saved?.originalPath ?? entry.url.path, currentPath: entry.url.path,
            resolvedPath: entry.resolvedURL?.path, location: location, isEnabled: saved == nil,
            contentHash: document.map(digest), document: nil, name: metadata.name, summary: metadata.summary,
            metadataErrors: metadata.errors, readError: readError)
    }

    private static func metadata(_ document: String?, fallback: String) -> (name: String, summary: String, errors: [String]) {
        guard let document else { return (fallback, "", []) }
        let lines = document.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (fallback, "", ["문서 맨 앞의 name·description 메타데이터를 확인해 주세요."])
        }
        // shortcut: Recognize top-level scalar and block fields only; use a YAML parser if editing full YAML becomes a feature.
        var fields: [String: String] = [:]
        var errors: [String] = []
        var index = 1
        while index < end {
            let line = lines[index]
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { index += 1; continue }
            let key = String(line[..<colon])
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if ["name", "description"].contains(key) {
                if fields[key] != nil { errors.append("\(key) 필드가 중복되어 있습니다.") }
                if [">", "|", ">-", "|-", ">+", "|+"].contains(value) {
                    let folded = value.hasPrefix(">")
                    var block: [String] = []
                    index += 1
                    while index < end && (lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") || lines[index].isEmpty) {
                        block.append(lines[index].trimmingCharacters(in: .whitespaces)); index += 1
                    }
                    value = block.joined(separator: folded ? " " : "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    fields[key] = value; continue
                }
                if value.count >= 2, (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") { value = String(value.dropFirst().dropLast()) }
                fields[key] = value
            }
            index += 1
        }
        for key in ["name", "description"] where fields[key, default: ""].isEmpty { errors.append("\(key) 메타데이터가 비어 있습니다.") }
        return (fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback, fields["description"] ?? "", errors)
    }
}
