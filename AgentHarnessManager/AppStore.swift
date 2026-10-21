import AppKit
import Observation
import Foundation
import SkillCore

enum AppDestination: String, CaseIterable, Identifiable {
    case skills, instructions, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .skills: "스킬 라이브러리"
        case .instructions: "전역 지침"
        case .activity: "활동 이력"
        }
    }
    var symbol: String {
        switch self {
        case .skills: "square.stack.3d.up"
        case .instructions: "text.document"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case library, findings, groups, history, changes, requests, profiles, instructions
    var id: String { rawValue }
    var destination: AppDestination {
        switch self {
        case .library, .findings, .groups: .skills
        case .instructions: .instructions
        case .history, .changes, .requests, .profiles: .activity
        }
    }
    var title: String {
        switch self {
        case .library: "스킬 라이브러리"
        case .findings: "검사 결과"
        case .profiles: "이전 작업 구성"
        case .groups: "그룹"
        case .history: "검사 이력"
        case .changes: "변경 이력"
        case .requests: "에이전트 요청"
        case .instructions: "전역 지침"
        }
    }
    var symbol: String {
        switch self {
        case .library: "square.stack.3d.up"
        case .findings: "exclamationmark.triangle"
        case .profiles: "slider.horizontal.3"
        case .groups: "folder"
        case .history: "clock.arrow.circlepath"
        case .changes: "arrow.left.arrow.right"
        case .requests: "tray.and.arrow.down"
        case .instructions: "text.document"
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

struct SkillUpdateCheck {
    enum Status { case available, current, modified, unavailable, failed }
    let status: Status
    let message: String
    let checkedAt = Date()
    var source: SkillUpdateSource?
    var listing: GitHubSkillListing?
    var candidate: GitHubSkillCandidate?
    var title: String {
        switch status { case .available: "업데이트 있음"; case .current: "최신 상태"; case .modified: "로컬 내용 다름"; case .unavailable: "자동 확인 불가"; case .failed: "확인 실패" }
    }
    var symbol: String {
        switch status { case .available: "arrow.down.circle"; case .current: "checkmark.circle"; case .modified: "pencil.circle"; case .unavailable: "info.circle"; case .failed: "exclamationmark.triangle" }
    }
}

@MainActor @Observable
final class AppStore {
    let instructions: InstructionStore
    var page: AppPage = .library {
        didSet {
            if page.destination == .activity { lastActivityPage = page }
            if page != oldValue { clearLibraryFilters(); selectedEntry = nil; selectedSkillID = nil; selectedFindingID = nil }
        }
    }
    private(set) var lastActivityPage: AppPage = .history
    var libraryFilter: LibraryFilter = .all
    var groupFilterID: UUID? {
        didSet {
            if let id = groupFilterID, !groups.contains(where: { $0.id == id }) { groupFilterID = nil }
        }
    }
    var selectedSkillID: String?
    var selectedGroupID: UUID?
    var selectedFindingID: String?
    var selectedReviewID: UUID?
    var selectedMutationID: UUID?
    var mutationPreview: MutationPlan?
    var skillsCLIPreview: SkillsCLIPlan?
    private(set) var managementMethod: SkillManagementMethod
    private(set) var skillsCLIExecutable: URL?
    private(set) var skillsCLIOutput: String?
    private(set) var skillsCLIFailed = false
    private(set) var updateChecks: [String: SkillUpdateCheck] = [:]
    private(set) var isCheckingUpdates = false
    private(set) var updatesProgress = ""
    private(set) var lastUpdatesChecked: Date?
    @ObservationIgnored private let skillsCLIService: SkillsCLIService
    @ObservationIgnored private let gitHubSkills: GitHubSkillService
    @ObservationIgnored private var skillsCLIDownload: GitHubSkillDownload?
    // Keep the existing choice when expanding installation to lifecycle management.
    private static let managementMethodKey = "skillInstallMethod"
    private static let skillsCLIPathKey = "skillsCLIExecutable"
    var libraryMessage: String?
    private(set) var preferences = AppPreferences()
    private(set) var preferencesLoadFailed = false
    private(set) var reviewsLoadFailed = false
    private(set) var reviews: [ReviewRecord] = []
    private(set) var skills: [CanonicalSkill] = []
    private(set) var currentReview = ReviewRecord(skills: [], roots: [])
    private(set) var journal = LibraryJournal()
    private(set) var journalLoadFailed = false
    private(set) var groupSyncFailed = false
    private(set) var isMutating = false
    private(set) var isPreparingChange = false
    private(set) var agentRequests: [AgentChangeRequest] = []
    private(set) var agentRequestsMessage: String?
    var selectedAgentRequestID: UUID?
    @ObservationIgnored private let agentRequestStore: AgentRequestStore
    @ObservationIgnored private let libraryService: LibraryService
    private static let preferencesKey = ManagementConfiguration.preferencesKey
    private static let reviewsKey = "review-history.v1"
    var search = ""
    var agentFilter: SkillAgent? {
        didSet {
            if let rootID = rootFilterID, let root = registeredRoots.first(where: { $0.id == rootID }),
               agentFilter == nil || !agents(for: root).contains(agentFilter!) {
                rootFilterID = nil
            }
        }
    }
    var linksOnly = false
    var rootFilterID: String? {
        didSet {
            if let rootID = rootFilterID {
                if let root = registeredRoots.first(where: { $0.id == rootID }) {
                    if agentFilter == nil || !agents(for: root).contains(agentFilter!) { agentFilter = root.agent }
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
    private(set) var agentInstallations: [AgentConnectionTarget: AgentInstallation] = [:]
    @ObservationIgnored private let installationDetector: AgentInstallationDetector
    @ObservationIgnored private var installationGeneration = 0
    private(set) var registeredRoots: [DiscoveryRoot]
    private(set) var snapshot = CatalogSnapshot(entries: [], roots: [])
    let automaticRoots: [DiscoveryRoot]
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scanGeneration = 0
    private static let sourcesKey = "skillSources"
    private static let rootsKey = ManagementConfiguration.rootsKey
    // ponytail: UserDefaults stores metadata only; join the journal-backed state before enabling file changes.
    private static let profilesKey = "workProfiles"

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         installationDetector: AgentInstallationDetector? = nil,
         skillsCLIService: SkillsCLIService? = nil,
         gitHubSkills: GitHubSkillService = GitHubSkillService(),
         instructionEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.home = home
        self.skillsCLIService = skillsCLIService ?? SkillsCLIService(home: home)
        self.gitHubSkills = gitHubSkills
        managementMethod = defaults.string(forKey: Self.managementMethodKey).flatMap(SkillManagementMethod.init(rawValue:)) ?? .direct
        let preferredCLI = defaults.string(forKey: Self.skillsCLIPathKey).map { URL(fileURLWithPath: $0) }
        skillsCLIExecutable = self.skillsCLIService.detect(preferred: preferredCLI)
        instructions = InstructionStore(service: GlobalInstructionService(home: home, environment: instructionEnvironment,
            backupDirectory: home.resolvingSymlinksInPath().appendingPathComponent("Library/Application Support/"
                + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager") + "/InstructionBackups")))
        self.installationDetector = installationDetector ?? AgentInstallationDetector(home: home)
        libraryService = LibraryService(stateDirectory: home.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/" + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager") + "/Library"))
        agentRequestStore = AgentRequestStore(stateDirectory: home.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/" + (Bundle.main.bundleIdentifier ?? "AgentHarnessManager")))
        automaticRoots = ManagementConfiguration.defaultRoots(home: home)
        registeredRoots = automaticRoots
        if let data = defaults.data(forKey: Self.preferencesKey) {
            do {
                preferences = try ManagementConfiguration.decodePreferences(data)
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
                registeredRoots = try ManagementConfiguration.decodeRoots(saved, home: home)
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
    func agents(for root: DiscoveryRoot) -> [SkillAgent] { ManagementConfiguration.readers(of: root, defaultRoots: automaticRoots) }
    func agents(for entry: SkillEntry) -> [SkillAgent] {
        registeredRoots.first { $0.id == entry.rootID }.map { agents(for: $0) } ?? [entry.agent]
    }
    var availableAgents: [SkillAgent] { SkillAgent.allCases.filter { agent in registeredRoots.contains { agents(for: $0).contains(agent) } } }
    var sidebarAgents: [SkillAgent] {
        availableAgents.filter { agent in
            agent == .custom || AgentConnectionTarget(rawValue: agent.rawValue).map { agentInstallations[$0]?.isInstalled == true } == true
        }
    }

    func refreshAgentInstallations() async {
        installationGeneration += 1
        let generation = installationGeneration
        let detector = installationDetector
        let detected = await Task.detached(priority: .utility) { detector.scan() }.value
        guard generation == installationGeneration else { return }
        let previous = agentInstallations
        agentInstallations = detected
        if let filter = agentFilter, let target = AgentConnectionTarget(rawValue: filter.rawValue),
           previous[target]?.isInstalled == true, detected[target]?.isInstalled == false, rootFilterID == nil {
            agentFilter = nil
        }
    }
    var availableRoots: [DiscoveryRoot] { registeredRoots.filter { agentFilter == nil || agents(for: $0).contains(agentFilter!) } }
    var hasFilters: Bool {
        !search.isEmpty || agentFilter != nil || linksOnly || rootFilterID != nil
        || libraryFilter != .all || groupFilterID != nil || sourceFilterID != nil
    }
    var filteredEntries: [SkillEntry] {
        scopeEntries.filter {
            (agentFilter == nil || agents(for: $0).contains(agentFilter!))
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
            && (agentFilter == nil || agents(for: $0.root).contains(agentFilter!))
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
    func clearLibraryFilters() {
        libraryFilter = .all
        groupFilterID = nil
        sourceFilterID = nil
        resetFilters()
        if let id = selectedSkillID, !filteredSkills.contains(where: { $0.id == id }) { selectedSkillID = nil }
    }
    func matchesSearch(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    func rescan() async {
        scanGeneration += 1
        let generation = scanGeneration
        let inputs = registeredRoots
        guard !isMutating, !isPreparingChange, !isCheckingUpdates else { return }
        updateChecks = [:]; lastUpdatesChecked = nil
        isScanning = true
        await refreshAgentInstallations()
        refreshSkillsCLI()
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
        reconcileGroupSelection()
        currentReview = ReviewRecord(skills: library, roots: problemRoots)
        migrateProfiles()
        installerSources = sources.repositories
        if !sourcesLoadFailed { sourceMessage = sources.message }
        if let agentFilter, !availableAgents.contains(agentFilter) { self.agentFilter = nil }
        lastScanned = .now
        hasScanned = true
        isScanning = false
        await refreshAgentRequests()
    }

    func chooseSkillFolder(agent: SkillAgent, name: String, replacing existing: DiscoveryRoot? = nil) async {
        guard canEditRoots else { return }
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
        guard canEditRoots else { return false }
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
        guard canEditRoots, additionalRoots.contains(where: { $0.id == root.id }) else { return }
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
    case all, updates, findings, on, off, favorites, variants
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "전체"
        case .updates: "업데이트 있음"
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
        case .updates: "arrow.down.circle"
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
    var metadataIsEditable: Bool { hasScanned && !isScanning && !isMutating && !isPreparingChange && !isCheckingUpdates && !preferencesLoadFailed && !journalLoadFailed && !groupSyncFailed && journal.pending == nil && mutationPreview == nil && skillsCLIPreview == nil }
    var canChangeFiles: Bool { hasScanned && !isScanning && !isMutating && !isPreparingChange && !isCheckingUpdates && !journalLoadFailed && !groupSyncFailed && journal.pending == nil && skillsCLIPreview == nil }
    var canEditRoots: Bool { !isScanning && !isMutating && !isPreparingChange && !isCheckingUpdates && !journalLoadFailed && !groupSyncFailed && journal.pending == nil && mutationPreview == nil && skillsCLIPreview == nil }
    var mutations: [MutationPlan] { (journal.pending.map { [$0] } ?? []) + journal.completed }
    var filteredMutations: [MutationPlan] {
        mutations.filter { plan in
            matchesSearch(([plan.title] + plan.installations.flatMap { [$0.installation.name, $0.source, $0.destination] }).joined(separator: " "))
        }
    }
    var selectedMutation: MutationPlan? { mutations.first { $0.id == selectedMutationID } }
    var hasVariantNames: Set<String> {
        Set(Dictionary(grouping: skills, by: \.name).filter { Set($0.value.flatMap(\.installations).compactMap(\.contentHash)).count > 1 }.keys)
    }
    var filteredSkills: [CanonicalSkill] {
        skills.filter { skill in
            matchesFilter(skill, libraryFilter)
            && (groupFilterID == nil || groups.first(where: { $0.id == groupFilterID })?.skillIDs.contains(skill.id) == true)
            && skill.installations.contains { item in
                (agentFilter == nil || agents(for: item.location).contains(agentFilter!))
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
        case .updates: updateChecks[skill.id]?.status == .available
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
    func navigate(to destination: AppDestination) {
        guard page.destination != destination else { return }
        switch destination {
        case .skills: navigate()
        case .instructions: page = .instructions
        case .activity:
            page = lastActivityPage == .profiles && profiles.isEmpty && !profilesLoadFailed ? .history : lastActivityPage
        }
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
        if savePreferences(updated) {
            if selectedGroupID == id { selectedGroupID = nil }
            if groupFilterID == id { groupFilterID = nil }
        }
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
    private func reconcileGroupSelection() {
        groupSyncFailed = false
        guard !journalLoadFailed, let committed = journal.groupSelection,
              preferences.lastAppliedGroupChangeID != committed.id else { return }
        guard !preferencesLoadFailed,
              committed.change.after.isSubset(of: Set(groups.map(\.id))),
              preferences.activeGroupIDs == committed.change.before || preferences.activeGroupIDs == committed.change.after else {
            groupSyncFailed = true
            libraryMessage = "파일 변경은 기록되어 있지만 그룹 선택 설정과 맞지 않습니다. 기존 설정과 기록을 보존했습니다. 설정을 복원한 뒤 앱을 다시 실행해 주세요."
            return
        }
        var updated = preferences
        updated.activeGroupIDs = committed.change.after
        updated.lastAppliedGroupChangeID = committed.id
        groupSyncFailed = !savePreferences(updated)
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
        let onItems = skills.filter { keepOn.contains($0.id) }.flatMap(\.activationInstallations)
        let offItems = skills.filter { turnOff.contains($0.id) }.flatMap(\.activationInstallations)
        let selection = GroupSelectionChange(before: preferences.activeGroupIDs, after: targetIDs, previousChangeID: journal.groupSelection?.id)
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                let on = try LibraryService.plan(title: group.name, installations: onItems, enabled: true, allInstallations: all, managedRoots: managed, protectedRoots: protected)
                let off = try LibraryService.plan(title: group.name, installations: offItems, enabled: false, allInstallations: all, managedRoots: managed, protectedRoots: protected)
                return MutationPlan(title: "\(group.name) · \(enabled ? "켜기" : "끄기")", installations: off.installations + on.installations, groupSelection: selection)
            }.value
            if plan.installations.isEmpty {
                if selection.before == selection.after { libraryMessage = "이미 요청한 그룹 상태입니다."; return }
                try await libraryService.apply(plan, roots: registeredRoots)
                selectedMutationID = plan.id
                isPreparingChange = false
                await rescan()
                if !groupSyncFailed { libraryMessage = "그룹 선택을 저장했습니다. 필요한 파일 변경은 없습니다." }
            } else {
                mutationPreview = plan
            }
        } catch { libraryMessage = error.localizedDescription }
    }
    func applyPreview() async {
        guard let plan = mutationPreview, canChangeFiles else { return }
        if let selection = plan.groupSelection {
            guard !preferencesLoadFailed, selection.before == preferences.activeGroupIDs,
                  selection.after.isSubset(of: Set(groups.map(\.id))) else {
                cancelPreview(); libraryMessage = "그룹 선택이 바뀌었습니다. 새 계획을 검토해 주세요."; return
            }
        }
        isMutating = true
        var applied = false
        do {
            try await libraryService.apply(plan, roots: registeredRoots)
            applied = true
            selectedMutationID = plan.id
            libraryMessage = plan.undoes == nil ? "변경을 완료했습니다. 변경 이력에서 확인할 수 있습니다." : "되돌리기를 완료했습니다. 원래 작업과 실행 기록을 함께 보존했습니다."
            mutationPreview = nil
        } catch {
            libraryMessage = error.localizedDescription
            if let latest = try? await libraryService.load(roots: registeredRoots), latest.pending == nil {
                LibraryService.discardInstallation(plan)
            }
            mutationPreview = nil
        }
        isMutating = false
        await rescan()
        if applied, let id = selectedSkillID, !skills.contains(where: { $0.id == id }) { selectedSkillID = nil }
        if applied, plan.undoes == nil, let installed = plan.installations.first(where: { $0.operation == .install }) {
            page = .library
            clearLibraryFilters()
            selectedSkillID = skills.first { $0.installations.contains { $0.originalPath == installed.destination } }?.id
            if let repository = installed.sourceRepository,
               let entry = selectedSkill?.installations.first(where: { $0.originalPath == installed.destination })?.entry {
                _ = saveSource(for: entry, input: repository)
            }
        }
    }
    func cancelPreview() {
        guard let plan = mutationPreview else { return }
        mutationPreview = nil
        LibraryService.discardInstallation(plan)
    }

    func prepareInstallation(source: URL, root: DiscoveryRoot, repository: SourceRepository? = nil) async -> MutationPlan? {
        guard managementMethod == .direct, canChangeFiles, mutationPreview == nil else { return nil }
        isPreparingChange = true
        defer { isPreparingChange = false }
        let managed = automaticRoots
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                let prepared = try LibraryService.planInstallation(source: source, root: root, managedRoots: managed)
                return MutationPlan(title: prepared.title, installations: prepared.installations.map {
                    var move = $0; move.sourceRepository = repository?.id; return move
                })
            }.value
            libraryMessage = nil
            return plan
        } catch { libraryMessage = error.localizedDescription; return nil }
    }

    func refreshSkillsCLI() {
        let preferred = defaults.string(forKey: Self.skillsCLIPathKey).map { URL(fileURLWithPath: $0) }
        skillsCLIExecutable = skillsCLIService.detect(preferred: preferred)
    }

    func setManagementMethod(_ method: SkillManagementMethod) {
        guard canEditRoots, method == .direct || skillsCLIExecutable != nil else { return }
        managementMethod = method
        updateChecks = [:]; lastUpdatesChecked = nil
        if libraryFilter == .updates { libraryFilter = .all }
        defaults.set(method.rawValue, forKey: Self.managementMethodKey)
    }

    func chooseSkillsCLIExecutable() {
        guard canEditRoots else { return }
        let panel = NSOpenPanel()
        panel.title = "skills CLI 실행 파일 선택"
        panel.message = "bunx, npx 또는 skills 실행 파일을 선택하세요. 감지만으로 실행하거나 다운로드하지 않습니다."
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard skillsCLIService.detect(preferred: url) != nil else { settingsMessage = "실행 가능한 일반 파일을 선택하세요."; return }
        defaults.set(url.path, forKey: Self.skillsCLIPathKey)
        refreshSkillsCLI()
    }

    func prepareSkillsCLIInstallation(source: URL, agent: SkillAgent, remoteSource: URL?) async -> SkillsCLIPlan? {
        await prepareSkillsCLIInstallation(source: source, agents: [agent], remoteSource: remoteSource)
    }

    func prepareSkillsCLIInstallation(source: URL, agents: [SkillAgent], remoteSource: URL?) async -> SkillsCLIPlan? {
        guard managementMethod == .skillsCLI, canChangeFiles, mutationPreview == nil, let executable = skillsCLIExecutable else {
            libraryMessage = "설정에서 skills CLI 실행 파일과 설치 방식을 확인하세요."; return nil
        }
        isPreparingChange = true
        defer { isPreparingChange = false }
        let service = skillsCLIService
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                try service.prepare(folder: source, agents: agents, executable: executable, remoteSource: remoteSource)
            }.value
            libraryMessage = nil
            return plan
        } catch { libraryMessage = error.localizedDescription; return nil }
    }

    func presentSkillsCLIInstall(_ plan: SkillsCLIPlan, download: GitHubSkillDownload?) {
        guard managementMethod == .skillsCLI, canChangeFiles, mutationPreview == nil else { download?.discard(); return }
        skillsCLIDownload = download
        skillsCLIOutput = nil; skillsCLIFailed = false
        skillsCLIPreview = plan
    }

    func cancelSkillsCLIChange() {
        guard !isMutating else { return }
        skillsCLIPreview = nil
        skillsCLIDownload?.discard(); skillsCLIDownload = nil
    }

    func applySkillsCLIChange() async {
        guard let plan = skillsCLIPreview, !isMutating, !isScanning, !isPreparingChange,
              !journalLoadFailed, !groupSyncFailed, journal.pending == nil, mutationPreview == nil,
              !skillsCLIFailed else { return }
        isMutating = true
        let priorSkillID = plan.operation == .update ? skills.first { skill in
            skill.installations.contains { plan.expectedPaths.contains($0.originalPath) }
        }?.id : nil
        let service = skillsCLIService
        var success = false
        do {
            if let repository = plan.updateRepository, let reference = plan.trackedReference, let expected = plan.reviewedCommit {
                let latest = try await gitHubSkills.list(repository: repository.url.absoluteString, reference: reference)
                guard latest.reference == expected else { throw CatalogReadError.inaccessible("검토 후 원격 버전이 바뀌었습니다. 파일을 변경하지 않았습니다. 닫은 뒤 업데이트를 다시 확인하세요.") }
            }
            skillsCLIOutput = try await Task.detached(priority: .userInitiated) { try service.apply(plan) }.value
            libraryMessage = "skills CLI " + plan.operation.title + "를 완료했습니다. CLI가 설치 파일과 설치 기록을 관리합니다."
            success = true
        } catch {
            skillsCLIFailed = true
            libraryMessage = error.localizedDescription
        }
        isMutating = false
        if success {
            cancelSkillsCLIChange()
            for root in plan.roots where !registeredRoots.contains(where: { $0.url.path == root.url.path }) && FileManager.default.fileExists(atPath: root.url.path) {
                _ = addRoot(url: root.url, agent: root.agent, name: root.label)
            }
        }
        await rescan()
        if success {
            page = .library; clearLibraryFilters()
            selectedSkillID = skills.first { skill in skill.installations.contains { plan.expectedPaths.contains($0.originalPath) } }?.id
            if let old = priorSkillID, let current = selectedSkillID, old != current, !preferencesLoadFailed {
                var updated = preferences
                if updated.favorites.remove(old) != nil { updated.favorites.insert(current) }
                for index in updated.groups.indices where updated.groups[index].skillIDs.remove(old) != nil {
                    updated.groups[index].skillIDs.insert(current)
                }
                _ = savePreferences(updated)
            }
        }
    }

    func prepareRemoval(_ installations: [SkillInstallation], allAgents: Bool = false) async {
        guard canChangeFiles, mutationPreview == nil else { return }
        isPreparingChange = true
        defer { isPreparingChange = false }
        let all = allInstallations, managed = automaticRoots, roots = registeredRoots
        do {
            if managementMethod == .skillsCLI {
                guard let executable = skillsCLIExecutable else { throw CatalogReadError.inaccessible("skills CLI를 찾을 수 없습니다. 설정에서 실행 파일을 확인하세요. 다른 삭제 방식으로 자동 전환하지 않습니다.") }
                let service = skillsCLIService
                let plan = try await Task.detached(priority: .userInitiated) {
                    try service.prepareRemoval(installations: installations, allInstallations: all, executable: executable, allAgents: allAgents)
                }.value
                skillsCLIFailed = false; skillsCLIOutput = nil; skillsCLIPreview = plan
                libraryMessage = nil
                return
            }
            mutationPreview = try await Task.detached(priority: .userInitiated) {
                try LibraryService.planRemoval(installations: installations, allInstallations: all,
                    managedRoots: managed, protectedRoots: roots)
            }.value
            libraryMessage = nil
        } catch { libraryMessage = error.localizedDescription }
    }

    var canCheckUpdates: Bool { managementMethod == .skillsCLI && canChangeFiles && mutationPreview == nil }
    var availableUpdateCount: Int { skills.filter { updateChecks[$0.id]?.status == .available }.count }

    func checkSkillUpdates(_ selected: [CanonicalSkill]? = nil) async {
        guard canCheckUpdates else { return }
        let targets = selected ?? skills
        isCheckingUpdates = true
        defer { isCheckingUpdates = false; updatesProgress = "" }
        let service = skillsCLIService
        let github = gitHubSkills
        var listings: [String: GitHubSkillListing] = [:], failures: [String: String] = [:]
        for (index, skill) in targets.enumerated() {
            if Task.isCancelled { break }
            updatesProgress = "\(index + 1)/\(targets.count) · " + skill.name
            let source: SkillUpdateSource
            do {
                source = try await Task.detached(priority: .userInitiated) {
                    try service.updateSource(for: skill.installations)
                }.value
            } catch {
                updateChecks[skill.id] = SkillUpdateCheck(status: .unavailable, message: error.localizedDescription)
                continue
            }
            do {
                let key = source.repository.id + "|" + (source.reference ?? "HEAD")
                if let failure = failures[key] { throw CatalogReadError.inaccessible(failure) }
                let listing: GitHubSkillListing
                if let cached = listings[key] { listing = cached }
                else {
                    do {
                        listing = try await github.list(repository: source.repository.url.absoluteString, reference: source.reference)
                        listings[key] = listing
                    } catch { failures[key] = error.localizedDescription; throw error }
                }
                let directory = source.skillPath == "SKILL.md" ? "" : String(source.skillPath.dropLast("/SKILL.md".count))
                guard let candidate = listing.skills.first(where: { $0.path == directory }) else {
                    throw CatalogReadError.inaccessible("원격 스킬 경로가 이동·삭제됐습니다. 기존 설치는 유지합니다. 출처를 확인하세요.")
                }
                let folders = Set(skill.installations.map { $0.resolvedPath ?? $0.originalPath })
                let matches = try await Task.detached(priority: .userInitiated) {
                    try folders.allSatisfy { try GitHubSkillService.contentMatches(folder: URL(fileURLWithPath: $0), skill: candidate, listing: listing) }
                }.value
                let ref = source.pinnedCommit ? "고정된 커밋을 최신 기본 브랜치와 비교했습니다." : "설치 기록의 기준(" + (source.reference ?? "기본 브랜치") + ")과 비교했습니다."
                let sameRemoteVersion = source.installedFolderHash != nil && source.installedFolderHash == listing.folderHash(for: candidate)
                updateChecks[skill.id] = SkillUpdateCheck(status: matches ? .current : sameRemoteVersion ? .modified : .available,
                    message: ref + (matches ? " 포함 파일 내용이 같습니다." : sameRemoteVersion
                        ? " 원격은 설치 기록과 같지만 로컬 파일 내용이 다릅니다. 원격 버전으로 복원하면 로컬 수정을 덮어씁니다."
                        : " 포함 파일이 다릅니다. 업데이트하면 로컬 수정도 덮어씁니다."),
                    source: source, listing: listing, candidate: candidate)
            } catch {
                updateChecks[skill.id] = SkillUpdateCheck(status: .failed, message: error.localizedDescription)
            }
        }
        lastUpdatesChecked = .now
    }

    func prepareSkillUpdate(_ skill: CanonicalSkill) async {
        guard managementMethod == .skillsCLI, canChangeFiles, mutationPreview == nil,
              let executable = skillsCLIExecutable else { libraryMessage = "설정에서 skills CLI 관리 도구와 실행 파일을 확인하세요."; return }
        guard let check = updateChecks[skill.id], check.status == .available || check.status == .modified,
              let source = check.source, let listing = check.listing, let candidate = check.candidate,
              let reference = listing.reference else { libraryMessage = "먼저 업데이트를 확인하세요."; return }
        isPreparingChange = true
        defer { isPreparingChange = false }
        var download: GitHubSkillDownload?
        defer { download?.discard() }
        do {
            let fetched = try await gitHubSkills.download(candidate, from: listing)
            download = fetched
            var url = listing.repository.url.appendingPathComponent("tree").appendingPathComponent(reference)
            for part in candidate.path.split(separator: "/") { url.appendPathComponent(String(part)) }
            let remote = url, service = skillsCLIService
            let plan = try await Task.detached(priority: .userInitiated) {
                try service.prepareUpdate(folder: fetched.folder, installations: skill.installations, source: source, remoteSource: remote, executable: executable,
                                          trackingReference: listing.trackingReference)
            }.value
            guard !Task.isCancelled else { return }
            skillsCLIDownload = fetched; download = nil
            skillsCLIFailed = false; skillsCLIOutput = nil; skillsCLIPreview = plan
            libraryMessage = nil
        } catch { libraryMessage = error.localizedDescription }
    }


    var selectedAgentRequest: AgentChangeRequest? { agentRequests.first { $0.id == selectedAgentRequestID } }
    var filteredAgentRequests: [AgentChangeRequest] { agentRequests.filter { matchesSearch($0.title + " " + $0.id.uuidString) } }

    func agentRequestState(_ request: AgentChangeRequest) -> String {
        if journal.pending?.id == request.id { return "복구 필요" }
        if journal.completed.contains(where: { $0.id == request.id }) { return "적용 완료" }
        if Date().timeIntervalSince(request.createdAt) > 86_400 { return "만료됨" }
        return "검토 대기"
    }

    func refreshAgentRequests() async {
        do { agentRequests = try await agentRequestStore.list(); agentRequestsMessage = nil }
        catch { agentRequestsMessage = "에이전트 요청을 읽을 수 없습니다. 기존 요청은 보존했습니다. " + error.localizedDescription }
    }

    func prepareAgentRequest(_ request: AgentChangeRequest) async {
        guard metadataIsEditable, canChangeFiles, mutationPreview == nil,
              !journal.completed.contains(where: { $0.id == request.id }) else {
            libraryMessage = "진행 중인 검토·복구를 마친 뒤 새 요청을 검토할 수 있습니다."; return
        }
        await rescan()
        guard metadataIsEditable, canChangeFiles, mutationPreview == nil, !preferencesLoadFailed else { return }
        do {
            let configuration = try ManagementConfiguration(home: home, domain: Bundle.main.bundleIdentifier ?? "AgentHarnessManager",
                preferencesData: JSONEncoder().encode(preferences), rootsData: JSONEncoder().encode(additionalRoots))
            let snapshot = ManagementSnapshot(configuration: configuration, journal: journal, skills: skills, observations: roots)
            let plan = try request.validatedPlan(snapshot: snapshot)
            guard !plan.installations.isEmpty else { libraryMessage = "이미 요청한 상태입니다."; return }
            mutationPreview = plan; libraryMessage = nil
        } catch { libraryMessage = error.localizedDescription }
    }

    func dismissAgentRequest(_ request: AgentChangeRequest) async {
        guard mutationPreview == nil, !isMutating, !isPreparingChange, journal.pending?.id != request.id else { return }
        do { try await agentRequestStore.remove(request.id); await refreshAgentRequests() }
        catch { agentRequestsMessage = error.localizedDescription }
    }
    func undoUnavailableReason(for plan: MutationPlan) -> String? {
        if let reason = journal.undoUnavailableReason(for: plan.id) { return reason }
        if let selection = plan.groupSelection {
            if preferencesLoadFailed || preferences.activeGroupIDs != selection.after || !selection.before.isSubset(of: Set(groups.map(\.id))) {
                return "그룹 선택이나 그룹 목록이 변경되어 이전 선택을 복원할 수 없습니다."
            }
        }
        return nil
    }
    func prepareUndo(_ plan: MutationPlan) async {
        guard canChangeFiles, mutationPreview == nil else { return }
        if let reason = undoUnavailableReason(for: plan) { libraryMessage = reason; return }
        isPreparingChange = true
        defer { isPreparingChange = false }
        do {
            mutationPreview = try await libraryService.planUndo(id: plan.id, roots: registeredRoots)
            libraryMessage = nil
        } catch { libraryMessage = error.localizedDescription }
    }
    func recoverChanges() async {
        guard !isScanning, !isMutating, !isPreparingChange else { return }
        isMutating = true
        do { try await libraryService.recover(roots: registeredRoots); libraryMessage = "중단된 파일 변경을 마쳤습니다." }
        catch { libraryMessage = error.localizedDescription }
        isMutating = false
        await rescan()
    }
}
