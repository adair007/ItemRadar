import Foundation

/// 应用元信息（名称 / Bundle ID / 安装路径 / LaunchAgent 路径 / 版本号）。
enum AppInfo {
    static let name = "ItemRadar"
    static let bundleID = "local.itemradar"
    static let launchAgentLabel = "local.itemradar"
    static let currentVersion = "1.1.0"

    static var appPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/\(name).app").path
    }

    static var executablePath: String {
        appPath + "/Contents/MacOS/" + name
    }

    static var launchAgentPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist").path
    }
}

/// 全局时间常量，避免魔法数字散落。
enum Timing {
    static let startTransition: TimeInterval = 0.4   // 「启动中…」过渡时长
    static let stopTransition: TimeInterval = 1.0    // 「停止中…」过渡时长
    static let livenessCheck: TimeInterval = 3.0     // 启动后存活检查延迟
    static let noticeDuration: TimeInterval = 6.0    // 提示/错误自动消失时长
    static let urlDetectTimeout: TimeInterval = 10.0 // 日志 URL 探测超时
    static let portWaitTimeout: TimeInterval = 15.0  // 手动 url 等服务端口就绪超时
}
