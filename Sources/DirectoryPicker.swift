import AppKit

/// 统一的文件夹选择器，避免三处重复的 NSOpenPanel 代码。
enum DirectoryPicker {
    /// 弹出系统文件夹选择器，返回选中的路径（用户取消则返回 nil）。
    static func pick(message: String = "选择文件夹") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择"
        panel.message = message
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}