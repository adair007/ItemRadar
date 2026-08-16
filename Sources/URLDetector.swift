import Foundation

/// 探测一个已启动服务对外提供的网页地址。
/// 优先级：手动配置的 url → 日志里的 URL → lsof 监听的端口。
/// 当有多个 URL 时，优先选择常见开发端口（3000 > 5173 > 8080 …）。
enum URLDetector {
    /// 常见开发端口，按优先级从高到低排列。
    static let preferredPorts: [Int] = [3000, 5173, 8080, 8000, 4200, 5000, 4000, 3001, 3002, 9000, 6006]

    /// 异步探测 URL，通过 completion 回调返回结果，避免阻塞线程。
    /// completion 始终在主线程回调，调用方可直接更新 UI。
    static func detect(manualURL: String?, logFile: String, pid: Int32, timeout: TimeInterval = Timing.urlDetectTimeout, completion: @escaping (URL?) -> Void) {
        // 统一在主线程回调，避免调用方在后台线程误改 UI 状态。
        let finish: (URL?) -> Void = { url in
            DispatchQueue.main.async { completion(url) }
        }
        // 1) 手动配置
        if let raw = manualURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = normalize(raw) {
            finish(fixLocalhost(url))
            return
        }
        // 2) 日志解析（异步定时器驱动）
        detectFromLog(logFile: logFile, timeout: timeout) { url in
            if let url = url {
                finish(fixLocalhost(url))
                return
            }
            // 3) lsof 端口兜底
            DispatchQueue.global(qos: .utility).async {
                let url = detectFromPorts(pid: pid)
                finish(url)
            }
        }
    }

    // MARK: 归一化

    /// 把 "localhost:3000" 之类的字符串归一化成 URL；无协议则补 http://。
    static func normalize(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") {
            return URL(string: s)
        }
        return URL(string: "http://\(s)")
    }

    /// 0.0.0.0 / :: 是绑定所有网卡的写法，浏览器打不开，替换成 localhost。
    static func fixLocalhost(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if comps.host == "0.0.0.0" || comps.host == "::" || comps.host == "[::]" {
            comps.host = "localhost"
            return comps.url ?? url
        }
        return url
    }

    // MARK: 日志解析（异步定时器驱动）

    static func detectFromLog(logFile: String, timeout: TimeInterval, completion: @escaping (URL?) -> Void) {
        var allURLs: [URL] = []
        var fileOffset: UInt64 = 0
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let deadline = DispatchTime.now() + timeout

        timer.setEventHandler { [timer] in
            // 增量读取：只扫描上次 offset 之后新增的日志内容。
            let (found, newOffset) = newURLsInFile(logFile, fromOffset: fileOffset)
            fileOffset = newOffset
            for url in found where !allURLs.contains(url) {
                allURLs.append(url)
                // 快速路径：出现在常用端口上立即返回
                if let port = url.port, preferredPorts.contains(port) {
                    timer.cancel()
                    completion(url)
                    return
                }
            }
            if DispatchTime.now() >= deadline {
                timer.cancel()
                completion(bestURL(from: allURLs))
            }
        }

        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.resume()
    }

    /// 全量读取日志并解析 URL（供自测等一次性场景使用）。
    static func allURLsInFile(_ logFile: String) -> [URL] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: logFile)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return allURLs(in: text)
    }

    /// 增量读取日志：只读取 `fromOffset` 之后新增的内容，返回解析出的 URL 与新 offset。
    /// 相比全量重读，日志持续增长时能避免重复 I/O 与重复正则扫描。
    static func newURLsInFile(_ logFile: String, fromOffset: UInt64) -> ([URL], UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: logFile)) else {
            return ([], fromOffset)
        }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? fromOffset
        var start = fromOffset
        // 日志被截断（offset 越过文件末尾）时，从头读取。
        if end < start {
            start = 0
        }
        guard end > start else { return ([], fromOffset) }
        try? handle.seek(toOffset: start)
        let data = handle.readData(ofLength: Int(end - start))
        guard let text = String(data: data, encoding: .utf8) else {
            return ([], end)
        }
        return (allURLs(in: text), end)
    }

    static func allURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        let ns = text as NSString

        // 完整 URL：http(s)://localhost[:port][/path]
        let fullPattern = #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d{1,5})?(?:/[^\s"'<>()]*)?(?::\d{1,5})?"#
        for match in matches(for: fullPattern, in: text) {
            let raw = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            if let url = normalize(raw) { urls.append(url) }
        }

        // host:port 无协议，如 "localhost:3000"
        let hostPortPattern = #"\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0):\d{1,5}\b"#
        for match in matches(for: hostPortPattern, in: text) {
            let raw = ns.substring(with: match.range)
            if let url = normalize(raw) { urls.append(url) }
        }

        // python http.server 风格："Serving HTTP on 0.0.0.0 port 8123"
        let portWordPattern = #"(?:localhost|127\.0\.0\.1|0\.0\.0\.0)\s+port\s+\d{1,5}"#
        for match in matches(for: portWordPattern, in: text) {
            let raw = ns.substring(with: match.range)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "port", with: ":")
            if let url = normalize(raw) { urls.append(url) }
        }

        return urls
    }

    private static func matches(for pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// 从多个 URL 中选最优：按端口优先常用端口，其次低端口。
    static func bestURL(from urls: [URL]) -> URL? {
        // 按端口去重，同端口取第一个。
        var byPort: [Int: URL] = [:]
        for url in urls {
            if let port = url.port, byPort[port] == nil {
                byPort[port] = url
            }
        }
        if byPort.isEmpty { return urls.first }
        // 常用端口优先
        for port in preferredPorts {
            if let url = byPort[port] { return url }
        }
        // 否则取最低端口
        if let lowest = byPort.keys.sorted().first {
            return byPort[lowest]
        }
        return nil
    }

    // MARK: lsof 端口探测

    static func detectFromPorts(pid: Int32) -> URL? {
        guard let text = ProcessRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-g", "\(pid)"]) else { return nil }
        let ports = allPorts(inLsof: text)
        guard let port = bestPort(from: ports) else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    static func allPorts(inLsof text: String) -> [Int] {
        let regex = try? NSRegularExpression(pattern: #":(\d{1,5})\s*\(LISTEN\)"#)
        var ports = Set<Int>()
        let ns = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in matches where match.numberOfRanges > 1 {
            let portStr = ns.substring(with: match.range(at: 1))
            if let port = Int(portStr) { ports.insert(port) }
        }
        return Array(ports).sorted()
    }

    static func bestPort(from ports: [Int]) -> Int? {
        for port in preferredPorts {
            if ports.contains(port) { return port }
        }
        return ports.first
    }

    /// 判断某端口当前是否已有进程在监听（用于「已在运行」检测）。
    static func isPortListening(_ port: Int) -> Bool {
        pidListening(on: port) != nil
    }

    /// 返回监听某端口的进程 PID（用于「已在运行」检测与外部停止）。
    static func pidListening(on port: Int) -> Int32? {
        guard let str = ProcessRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]) else { return nil }
        return Int32(str)
    }

    /// 判断监听某端口的进程是否「像」这个项目启动的。
    /// 命令关键词 或 项目路径名 任一命中即算匹配（兼容壳命令如 pnpm → node vite）。
    static func pidMatchesProject(_ pid: Int32, command: String, path: String) -> Bool {
        guard let args = ProcessRunner.run("/bin/ps", ["-p", "\(pid)", "-o", "args="]) else { return false }
        let firstWord = command.split(separator: " ").first.map(String.init) ?? ""
        if !firstWord.isEmpty && args.contains(firstWord) { return true }
        let name = (path as NSString).lastPathComponent
        if !name.isEmpty && args.contains(name) { return true }
        return false
    }

    /// 异步等待某端口开始监听（用于手动 url 时等服务就绪再开浏览器）。
    /// completion 始终在主线程回调。
    static func waitForPort(_ port: Int, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in
            DispatchQueue.main.async { completion(ok) }
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let deadline = DispatchTime.now() + timeout

        timer.setEventHandler { [timer] in
            if isPortListening(port) {
                timer.cancel()
                finish(true)
                return
            }
            if DispatchTime.now() >= deadline {
                timer.cancel()
                finish(false)
            }
        }

        // 端口就绪无需秒级以下精度，1 秒探测一次即可，降低 lsof 调用频率。
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.resume()
    }

    // MARK: 批量端口探测（减少系统调用）

    /// 一次性获取所有监听端口及其 PID，避免对每个端口单独执行 lsof。
    static func allListeningPorts() -> [Int: Int32] {
        guard let text = ProcessRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return [:] }
        var result: [Int: Int32] = [:]
        var currentPID: Int32?
        for line in text.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPID = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPID {
                // 格式如 "n127.0.0.1:3000" 或 "n*:3000"
                let addr = String(line.dropFirst())
                if let portStr = addr.split(separator: ":").last,
                   let port = Int(portStr),
                   result[port] == nil {
                    result[port] = pid
                }
            }
        }
        return result
    }

    // MARK: 从项目文件里猜网页地址

    /// 根据项目目录和启动命令，猜一个网页地址（拿不准就返回 nil）。
    static func suggestURL(path: String, command: String?) -> String? {
        let fm = FileManager.default
        func file(_ name: String) -> Bool {
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(name))
        }
        func read(_ name: String) -> String? {
            try? String(contentsOfFile: (path as NSString).appendingPathComponent(name), encoding: .utf8)
        }

        // 1) 从启动命令里解析端口，如 vite --port=3000 / next -p 3000
        if let cmd = command, let port = portInCommand(cmd) {
            return "http://localhost:\(port)"
        }
        // 2) .env 里的 PORT
        if let env = read(".env"), let port = portInText(env, pattern: #"(?:^|\n)\s*PORT\s*=\s*(\d{2,5})"#) {
            return "http://localhost:\(port)"
        }
        // 3) vite.config 里的 server.port，否则 vite 默认 5173
        for name in ["vite.config.js", "vite.config.ts", "vite.config.mjs"] {
            if let cfg = read(name) {
                if let port = portInText(cfg, pattern: #"port\s*:\s*(\d{2,5})"#) {
                    return "http://localhost:\(port)"
                }
                return "http://localhost:5173"
            }
        }
        // 4) ComfyUI（main.py 里带 ComfyUI / 8188）
        if file("main.py"), let main = read("main.py"),
           main.contains("ComfyUI") || main.contains("8188") {
            return "http://127.0.0.1:8188"
        }
        // 5) Django
        if file("manage.py") { return "http://localhost:8000" }
        // 6) Next.js
        if file("next.config.js") || file("next.config.mjs") || file("next.config.ts") {
            return "http://localhost:3000"
        }
        // 7) package.json 依赖里有 next / react-scripts
        if let pkg = read("package.json"),
           pkg.contains("\"next\"") || pkg.contains("\"react-scripts\"") {
            return "http://localhost:3000"
        }
        return nil
    }

    private static func portInCommand(_ command: String) -> Int? {
        if let m = firstMatch(pattern: #"(?:--port[=\s]|-p\s+)(\d{2,5})"#, in: command) {
            return Int(m)
        }
        return nil
    }

    private static func portInText(_ text: String, pattern: String) -> Int? {
        if let m = firstMatch(pattern: pattern, in: text) {
            return Int(m)
        }
        return nil
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
