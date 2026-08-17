import SwiftUI
import AppKit

/// 可编辑的项目字段。
enum EditField: String, CaseIterable {
    case name, command, url

    var label: String {
        switch self {
        case .name: return "名称"
        case .command: return "启动命令"
        case .url: return "网页地址"
        }
    }

    func initialValue(for project: Project) -> String {
        switch self {
        case .name: return project.name
        case .command: return project.command ?? ""
        case .url: return project.url ?? ""
        }
    }
}

/// 独立编辑窗口的内容视图。
/// 放在独立 NSWindow 中呈现，绕开「菜单栏应用 popover 内 TextField 收不到键盘输入」的问题。
struct EditFieldView: View {
    let project: Project
    let field: EditField
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(project: Project, field: EditField, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.field = field
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: field.initialValue(for: project))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑「\(project.name)」的\(field.label)")
                .font(.headline)
            TextField(field.label, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
