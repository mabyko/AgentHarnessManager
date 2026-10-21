import AppKit
import SkillCore
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var groupEditor: SkillGroup?
    @State private var showsInstaller = false
    @State private var installationPlan: MutationPlan?
    @State private var preparedCLIInstall: (SkillsCLIPlan, GitHubSkillDownload?)?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            VStack(spacing: 0) {
                listHeader
                Divider()
                switch store.page {
                case .library: skillList
                case .groups: groupList
                case .findings: findingList
                case .history: historyList
                case .changes: mutationList
                case .requests: agentRequestList
                case .instructions: InstructionFileList()
                case .profiles:
                    ContentUnavailableView("이전 작업 구성", systemImage: "archivebox", description: Text("기존 데이터와 메모를 오른쪽에서 확인하세요. 그룹으로 가져온 뒤에도 원본은 보존됩니다."))
                }
                Divider()
                HStack {
                    if store.page == .instructions {
                        Text("있음 \(store.instructions.agentDocuments.filter { $0.data != nil }.count) · 후보 \(store.instructions.agentDocuments.count)")
                            .accessibilityIdentifier("instructions.counts")
                            .help("파일 탐지는 현재 에이전트 세션의 지침 로딩을 확인하지 않습니다.")
                    }
                    else if store.isScanning || store.isPreparingChange || store.isCheckingUpdates {
                        ProgressView().controlSize(.mini)
                        Text(store.isCheckingUpdates ? store.updatesProgress : store.isPreparingChange ? "변경 계획 확인 중" : "확인 중").lineLimit(1)
                    }
                    else { Text("스킬 \(store.skills.count) · 설치 \(store.allInstallations.count)") }
                    Spacer()
                    if store.page != .instructions, let date = store.lastScanned { Text(date, format: .dateTime.hour().minute()) }
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WorkbenchTheme.surface)
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
        } detail: {
            VStack(spacing: 0) {
                notices
                switch store.page {
                case .library:
                    if store.selectedSkills.count > 1 {
                        ContentUnavailableView("\(store.selectedSkills.count)개 스킬 선택", systemImage: "checklist",
                            description: Text(store.managementMethod == .skillsCLI
                                ? "목록 위의 CLI 삭제 버튼에서 선택한 스킬과 전체 설치 범위를 검토하세요."
                                : "일괄 삭제는 설정 → 일반에서 skills CLI 관리 도구를 선택하면 사용할 수 있습니다."))
                    }
                    else if let skill = store.selectedSkill { LibrarySkillDetail(skill: skill).id(skill.id) }
                    else { selectionPrompt(store.selectedSkillID == nil ? "스킬을 선택하세요" : "선택한 스킬을 찾을 수 없습니다", symbol: "doc.text", description: "설치 위치와 상태, 그룹, SKILL.md 원문을 확인할 수 있습니다.") }
                case .groups:
                    if let group = store.selectedGroup { GroupDetail(group: group) { groupEditor = group } }
                    else { selectionPrompt("그룹을 선택하세요", symbol: "folder", description: "함께 사용할 스킬을 그룹으로 정리하세요.") }
                case .findings:
                    if let finding = store.currentFindings.first(where: { $0.id == store.selectedFindingID }) { FindingDetail(finding: finding) }
                    else { selectionPrompt("검사 결과를 선택하세요", symbol: "checkmark.shield", description: "로컬 검사에서는 문서 읽기와 메타데이터, 등록 경로의 문제를 확인합니다.") }
                case .history:
                    if let record = store.selectedReview { ReviewDetail(record: record) }
                    else { selectionPrompt("검사 이력을 선택하세요", symbol: "clock.arrow.circlepath", description: "저장한 검사 시점의 근거와 현재 상태를 비교할 수 있습니다.") }
                case .changes:
                    if let plan = store.selectedMutation { MutationDetail(plan: plan) }
                    else { selectionPrompt("변경 이력을 선택하세요", symbol: "arrow.left.arrow.right", description: "완료·중단된 작업의 이동 경로를 확인하고, 되돌릴 작업을 검토할 수 있습니다.") }
                case .requests:
                    if let request = store.selectedAgentRequest { AgentRequestDetail(request: request) }
                    else { selectionPrompt("에이전트 요청을 선택하세요", symbol: "tray.and.arrow.down", description: "CLI·MCP에서 보낸 요청을 확인하세요. 검토·적용 전에는 스킬 파일을 변경하지 않습니다.") }
                case .profiles: ProfilesView()
                case .instructions: InstructionDetail()
                }
            }
            .frame(minWidth: 360)
            .background(WorkbenchTheme.surface)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("Agent Harness Manager")
        .tint(WorkbenchTheme.accent)
        .toolbar {
            ToolbarItem {
                Button { Task {
                    if store.page == .instructions { await store.instructions.refresh(); await store.instructions.loadBackups() }
                    else { await store.rescan() }
                } } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    .disabled(store.isScanning || store.isMutating || store.isPreparingChange || store.isCheckingUpdates || store.instructions.busy).help("현재 목록 다시 확인 (⌘R)")
            }
            ToolbarItem {
                if store.page != .instructions { Button { store.runLocalReview() } label: { Label("검사", systemImage: "checkmark.shield") }
                    .disabled(!store.hasScanned || store.isScanning || store.isMutating || store.isPreparingChange || store.reviewsLoadFailed)
                }
            }
            ToolbarItem { Button { openSettings() } label: { Label("설정", systemImage: "gearshape") } }
        }
        .searchable(text: $store.search, placement: .toolbar, prompt: store.page == .instructions ? "지침 파일 이름 또는 경로 검색" : store.page == .requests ? "요청 제목 또는 ID 검색" : "이름, 설명 또는 경로 검색")
        .onChange(of: [store.search, store.libraryFilter.rawValue, store.groupFilterID?.uuidString ?? "", store.agentFilter?.rawValue ?? "", store.rootFilterID ?? "", store.sourceFilterID ?? "", String(store.linksOnly)]) { _, _ in
            store.selectSkills(store.selectedSkillIDs)
        }
        .sheet(isPresented: $showsInstaller, onDismiss: {
            if let plan = installationPlan { store.mutationPreview = plan; installationPlan = nil }
            if let pending = preparedCLIInstall { store.presentSkillsCLIInstall(pending.0, download: pending.1); preparedCLIInstall = nil }
        }) {
            SkillInstallSheet(onPrepared: { installationPlan = $0 }, onCLIPrepared: { preparedCLIInstall = ($0, $1) })
        }
        .sheet(item: $groupEditor) { GroupEditor(group: $0) }
        .sheet(item: $store.skillsCLIPreview, onDismiss: { store.cancelSkillsCLIChange() }) { SkillsCLIReview(plan: $0) }
        .sheet(item: $store.mutationPreview, onDismiss: { store.cancelPreview() }) { MutationPreview(plan: $0) }
        .sheet(item: Binding(get: { store.instructions.preview }, set: { store.instructions.preview = $0 })) {
            InstructionChangeReview(plan: $0, editor: store.instructions)
        }
        .task { if !store.hasScanned && !store.isScanning { await store.rescan() } }
        .task(id: store.page) { if store.page == .instructions, !store.instructions.loaded { await store.instructions.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshAgentRequests() }
            if store.page == .instructions { Task { await store.instructions.refresh() } }
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(listTitle).font(.title2.weight(.semibold)).accessibilityIdentifier("workbench.listTitle")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if store.page == .library {
                    Button { showsInstaller = true } label: { Label("설치…", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).disabled(!store.metadataIsEditable)
                        .accessibilityIdentifier("library.install")
                }
                if store.page == .groups {
                    Button { groupEditor = SkillGroup() } label: { Label("새 그룹", systemImage: "plus") }
                        .labelStyle(.iconOnly).buttonStyle(.bordered)
                        .keyboardActivation { groupEditor = SkillGroup() }
                        .disabled(!store.metadataIsEditable).accessibilityIdentifier("groups.new")
                }
            }
            if store.page.destination == .skills {
                Picker("라이브러리 항목", selection: sectionSelection) {
                    Text("스킬").tag(AppPage.library)
                    Text("그룹").tag(AppPage.groups)
                    Text("검사 결과").tag(AppPage.findings)
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityLabel("라이브러리 항목").accessibilityIdentifier("workbench.skillSection")
            }
            if store.page.destination == .activity {
                Picker("활동 항목", selection: sectionSelection) {
                    Text("요청").tag(AppPage.requests)
                    Text("변경").tag(AppPage.changes)
                    Text("검사 이력").tag(AppPage.history)
                    if !store.profiles.isEmpty || store.profilesLoadFailed || store.page == .profiles { Text("보관").tag(AppPage.profiles) }
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityLabel("활동 항목").accessibilityIdentifier("workbench.activitySection")
            }
            if store.page == .library {
                LibraryFilters()
                HStack(spacing: 8) {
                    Button { Task { await store.checkSkillUpdates() } } label: {
                        if store.isCheckingUpdates { ProgressView().controlSize(.small); Text("업데이트 확인 중…") }
                        else { Label("전체 업데이트 확인", systemImage: "arrow.triangle.2.circlepath") }
                    }.disabled(!store.canCheckUpdates || store.skills.isEmpty)
                        .accessibilityIdentifier("library.checkUpdates")
                        .help("현재 필터와 관계없이 전체 스킬의 업데이트 유무를 확인합니다. 파일을 바꾸지 않으며, 실제 적용은 각 스킬의 업데이트 검토에서 진행합니다.")
                    Spacer(minLength: 0)
                    if store.availableUpdateCount > 0 && store.libraryFilter != .updates {
                        Button("업데이트 \(store.availableUpdateCount)개 보기") { store.libraryFilter = .updates }
                            .font(.caption).accessibilityIdentifier("library.showUpdates")
                    } else if let date = store.lastUpdatesChecked {
                        Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                            .help("업데이트를 확인한 시각입니다. 확인 불가·실패 항목은 각 스킬 상세에서 확인하세요.")
                    }
                }
                if store.selectedSkillIDs.count > 1 && store.managementMethod == .skillsCLI {
                    HStack {
                        Button { Task { await store.prepareSelectedSkillsRemoval() } } label: {
                            Label("선택한 \(store.selectedSkills.count)개 CLI 삭제…", systemImage: "trash")
                        }.disabled(!store.canChangeFiles || store.mutationPreview != nil)
                            .accessibilityIdentifier("library.removeSelected")
                        Spacer(minLength: 0)
                        Button("선택 해제") { store.selectSkills([]) }.buttonStyle(.plain).font(.caption)
                            .disabled(!store.metadataIsEditable)
                    }
                }
                if store.managementMethod != .skillsCLI {
                    Button("설정에서 skills CLI 관리 선택…") { openSettings() }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if store.page == .groups {
                Picker("그룹 전환", selection: Binding(get: { store.preferences.groupSelectionMode }, set: { store.setGroupMode($0) })) {
                    Text("여러 그룹 함께 켜기").tag(GroupSelectionMode.multiple)
                    Text("다른 그룹 끄기").tag(GroupSelectionMode.single)
                }.disabled(!store.metadataIsEditable)
            }
            if store.page == .findings { Text("로컬 검사 · \(store.filteredFindings.count)건").font(.caption).foregroundStyle(.secondary) }
            if store.page == .history { Text("로컬 검사 이력 · 최근 50회 보관").font(.caption).foregroundStyle(.secondary) }
            if store.page == .changes { Text("완료 기록 최근 100회 · 중단된 작업 포함").font(.caption).foregroundStyle(.secondary) }
            if store.page == .requests { Text("에이전트가 제안한 변경 · 앱에서 검토 후 적용").font(.caption).foregroundStyle(.secondary) }
            if store.page == .instructions { InstructionAgentPicker() }
        }.padding(16)
    }
    private var listTitle: String {
        switch store.page.destination {
        case .skills: "스킬 라이브러리"
        case .instructions: "전역 지침"
        case .activity: "활동 이력"
        }
    }
    private var sectionSelection: Binding<AppPage> {
        Binding(get: { store.page }, set: { page in
            guard page != store.page else { return }
            switch page {
            case .library: store.navigate()
            case .findings: store.navigate(.findings)
            default: store.page = page
            }
        })
    }
    private var skillList: some View {
        @Bindable var store = store
        return List(selection: Binding(get: { store.selectedSkillIDs }, set: { store.selectSkills($0) })) {
            ForEach(store.filteredSkills) { skill in
                SkillListRow(skill: skill).tag(skill.id)
                    .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(store.selectedSkillIDs.contains(skill.id) ? WorkbenchTheme.selection : WorkbenchTheme.surface).padding(.vertical, 3))
            }
        }
        .listStyle(.inset).scrollContentBackground(.hidden)
        .accessibilityIdentifier("library.skillList")
        .help("⌘클릭 또는 ⇧클릭으로 여러 스킬을 선택할 수 있습니다. ⌘A는 현재 목록 전체를 선택합니다.")
        .overlay { if store.filteredSkills.isEmpty { emptyList("스킬이 없습니다", description: store.hasFilters ? "검색어나 필터를 바꿔 보세요." : "위의 설치 버튼으로 스킬을 추가하세요. 기존 폴더는 설정에서 등록할 수 있습니다.") } }
    }

    private var agentRequestList: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            if let message = store.agentRequestsMessage { Text(message).font(.callout).padding(16) }
            List(selection: $store.selectedAgentRequestID) {
                ForEach(store.filteredAgentRequests) { request in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(request.title).lineLimit(2)
                        Text("\(store.agentRequestState(request)) · \(request.moves.count)개 이동")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(request.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(request.id)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
                .overlay {
                    if store.agentRequests.isEmpty && store.agentRequestsMessage == nil {
                        emptyList("에이전트 요청이 없습니다", description: "설정에서 에이전트 연동을 설치한 뒤 변경 요청을 보내세요.")
                    }
                }
        }
    }
    private var groupList: some View {
        @Bindable var store = store
        return List(selection: $store.selectedGroupID) {
            ForEach(store.filteredGroups) { group in
                HStack {
                    Image(systemName: group.symbol).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).fontWeight(.medium)
                        Text("스킬 \(group.skillIDs.count)개").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("\(group.name) 켜기", isOn: Binding(get: { groupIsOn(group) }, set: { enabled in Task { await store.prepareGroupChange(group, enabled: enabled) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!store.canChangeFiles || !store.metadataIsEditable)
                }.padding(.vertical, 6).tag(group.id)
            }
        }.listStyle(.inset).scrollContentBackground(.hidden)
            .overlay { if store.filteredGroups.isEmpty { emptyList("그룹이 없습니다", description: "새 그룹을 만들고 함께 사용할 스킬을 선택하세요.") } }
    }
    private var findingList: some View {
        @Bindable var store = store
        return List(selection: $store.selectedFindingID) {
            ForEach(store.filteredFindings) { finding in
                VStack(alignment: .leading, spacing: 6) {
                    Label(finding.title, systemImage: "exclamationmark.triangle").fontWeight(.medium)
                    Text(finding.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Text((finding.path as NSString).abbreviatingWithTildeInPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 6).tag(finding.id)
            }
        }.listStyle(.inset).scrollContentBackground(.hidden)
            .overlay { if store.filteredFindings.isEmpty { emptyList("확인이 필요한 결과가 없습니다", description: "파일 발견은 에이전트의 실제 로딩을 뜻하지 않습니다.") } }
    }
    private var historyList: some View {
        @Bindable var store = store
        return List(selection: $store.selectedReviewID) {
            ForEach(store.filteredReviews) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.date, format: .dateTime.month().day().hour().minute()).fontWeight(.medium)
                    Text("\(record.provider) · 스킬 \(record.skillCount)개").font(.caption).foregroundStyle(.secondary)
                    Text("확인 필요 \(record.findings.count)건").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6).tag(record.id)
            }
        }.listStyle(.inset).scrollContentBackground(.hidden)
            .overlay { if store.filteredReviews.isEmpty { emptyList("저장한 검사가 없습니다", description: "도구 막대의 검사를 누르면 현재 결과가 저장됩니다.") } }
    }
    private var notices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.libraryMessage {
                HStack(alignment: .top) {
                    Label(message, systemImage: "info.circle").font(.caption)
                    Spacer(minLength: 4)
                    if store.selectedMutationID != nil, store.page != .changes {
                        Button("변경 이력") { store.page = .changes }.font(.caption)
                    }
                    Button { store.libraryMessage = nil } label: { Label("알림 닫기", systemImage: "xmark") }.labelStyle(.iconOnly).buttonStyle(.plain)
                }.padding(12)
            }
            if let message = store.sourceMessage, store.page == .library {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).padding(12).foregroundStyle(WorkbenchTheme.warning)
            }
            if store.journalLoadFailed {
                Label("변경 기록을 확인할 수 없어 파일 변경을 잠갔습니다. 기록을 보존한 채 원인을 해결하고 새로고침해 주세요.", systemImage: "lock")
                    .font(.caption).padding(12).foregroundStyle(WorkbenchTheme.warning)
            }
            if store.journal.pending != nil {
                HStack {
                    Label("중단된 파일 변경이 있습니다. 기록된 작업을 마쳐야 다른 변경을 할 수 있습니다.", systemImage: "exclamationmark.triangle")
                    Button("복구 재시도") { Task { await store.recoverChanges() } }.disabled(store.isScanning || store.isMutating || store.isPreparingChange)
                    Button("상세") { store.selectedMutationID = store.journal.pending?.id; store.page = .changes }
                }.font(.caption).padding(12).background(WorkbenchTheme.warningSurface)
            }
            if store.journal.disabled.contains(where: { !$0.matchesCurrentItem }) {
                Label("보관 항목의 위치나 식별 정보가 바뀌었습니다. 변경 기록을 보존했습니다. 원래 폴더를 확인하세요.", systemImage: "exclamationmark.triangle").font(.caption).padding(12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var mutationList: some View {
        @Bindable var store = store
        return List(selection: $store.selectedMutationID) {
            ForEach(store.filteredMutations) { plan in
                VStack(alignment: .leading, spacing: 6) {
                    Label(plan.title, systemImage: plan.undoes == nil ? "arrow.left.arrow.right" : "arrow.uturn.backward")
                        .fontWeight(.medium).lineLimit(2).foregroundStyle(.primary)
                    HStack {
                        Text(store.journal.pending?.id == plan.id ? "복구 필요" : "완료")
                        if let date = plan.completedAt ?? plan.createdAt {
                            Text(date, format: .dateTime.month().day().hour().minute())
                        } else { Text("이전 기록 · 시각 미기록") }
                    }.font(.caption).foregroundStyle(.secondary)
                    Text("파일 이동 \(plan.installations.count)건" + (plan.groupSelection == nil ? "" : " · 그룹 선택 변경"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6).tag(plan.id)
            }
        }.listStyle(.inset).scrollContentBackground(.hidden)
            .overlay {
                if store.filteredMutations.isEmpty {
                    emptyList(store.search.isEmpty ? "변경 기록이 없습니다" : "일치하는 변경 기록이 없습니다",
                              description: store.search.isEmpty ? "검토 후 적용한 파일 변경과 그룹 선택이 여기에 저장됩니다." : "작업 이름이나 설치 경로로 다시 검색하세요.")
                }
            }
    }
    private func groupIsOn(_ group: SkillGroup) -> Bool { store.preferences.activeGroupIDs.contains(group.id) }
    private func emptyList(_ title: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: store.isScanning ? "arrow.clockwise" : "magnifyingglass", description: Text(description)).padding(12)
    }
    private func selectionPrompt(_ title: String, symbol: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(description)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryFilters: View {
    @Environment(AppStore.self) private var store
    @State private var showsFilters = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("보기", selection: $store.libraryFilter) {
                    ForEach(LibraryFilter.allCases.filter { $0 != .findings }) { filter in
                        Text("\(filter.title) · \(store.count(filter))").tag(filter)
                    }
                }.labelsHidden().accessibilityLabel("스킬 보기").accessibilityIdentifier("library.scope")
                Spacer(minLength: 0)
                Button { showsFilters.toggle() } label: {
                    Label(filterCount == 0 ? "필터" : "필터 \(filterCount)", systemImage: "line.3.horizontal.decrease")
                }.accessibilityIdentifier("library.filters")
                    .popover(isPresented: $showsFilters, arrowEdge: .bottom) { filterPanel }
            }.controlSize(.regular)
            if filterCount > 0 {
                Button { showsFilters = true } label: {
                    Text(filterSummary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("적용 중인 필터: " + filterSummary)
            }
            HStack {
                Text("스킬 \(store.filteredSkills.count)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.hasFilters {
                    Button("필터 초기화") { store.clearLibraryFilters() }
                        .buttonStyle(.plain).font(.caption)
                        .accessibilityIdentifier("library.clearFilters")
                }
            }
        }
    }

    private var filterPanel: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("스킬 필터").font(.headline)
                Spacer()
                Button("완료") { showsFilters = false }.keyboardShortcut(.cancelAction)
            }
            Form {
                Picker("에이전트", selection: $store.agentFilter) {
                    Text("모든 에이전트").tag(SkillAgent?.none)
                    ForEach(menuAgents, id: \.self) { agent in
                        Label { Text(agentTitle(agent)) } icon: { AgentIcon(agent: agent) }.tag(Optional(agent))
                    }
                }.accessibilityIdentifier("library.agent")
                Picker("그룹", selection: $store.groupFilterID) {
                    Text("모든 그룹").tag(UUID?.none)
                    ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                }.accessibilityIdentifier("library.group")
                Picker("설치 위치", selection: $store.rootFilterID) {
                    Text("모든 설치 위치").tag(String?.none)
                    ForEach(store.availableRoots) { Text($0.label).tag(Optional($0.id)) }
                }.accessibilityIdentifier("library.root")
                Picker("출처", selection: $store.sourceFilterID) {
                    Text("모든 출처").tag(String?.none)
                    ForEach(store.sourceGroups) { Text($0.repository.name).tag(Optional($0.id)) }
                    Text("출처 미확인").tag(Optional(AppStore.unknownSourceID))
                }.accessibilityIdentifier("library.source")
                Toggle("설치 링크만 보기", isOn: $store.linksOnly).toggleStyle(.checkbox)
            }.pickerStyle(.menu)
            Divider()
            HStack {
                Text("일치하는 스킬 \(store.filteredSkills.count)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("필터 초기화") { store.clearLibraryFilters() }
                    .disabled(!store.hasFilters).accessibilityIdentifier("library.clearFilters")
            }
        }.padding(20).frame(width: 340)
    }

    private var filterCount: Int {
        [store.agentFilter != nil, store.groupFilterID != nil, store.rootFilterID != nil,
         store.sourceFilterID != nil, store.linksOnly].filter { $0 }.count
    }
    private var filterSummary: String {
        [store.agentFilter.map { agentTitle($0) }, store.groups.first { $0.id == store.groupFilterID }?.name,
         store.availableRoots.first { $0.id == store.rootFilterID }?.label,
         store.sourceFilterID == nil ? nil : store.sourceTitle, store.linksOnly ? "설치 링크만" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
    private var menuAgents: [SkillAgent] {
        let agents = store.sidebarAgents
        guard let selected = store.agentFilter, !agents.contains(selected) else { return agents }
        return agents + [selected]
    }
    private func agentTitle(_ agent: SkillAgent) -> String {
        if let target = AgentConnectionTarget(rawValue: agent.rawValue), store.agentInstallations[target]?.isInstalled == false {
            return "\(agent.displayName) (미설치)"
        }
        return agent.displayName
    }
}

private struct SkillListRow: View {
    let skill: CanonicalSkill
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: skill.installations.allSatisfy(\.isSymbolicLink) ? "link" : "doc.text").foregroundStyle(WorkbenchTheme.sidebarSecondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(skill.name).font(.callout.weight(.semibold)).foregroundStyle(WorkbenchTheme.sidebarText).lineLimit(2)
                    if store.preferences.favorites.contains(skill.id) { Image(systemName: "star.fill").font(.caption).accessibilityLabel("즐겨찾기") }
                }
                Text(skill.summary).font(.caption).foregroundStyle(WorkbenchTheme.sidebarSecondary).lineLimit(2)
                if let check = store.updateChecks[skill.id], check.status == .available || check.status == .modified || check.status == .failed {
                    Label(check.title, systemImage: check.symbol).font(.caption.weight(.medium))
                        .foregroundStyle(check.status == .available ? WorkbenchTheme.accent : WorkbenchTheme.warning)
                }
                                HStack(spacing: 6) {
                    Text("설치 \(skill.installations.count)")
                    Text(stateTitle)
                    if skill.hasProblems { Label("확인 필요", systemImage: "exclamationmark.triangle") }
                }.font(.caption2).foregroundStyle(WorkbenchTheme.sidebarSecondary)
            }
        }.padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
    private var stateTitle: String {
        let enabled = skill.installations.filter(\.isEnabled).count
        return enabled == 0 ? "꺼짐" : enabled == skill.installations.count ? "켜짐" : "일부 켜짐"
    }
}
