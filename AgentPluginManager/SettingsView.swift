import AppKit
import SkillCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var agentName = ""

    var body: some View {
        Form {
            Section {
                ForEach(store.automaticRoots) { root in rootRow(root) }
                Button("경로 상태 새로고침") { Task { await store.rescan() } }.disabled(store.isScanning)
            } header: { Text("자동으로 확인하는 에이전트") }
            footer: { Text("스킬 폴더를 확인합니다. 에이전트 설치 여부나 실제 스킬 로딩 여부를 뜻하지 않습니다.") }

            Section {
                if store.additionalRoots.isEmpty { Text("추가로 등록한 경로가 없습니다.").foregroundStyle(.secondary) }
                ForEach(store.additionalRoots) { root in
                    rootRow(root)
                    Button("등록 해제: \(root.label)", role: .destructive) {
                        Task { await store.removeRoot(root) }
                    }.disabled(store.isScanning)
                }
            } header: { Text("추가 스킬 경로") }
            footer: { Text("경로는 다음 실행에도 유지됩니다. 등록을 해제해도 원래 폴더와 파일은 그대로 있습니다.") }

            Section {
                ForEach(SkillAgent.allCases.filter { $0 != .custom }, id: \.self) { agent in
                    HStack {
                        Text(agent.displayName)
                        Spacer()
                        Button("폴더 선택…") {
                            Task { await store.chooseSkillFolder(agent: agent, name: "\(agent.displayName) · 추가 경로") }
                        }
                        .disabled(store.isScanning)
                        .accessibilityLabel("\(agent.displayName) 스킬 폴더 추가")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("다른 에이전트")
                    HStack {
                        TextField("에이전트 이름", text: $agentName, prompt: Text("예: Cursor"))
                            .accessibilityLabel("다른 에이전트 이름")
                        Button("폴더 선택…") {
                            Task { await store.chooseSkillFolder(agent: .custom, name: agentName) }
                        }
                        .disabled(store.isScanning || agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentName.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
                        .accessibilityLabel("다른 에이전트 스킬 폴더 추가")
                    }
                }
                if let message = store.settingsMessage { Text(message).font(.caption).accessibilityLabel(message) }
            } header: { Text("경로 추가") }
            footer: { Text("SKILL.md가 있는 폴더 또는 그 스킬들을 모아 둔 폴더를 선택하세요. 다른 에이전트의 경로는 SKILL.md 조회만 지원합니다.") }

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
        let observation = store.roots.first { $0.id == root.id }
        let count = store.entries.filter { $0.rootID == root.id }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(root.label).font(.headline)
                Spacer()
                Text(store.isScanning ? "확인 중" : status(observation?.status)).font(.caption)
                    .foregroundStyle(observation?.status == .blocked || observation?.status == .partial ? WorkbenchTheme.warning : .secondary)
            }
            Text(root.url.displayPath).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled).help(root.url.path)
            if let message = observation?.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if observation?.status == .available || observation?.status == .partial {
                HStack {
                    Text("스킬 \(count)개").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
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
