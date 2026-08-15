import Foundation

/// 启动命令校验：判断命令的第一个词是否是本机可执行的命令。
enum CommandValidator {
    /// 用户默认 shell（优先读 $SHELL，取不到就退回 /bin/zsh）。
    static let userShell: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let fm = FileManager.default
        if shell.isEmpty || !fm.isExecutableFile(atPath: shell) {
            return "/bin/zsh"
        }
        return shell
    }()

    /// 用户登录 shell 的 PATH（与启动服务时用的 `shell -lc` 一致）。
    static let loginShellPath: [String] = {
        guard let str = ProcessRunner.run(userShell, ["-lc", "echo \"$PATH\""]) else { return [] }
        // zsh/bash 用冒号分隔；fish 用空格分隔
        if str.contains(":") {
            return str.split(separator: ":").map(String.init)
        }
        return str.split(separator: " ").map(String.init)
    }()

    /// 判断命令的第一个词是否可执行（绝对路径直接检查；否则在登录 shell PATH 里找）。
    static func exists(_ command: String) -> Bool {
        let first = command.split(separator: " ").first.map(String.init) ?? ""
        guard !first.isEmpty else { return false }
        if first.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: first)
        }
        let fm = FileManager.default
        // 常见 bin 目录（覆盖 PATH 里可能没有的场景）
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = loginShellPath
        dirs += [
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "/usr/local/bin", "/opt/homebrew/bin",
            "\(home)/.local/bin", "\(home)/bin", "\(home)/.cargo/bin",
        ]
        for dir in dirs where !dir.isEmpty {
            let full = (dir as NSString).appendingPathComponent(first)
            if fm.isExecutableFile(atPath: full) { return true }
        }
        return false
    }
}
