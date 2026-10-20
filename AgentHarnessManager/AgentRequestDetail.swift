import SkillCore
import SwiftUI

struct AgentRequestDetail: View {
    let request: AgentChangeRequest
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("에이전트 변경 요청", systemImage: "tray.and.arrow.down").font(.headline)
                Text(request.title).font(.title2.weight(.semibold))
                LabeledContent("상태", value: store.agentRequestState(request))
                LabeledContent("요청 시각") { Text(request.createdAt, format: .dateTime) }
                Text("아래 내용은 에이전트가 보낸 제안입니다. 검토 시 현재 파일과 설정으로 계획을 다시 만들며, 다음 창에서 적용을 눌러야 파일이 변경됩니다.")
                    .foregroundStyle(.secondary)
                ForEach(request.moves) { move in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(move.installation.name, systemImage: move.enabled ? "checkmark.circle" : "archivebox")
                        Text(move.installation.originalPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text(move.enabled ? "설치 위치로 복원 요청" : "설치 위치에서 보관 요청").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button("현재 상태로 검토…") { Task { await store.prepareAgentRequest(request) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.metadataIsEditable || store.agentRequestState(request) != "검토 대기")
                    Button("요청 목록에서 제거", role: .destructive) { Task { await store.dismissAgentRequest(request) } }
                        .disabled(store.mutationPreview != nil || store.isMutating || store.journal.pending?.id == request.id)
                }
                Text("요청은 24시간 후 만료됩니다. 목록에서 제거해도 스킬과 적용 이력은 유지됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(request.id.uuidString).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
