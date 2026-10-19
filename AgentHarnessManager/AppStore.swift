import AppKit
import Observation
import Foundation
import SkillCore

enum AppPage: String, CaseIterable, Identifiable {
    case library, findings, profiles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: "스킬 목록"
        case .findings: "확인 필요"
        case .profiles: "작업 구성"
        }
    }
    var symbol: String {
        switch self {
        case .library: "square.stack.3d.up"
        case .findings: "exclamationmark.triangle"
        case .profiles: "slider.horizontal.3"
        }
    }
}

struct ProfileMember: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let agentName: String
}

struct WorkProfile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var note = ""
    var members: [ProfileMember] = []
}

struct SourceGroup: Identifiable {
    let repository: SourceRepository
    let count: Int
    var id: String { repository.id }
}

@MainActor @Observable
final class AppStore {
    var page: AppPage = .profiles {
        didSet {
            if page != oldValue { sourceFilterID = nil; rootFilterID = nil; resetFilters(); selectedEntry = nil }
        }
    }
    var search = ""
    var agentFilter: SkillAgent? {
        didSet {
            if let rootID = rootFilterID,
               registeredRoots.first(where: { $0.id == rootID })?.agent != agentFilter {
                rootFilterID = nil
            }
        }
    }
    var linksOnly = false
    var rootFilterID: String? {
        didSet {
            if let rootID = rootFilterID {
                if let root = registeredRoots.first(where: { $0.id == rootID }) {
                    agentFilter = root.agent
                } else { rootFilterID = nil }
            }
        }
    }
    var sourceFilterID: String?
    static let unknownSourceID = "unknown"
    private(set) var manualSources: [String: String] = [:]
    private(set) var installerSources: [String: SourceRepository] = [:]
    private(set) var sourcesLoadFailed = false
    private(set) var sourceMessage: String?
    var selectedEntry: SkillEntry?
    var selectedProfileID: UUID?
    var profileMessage: String?
    private(set) var profiles: [WorkProfile] = []
    private(set) var profilesLoadFailed = false
    var settingsMessage: String?
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var lastScanned: Date?
    private(set) var registeredRoots: [DiscoveryRoot]
    private(set) var snapshot = CatalogSnapshot(entries: [], roots: [])
    let automaticRoots: [DiscoveryRoot]
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scanGeneration = 0
    private static let sourcesKey = "skillSources"
    private static let rootsKey = "additionalSkillRoots"
    // ponytail: UserDefaults stores metadata only; join the journal-backed state before enabling file changes.
    private static let profilesKey = "workProfiles"

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.home = home
        automaticRoots = [
            DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "Codex · 사용자 스킬"),
            DiscoveryRoot(agent: .claudeCode, url: home.appendingPathComponent(".claude/skills"), label: "Claude Code · 사용자 스킬")
        ]
        registeredRoots = automaticRoots
        if let saved = defaults.data(forKey: Self.rootsKey) {
            do {
                let additional = try JSONDecoder().decode([DiscoveryRoot].self, from: saved)
                for root in additional where root.url.isFileURL && root.url.path.hasPrefix("/") {
                    if !registeredRoots.contains(where: { $0.id == root.id }) { registeredRoots.append(root) }
                }
            } catch { settingsMessage = "추가 경로 설정을 읽을 수 없습니다. 경로를 다시 등록해 주세요." }
        }
        if let saved = defaults.data(forKey: Self.sourcesKey) {
            do {
                let loaded = try JSONDecoder().decode([String: String].self, from: saved)
                guard loaded.values.allSatisfy({ SourceRepository($0) != nil }) else { throw CocoaError(.coderReadCorrupt) }
                manualSources = loaded
            } catch {
                sourcesLoadFailed = true
                sourceMessage = "출처 설정을 읽을 수 없습니다. 기존 데이터를 보존하고 출처 저장을 잠갔습니다."
            }
        }
        if let saved = defaults.data(forKey: Self.profilesKey) {
            do {
                let loaded = try JSONDecoder().decode([WorkProfile].self, from: saved)
                guard Set(loaded.map(\.id)).count == loaded.count else { throw CocoaError(.coderReadCorrupt) }
                profiles = loaded
                selectedProfileID = loaded.first?.id
            } catch {
                profilesLoadFailed = true
                profileMessage = "저장한 작업 구성을 읽을 수 없습니다. 기존 데이터를 보존하고 구성 저장을 잠갔습니다."
            }
        }
    }

    var entries: [SkillEntry] { snapshot.entries }
    var roots: [RootObservation] { snapshot.roots }
    var additionalRoots: [DiscoveryRoot] { registeredRoots.filter { !automaticRoots.contains($0) } }
    var sourceGroups: [SourceGroup] {
        Dictionary(grouping: entries.compactMap { sourceRepository(for: $0) }, by: \.id)
            .values.map { SourceGroup(repository: $0[0], count: $0.count) }
            .sorted { $0.count == $1.count ? $0.repository.name.localizedStandardCompare($1.repository.name) == .orderedAscending : $0.count > $1.count }
    }
    var unknownSourceCount: Int { entries.filter { sourceRepository(for: $0) == nil }.count }
    var sourceTitle: String {
        if sourceFilterID == Self.unknownSourceID { return "출처 미확인" }
        return sourceFilterID.flatMap { SourceRepository($0)?.name } ?? "모든 출처"
    }
    var sourceEntryCount: Int {
        entries.filter { sourceFilterID == nil || (sourceRepository(for: $0)?.id ?? Self.unknownSourceID) == sourceFilterID }.count
    }
    var scopeEntries: [SkillEntry] {
        entries.filter {
            (rootFilterID == nil || $0.rootID == rootFilterID)
            && (sourceFilterID == nil || (sourceRepository(for: $0)?.id ?? Self.unknownSourceID) == sourceFilterID)
        }
    }

    func sourceRepository(for entry: SkillEntry) -> SourceRepository? {
        manualSources[entry.id].flatMap { SourceRepository($0) } ?? installerSources[entry.id]
    }

    func sourceEvidence(for entry: SkillEntry) -> String {
        if manualSources[entry.id] != nil { return "직접 연결" }
        return installerSources[entry.id] == nil ? "출처 미확인" : "설치 기록"
    }

    @discardableResult
    func saveSource(for entry: SkillEntry, input: String?) -> Bool {
        guard !sourcesLoadFailed else { return false }
        guard hasScanned, !isScanning, entries.contains(where: { $0.id == entry.id }) else {
            sourceMessage = "설치 항목이 바뀌었거나 확인 중입니다. 창을 닫고 새로고침한 뒤 다시 연결해 주세요."
            return false
        }
        var updated = manualSources
        if let input {
            guard let repository = SourceRepository(input) else {
                sourceMessage = "owner/repo 또는 HTTPS 저장소 주소를 입력해 주세요. 인증 정보가 포함된 주소는 저장할 수 없습니다."
                return false
            }
            updated[entry.id] = repository.id
        } else { updated.removeValue(forKey: entry.id) }
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.sourcesKey)
            manualSources = updated
            sourceMessage = nil
            return true
        } catch { sourceMessage = "출처를 저장할 수 없습니다. 입력한 주소는 창에 남아 있습니다."; return false }
    }
    var availableAgents: [SkillAgent] { SkillAgent.allCases.filter { agent in registeredRoots.contains { $0.agent == agent } } }
    var availableRoots: [DiscoveryRoot] { registeredRoots.filter { agentFilter == nil || $0.agent == agentFilter } }
    var hasFilters: Bool { !search.isEmpty || agentFilter != nil || linksOnly || rootFilterID != nil }
    var filteredEntries: [SkillEntry] {
        scopeEntries.filter {
            (agentFilter == nil || $0.agent == agentFilter)
            && (!linksOnly || $0.isSymbolicLink)
            && (page != .findings || $0.problem != nil)
            && matchesSearch("\($0.name) \($0.url.path) \(agentName(for: $0)) \(sourceRepository(for: $0)?.name ?? "출처 미확인")")
        }
    }
    var problemRoots: [RootObservation] {
        roots.filter {
            $0.status == .blocked || $0.status == .partial
            || ($0.status == .missing && !automaticRoots.contains($0.root))
        }
    }
    var filteredProblemRoots: [RootObservation] {
        problemRoots.filter {
            (rootFilterID == nil || $0.root.id == rootFilterID)
            && (agentFilter == nil || $0.root.agent == agentFilter)
            && matchesSearch("\($0.root.label) \($0.root.url.path) \($0.message ?? "")")
        }
    }
    var findingCount: Int { entries.filter { $0.problem != nil }.count + problemRoots.count }

    func agentName(for entry: SkillEntry) -> String {
        entry.agent == .custom ? registeredRoots.first { $0.id == entry.rootID }?.label ?? entry.agent.displayName : entry.agent.displayName
    }

    var filteredProfiles: [WorkProfile] { profiles.filter { matchesSearch("\($0.name) \($0.note)") } }
    var selectedProfile: WorkProfile? { filteredProfiles.first { $0.id == selectedProfileID } }
    var profilesAreEditable: Bool { hasScanned && !isScanning && !profilesLoadFailed }

    @discardableResult
    func saveProfile(id: UUID, name: String, note: String, memberIDs: Set<String>) -> Bool {
        guard profilesAreEditable else { profileMessage = "스킬 확인을 마친 뒤 작업 구성을 저장할 수 있습니다."; return false }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80, note.count <= 240 else {
            profileMessage = "이름은 1~80자, 설명은 240자 이내로 입력해 주세요."; return false
        }
        let previous = profiles.first { $0.id == id }
        let allowedIDs = Set(entries.map(\.id)).union(previous?.members.map(\.id) ?? [])
        guard memberIDs.isSubset(of: allowedIDs) else {
            profileMessage = "선택한 스킬의 상태가 바뀌었습니다. 목록을 새로고침한 뒤 다시 선택해 주세요."; return false
        }
        let members = memberIDs.compactMap { memberID -> ProfileMember? in
            if let entry = entries.first(where: { $0.id == memberID }) {
                return ProfileMember(id: entry.id, name: entry.name, path: entry.url.path, agentName: agentName(for: entry))
            }
            return previous?.members.first { $0.id == memberID }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let profile = WorkProfile(id: id, name: title, note: note.trimmingCharacters(in: .whitespacesAndNewlines), members: members)
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == id }) { updated[index] = profile }
        else { updated.append(profile) }
        guard persistProfiles(updated) else { return false }
        profiles = updated
        selectedProfileID = id
        profileMessage = nil
        return true
    }

    func deleteProfile(_ id: UUID) {
        guard profilesAreEditable else { return }
        let updated = profiles.filter { $0.id != id }
        guard persistProfiles(updated) else { return }
        profiles = updated
        if selectedProfileID == id { selectedProfileID = updated.first?.id }
        profileMessage = nil
    }

    func profileMemberIDs(_ id: UUID) -> Set<String>? {
        guard profilesAreEditable, let profile = profiles.first(where: { $0.id == id }) else {
            profileMessage = "작업 구성을 불러올 수 없습니다. 스킬 목록과 구성을 확인해 주세요."
            return nil
        }
        let ids = Set(profile.members.map(\.id))
        guard ids.isSubset(of: Set(entries.map(\.id))) else {
            profileMessage = "‘\(profile.name)’ 구성에 현재 목록에 없는 스킬이 있습니다. 해당 구성을 편집해 확인해 주세요."
            return nil
        }
        profileMessage = nil
        return ids
    }

    private func persistProfiles(_ updated: [WorkProfile]) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.profilesKey)
            return true
        } catch { profileMessage = "작업 구성을 저장할 수 없습니다. 입력한 내용은 창에 남아 있습니다."; return false }
    }

    func showLibrary(rootID: String? = nil, sourceID: String? = nil) {
        page = .library
        resetFilters()
        rootFilterID = rootID
        sourceFilterID = sourceID
        selectedEntry = nil
    }

    func resetFilters() { search = ""; agentFilter = nil; linksOnly = false; rootFilterID = nil }
    private func matchesSearch(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    func rescan() async {
        scanGeneration += 1
        let generation = scanGeneration
        let inputs = registeredRoots
        isScanning = true
        let home = home
        let (result, sources) = await Task.detached(priority: .userInitiated) {
            let catalog = SkillCatalog.scan(roots: inputs)
            return (catalog, SkillCatalog.installerSources(entries: catalog.entries, home: home))
        }.value
        guard generation == scanGeneration else { return }
        snapshot = result
        installerSources = sources.repositories
        if !sourcesLoadFailed { sourceMessage = sources.message }
        if let agentFilter, !availableAgents.contains(agentFilter) { self.agentFilter = nil }
        lastScanned = .now
        hasScanned = true
        isScanning = false
    }

    func chooseSkillFolder(agent: SkillAgent, name: String, replacing existing: DiscoveryRoot? = nil) async {
        guard !isScanning else { return }
        let panel = NSOpenPanel()
        panel.title = existing == nil ? "스킬 폴더 추가" : "스킬 경로 수정"
        panel.message = "SKILL.md를 포함한 스킬들이 있는 폴더를 선택하세요. 선택한 폴더만 읽으며 파일을 변경하지 않습니다."
        panel.prompt = existing == nil ? "경로 추가" : "경로 변경"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if addRoot(url: url, agent: agent, name: name, replacing: existing) { await rescan() }
    }

    @discardableResult
    func addRoot(url: URL, agent: SkillAgent, name: String, replacing existing: DiscoveryRoot? = nil) -> Bool {
        guard !isScanning else { return false }
        if let existing {
            guard additionalRoots.contains(where: { $0.id == existing.id }), existing.agent == agent else {
                settingsMessage = "추가로 등록한 경로만 수정할 수 있습니다."
                return false
            }
        }
        guard url.isFileURL, url.path.hasPrefix("/") else { settingsMessage = "로컬 폴더를 선택해 주세요."; return false }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 80 else { settingsMessage = "에이전트 이름은 1~80자로 입력해 주세요."; return false }
        let root = DiscoveryRoot(agent: agent, url: url, label: label)
        guard !registeredRoots.contains(where: { $0.id == root.id && $0.id != existing?.id }) else {
            settingsMessage = "이 에이전트의 경로는 이미 등록되어 있습니다."
            return false
        }
        let updated = existing == nil ? additionalRoots + [root] : additionalRoots.map { $0.id == existing?.id ? root : $0 }
        guard saveRoots(updated) else { return false }
        registeredRoots = automaticRoots + updated
        if let existing {
            if rootFilterID == existing.id { rootFilterID = root.id }
            if selectedEntry?.rootID == existing.id { selectedEntry = nil }
        }
        settingsMessage = existing == nil ? "\(label) 경로를 추가했습니다." : "\(label) 경로를 변경했습니다. 폴더와 파일은 그대로 있습니다."
        return true
    }

    func removeRoot(_ root: DiscoveryRoot) async {
        guard !isScanning, additionalRoots.contains(where: { $0.id == root.id }) else { return }
        guard saveRoots(additionalRoots.filter { $0.id != root.id }) else { return }
        registeredRoots.removeAll { $0.id == root.id }
        if rootFilterID == root.id { rootFilterID = nil }
        if let agentFilter, !availableAgents.contains(agentFilter) { self.agentFilter = nil }
        if selectedEntry?.rootID == root.id { selectedEntry = nil }
        settingsMessage = "경로 등록을 해제했습니다. 원래 폴더와 파일은 그대로 있습니다."
        await rescan()
    }

    private func saveRoots(_ roots: [DiscoveryRoot]) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(roots), forKey: Self.rootsKey)
            return true
        } catch { settingsMessage = "경로 설정을 저장할 수 없습니다. 다시 시도해 주세요."; return false }
    }
}
