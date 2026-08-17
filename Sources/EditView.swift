import SwiftUI
import AppKit

/// 编辑项目信息的独立窗口内容视图。
/// 预加载项目的名称 / 启动命令 / 网页地址 / 自动打开浏览器开关，供用户统一修改。
/// 放在独立 NSWindow 中呈现，绕开「菜单栏应用 popover 内 TextField 收不到键盘输入」的问题。
struct EditProjectView: View {
    let project: Project
    let onSave: (String, String, String, Bool) -> Void // name, command, url, openBrowser
    let onCancel: () -> Void

    @State private var name: String
    @State private var command: String
    @State private var url: String
    @State private var openBrowser: Bool
    @State private var validationError: String?
    @State private var autoFillNote: String?
    @State private var autoFillNoteIsWarning = false

    init(project: Project, onSave: @escaping (String, String, String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: project.name)
        _command = State(initialValue: project.command ?? "")
        _url = State(initialValue: project.url ?? "")
        _openBrowser = State(initialValue: project.openBrowser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("编辑项目")
                .font(.headline)

            if let note = autoFillNote {
                HStack(spacing: 5) {
                    Image(systemName: autoFillNoteIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(note)
                }
                .font(.caption)
                .foregroundColor(autoFillNoteIsWarning ? .orange : .green)
                .fixedSize(horizontal: false, vertical: true)
            }

            fieldLabel("项目安装位置")
            Text(project.path)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            fieldLabel("名称（选填）")
            TextField("给它起个名字，如「我的机器人」", text: $name)
            helpText("不填就用文件夹的名字。")

            HStack {
                fieldLabel("启动命令")
                Spacer()
                Button("自动识别") { autoFill() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            TextField("如 dsh web、astrbot run、npm run dev", text: $command)
            helpText("点「自动识别」会根据项目安装包自动填好命令和网页地址，可再手动改。")

            fieldLabel("网页地址（选填）")
            TextField("如 http://localhost:3000", text: $url)
            helpText("启动后要在浏览器打开的地址；留空会自动探测。")

            Toggle("启动后自动打开浏览器", isOn: $openBrowser)
                .padding(.top, 2)

            if let error = validationError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("保存") {
                    if let error = validate() {
                        validationError = error
                    } else {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            command.trimmingCharacters(in: .whitespacesAndNewlines),
                            url.trimmingCharacters(in: .whitespacesAndNewlines),
                            openBrowser
                        )
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .textFieldStyle(.roundedBorder)
    }

    private func validate() -> String? {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !c.isEmpty else { return "请填写「启动命令」" }
        let first = c.split(separator: " ").first.map(String.init) ?? ""
        if !first.isEmpty && !CommandValidator.exists(first) {
            return "找不到命令「\(first)」，请确认已安装或命令名是否写错"
        }
        if !u.isEmpty && URLDetector.normalize(u) == nil {
            return "网页地址格式不对，例如 http://localhost:3000"
        }
        return nil
    }

    private func autoFill() {
        let detectedCommand = ProjectScanner.resolveCommand(for: project.path)
        let detectedURL = URLDetector.suggestURL(path: project.path, command: detectedCommand ?? command)
        if let cmd = detectedCommand { command = cmd }
        if let u = detectedURL { url = u }

        switch (detectedCommand != nil, detectedURL != nil) {
        case (true, true):
            autoFillNote = "已自动识别启动命令和网页地址，请确认"
            autoFillNoteIsWarning = false
        case (true, false):
            autoFillNote = "已自动识别启动命令，网页地址请手动补充"
            autoFillNoteIsWarning = false
        case (false, true):
            autoFillNote = "已自动识别网页地址，启动命令请手动填写"
            autoFillNoteIsWarning = false
        case (false, false):
            autoFillNote = "未能自动识别，请手动填写启动命令和网页地址"
            autoFillNoteIsWarning = true
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
