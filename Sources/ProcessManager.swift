import Foundation

/// 一条已启动服务的记录。
struct RunningInfo: Codable {
    var pid: Int32
    var logFile: String
    var startedAt: Date
}

/// 负责服务的启动 / 停止 / 状态跟踪与持久化。
/// 启动使用 posix_spawn 建立独立进程组，便于一键停止整棵进程树。
final class ProcessManager {
    private struct State: Codable {
        var running: [String: RunningInfo]
    }

    private(set) var running: [String: RunningInfo] = [:]
    private let stateURL: URL
    private let logsDir: URL

    init(stateURL: URL, logsDir: URL) {
        self.stateURL = stateURL
        self.logsDir = logsDir
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        loadState()
    }

    // MARK: - 对外接口

    func isRunning(path: String) -> Bool {
        guard let info = running[path] else { return false }
        return isAlive(pid: info.pid)
    }

    func runningInfo(path: String) -> RunningInfo? {
        running[path]
    }

    func isAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return kill(-pid, 0) == 0
    }

    @discardableResult
    func start(path: String, command: String) throws -> RunningInfo {
        if let existing = running[path], isAlive(pid: existing.pid) {
            return existing
        }
        let base = (path as NSString).lastPathComponent
        let logFile = logsDir
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6)).log")
            .path
        let pid = try spawn(command: command, cwd: path, logFile: logFile)
        let info = RunningInfo(pid: pid, logFile: logFile, startedAt: Date())
        running[path] = info
        saveState()
        return info
    }

    func stop(path: String) {
        guard let info = running.removeValue(forKey: path) else { return }
        saveState()
        terminate(pid: info.pid)
    }

    /// 优雅停止整棵进程树：先 SIGTERM，3 秒后仍存活则 SIGKILL。
    /// 不仅杀进程组，还要杀所有后代——因为 turbo 等工具会把子进程放到独立进程组。
    func terminate(pid: Int32) {
        let descendants = allDescendants(of: pid)
        kill(-pid, SIGTERM)
        for d in descendants {
            kill(d, SIGTERM)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            kill(-pid, SIGKILL)
            for d in descendants where self.isAlive(pid: d) {
                kill(d, SIGKILL)
            }
        }
    }

    /// 找出 pid 的所有后代进程（递归，跨进程组）。
    private func allDescendants(of pid: Int32) -> [Int32] {
        guard let output = ProcessRunner.run("/bin/ps", ["-eo", "pid=,ppid="]) else { return [] }
        var childrenMap: [Int32: [Int32]] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }
            guard parts.count >= 2 else { continue }
            childrenMap[parts[1], default: []].append(parts[0])
        }
        var result: [Int32] = []
        var queue: [Int32] = [pid]
        while let current = queue.first {
            queue.removeFirst()
            guard let children = childrenMap[current] else { continue }
            for child in children {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    // MARK: - posix_spawn

    private func spawn(command: String, cwd: String, logFile: String) throws -> Int32 {
        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        var attrs: posix_spawnattr_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawnattr_init(&attrs)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attrs)
        }

        // stdin 来自 /dev/null；stdout/stderr 追加写入日志文件。
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        let logC = strdup(logFile)
        defer { free(logC) }
        posix_spawn_file_actions_addopen(&fileActions, 1, logC, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, 2, logC, O_WRONLY | O_CREAT | O_APPEND, 0o644)

        // 切换到项目目录。
        let cwdC = strdup(cwd)
        defer { free(cwdC) }
        posix_spawn_file_actions_addchdir_np(&fileActions, cwdC)

        // 新进程组：pgid = 子进程 pid，从而可以 kill(-pid) 停止整棵树。
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attrs, 0)

        // 通过登录 shell 运行，使用用户实际 shell 以便继承正确的 PATH 配置。
        let shell = CommandValidator.userShell
        let argv: [UnsafeMutablePointer<CChar>?] =
            [shell, "-l", "-c", command].map { $0.withCString { strdup($0) } } + [nil]
        defer { argv.forEach { $0.map { free($0) } } }

        let status = posix_spawn(&pid, shell, &fileActions, &attrs, argv, nil)
        guard status == 0 else {
            throw NSError(
                domain: "ItemRadar.ProcessManager",
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey: "posix_spawn 失败: \(String(cString: strerror(status)))"
                ]
            )
        }
        return pid
    }

    // MARK: - 状态持久化

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(State.self, from: data) else { return }
        for (path, info) in state.running where isAlive(pid: info.pid) {
            running[path] = info
        }
        saveState() // 清理已失效记录
    }

    private func saveState() {
        let state = State(running: running)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
