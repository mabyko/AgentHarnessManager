import AppKit
import SkillCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var agentName = ""

    var body: some View {
        Form {
            ForEach(SkillAgent.allCases.filter { $0 != .custom }, id: \.self) { agent in
                Section {
                    ForEach(store.registeredRoots.filter { $0.agent == agent }) { root in rootRow(root) }
                    Button("경로 추가…") {
                        Task { await store.chooseSkillFolder(agent: agent, name: "\(agent.displayName) · 추가 경로") }
                    }
                    .disabled(!store.canEditRoots)
                    .accessibilityLabel("\(agent.displayName) 스킬 폴더 추가")
                } header: { Text("\(agent.displayName) 스킬 경로") }
            }

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

            Section {
                Button("경로 상태 새로고침") { Task { await store.rescan() } }.disabled(store.isScanning || store.isMutating || store.isPreparingChange)
                if !store.canEditRoots { Text("검토·적용·복구를 마친 뒤 경로를 편집할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
                if let message = store.settingsMessage { Text(message).font(.caption).accessibilityLabel(message) }
            } footer: {
                Text("기본 경로는 고정입니다. 추가 경로는 수정하거나 삭제할 수 있으며 폴더와 파일은 그대로 있습니다. 경로는 다음 실행에도 유지됩니다. 에이전트의 실제 스킬 로딩 여부는 확인하지 않습니다.")
            }

            Section("화면") {
                Picker("화면 모드", selection: $appearance) {
                    Text("시스템 설정").tag("system")
                    Text("밝게").tag("light")
                    Text("어둡게").tag("dark")
                }
            }
        }
        .formStyle(.grouped).frame(width: 640, height: 680)
        .tint(WorkbenchTheme.accent)
        .task { if !store.hasScanned && !store.isScanning { await store.rescan() } }
    }

    private func rootRow(_ root: DiscoveryRoot) -> some View {
        let isDefault = store.automaticRoots.contains { $0.id == root.id }
        let observation = store.roots.first { $0.id == root.id }
        let count = store.entries.filter { $0.rootID == root.id }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isDefault {
                    Label("기본 경로", systemImage: "lock").font(.headline)
                } else {
                    Text(root.agent == .custom ? root.label : "추가 경로").font(.headline)
                }
                Spacer()
                Text(store.isScanning ? "확인 중" : status(observation?.status)).font(.caption)
                    .foregroundStyle(observation?.status == .blocked || observation?.status == .partial ? WorkbenchTheme.warning : .secondary)
            }
            Text(root.url.displayPath).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled).help(root.url.path)
            if let message = observation?.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if observation?.status == .available || observation?.status == .partial {
                    Text("스킬 \(count)개").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if observation?.status == .available || observation?.status == .partial {
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
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
