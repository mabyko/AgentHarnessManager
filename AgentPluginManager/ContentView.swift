import AppKit
import SkillCore
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if store.page == .profiles {
                    ProfilesView()
                } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.page.title).font(.title2.weight(.semibold))
                        Text(scopeTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.filteredEntries.count + (store.page == .findings ? store.filteredProblemRoots.count : 0))개 표시").foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(24)
                filters
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
            .searchable(text: $store.search, placement: .toolbar, prompt: store.page == .profiles ? "작업 구성 검색" : "이름 또는 설치 경로")
        }
        .tint(WorkbenchTheme.accent)
        .sheet(item: $store.selectedEntry) { entry in
            SkillDetailSheet(entry: entry, roots: store.registeredRoots, agentName: store.agentName(for: entry))
        }
        .task { if !store.hasScanned && !store.isScanning { await store.rescan() } }
    }

    private var sidebar: some View {
        List {
            Section("스킬 관리") {
                navigationRow(.profiles)
                navigationRow(.library)
                navigationRow(.findings)
            }
            Section("스킬 폴더") {
                ForEach(store.registeredRoots) { root in
                    Button { store.showLibrary(rootID: root.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(root.label).font(.callout)
                            Text(root.url.displayPath).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        .background(store.rootFilterID == root.id ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(root.url.path)
                    .accessibilityLabel("\(root.label), \(root.url.path), 스킬 목록 보기")
                    .accessibilityAddTraits(store.rootFilterID == root.id ? .isSelected : [])
                }
            }

        }.listStyle(.sidebar)
    }

    private func navigationRow(_ page: AppPage) -> some View {
        let selected = store.page == page && store.rootFilterID == nil
        return Button {
            if page == .library { store.showLibrary() } else { store.page = page }
        } label: {
            HStack {
                Image(systemName: page.symbol).frame(width: 18)
                Text(page == .library ? "모든 스킬" : page.title)
                Spacer()
                if page == .findings, store.findingCount > 0 { Text("\(store.findingCount)").font(.caption) }
            }
            .foregroundStyle(selected ? WorkbenchTheme.accent : .secondary)
            .padding(8)
            .background(selected ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scopeTitle: String {
        if store.page == .findings { return "읽기 문제와 등록 경로의 오류" }
        return store.registeredRoots.first { $0.id == store.rootFilterID }?.label ?? "등록한 모든 스킬 폴더"
    }

    private var filters: some View {
        @Bindable var store = store
        return HStack(spacing: 16) {
            if store.availableAgents.count > 1 {
                Picker("에이전트", selection: $store.agentFilter) {
                    Text("모든 에이전트").tag(SkillAgent?.none)
                    ForEach(store.availableAgents, id: \.self) { agent in
                        Text(agent.displayName).tag(Optional(agent))
                    }
                }.frame(maxWidth: 260)
            }
            Toggle("링크 항목만", isOn: $store.linksOnly).toggleStyle(.checkbox)
                .help("다른 위치의 원본을 가리키는 심볼릭 링크만 표시합니다")
            Spacer()
            if store.hasFilters { Button("필터 초기화") { store.resetFilters() } }
        }.padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.page == .findings ? "checkmark.circle" : "doc.text.magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text((!store.hasScanned || store.isScanning) ? "스킬을 확인하고 있습니다" : store.hasFilters ? "조건에 맞는 결과가 없습니다" : store.page == .findings ? "확인이 필요한 문제가 없습니다" : "이 위치에서 스킬을 찾지 못했습니다")
                .font(.title3.weight(.semibold))
            if store.hasFilters { Text("검색어나 필터를 바꾸거나 위의 필터 초기화를 눌러 주세요.").foregroundStyle(.secondary) }
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
                    HStack {
                        Text(entry.name).font(.callout.weight(.semibold))
                        Text(store.agentName(for: entry)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.url.displayPath).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let problem = entry.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(WorkbenchTheme.warning)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.url.path)\n눌러서 SKILL.md 원문 보기")
        .accessibilityLabel("\(entry.name), \(store.agentName(for: entry)), \(entry.url.path), \(entry.problem ?? "원문 보기")")
        .accessibilityIdentifier("entry-\(entry.id)")
    }
}

private struct SkillDetailSheet: View {
    let entry: SkillEntry
    let roots: [DiscoveryRoot]
    let agentName: String
    @Environment(\.dismiss) private var dismiss
    @State private var document: String?
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.name).font(.title2.weight(.semibold))
                    LabeledContent("에이전트", value: agentName)
                    LabeledContent("출처 저장소", value: "확인되지 않음")
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
