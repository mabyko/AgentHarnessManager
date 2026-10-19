import SkillCore
import SwiftUI

struct SourceEditorSheet: View {
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
