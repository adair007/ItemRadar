import Foundation

/// 一个手动声明（或用于覆盖自动扫描结果）的项目条目。
struct ProjectConfig: Codable {
    var name: String?
    var path: String
    var command: String?
    var enabled: Bool?
    var url: String?        // 手动指定网页地址（启动后打开它）
    var openBrowser: Bool?  // 是否自动打开浏览器（缺省 true）

    var isEnabled: Bool { enabled ?? true }
    var shouldOpenBrowser: Bool { openBrowser ?? true }
}

/// 插件主配置，保存在 ~/.projectbar/config.json。
struct AppConfig: Codable {
    var roots: [String]
    var scanDepth: Int
    var projects: [ProjectConfig]
    var scanHomeTopLevel: Bool?  // 是否额外扫描用户目录顶层（深度 1），缺省 true
    var projectOrder: [String]?  // 列表自定义顺序（存绝对路径）

    var shouldScanHomeTopLevel: Bool { scanHomeTopLevel ?? true }

    static func makeDefault() -> AppConfig {
        AppConfig(
            roots: ["~/Documents", "~/Downloads", "~/Desktop"],
            scanDepth: 3,
            projects: [],
            scanHomeTopLevel: true,
            projectOrder: nil
        )
    }
}

/// 负责配置文件与目录的读写、路径展开。
final class ConfigManager {
    let directoryURL: URL
    let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directoryURL = home.appendingPathComponent(".projectbar")
        configURL = directoryURL.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .makeDefault()
        }
        return config
    }

    func ensureExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            save(.makeDefault())
        }
    }

    func save(_ config: AppConfig) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    /// 把 ~ 或 ~/xxx 展开为绝对路径。
    func expandTilde(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            let sub = String(path.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(sub).path
        }
        return path
    }

    /// 把绝对路径尽量转回 `~` 开头的相对写法，便于阅读。
    func makeRelative(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// 新增或更新某路径对应的手动条目，然后保存。
    /// `block` 在已存在的条目（若有）或新建条目上修改字段。
    func upsertManual(path: String, block: (inout ProjectConfig) -> Void) {
        var config = load()
        let expandedPath = expandTilde(path)
        if let index = config.projects.firstIndex(where: { expandTilde($0.path) == expandedPath }) {
            block(&config.projects[index])
        } else {
            var entry = ProjectConfig(path: makeRelative(expandedPath))
            block(&entry)
            config.projects.append(entry)
        }
        save(config)
    }

    /// 把目录加入扫描根目录（若已存在则跳过），然后保存。
    /// 返回是否真的新增了（false 表示已存在）。
    @discardableResult
    func addRootIfNew(_ path: String) -> Bool {
        var config = load()
        let expandedPath = expandTilde(path)
        guard !config.roots.contains(where: { expandTilde($0) == expandedPath }) else {
            return false
        }
        config.roots.append(makeRelative(expandedPath))
        save(config)
        return true
    }

    /// 保存列表的自定义顺序（存绝对路径）。
    func saveProjectOrder(_ order: [String]) {
        var config = load()
        config.projectOrder = order
        save(config)
    }
}
