import AppKit
import SkillCore
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if store.page == .profiles {
                    ProfilesView()
                } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.page == .library ? store.sourceTitle : store.page.title).font(.title2.weight(.semibold))
                        Text(scopeTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(store.filteredEntries.count + (store.page == .findings ? store.filteredProblemRoots.count : 0))개 표시")
                        if store.page == .library {
                            Text("출처 전체 \(store.sourceEntryCount)개").font(.caption)
                        }
                    }.foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(24)
                filters
                if let message = store.sourceMessage, store.page == .library {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(WorkbenchTheme.warning)
                        .padding(.horizontal, 24).padding(.bottom, 12)
                }
                Divider()
                if store.filteredEntries.isEmpty && (store.page != .findings || store.filteredProblemRoots.isEmpty) {
                    emptyState.frame(maxHeight: .infinity)
                } else {
                    List {
                        if store.page == .findings {
                            ForEach(store.filteredProblemRoots) { observation in
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(observation.root.label, systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(WorkbenchTheme.warning)
                                    Text(observation.root.url.displayPath).font(.caption).foregroundStyle(.secondary)
                                    if let message = observation.message { Text(message).font(.caption) }
                                    Button("설정에서 경로 확인") { openSettings() }
                                }.padding(.vertical, 8)
                            }
                        }
                        ForEach(store.filteredEntries) { entry in entryRow(entry) }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
                }
                Divider()
                HStack {
                    Label("스킬 파일 읽기 전용", systemImage: "lock")
                    Spacer()
                    if store.isScanning {
                        ProgressView().controlSize(.mini)
                        Text("새로고침 중")
                    } else if let date = store.lastScanned {
                        Text("마지막 확인")
                        Text(date, format: .dateTime.hour().minute())
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(WorkbenchTheme.raised)
            }
            .background(WorkbenchTheme.surface)
            .navigationTitle("Agent Plugin Manager")
            .toolbar {
                ToolbarItem {
                    Button { Task { await store.rescan() } } label: {
                        Label("새로고침", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                    }.disabled(store.isScanning).help("등록한 스킬 폴더를 다시 읽습니다 (⌘R)")
                }
                ToolbarItem {
                    Button { openSettings() } label: {
                        Label("설정", systemImage: "gearshape").labelStyle(.titleAndIcon)
                    }.help("에이전트 경로와 화면 모드 관리 (⌘,)")
                }
            }
            .searchable(text: $store.search, placement: .toolbar, prompt: store.page == .profiles ? "작업 구성 검색" : "이름, 출처 또는 설치 경로")
        }
        .tint(WorkbenchTheme.accent)
        .sheet(item: $store.selectedEntry) { entry in
            SkillDetailSheet(entry: entry, roots: store.registeredRoots, agentName: store.agentName(for: entry))
        }
        .task { if !store.hasScanned && !store.isScanning { await store.rescan() } }
    }

    private var sidebar: some View {
        List {
            Section {
                navigationRow(.profiles)
                navigationRow(.library)
                navigationRow(.findings)
            } header: { Text("스킬 관리").foregroundStyle(WorkbenchTheme.sidebarText) }
            Section {
                sourceRow("모든 출처", id: nil, count: store.entries.count)
                ForEach(store.sourceGroups) { group in
                    sourceRow(group.repository.name, id: group.id, count: group.count)
                }
                sourceRow("출처 미확인", id: AppStore.unknownSourceID, count: store.unknownSourceCount)
            } header: { Text("출처").foregroundStyle(WorkbenchTheme.sidebarText) }

        }.listStyle(.sidebar)
    }

    private func sourceRow(_ title: String, id: String?, count: Int) -> some View {
        let selected = store.page == .library && store.sourceFilterID == id
        return Button { store.showLibrary(sourceID: id) } label: {
            HStack(spacing: 8) {
                Image(systemName: id == AppStore.unknownSourceID ? "questionmark.folder" : "shippingbox").frame(width: 18)
                Text(title).foregroundStyle(selected ? WorkbenchTheme.accent : WorkbenchTheme.sidebarText).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Text("\(count)").foregroundStyle(selected ? WorkbenchTheme.accent : WorkbenchTheme.sidebarSecondary).font(.caption).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(WorkbenchTheme.raised, in: Capsule())
                    .fixedSize()
            }
            .foregroundStyle(selected ? WorkbenchTheme.accent : WorkbenchTheme.sidebarSecondary)
            .padding(8)
            .background(selected ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) · 설치 항목 \(count)개 (복사본과 링크 포함)")
        .accessibilityLabel("\(title), 설치 항목 \(count)개")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func navigationRow(_ page: AppPage) -> some View {
        let selected = store.page == page
        return Button {
            if page == .library { store.showLibrary() } else { store.page = page }
        } label: {
            HStack {
                Image(systemName: page.symbol).frame(width: 18)
                Text(page.title).foregroundStyle(selected ? WorkbenchTheme.accent : WorkbenchTheme.sidebarText)
                Spacer()
                if page == .findings, store.findingCount > 0 { Text("\(store.findingCount)").font(.caption).foregroundStyle(WorkbenchTheme.sidebarSecondary) }
            }
            .foregroundStyle(selected ? WorkbenchTheme.accent : WorkbenchTheme.sidebarSecondary)
            .padding(8)
            .background(selected ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scopeTitle: String {
        if store.page == .findings { return "읽기 문제와 등록 경로의 오류" }
        if let root = store.registeredRoots.first(where: { $0.id == store.rootFilterID }) { return root.label }
        if let agent = store.agentFilter { return "\(agent.displayName) · 모든 설치 위치 · 복사본과 링크를 각각 표시" }
        return "등록한 모든 설치 위치 · 복사본과 링크를 각각 표시"
    }

    private var filters: some View {
        @Bindable var store = store
        return HStack(spacing: 12) {
            Picker("에이전트", selection: $store.agentFilter) {
                Text("모든 에이전트").tag(SkillAgent?.none)
                ForEach(store.availableAgents, id: \.self) { agent in
                    Text(agent.displayName).tag(Optional(agent))
                }
            }.labelsHidden().accessibilityLabel("에이전트").frame(maxWidth: 170)
                .help("선택한 에이전트의 설치 위치만 표시합니다")
            Picker("설치 위치", selection: $store.rootFilterID) {
                Text("모든 설치 위치").tag(String?.none)
                ForEach(store.availableRoots) { root in
                    Text(root.label).tag(Optional(root.id))
                }
            }.labelsHidden().accessibilityLabel("설치 위치").frame(maxWidth: 230)
                .help("특정 위치를 선택하면 해당 에이전트가 함께 선택됩니다. 모든 설치 위치는 현재 에이전트의 모든 경로입니다")
            Toggle("링크만", isOn: $store.linksOnly).toggleStyle(.checkbox)
                .help("다른 위치의 원본을 가리키는 심볼릭 링크만 표시합니다")
            Spacer(minLength: 0)
            if store.hasFilters { Button("초기화") { store.resetFilters() }.help("현재 출처의 검색과 필터 초기화") }
        }.padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.page == .findings ? "checkmark.circle" : "doc.text.magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text((!store.hasScanned || store.isScanning) ? "스킬을 확인하고 있습니다" : store.hasFilters ? "조건에 맞는 결과가 없습니다" : store.page == .findings ? "확인이 필요한 문제가 없습니다" : "이 출처나 위치에서 스킬을 찾지 못했습니다")
                .font(.title3.weight(.semibold))
            if store.hasFilters { Text("검색어나 필터를 바꾸거나 위의 초기화를 눌러 주세요.").foregroundStyle(.secondary) }
            else if store.page == .library {
                Text("설정에서 스킬 폴더의 상태를 확인하거나 경로를 추가하세요.").foregroundStyle(.secondary)
                Button("설정 열기") { openSettings() }
            }
        }.padding(24).frame(maxWidth: .infinity)
    }

    private func entryRow(_ entry: SkillEntry) -> some View {
        Button { store.selectedEntry = entry } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.isSymbolicLink ? "link" : "doc.text")
                    .foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.callout.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(store.sourceRepository(for: entry)?.name ?? "출처 미확인")
                        if store.sourceRepository(for: entry) != nil {
                            Text("· " + store.sourceEvidence(for: entry))
                        }
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(entry.url.displayPath).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let problem = entry.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(WorkbenchTheme.warning)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(store.agentName(for: entry)).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }.padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.url.path)\n눌러서 SKILL.md 원문 보기")
        .accessibilityLabel("\(entry.name), \(store.agentName(for: entry)), \(store.sourceRepository(for: entry)?.name ?? "출처 미확인"), \(entry.url.path), \(entry.problem ?? "원문 보기")")
        .accessibilityIdentifier("entry-\(entry.id)")
    }
}

private struct SkillDetailSheet: View {
    let entry: SkillEntry
    let roots: [DiscoveryRoot]
    let agentName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var editingSource: SkillEntry?
    @State private var document: String?
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.name).font(.title2.weight(.semibold))
                    LabeledContent("에이전트", value: agentName)
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("출처 저장소", value: store.sourceRepository(for: entry)?.name ?? "출처 미확인")
                        HStack {
                            Text(store.sourceEvidence(for: entry)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(store.sourceRepository(for: entry) == nil ? "출처 연결…" : "출처 수정…") { editingSource = entry }
                                .disabled(store.isScanning || store.sourcesLoadFailed)
                        }
                        Text("설치 기록이나 직접 연결한 주소입니다. 현재 파일과 저장소의 일치 여부는 확인하지 않습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("설치 위치").foregroundStyle(.secondary)
                        Text(entry.url.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button(copied ? "복사됨" : "경로 복사") {
                                NSPasteboard.general.clearContents()
                                copied = NSPasteboard.general.setString(entry.url.path, forType: .string)
                            }
                            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                        }
                    }
                    if entry.isSymbolicLink {
                        Label("원본을 가리키는 링크", systemImage: "link")
                        if let target = entry.resolvedURL { Text(target.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    }
                    if let problem = entry.problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning) }
                    Divider()
                    Text("SKILL.md 원문").font(.headline)
                    if let document {
                        Text(document).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning)
                        Text("설치 위치를 확인한 후 창을 닫고 새로고침해 주세요.").foregroundStyle(.secondary)
                    } else { ProgressView("문서 읽는 중") }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Label("읽기 전용 · 문서의 명령을 실행하지 않습니다", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18).background(WorkbenchTheme.raised)
        }.frame(width: 700, height: 600).background(WorkbenchTheme.surface)
        .sheet(item: $editingSource) { SourceEditorSheet(entry: $0) }
        .task(id: entry.id) {
            document = nil; errorMessage = nil
            do {
                let content = try await Task.detached(priority: .userInitiated) {
                    try SkillCatalog.readDocument(entry: entry, approvedRoots: roots)
                }.value
                if !Task.isCancelled { document = content }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct SourceEditorSheet: View {
    let entry: SkillEntry
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("출처 연결").font(.title2.weight(.semibold))
            Text(entry.name).foregroundStyle(.secondary)
            TextField("저장소 주소", text: $input, prompt: Text("owner/repo 또는 https://github.com/owner/repo"))
                .textFieldStyle(.roundedBorder)
            if !store.sourceGroups.isEmpty {
                Menu("등록된 출처에서 선택") {
                    ForEach(store.sourceGroups) { group in
                        Button(group.repository.name) { input = group.repository.id }
                    }
                }.fixedSize()
            }
            Text("이 설치 항목의 출처만 앱에 저장합니다. 다른 복사본이나 원본 파일에는 적용하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.sourceMessage {
                Text(message).font(.caption).foregroundStyle(WorkbenchTheme.warning)
            }
            HStack {
                if store.manualSources[entry.id] != nil {
                    Button("수동 연결 해제") {
                        if store.saveSource(for: entry, input: nil) { dismiss() }
                    }.disabled(store.isScanning || store.sourcesLoadFailed)
                        .help("설치 기록이 있으면 해당 출처로 돌아갑니다")
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    if store.saveSource(for: entry, input: input) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(store.isScanning || store.sourcesLoadFailed)
            }
        }
        .padding(24).frame(width: 560)
        .task { input = store.sourceRepository(for: entry)?.id ?? "" }
    }
}
