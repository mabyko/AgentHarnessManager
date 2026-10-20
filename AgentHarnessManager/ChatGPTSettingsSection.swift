import SwiftUI

struct ChatGPTSettingsSection: View {
    @Environment(ChatGPTConnection.self) private var connection

    var body: some View {
        Section {
            Text("앱에서 ChatGPT에 직접 연결하는 선택 기능입니다. 에이전트 CLI·MCP 연동에는 필요하지 않습니다.")
                .foregroundStyle(.secondary)
            Button("저장된 ChatGPT 연결 확인") { connection.load() }
                .disabled(connection.isBusy)
            if !connection.accounts.isEmpty {
                Picker("ChatGPT 계정", selection: Binding(get: { connection.activeID ?? "" }, set: { connection.chooseAccount($0) })) {
                    if connection.activeID == nil { Text("계정 선택").tag("") }
                    ForEach(connection.accounts) { account in Text(account.label).tag(account.id) }
                }
                .disabled(connection.isBusy)
            }
            if let account = connection.active {
                Label(account.canUsePlan ? "ChatGPT 요금제 사용" : account.signedIn ? "요금제 사용 권한 필요" : "연결 해제됨",
                      systemImage: account.canUsePlan ? "checkmark.circle" : "person.crop.circle")
                if account.canUsePlan {
                    if !connection.models.isEmpty {
                        Picker("모델", selection: Binding(get: { connection.selectedModel }, set: { connection.chooseModel($0) })) {
                            ForEach(connection.models) { model in Text(model.display_name).tag(model.id) }
                        }
                        .disabled(connection.isBusy)
                    } else if let model = account.model {
                        LabeledContent("저장된 모델", value: model)
                    }
                    HStack {
                        Button("모델 새로고침") { connection.refreshModels() }
                        Button("연결 테스트") { connection.testConnection() }
                            .disabled(connection.selectedModel.isEmpty)
                    }
                    .disabled(connection.isBusy)
                }
            }
            HStack {
                Button("Continue with ChatGPT") { connection.connect(consent: connection.active?.signedIn == true && connection.active?.canUsePlan == false) }
                    .disabled(connection.isBusy)
                    .accessibilityHint("기본 브라우저에서 ChatGPT 로그인과 권한 허용을 진행합니다.")
                if !connection.accounts.isEmpty {
                    Button("다른 계정 추가") { connection.connect(newAccount: true) }.disabled(connection.isBusy)
                }
                Spacer()
                if connection.isSigningIn {
                    ProgressView().controlSize(.small)
                    Button("취소") { connection.cancelSignIn() }
                } else if connection.isBusy {
                    ProgressView().controlSize(.small).accessibilityLabel("ChatGPT 연결 처리 중")
                } else if connection.active?.signedIn == true {
                    Button("연결 해제") { connection.signOut() }
                }
            }
            if let message = connection.message {
                Text(message).font(.callout).textSelection(.enabled).accessibilityLabel(message)
            }
            Link("ChatGPT 사용량 및 접근 관리", destination: ChatGPTConnection.usageURL)
        } header: {
            Text("AI 연결 · ChatGPT")
        } footer: {
            Text("인증 정보는 이 기기의 키체인에 보관합니다. 연결 테스트는 고정된 짧은 문장만 전송하며 ChatGPT 사용 한도를 소비할 수 있습니다. 스킬 문서는 전송하지 않습니다. AI 검토는 아직 연결되지 않았습니다.")
        }
        .alert("ChatGPT 요금제를 사용합니다", isPresented: Binding(get: { connection.showWelcome }, set: { if !$0 { connection.acknowledgeWelcome() } })) {
            Button("확인") { connection.acknowledgeWelcome() }
        } message: {
            Text("이 앱의 지원되는 AI 요청은 ChatGPT 요금제 또는 사용 가능한 크레딧을 사용합니다. ChatGPT 설정에서 앱별 사용량과 접근 권한을 관리할 수 있습니다.")
        }
    }
}
