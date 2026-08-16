import Foundation
import Combine
import AppKit

/// UI 与后端之间的桥梁：持有配置、扫描结果与进程管理状态。
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var runningPaths: Set<String> = []
    @Published private(set) var startingPaths: Set<String> = []
    @Published private(set) var stoppingPaths: Set<String> = []
    @Published private(set) var lastError: String?
    @Published private(set) var configPath: String
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsWarning: Bool = false

    let configManager: ConfigManager
    private let processManager: ProcessManager
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var statusClearWorkItem: DispatchWorkItem?
    private var errorClearWorkItem: DispatchWorkItem?
    private var detectedURLs: [String: URL] = [:]
    private var externalPIDs: [String: Int32] = [:]

    /// 防抖：记录上次 refreshRunning 的时间，避免短时间内重复执行。
    private var lastRefreshRunningTime: Date?
    private let refreshRunningDebounceInterval: TimeInterval = 5.0

    init() {
        configManager = ConfigManager()
        configManager.ensureExists()
        configPath = configManager.configURL.path

        let dir = configManager.directoryURL
        processManager = ProcessManager(
            stateURL: dir.appendingPathComponent("state.json"),
            logsDir: dir.appendingPathComponent("logs")
        )

        scanNow()
        refreshRunning()
        startWatchingConfig()
    }

    func scanNow() {
        let config = configManager.load()
        var scanned = ProjectScanner.scan(config: config, expandTilde: configManager.expandTilde)
        // 应用用户自定义顺序：先按 projectOrder 排列，未在顺序里的按字母序补在末尾。
        if let order = config.projectOrder, !order.isEmpty {
            var ordered: [Project] = []
            var seen = Set<String>()
            for path in order {
                if let project = scanned.first(where: { $0.id == path }) {
                    ordered.append(project)
                    seen.insert(path)
                }
            }
            ordered += scanned.filter { !seen.contains($0.id) }
            scanned = ordered
        }
        projects = scanned
    }

    func refresh() {
        cleanupMissingManualProjects()
        scanNow()
        refreshRunning(force: true)
        setStatus("已刷新，当前 \(projects.count) 个可启动项目")
    }

    /// 清理「手动添加的项目」中路径已不存在的条目（只清理手动项目，保留排除项）。
    private func cleanupMissingManualProjects() {
        var config = configManager.load()
        let before = config.projects.count
        config.projects.removeAll { entry in
            entry.isEnabled && !FileManager.default.fileExists(atPath: configManager.expandTilde(entry.path))
        }
        if config.projects.count != before {
            configManager.save(config)
        }
    }

    /// 根据进程管理器的实际状态，刷新运行状态集合。
    /// 本应用启动的进程同步识别；外部进程（端口监听）在后台探测，避免阻塞主线程。
    /// 默认带 5 秒防抖，force: true 可跳过防抖（用于手动刷新）。
    private func refreshRunning(force: Bool = false) {
        if !force,
           let last = lastRefreshRunningTime,
           Date().timeIntervalSince(last) < refreshRunningDebounceInterval {
            return
        }
        lastRefreshRunningTime = Date()

        let snapshot = projects
        let paths = Set(snapshot.filter { processManager.isRunning(path: $0.id) }.map { $0.id })
        runningPaths = paths
        externalPIDs = [:]
        let toProbe = snapshot.filter { !paths.contains($0.id) && portOf($0) != nil }
        guard !toProbe.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            // 批量获取所有监听端口，减少 lsof 调用次数
            let allPorts = URLDetector.allListeningPorts()
            var newPaths = paths
            var pids: [String: Int32] = [:]
            for project in toProbe {
                guard let port = self.portOf(project),
                      let pid = allPorts[port],
                      URLDetector.pidMatchesProject(pid, command: project.command ?? "", path: project.id)
                else { continue }
                newPaths.insert(project.id)
                pids[project.id] = pid
            }
            DispatchQueue.main.async {
                self.runningPaths = newPaths
                self.externalPIDs = pids
            }
        }
    }

    private func portOf(_ project: Project) -> Int? {
        urlOf(project)?.port
    }

    private func urlOf(_ project: Project) -> URL? {
        guard let raw = project.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URLDetector.normalize(raw),
              url.port != nil else { return nil }
        return url
    }

    /// 拖拽排序后更新顺序并持久化。
    func moveProjects(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        configManager.saveProjectOrder(projects.map { $0.id })
    }

    func isRunning(_ project: Project) -> Bool {
        runningPaths.contains(project.id)
    }

    func isStarting(_ project: Project) -> Bool {
        startingPaths.contains(project.id)
    }

    func isStopping(_ project: Project) -> Bool {
        stoppingPaths.contains(project.id)
    }

    func start(_ project: Project) {
        guard let command = project.command else {
            setError("「\(project.name)」没有可用的启动命令，请在配置文件中手动指定。")
            return
        }
        startingPaths.insert(project.id)
        // 已在运行检测：若配置了 url 且其端口已监听，则直接打开浏览器，避免重复启动。
        if let url = urlOf(project),
           let pid = URLDetector.pidListening(on: url.port ?? 0),
           URLDetector.pidMatchesProject(pid, command: command, path: project.id) {
            let finalURL = URLDetector.fixLocalhost(url)
            detectedURLs[project.id] = finalURL
            externalPIDs[project.id] = pid
            runningPaths.insert(project.id)
            NSWorkspace.shared.open(finalURL)
            setStatus("「\(project.name)」已在运行，已打开网页")
            finishStarting(project.id)
            return
        }
        do {
            let info = try processManager.start(path: project.id, command: command)
            lastError = nil
            runningPaths.insert(project.id)
            setStatus("「\(project.name)」已启动")
            autoOpenBrowserIfNeeded(project: project, info: info)
            scheduleLivenessCheck(project: project)
            finishStarting(project.id)
        } catch {
            setError("「\(project.name)」启动失败，请检查启动命令是否正确")
            finishStarting(project.id)
        }
    }

    /// 延迟清除「启动中」状态，让按钮的过渡态可见。
    private func finishStarting(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.startTransition) { [weak self] in
            self?.startingPaths.remove(id)
        }
    }

    /// 延迟清除「停止中」状态。
    private func finishStopping(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.stopTransition) { [weak self] in
            self?.stoppingPaths.remove(id)
        }
    }

    /// 设置错误信息，自动清除。
    private func setError(_ message: String) {
        lastError = message
        errorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.lastError = nil
        }
        errorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.noticeDuration, execute: workItem)
    }

    /// 手动关闭错误横幅。
    func dismissError() {
        errorClearWorkItem?.cancel()
        lastError = nil
    }

    /// 启动 3 秒后检查进程是否还活着；若已退出且未被用户停止，则提示可能命令有误。
    /// 检查只做 kill(pid, 0) 这类非阻塞系统调用，直接在主线程延迟即可，省一次线程切换。
    private func scheduleLivenessCheck(project: Project) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.livenessCheck) { [weak self] in
            guard let self else { return }
            let stillTracked = self.processManager.runningInfo(path: project.id) != nil
            let alive = self.processManager.isRunning(path: project.id)
            if stillTracked && !alive {
                self.runningPaths.remove(project.id)
                self.setStatus("「\(project.name)」启动后异常退出，可能是启动命令不对", warning: true)
            }
        }
    }

    func stop(_ project: Project) {
        if processManager.runningInfo(path: project.id) != nil {
            processManager.stop(path: project.id)
        } else if let pid = externalPIDs[project.id] {
            processManager.terminate(pid: pid)
        }
        detectedURLs[project.id] = nil
        externalPIDs[project.id] = nil
        runningPaths.remove(project.id)
        stoppingPaths.insert(project.id)
        finishStopping(project.id)
    }

    /// 启动后异步探测网页地址，需要时自动用默认浏览器打开。
    private func autoOpenBrowserIfNeeded(project: Project, info: RunningInfo) {
        guard project.openBrowser else { return }

        if let manual = project.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manual.isEmpty,
           let normalized = URLDetector.normalize(manual) {
            // 手动 url：等服务端口就绪后再打开（如 NapCat 启动较慢）
            if let port = normalized.port {
                URLDetector.waitForPort(port, timeout: Timing.portWaitTimeout) { [weak self] _ in
                    guard let self else { return }
                    let url = URLDetector.fixLocalhost(normalized)
                    self.detectedURLs[project.id] = url
                    NSWorkspace.shared.open(url)
                    self.setStatus("「\(project.name)」已启动，正在浏览器打开")
                    self.objectWillChange.send()
                }
            } else {
                let url = URLDetector.fixLocalhost(normalized)
                detectedURLs[project.id] = url
                NSWorkspace.shared.open(url)
                setStatus("「\(project.name)」已启动，正在浏览器打开")
            }
            return
        }

        // 自动探测：从日志或端口推断 URL
        URLDetector.detect(manualURL: nil, logFile: info.logFile, pid: info.pid) { [weak self] url in
            guard let self else { return }
            if let url {
                self.detectedURLs[project.id] = url
                NSWorkspace.shared.open(url)
                self.setStatus("「\(project.name)」已启动，正在浏览器打开")
            } else {
                self.setStatus("「\(project.name)」已启动，未检测到网页地址", warning: true)
            }
            self.objectWillChange.send()
        }
    }

    /// 手动打开项目的网页（自动探测失败时的兜底）。
    func openBrowser(_ project: Project) {
        if let url = detectedURLs[project.id] {
            NSWorkspace.shared.open(url)
            return
        }
        if let manual = project.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manual.isEmpty,
           let url = URLDetector.normalize(manual) {
            NSWorkspace.shared.open(URLDetector.fixLocalhost(url))
            return
        }
        guard let info = processManager.runningInfo(path: project.id) else {
            setStatus("「\(project.name)」未在运行", warning: true)
            return
        }
        URLDetector.detect(manualURL: nil, logFile: info.logFile, pid: info.pid, timeout: 3) { [weak self] url in
            guard let self else { return }
            if let url {
                self.detectedURLs[project.id] = url
                NSWorkspace.shared.open(url)
            } else {
                self.setStatus("未检测到「\(project.name)」的网页地址", warning: true)
            }
        }
    }

    // MARK: - 列表管理（移除 / 编辑命令）

    /// 从列表移除项目：写入 enabled=false 的排除条目并刷新。
    func removeFromList(_ project: Project) {
        configManager.upsertManual(path: project.id) { entry in
            entry.enabled = false
        }
        scanNow()
    }

    /// 覆盖项目的启动命令并刷新。
    func updateCommand(_ project: Project, command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.upsertManual(path: project.id) { entry in
            entry.command = trimmed.isEmpty ? nil : trimmed
        }
        scanNow()
    }

    /// 设置项目的网页地址并刷新。
    func updateURL(_ project: Project, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.upsertManual(path: project.id) { entry in
            entry.url = trimmed.isEmpty ? nil : trimmed
        }
        scanNow()
    }

    /// 设置项目的显示名称并刷新。
    func updateName(_ project: Project, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.upsertManual(path: project.id) { entry in
            entry.name = trimmed.isEmpty ? nil : trimmed
        }
        scanNow()
    }

    /// 开关「自动打开浏览器」并刷新。
    func updateOpenBrowser(_ project: Project, openBrowser: Bool) {
        configManager.upsertManual(path: project.id) { entry in
            entry.openBrowser = openBrowser
        }
        scanNow()
    }

    /// 手动添加一个服务（用于扫描器识别不到的服务，如全局 CLI 工具 / 注入式运行时）。
    func addManualProject(name: String?, path: String, command: String, url: String?, openBrowser: Bool) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedCommand.isEmpty else { return }
        configManager.upsertManual(path: trimmedPath) { entry in
            entry.name = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? name : nil
            entry.command = trimmedCommand
            entry.url = (url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? url : nil
            entry.openBrowser = openBrowser
            entry.enabled = true
        }
        scanNow()
    }

    /// 添加扫描根目录并刷新列表，给出明确的结果提示。
    func addRootAndRefresh(_ path: String) {
        let added = configManager.addRootIfNew(path)
        let before = Set(projects.map { $0.id })
        scanNow()
        let after = Set(projects.map { $0.id })
        let newCount = after.subtracting(before).count
        let name = (path as NSString).lastPathComponent

        if !added {
            setStatus("「\(name)」已在扫描列表中")
        } else if newCount > 0 {
            setStatus("已添加「\(name)」，发现 \(newCount) 个可启动项目")
        } else if after.isEmpty {
            setStatus("「\(name)」下没有找到可启动的项目", warning: true)
        } else {
            setStatus("已添加「\(name)」，但没有新增项目", warning: true)
        }
    }

    // MARK: - 设置

    var currentRoots: [String] { configManager.load().roots }
    var isScanHomeTopLevel: Bool { configManager.load().shouldScanHomeTopLevel }

    func removeRoot(_ path: String) {
        var config = configManager.load()
        let expanded = configManager.expandTilde(path)
        config.roots.removeAll { configManager.expandTilde($0) == expanded }
        configManager.save(config)
        scanNow()
    }

    func setScanHomeTopLevel(_ enabled: Bool) {
        var config = configManager.load()
        config.scanHomeTopLevel = enabled
        configManager.save(config)
        scanNow()
    }

    func makeRelative(_ path: String) -> String {
        configManager.makeRelative(path)
    }

    // MARK: - 开机自启动

    func isAutoLaunchEnabled() -> Bool {
        FileManager.default.fileExists(atPath: AppInfo.launchAgentPath)
    }

    func setAutoLaunch(_ enabled: Bool) {
        if enabled {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>\(AppInfo.launchAgentLabel)</string>
              <key>ProgramArguments</key>
              <array>
                <string>\(AppInfo.executablePath)</string>
              </array>
              <key>RunAtLoad</key>
              <true/>
              <key>KeepAlive</key>
              <false/>
            </dict>
            </plist>
            """
            try? plist.write(toFile: AppInfo.launchAgentPath, atomically: true, encoding: .utf8)
            _ = ProcessRunner.run("/bin/launchctl", ["load", AppInfo.launchAgentPath])
            setStatus("已开启开机自启动")
        } else {
            _ = ProcessRunner.run("/bin/launchctl", ["unload", AppInfo.launchAgentPath])
            try? FileManager.default.removeItem(atPath: AppInfo.launchAgentPath)
            setStatus("已关闭开机自启动")
        }
    }

    // MARK: - 状态提示

    private func setStatus(_ message: String, warning: Bool = false) {
        statusMessage = message
        statusIsWarning = warning
        statusClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.statusMessage = nil
        }
        statusClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.noticeDuration, execute: workItem)
    }

    /// 复制项目的启动命令到剪贴板。
    func copyCommand(_ project: Project) {
        guard let command = project.command, !command.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        setStatus("已复制启动命令：\(command)")
    }

    // MARK: - 打开相关文件

    func openConfig() {
        configManager.ensureExists()
        NSWorkspace.shared.open(configManager.configURL)
    }

    func revealConfig() {
        configManager.ensureExists()
        NSWorkspace.shared.activateFileViewerSelecting([configManager.configURL])
    }

    func openLog(_ project: Project) {
        guard let info = processManager.runningInfo(path: project.id) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: info.logFile))
    }

    func reveal(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
    }

    // MARK: - 配置文件热更新

    private func startWatchingConfig() {
        let fd = open(configManager.configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scanNow()
            self?.refreshRunning()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }
}
