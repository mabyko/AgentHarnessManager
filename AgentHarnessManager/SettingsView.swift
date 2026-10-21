import AppKit
import SkillCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, connections, paths
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "일반"
        case .connections: "에이전트 연동"
        case .paths: "스킬 경로"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .connections: "terminal"
        case .paths: "folder"
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var agentName = ""
    @State private var pathAgent: SkillAgent = .codex
    @State private var page: SettingsPage = .general

    init(pathAgent: SkillAgent = .codex) {
        _pathAgent = State(initialValue: pathAgent)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        Label(item.title, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(WorkbenchTheme.sidebarText)
                            .contentShape(Rectangle())
                    }.buttonStyle(SidebarButtonStyle(selected: page == item)).keyboardActivation { page = item }
                    .accessibilityIdentifier("settings.page." + item.rawValue)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WorkbenchTheme.raised)
            .frame(width: 190)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("설정 카테고리")
            Divider().overlay(WorkbenchTheme.border)
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title).font(.title2.weight(.semibold))
                    .foregroundStyle(WorkbenchTheme.sidebarText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            Form {
                    switch page {
                    case .connections: AgentIntegrationSection()
                    case .paths: pathSections
                    case .general:
                        managementMethodSection
                        Section("화면") {
                            Picker("화면 모드", selection: $appearance) {
                                Text("시스템 설정").tag("system")
                                Text("밝게").tag("light")
                                Text("어둡게").tag("dark")
                            }
                        }
                    }
            }.formStyle(.grouped)
                .scrollEdgeEffectHidden(for: .top)
            }
            .background(WorkbenchTheme.surface)
        }
        .navigationTitle("설정")
        .frame(minWidth: 840, minHeight: 580)
        .tint(WorkbenchTheme.accent)
        .task { if !store.hasScanned && !store.isScanning { await store.rescan() } }
    }

    private var managementMethodSection: some View {
        Section("스킬 관리") {
            Picker("관리 도구", selection: Binding(get: { store.managementMethod }, set: { store.setManagementMethod($0) })) {
                Text("앱 직접 관리").tag(SkillManagementMethod.direct)
                Text("skills CLI").tag(SkillManagementMethod.skillsCLI).disabled(store.skillsCLIExecutable == nil)
            }.disabled(!store.canEditRoots).accessibilityIdentifier("settings.managementMethod")
            LabeledContent("skills CLI", value: store.skillsCLIExecutable == nil ? "감지되지 않음" : "실행 파일 감지됨")
                .accessibilityIdentifier("settings.skillsCLIStatus")
            if let executable = store.skillsCLIExecutable {
                Text(executable.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("다시 확인") { store.refreshSkillsCLI() }.disabled(!store.canEditRoots)
                    .accessibilityIdentifier("settings.refreshSkillsCLI")
                Button("실행 파일 선택…") { store.chooseSkillsCLIExecutable() }.disabled(!store.canEditRoots)
            }
            Text(store.managementMethod == .skillsCLI
                 ? "설치·삭제·업데이트를 모두 skills CLI로 실행합니다. 실행 전 명령과 영향 범위를 검토하며 CLI가 파일과 설치 기록을 관리합니다. 1.7.4 이상의 1.x 버전이 필요합니다."
                 : "앱이 스킬을 복사 설치하고 삭제 시 복구용으로 보관합니다. CLI 설치 기록은 변경하지 않습니다. 업데이트 확인·적용은 skills CLI 관리에서 제공합니다.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("설치", value: store.managementMethod == .skillsCLI ? "CLI · GitHub / 로컬" : "앱 · 복사 설치")
            LabeledContent("삭제", value: store.managementMethod == .skillsCLI ? "CLI · 파일 및 설치 기록 정리" : "앱 · 복구 가능한 보관")
            LabeledContent("업데이트", value: store.managementMethod == .skillsCLI ? "읽기 전용 확인 → 검토 → CLI 적용" : "skills CLI 선택 필요")
            if store.managementMethod == .skillsCLI {
                Text("CLI 삭제는 영구 삭제이며 업데이트는 로컬 수정을 덮어씁니다. 앱 변경 이력의 자동 되돌리기는 제공하지 않습니다. 켜기·끄기는 기존 앱의 복구 가능한 전환을 사용합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.skillsCLIExecutable == nil {
                Text("전역 설치 또는 기존 npx·bunx 캐시에서 skills 실행 파일을 찾습니다. npx만 설치돼 있거나 CLI가 없어져도 자동 다운로드하거나 설치 방식을 바꾸지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var pathSections: some View {
        Section {
            Picker("에이전트", selection: $pathAgent) {
                ForEach(SkillAgent.allCases, id: \.self) { agent in
                    Label { Text(agent.displayName) } icon: { AgentIcon(agent: agent) }.tag(agent)
                }
            }.pickerStyle(.menu).accessibilityIdentifier("settings.pathAgent")
            if let target = AgentConnectionTarget(rawValue: pathAgent.rawValue) {
                LabeledContent("설치 상태", value: store.agentInstallations[target]?.label ?? "확인 중…")
                Text("에이전트 설치 여부와 관계없이 등록한 스킬 경로를 확인하고 관리할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if pathAgent != .custom {
            let agent = pathAgent
            Section {
                ForEach(store.registeredRoots.filter { store.agents(for: $0).contains(agent) }) { root in rootRow(root) }
                Button("경로 추가…") {
                    Task { await store.chooseSkillFolder(agent: agent, name: "\(agent.displayName) · 추가 경로") }
                }
                .disabled(!store.canEditRoots)
                .accessibilityLabel("\(agent.displayName) 스킬 폴더 추가")
            } header: {
                Label { Text("\(agent.displayName) 스킬 경로") } icon: { AgentIcon(agent: agent, size: 16) }
            }
            footer: {
                Text(agent == .antigravity
                     ? "앱·IDE·CLI와 이전 버전 경로를 구분합니다. 사용 중인 버전에 따라 읽는 경로가 다릅니다."
                     : "공유 경로는 호환 설정에 따라 여러 에이전트가 함께 읽습니다. 폴더 상태와 에이전트의 실제 로딩은 별개입니다.")
            }
        }

        if pathAgent == .custom {
        Section {
            ForEach(store.additionalRoots.filter { $0.agent == .custom }) { root in rootRow(root) }
            HStack {
                TextField("에이전트 이름", text: $agentName, prompt: Text("예: Cursor"))
                    .accessibilityLabel("다른 에이전트 이름")
                Button("경로 추가…") {
                    Task { await store.chooseSkillFolder(agent: .custom, name: agentName) }
                }
                .disabled(!store.canEditRoots || agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentName.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
                .accessibilityLabel("다른 에이전트 스킬 폴더 추가")
            }
        } header: { Text("다른 에이전트") }
        footer: { Text("SKILL.md가 있는 폴더 또는 스킬들을 모아 둔 폴더를 선택하세요.") }
        }

        Section {
            Button("경로 상태 새로고침") { Task { await store.rescan() } }.disabled(store.isScanning || store.isMutating || store.isPreparingChange)
            if !store.canEditRoots { Text("검토·적용·복구를 마친 뒤 경로를 편집할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
            if let message = store.settingsMessage { Text(message).font(.caption).accessibilityLabel(message) }
        } footer: {
            Text("기본 경로는 고정입니다. 추가 경로는 수정하거나 삭제할 수 있으며 폴더와 파일은 그대로 있습니다. 경로는 다음 실행에도 유지됩니다. 에이전트의 실제 스킬 로딩 여부는 확인하지 않습니다.")
        }

    }

    private func rootRow(_ root: DiscoveryRoot) -> some View {
        let isDefault = store.automaticRoots.contains { $0.id == root.id }
        let observation = store.roots.first { $0.id == root.id }
        let count = store.entries.filter { $0.rootID == root.id }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isDefault {
                    Label(store.agents(for: root).count > 1 ? "공유 경로" : root.agent == .antigravity ? root.label : "기본 경로", systemImage: "lock").font(.headline)
                } else {
                    Text(root.agent == .custom ? root.label : "추가 경로").font(.headline)
                }
                Spacer()
                Text(store.isScanning ? "확인 중" : status(observation?.status)).font(.caption)
                    .foregroundStyle(observation?.status == .blocked || observation?.status == .partial ? WorkbenchTheme.warning : .secondary)
            }
            Text(root.url.displayPath).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled).help(root.url.path)
            if store.agents(for: root).count > 1 {
                Text("호환 에이전트: " + store.agents(for: root).map(\.displayName).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = observation?.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if observation?.status == .available || observation?.status == .partial {
                    Text("스킬 \(count)개").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if observation?.status == .available || observation?.status == .partial {
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
                        .accessibilityLabel("\(root.label), \(root.url.path), Finder에서 보기")
                }
                if !isDefault {
                    Button("수정…") {
                        Task { await store.chooseSkillFolder(agent: root.agent, name: root.label, replacing: root) }
                    }
                    .disabled(!store.canEditRoots)
                    .accessibilityLabel("\(root.label), \(root.url.path), 경로 수정")
                    Button("삭제", role: .destructive) { Task { await store.removeRoot(root) } }
                        .disabled(!store.canEditRoots)
                        .help("앱에 등록한 경로만 삭제하며 폴더와 파일은 그대로 있습니다.")
                        .accessibilityLabel("\(root.label), \(root.url.path), 경로 삭제")
                }
            }
        }.padding(.vertical, 4)
    }

    private func status(_ status: RootStatus?) -> String {
        switch status {
        case .available: "스킬 폴더 찾음"
        case .missing: "폴더 없음"
        case .blocked: "읽기 실패"
        case .partial: "일부 확인"
        case nil: "확인 전"
        }
    }
}
