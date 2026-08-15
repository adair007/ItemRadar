import SwiftUI
import AppKit

// MARK: - 手动添加服务的小窗

struct AddProjectView: View {
    let onSave: (String, String, String, String, Bool) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var path = ""
    @State private var command = ""
    @State private var url = ""
    @State private var openBrowser = true
    @State private var validationError: String?
    @State private var autoFillNote: String?
    @State private var autoFillNoteIsWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动添加")
                .font(.headline)
            Text("把「终端能启动、但桌面没入口」的服务加进来，以后就能在这里一键启动。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = autoFillNote {
                HStack(spacing: 5) {
                    Image(systemName: autoFillNoteIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(note)
                }
                .font(.caption)
                .foregroundColor(autoFillNoteIsWarning ? .orange : .green)
                .fixedSize(horizontal: false, vertical: true)
            }

            fieldLabel("名称（选填）")
            TextField("给它起个名字，如「我的机器人」", text: $name)
            helpText("不填就用文件夹的名字。")

            fieldLabel("项目安装位置（必填）")
            HStack(spacing: 6) {
                TextField("项目安装的文件夹", text: $path)
                Button("选择…", action: pickDirectory)
                    .controlSize(.small)
            }
            helpText("点「选择」直接选文件夹，不用手打路径。")

            HStack {
                fieldLabel("启动命令（必填）")
                Spacer()
                Button("自动识别") { autoFill() }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            path.trimmingCharacters(in: .whitespacesAndNewlines),
                            command.trimmingCharacters(in: .whitespacesAndNewlines),
                            url.trimmingCharacters(in: .whitespacesAndNewlines),
                            openBrowser
                        )
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .textFieldStyle(.roundedBorder)
    }

    /// 校验填写内容，返回错误信息；通过则返回 nil。
    private func validate() -> String? {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !p.isEmpty else { return "请填写「项目安装位置」" }
        let expanded = expandTilde(p)
        guard FileManager.default.fileExists(atPath: expanded) else {
            return "项目安装位置不存在，请检查路径"
        }
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

    private func expandTilde(_ path: String) -> String {
        if path == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
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

    private func pickDirectory() {
        if let picked = DirectoryPicker.pick(message: "选择项目所在的文件夹") {
            path = picked
            autoFill()
        }
    }

    /// 根据「项目安装位置」自动识别启动命令和网页地址。
    private func autoFill() {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        let expanded = expandTilde(p)
        guard FileManager.default.fileExists(atPath: expanded) else { return }

        let detectedCommand = ProjectScanner.resolveCommand(for: expanded)
        let detectedURL = URLDetector.suggestURL(path: expanded, command: detectedCommand ?? command)
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
}

