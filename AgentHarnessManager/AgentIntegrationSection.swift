import AppKit
import SkillCore
import SwiftUI

struct AgentIntegrationSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var installer = AgentConnectionInstaller()
    @State private var plan: AgentConnectionPlan?
    @State private var busy = false
    @State private var message: String?
    @State private var statuses: [AgentConnectionTarget: String] = [:]

    private var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ahm") }

    var body: some View {
        Section {
            Text("에이전트가 이 앱의 목록·문서·검사 결과를 조회하고 변경을 제안할 수 있게 연결합니다. 파일 변경은 앱에서 검토하고 적용합니다.")
                .foregroundStyle(.secondary)
            ForEach(AgentConnectionTarget.allCases) { target in
                HStack {
                    HStack(alignment: .top, spacing: 10) {
                        AgentIcon(agent: SkillAgent(rawValue: target.rawValue)!)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.name)
                            Text(statusText(target)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(target.name)
                    .accessibilityValue(statusText(target))
                    .help(store.agentInstallations[target]?.executableURL?.path
                          ?? store.agentInstallations[target]?.applicationURL?.path ?? "CLI 또는 앱 설치를 감지하지 못했습니다.")
                    Spacer()
                    Button("연결 설치…") { prepare(target, removing: false) }
                        .accessibilityLabel("\(target.name) 연결 설치")
                        .accessibilityIdentifier("agent.connection.install." + target.rawValue)
                        .disabled(store.agentInstallations[target]?.canInstallConnection(for: target) != true)
                    Button("연결 제거…") { prepare(target, removing: true) }
                        .accessibilityLabel("\(target.name) 연결 제거")
                        .accessibilityIdentifier("agent.connection.remove." + target.rawValue)
                        .disabled(target.requiresCLIForConnection && store.agentInstallations[target]?.executableURL == nil)
                }.disabled(busy)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("agent.connection." + target.rawValue)
            }
            HStack {
                Button("설치 상태 확인") { refreshInstallations() }.disabled(busy || store.isScanning)
                Button("등록 상태 확인") { refreshStatuses() }.disabled(busy)
                Button("CLI 경로 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(helperURL.path, forType: .string)
                    message = "관리 CLI 경로를 복사했습니다. 터미널에서는 경로를 따옴표로 감싸서 실행하세요."
                }
                Button("에이전트 요청 보기") {
                    store.page = .requests; openWindow(id: "workbench")
                    Task { await store.refreshAgentRequests() }
                }
                if busy { ProgressView().controlSize(.small).accessibilityLabel("에이전트 연결 설정 확인 중") }
            }
            if let message { Text(message).font(.callout).textSelection(.enabled).accessibilityLabel(message) }
        }
        footer: { Text("설치 감지는 CLI·앱 파일만 확인하며 로그인이나 에이전트를 실행하지 않습니다. 미감지 에이전트의 연결 설치는 비활성화합니다. 설치와 MCP 등록·실제 도구 로딩은 별개이며 모델 로그인은 각 에이전트에서 진행합니다.") }
        .sheet(item: $plan) { selected in
            VStack(alignment: .leading, spacing: 16) {
                Text("\(selected.target.name) 연결 \(selected.removing ? "제거" : "설치")").font(.title2.weight(.semibold))
                Text("변경할 사용자 설정").font(.headline)
                Text(selected.configurationURL.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(selected.editsConfiguration ? "변경할 MCP 등록" : "실행할 설정 명령").font(.headline)
                ScrollView { Text(selected.displayCommand).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 150)
                Text("기존 설정이 있으면 먼저 앱의 ConnectionBackups 폴더에 보관합니다. 같은 이름의 다른 서버는 변경하지 않습니다. 이 변경은 AI 요청이나 로그인 작업을 실행하지 않습니다.")
                    .foregroundStyle(.secondary)
                if let message { Text(message).font(.callout).textSelection(.enabled) }
                HStack {
                    Spacer()
                    Button("취소") { plan = nil }.keyboardShortcut(.cancelAction).disabled(busy)
                    Button(busy ? "처리 중…" : selected.removing ? "연결 제거" : "연결 설치") { apply(selected) }
                        .keyboardShortcut(.defaultAction).disabled(busy)
                }
            }.padding(24).frame(width: 600).interactiveDismissDisabled(busy)
        }
    }

    private func prepare(_ target: AgentConnectionTarget, removing: Bool) {
        if !removing && store.agentInstallations[target]?.canInstallConnection(for: target) != true {
            message = "에이전트 설치 상태를 확인하세요. Codex·Claude Code·Grok Build 연결 설정에는 CLI가 필요합니다."
            return
        }
        busy = true; message = nil
        let helper = helperURL, domain = Bundle.main.bundleIdentifier ?? ManagementConfiguration.releaseDomain
        Task {
            defer { busy = false }
            do { plan = try await installer.prepare(target: target, removing: removing, helperURL: helper, domain: domain) }
            catch { message = error.localizedDescription }
        }
    }

    private func statusText(_ target: AgentConnectionTarget) -> String {
        guard let installation = store.agentInstallations[target] else { return "설치 확인 중…" }
        let connection = target.requiresCLIForConnection && installation.isInstalled && installation.executableURL == nil
            ? "연결 CLI 필요" : "MCP " + (statuses[target] ?? "등록 미확인")
        return installation.label + " · " + connection
    }

    private func refreshInstallations() {
        busy = true; message = nil
        Task {
            defer { busy = false }
            await store.refreshAgentInstallations()
            message = "CLI·앱 파일의 설치 상태를 확인했습니다. 사용자 지정 위치에 설치했다면 기본 검색 경로나 PATH에서 찾을 수 있는지 확인하세요."
        }
    }

    private func refreshStatuses() {
        busy = true; message = nil
        let helper = helperURL, domain = Bundle.main.bundleIdentifier ?? ManagementConfiguration.releaseDomain
        Task {
            defer { busy = false }
            for target in AgentConnectionTarget.allCases {
                do { statuses[target] = try await installer.status(target: target, helperURL: helper, domain: domain).label }
                catch { statuses[target] = error.localizedDescription }
            }
            message = "설정의 등록 상태를 확인했습니다. 실제 도구 사용 가능 여부는 각 에이전트의 새 세션에서 확인하세요."
        }
    }

    private func apply(_ selected: AgentConnectionPlan) {
        busy = true; message = nil
        let domain = Bundle.main.bundleIdentifier ?? ManagementConfiguration.releaseDomain
        let backups = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(domain)/ConnectionBackups")
        Task {
            defer { busy = false }
            do {
                let backup = try await installer.apply(selected, backupDirectory: backups)
                statuses[selected.target] = selected.removing ? AgentConnectionStatus.notRegistered.label : AgentConnectionStatus.registered.label
                plan = nil
                message = "\(selected.target.name) 연결을 \(selected.removing ? "제거" : "등록")했습니다."
                    + (selected.removing ? " 기존 에이전트 세션은 별도로 종료하세요." : " 에이전트의 새 세션에서 MCP 상태를 확인하세요.")
                    + (backup.map { "\n백업: " + $0.path } ?? "")
            } catch { message = error.localizedDescription }
        }
    }
}
