import Foundation

/// 展示用的项目模型。
struct Project: Identifiable, Hashable {
    let id: String        // 绝对路径，作为唯一标识
    let name: String      // 展示名
    let path: String      // 绝对路径
    let command: String?  // 解析出的启动命令；nil 表示无法自动推断
    let isManual: Bool    // 是否来自手动配置
    let url: String?      // 手动指定的网页地址（启动后打开）
    let openBrowser: Bool // 是否自动打开浏览器

    var needsConfig: Bool { command == nil }
}

/// 项目发现与启动命令推断（纯函数，非 UI）。
enum ProjectScanner {
    static let markers = [
        "package.json",
        "docker-compose.yml", "docker-compose.yaml",
        "compose.yml", "compose.yaml",
        "pyproject.toml", "Cargo.toml", "go.mod",
        "manage.py", "requirements.txt",
        "Gemfile", "index.php",
    ]

    /// 判断某目录是否为「项目」：含项目特征文件，或含 dotnet 工程文件。
    static func isProjectDir(_ dir: String) -> Bool {
        if markers.contains(where: {
            FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent($0))
        }) {
            return true
        }
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            if entries.contains(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".sln") }) {
                return true
            }
        }
        return false
    }

    /// 合并「手动配置」与「自动扫描」两路来源，按路径去重后返回。
    /// 只展示「可启动」的项目：必须解析出启动命令，否则不进入列表。
    static func scan(config: AppConfig, expandTilde: (String) -> String) -> [Project] {
        var byPath: [String: Project] = [:]

        // 被手动配置明确排除（enabled=false）的路径。
        let excluded = Set(config.projects.filter { !$0.isEnabled }.map { expandTilde($0.path) })

        // 1) 手动条目优先（也充当覆盖/排除）。
        for entry in config.projects {
            guard entry.isEnabled else { continue }
            let path = expandTilde(entry.path)
            let command = (entry.command?.isEmpty == false)
                ? entry.command
                : resolveCommand(for: path)
            // 关键判断：必须有可执行的启动命令才展示。
            guard let command = command else { continue }
            let name = (entry.name?.isEmpty == false)
                ? entry.name!
                : (path as NSString).lastPathComponent
            byPath[path] = Project(
                id: path, name: name, path: path,
                command: command, isManual: true,
                url: (entry.url?.isEmpty == false) ? entry.url : nil,
                openBrowser: entry.shouldOpenBrowser
            )
        }

        // 自动扫描用到的局部助手：去重 / 排除 / 必须有命令。
        func addScanned(_ path: String) {
            guard byPath[path] == nil else { return }
            guard !excluded.contains(path) else { return }
            guard let command = resolveCommand(for: path) else { return }
            let name = (path as NSString).lastPathComponent
            byPath[path] = Project(
                id: path, name: name, path: path,
                command: command, isManual: false,
                url: nil, openBrowser: true
            )
        }

        // 2) 自动扫描 roots。
        let depth = max(1, config.scanDepth)
        for root in config.roots {
            let rootPath = expandTilde(root)
            for path in projectPaths(in: rootPath, depth: depth) {
                addScanned(path)
            }
            addScanned(rootPath) // root 目录本身也可能是项目
        }

        // 3) 额外扫描用户目录顶层（深度 1），覆盖 ~/code、~/github 等。
        if config.shouldScanHomeTopLevel {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for path in projectPaths(in: home, depth: 1) {
                addScanned(path)
            }
        }

        return byPath.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// 递归查找项目目录，`depth` 表示最大递归层数（1 = 只看根目录的直接子目录）。
    static func projectPaths(in dir: String, depth: Int, current: Int = 1) -> [String] {
        var result: [String] = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return result }
        for name in entries.sorted() {
            if name.hasPrefix(".") || name == "node_modules" { continue }
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            if isProjectDir(full) {
                result.append(full)
            } else if current < depth {
                result += projectPaths(in: full, depth: depth, current: current + 1)
            }
        }
        return result
    }

    /// 依据锁文件推断包管理器。
    static func packageManager(for path: String) -> String {
        let fm = FileManager.default
        let p = { (name: String) -> Bool in
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(name))
        }
        if p("pnpm-lock.yaml") { return "pnpm" }
        if p("yarn.lock") { return "yarn" }
        if p("bun.lockb") || p("bun.lock") { return "bun" }
        return "npm"
    }

    /// 推断项目的默认启动命令。
    static func resolveCommand(for path: String) -> String? {
        let fm = FileManager.default
        let file = { (name: String) -> Bool in
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(name))
        }

        // Node
        if let data = fm.contents(atPath: (path as NSString).appendingPathComponent("package.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = obj["scripts"] as? [String: String] {
            let pm = packageManager(for: path)
            for key in ["dev", "start", "serve"] where scripts[key] != nil {
                return "\(pm) run \(key)"
            }
        }

        // Docker
        for compose in ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"] {
            if file(compose) { return "docker compose up" }
        }

        // Python
        if file("manage.py") { return "python3 manage.py runserver" }
        if file("app.py") { return "python3 app.py" }
        if file("main.py") { return "python3 main.py" }

        // Rust / Go / PHP
        if file("Cargo.toml") { return "cargo run" }
        if file("go.mod") { return "go run ." }
        if file("index.php") { return "php -S localhost:8000" }

        // dotnet
        if let entries = try? fm.contentsOfDirectory(atPath: path),
           entries.contains(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".sln") }) {
            return "dotnet run"
        }

        // Ruby（仅当看起来像 Rails 时才推断）
        if file("Gemfile") && (file("bin/rails") || file("config/routes.rb")) {
            return "bundle exec rails server"
        }

        return nil
    }
}
