import AppKit
import Observation
import Foundation
import SkillCore

enum AppPage: String, CaseIterable, Identifiable {
    case library, findings, groups, history, profiles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: "스킬 목록"
        case .findings: "확인 필요"
        case .profiles: "이전 작업 구성"
        case .groups: "그룹"
        case .history: "검사 이력"
        }
    }
    var symbol: String {
        switch self {
        case .library: "square.stack.3d.up"
        case .findings: "exclamationmark.triangle"
        case .profiles: "slider.horizontal.3"
        case .groups: "folder"
        case .history: "clock.arrow.circlepath"
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
    var page: AppPage = .library {
        didSet {
            if page != oldValue { sourceFilterID = nil; rootFilterID = nil; resetFilters(); selectedEntry = nil; selectedSkillID = nil; selectedFindingID = nil }
        }
    }
    var libraryFilter: LibraryFilter = .all
    var groupFilterID: UUID?
    var selectedSkillID: String?
    var selectedGroupID: UUID?
    var selectedFindingID: String?
    var selectedReviewID: UUID?
    var mutationPreview: MutationPlan?
    private var pendingActiveGroupIDs: Set<UUID>?
    var libraryMessage: String?
    private(set) var preferences = AppPreferences()
    private(set) var preferencesLoadFailed = false
    private(set) var reviewsLoadFailed = false
    private(set) var reviews: [ReviewRecord] = []
    private(set) var skills: [CanonicalSkill] = []
    private(set) var currentReview = ReviewRecord(skills: [], roots: [])
    private(set) var journal = LibraryJournal()
    private(set) var journalLoadFailed = false
    private(set) var isMutating = false
    private(set) var isPreparingChange = false
    @ObservationIgnored private let libraryService: LibraryService
    private static let preferencesKey = "libraryPreferences.v1"
    private static let reviewsKey = "review-history.v1"
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
        libraryService = LibraryService(stateDirectory: home.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/" + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager") + "/Library"))
        automaticRoots = [
            DiscoveryRoot(agent: .codex, url: home.appendingPathComponent(".agents/skills"), label: "Codex · 사용자 스킬"),
            DiscoveryRoot(agent: .claudeCode, url: home.appendingPathComponent(".claude/skills"), label: "Claude Code · 사용자 스킬")
        ]
        registeredRoots = automaticRoots
        if let data = defaults.data(forKey: Self.preferencesKey) {
            do {
                let loaded = try JSONDecoder().decode(AppPreferences.self, from: data)
                guard loaded.version == 1, Set(loaded.groups.map(\.id)).count == loaded.groups.count,
                      loaded.groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                      loaded.activeGroupIDs.isSubset(of: Set(loaded.groups.map(\.id))) else { throw CocoaError(.coderReadCorrupt) }
                preferences = loaded
            } catch { preferencesLoadFailed = true; libraryMessage = "그룹·즐겨찾기 설정이 손상되었습니다. 기존 데이터를 보존하고 저장을 잠갔습니다." }
        }
        if let data = defaults.data(forKey: Self.reviewsKey) {
            do {
                let loaded = try JSONDecoder().decode([ReviewRecord].self, from: data)
                guard Set(loaded.map(\.id)).count == loaded.count else { throw CocoaError(.coderReadCorrupt) }
                reviews = loaded
            } catch { reviewsLoadFailed = true; libraryMessage = "검사 이력을 읽을 수 없습니다. 기존 데이터를 보존하고 이력 저장을 잠갔습니다." }
        }
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
        Dictionary(grouping: allInstallations.compactMap { sourceRepository(for: $0) }, by: \.id)
            .values.map { SourceGroup(repository: $0[0], count: $0.count) }
            .sorted { $0.count == $1.count ? $0.repository.name.localizedStandardCompare($1.repository.name) == .orderedAscending : $0.count > $1.count }
    }
    var unknownSourceCount: Int { allInstallations.filter { sourceRepository(for: $0) == nil }.count }
    var sourceTitle: String {
        if sourceFilterID == Self.unknownSourceID { return "출처 미확인" }
        return sourceFilterID.flatMap { SourceRepository($0)?.name } ?? "모든 출처"
    }
    var sourceEntryCount: Int {
        allInstallations.filter { sourceFilterID == nil || (sourceRepository(for: $0)?.id ?? Self.unknownSourceID) == sourceFilterID }.count
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
    var profilesAreEditable: Bool { hasScanned && !isScanning && !isMutating && !isPreparingChange && !profilesLoadFailed }

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
        libraryFilter = .all; groupFilterID = nil
        selectedSkillID = nil
        resetFilters()
        rootFilterID = rootID
        sourceFilterID = sourceID
        selectedEntry = nil
    }

    func resetFilters() { search = ""; agentFilter = nil; linksOnly = false; rootFilterID = nil }
    func matchesSearch(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    func rescan() async {
        scanGeneration += 1
        let generation = scanGeneration
        let inputs = registeredRoots
        guard !isMutating, !isPreparingChange else { return }
        isScanning = true
        let home = home
        let managed = automaticRoots
        let saved: LibraryJournal
        do { saved = try await libraryService.load(roots: managed); journalLoadFailed = false }
        catch { saved = journal; journalLoadFailed = true; libraryMessage = error.localizedDescription }
        let (result, sources, library) = await Task.detached(priority: .userInitiated) {
            let catalog = SkillCatalog.scan(roots: inputs)
            return (catalog, SkillCatalog.installerSources(entries: catalog.entries, home: home),
                    LibraryCatalog.build(snapshot: catalog, roots: inputs, disabled: saved.disabled))
        }.value
        guard generation == scanGeneration else { return }
        snapshot = result
        skills = library
        journal = saved
        currentReview = ReviewRecord(skills: library, roots: problemRoots)
        migrateProfiles()
        installerSources = sources.repositories
        if !sourcesLoadFailed { sourceMessage = sources.message }
        if let agentFilter, !availableAgents.contains(agentFilter) { self.agentFilter = nil }
        lastScanned = .now
        hasScanned = true
        isScanning = false
    }

    func chooseSkillFolder(agent: SkillAgent, name: String, replacing existing: DiscoveryRoot? = nil) async {
        guard !isScanning, !isMutating, !isPreparingChange else { return }
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
        guard !isScanning, !isMutating, !isPreparingChange else { return false }
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
        guard !isScanning, !isMutating, !isPreparingChange, additionalRoots.contains(where: { $0.id == root.id }) else { return }
        guard !journal.disabled.contains(where: { $0.location.id == root.id }), journal.pending == nil else {
            settingsMessage = "보관 중인 설치 항목을 복원하고 중단된 변경을 해결한 뒤 경로를 해제해 주세요."; return
        }
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

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, findings, on, off, favorites, variants
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "전체"
        case .findings: "검사 결과"
        case .on: "켜짐"
        case .off: "꺼짐"
        case .favorites: "즐겨찾기"
        case .variants: "다른 버전"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .findings: "exclamationmark.triangle"
        case .on: "checkmark.circle"
        case .off: "minus.circle"
        case .favorites: "star"
        case .variants: "square.on.square"
        }
    }
}

extension AppStore {
    var allInstallations: [SkillInstallation] { skills.flatMap(\.installations) }
    var selectedSkill: CanonicalSkill? { skills.first { $0.id == selectedSkillID } }
    var groups: [SkillGroup] { preferences.groups }
    var filteredGroups: [SkillGroup] { groups.filter { matchesSearch($0.name) } }
    var selectedGroup: SkillGroup? { groups.first { $0.id == selectedGroupID } }
    var localReview: ReviewRecord { currentReview }
    var currentFindings: [ReviewFinding] { localReview.findings }
    var filteredFindings: [ReviewFinding] { currentFindings.filter { matchesSearch("\($0.title) \($0.evidence) \($0.path)") } }
    var filteredReviews: [ReviewRecord] { reviews.filter { matchesSearch("\($0.provider) \($0.date.formatted())") } }
    var selectedReview: ReviewRecord? { reviews.first { $0.id == selectedReviewID } }
    var metadataIsEditable: Bool { hasScanned && !isScanning && !isMutating && !isPreparingChange && !preferencesLoadFailed }
    var canChangeFiles: Bool { hasScanned && !isScanning && !isMutating && !isPreparingChange && !journalLoadFailed && journal.pending == nil }
    var hasVariantNames: Set<String> {
        Set(Dictionary(grouping: skills, by: \.name).filter { Set($0.value.flatMap(\.installations).compactMap(\.contentHash)).count > 1 }.keys)
    }
    var filteredSkills: [CanonicalSkill] {
        skills.filter { skill in
            matchesFilter(skill, libraryFilter)
            && (groupFilterID == nil || groups.first(where: { $0.id == groupFilterID })?.skillIDs.contains(skill.id) == true)
            && skill.installations.contains { item in
                (agentFilter == nil || item.location.agent == agentFilter)
                && (rootFilterID == nil || item.location.id == rootFilterID)
                && (!linksOnly || item.isSymbolicLink)
                && (sourceFilterID == nil || (sourceRepository(for: item)?.id ?? Self.unknownSourceID) == sourceFilterID)
                && matchesSearch("\(skill.name) \(item.summary) \(item.originalPath) \(item.location.label) \(sourceRepository(for: item)?.name ?? "출처 미확인")")
            }
        }
    }
    func sourceRepository(for installation: SkillInstallation) -> SourceRepository? {
        if let current = sourceRepository(for: installation.entry) { return current }
        return manualSources.first { LibraryCatalog.digest($0.key) == installation.id }.flatMap { SourceRepository($0.value) }
    }
    func matchesFilter(_ skill: CanonicalSkill, _ filter: LibraryFilter) -> Bool {
        switch filter {
        case .all: true
        case .findings: skill.hasProblems
        case .on: skill.isEnabled
        case .off: skill.installations.contains { !$0.isEnabled }
        case .favorites: preferences.favorites.contains(skill.id)
        case .variants: skill.hasVariants || hasVariantNames.contains(skill.name)
        }
    }
    func count(_ filter: LibraryFilter) -> Int {
        filter == .findings ? currentFindings.count : skills.filter { matchesFilter($0, filter) }.count
    }
    func navigate(_ filter: LibraryFilter = .all, agent: SkillAgent? = nil, group: UUID? = nil) {
        page = filter == .findings ? .findings : .library
        resetFilters(); sourceFilterID = nil
        libraryFilter = filter; agentFilter = agent; groupFilterID = group
        selectedSkillID = nil; selectedFindingID = nil
    }
    func toggleFavorite(_ id: String) {
        guard metadataIsEditable, skills.contains(where: { $0.id == id }) else { return }
        var updated = preferences
        if !updated.favorites.insert(id).inserted { updated.favorites.remove(id) }
        _ = savePreferences(updated)
    }
    @discardableResult
    func saveGroup(_ group: SkillGroup) -> Bool {
        guard metadataIsEditable else { return false }
        var group = group
        group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = groups.first { $0.id == group.id }
        let allowed = Set(skills.map(\.id)).union(previous?.skillIDs ?? [])
        guard !group.name.isEmpty, group.name.count <= 80, group.skillIDs.isSubset(of: allowed) else {
            libraryMessage = "그룹 이름은 1~80자여야 하며 현재 목록 또는 기존 그룹의 스킬만 선택할 수 있습니다."; return false
        }
        var updated = preferences
        if let index = updated.groups.firstIndex(where: { $0.id == group.id }) { updated.groups[index] = group }
        else { updated.groups.append(group) }
        guard savePreferences(updated) else { return false }
        selectedGroupID = group.id; libraryMessage = nil
        return true
    }
    func deleteGroup(_ id: UUID) {
        guard metadataIsEditable else { return }
        var updated = preferences
        updated.groups.removeAll { $0.id == id }; updated.activeGroupIDs.remove(id)
        if savePreferences(updated), selectedGroupID == id { selectedGroupID = nil }
    }
    func setGroupMode(_ mode: GroupSelectionMode) {
        guard metadataIsEditable else { return }
        var updated = preferences; updated.groupSelectionMode = mode
        _ = savePreferences(updated)
    }
    private func savePreferences(_ updated: AppPreferences) -> Bool {
        guard !preferencesLoadFailed else { return false }
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.preferencesKey)
            preferences = updated; return true
        } catch { libraryMessage = "그룹·즐겨찾기를 저장할 수 없습니다."; return false }
    }
    private func migrateProfiles() {
        guard !preferencesLoadFailed, !profilesLoadFailed else { return }
        let map = Dictionary(allInstallations.map { ($0.entry.id, "skill:" + $0.id) }, uniquingKeysWith: { first, _ in first })
        let canonicalIDs = Dictionary(skills.flatMap { skill in skill.installations.map { ($0.entry.id, skill.id) } }, uniquingKeysWith: { first, _ in first })
        var updated = preferences
        for profile in profiles where !updated.importedProfileIDs.contains(profile.id) {
            let ids = Set(profile.members.map { canonicalIDs[$0.id] ?? map[$0.id] ?? "legacy:" + $0.id })
            if !updated.groups.contains(where: { $0.id == profile.id }) {
                updated.groups.append(SkillGroup(id: profile.id, name: profile.name.isEmpty ? "이전 작업 구성" : profile.name, skillIDs: ids))
            }
            updated.importedProfileIDs.insert(profile.id)
        }
        for index in updated.groups.indices {
            updated.groups[index].skillIDs = Set(updated.groups[index].skillIDs.map { id in
                id.hasPrefix("legacy:") ? canonicalIDs[String(id.dropFirst("legacy:".count))] ?? id : id
            })
        }
        // Original profiles (including notes and unavailable references) remain untouched.
        if updated.groups != preferences.groups || updated.importedProfileIDs != preferences.importedProfileIDs { _ = savePreferences(updated) }
    }
    func runLocalReview() {
        guard hasScanned, !isScanning, !isMutating, !reviewsLoadFailed else { return }
        let record = localReview
        do {
            let updated = Array(([record] + reviews).prefix(50))
            let data = try JSONEncoder().encode(updated)
            guard data.count <= 2 * 1_024 * 1_024 else { libraryMessage = "검사 이력이 2 MiB 한도를 넘습니다. 기존 이력은 보존했습니다."; return }
            defaults.set(data, forKey: Self.reviewsKey); reviews = updated
            page = .history; selectedReviewID = record.id
        } catch { libraryMessage = "검사 이력을 저장할 수 없습니다." }
    }
    func prepareChange(title: String, installations: [SkillInstallation], enabled: Bool) async {
        guard canChangeFiles else { libraryMessage = "검사 또는 복구를 마친 뒤 변경할 수 있습니다."; return }
        pendingActiveGroupIDs = nil
        isPreparingChange = true
        defer { isPreparingChange = false }
        let all = allInstallations, managed = automaticRoots, protected = registeredRoots
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                try LibraryService.plan(title: title, installations: installations, enabled: enabled,
                    allInstallations: all, managedRoots: managed, protectedRoots: protected)
            }.value
            if plan.installations.isEmpty { libraryMessage = "이미 요청한 상태입니다." }
            else { mutationPreview = plan; libraryMessage = nil }
        } catch { libraryMessage = error.localizedDescription }
    }
    func prepareGroupChange(_ group: SkillGroup, enabled: Bool) async {
        guard metadataIsEditable, groups.contains(group), group.skillIDs.isSubset(of: Set(skills.map(\.id))), !group.skillIDs.isEmpty else {
            libraryMessage = "그룹이 비어 있거나 현재 목록에 없는 스킬이 있습니다. 그룹을 편집해 확인해 주세요."; return
        }
        let activation = GroupActivationPlan(groups: groups, currentActiveGroupIDs: preferences.activeGroupIDs,
            mode: preferences.groupSelectionMode, groupID: group.id, enabled: enabled)
        let targetIDs = activation.activeGroupIDs
        let keepOn = activation.enabling
        let turnOff = activation.disabling
        guard keepOn.union(turnOff).isSubset(of: Set(skills.map(\.id))) else {
            libraryMessage = "전환할 그룹에 현재 목록에 없는 스킬이 있습니다. 그룹을 편집해 확인해 주세요."; return
        }
        guard canChangeFiles else { return }
        isPreparingChange = true
        defer { isPreparingChange = false }
        let all = allInstallations, managed = automaticRoots, protected = registeredRoots
        let onItems = skills.filter { keepOn.contains($0.id) }.flatMap(\.installations)
        let offItems = skills.filter { turnOff.contains($0.id) }.flatMap(\.installations)
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                let on = try LibraryService.plan(title: group.name, installations: onItems, enabled: true, allInstallations: all, managedRoots: managed, protectedRoots: protected)
                let off = try LibraryService.plan(title: group.name, installations: offItems, enabled: false, allInstallations: all, managedRoots: managed, protectedRoots: protected)
                return MutationPlan(title: "\(group.name) · \(enabled ? "켜기" : "끄기")", installations: off.installations + on.installations)
            }.value
            if plan.installations.isEmpty {
                var updated = preferences; updated.activeGroupIDs = targetIDs
                if savePreferences(updated) { libraryMessage = "그룹 선택을 저장했습니다. 필요한 파일 변경은 없습니다." }
            } else {
                mutationPreview = plan
                pendingActiveGroupIDs = targetIDs
            }
        } catch { libraryMessage = error.localizedDescription }
    }
    func applyPreview() async {
        guard let plan = mutationPreview, canChangeFiles else { return }
        isMutating = true
        do {
            try await libraryService.apply(plan, roots: registeredRoots)
            if let ids = pendingActiveGroupIDs {
                var updated = preferences; updated.activeGroupIDs = ids; _ = savePreferences(updated)
            }
            libraryMessage = "파일 변경을 완료했습니다. 에이전트의 새 대화에서 반영 여부를 확인하세요."
            mutationPreview = nil; pendingActiveGroupIDs = nil
        } catch { libraryMessage = error.localizedDescription; mutationPreview = nil; pendingActiveGroupIDs = nil }
        isMutating = false
        await rescan()
    }
    func cancelPreview() { mutationPreview = nil; pendingActiveGroupIDs = nil }
    func recoverChanges() async {
        guard !isScanning, !isMutating, !isPreparingChange else { return }
        isMutating = true
        do { try await libraryService.recover(roots: registeredRoots); libraryMessage = "중단된 파일 변경을 마쳤습니다." }
        catch { libraryMessage = error.localizedDescription }
        isMutating = false
        await rescan()
    }
}
