import Foundation
import AppKit

/// 更新检查结果状态。
enum UpdateStatus: Equatable {
    case idle              // 尚未检查
    case checking          // 检查中
    case upToDate          // 已是最新
    case updateAvailable   // 有新版本
    case failed            // 检查失败
}

/// 检查 GitHub 上的最新版本 tag，比较版本号，并缓存「每天首次检查」的结果。
final class UpdateManager: ObservableObject {
    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: String?

    private let repo = "adair007/ItemRadar"
    private let defaults = UserDefaults.standard
    private let lastCheckKey = "updateLastCheckDate"
    private let latestVersionKey = "updateLatestVersion"
    private let releaseURLKey = "updateReleaseURL"

    init() {
        // 恢复缓存：上次检查到新版本后，即使不重新请求也持续显示「有更新」。
        if let version = defaults.string(forKey: latestVersionKey) {
            latestVersion = version
            releaseURL = defaults.string(forKey: releaseURLKey)
            status = .updateAvailable
        }
    }

    /// 菜单栏图标是否应显示「有更新」标识。
    var hasUpdate: Bool { status == .updateAvailable }

    /// 每天首次检查：同一天内只检查一次，避免反复请求。
    func checkDailyIfNeeded() {
        let today = Self.dateString(Date())
        guard defaults.string(forKey: lastCheckKey) != today else { return }
        check()
    }

    /// 执行一次检查；completion 用于手动检查时的结果反馈。
    func check(completion: ((UpdateStatus) -> Void)? = nil) {
        guard status != .checking else { return }
        status = .checking

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let remote = Self.fetchLatestVersion()
            DispatchQueue.main.async {
                self.defaults.set(Self.dateString(Date()), forKey: self.lastCheckKey)

                guard let remote else {
                    self.status = .failed
                    completion?(.failed)
                    return
                }
                if Self.isNewer(remote, than: AppInfo.currentVersion) {
                    self.latestVersion = remote
                    self.releaseURL = "https://github.com/\(self.repo)/releases/tag/v\(remote)"
                    self.defaults.set(remote, forKey: self.latestVersionKey)
                    self.defaults.set(self.releaseURL, forKey: self.releaseURLKey)
                    self.status = .updateAvailable
                } else {
                    self.latestVersion = nil
                    self.releaseURL = nil
                    self.defaults.removeObject(forKey: self.latestVersionKey)
                    self.defaults.removeObject(forKey: self.releaseURLKey)
                    self.status = .upToDate
                }
                completion?(self.status)
            }
        }
    }

    /// 打开发布页面。
    func openReleasePage() {
        let url = releaseURL.flatMap { URL(string: $0) }
            ?? URL(string: "https://github.com/\(repo)/releases")
        if let url { NSWorkspace.shared.open(url) }
    }

    /// 下载新版本 zip 并替换当前应用，然后重启。
    func performUpdate() {
        guard let version = latestVersion else { return }
        let downloadURL = URL(string: "https://github.com/\(repo)/releases/download/v\(version)/ItemRadar-v\(version).zip")!
        let tmpDir = URL(fileURLWithPath: "/tmp/ItemRadar-update")

        DispatchQueue.global(qos: .utility).async {
            do {
                // 清理并创建临时目录。
                try? FileManager.default.removeItem(at: tmpDir)
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

                let zipPath = tmpDir.appendingPathComponent("update.zip")
                let data = try Data(contentsOf: downloadURL)
                try data.write(to: zipPath)

                // 用 ditto 解压（macOS 内置，处理 .zip 最可靠）。
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", zipPath.path, tmpDir.path]
                try unzip.run()
                unzip.waitUntilExit()

                // 启动替换脚本（独立进程，主进程退出后执行替换）。
                Self.launchReplaceScript(tmpDir: tmpDir)

                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                // 下载/解压失败，静默处理（不破坏用户当前操作）。
                try? FileManager.default.removeItem(at: tmpDir)
            }
        }
    }

    /// 启动一个独立 shell 脚本：等主进程退出后替换 app 并重启。
    private static func launchReplaceScript(tmpDir: URL) {
        let appPath = NSHomeDirectory() + "/Applications/ItemRadar.app"
        let script = """
        #!/bin/sh
        sleep 2
        rm -rf "\(appPath)"
        mv "\(tmpDir.path)/ItemRadar.app" "\(appPath)"
        codesign --force --deep --sign - "\(appPath)"
        open "\(appPath)"
        rm -rf "\(tmpDir.path)"
        """
        let scriptPath = tmpDir.appendingPathComponent("replace.sh")
        try? script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [scriptPath.path]
        try? task.run()
        // 不等待 task 完成——主进程即将退出，脚本独立运行。
    }

    // MARK: - 通过 git 协议获取最新 tag（不受 GitHub REST API 限流影响）

    private static func fetchLatestVersion() -> String? {
        guard let output = ProcessRunner.run("/usr/bin/git", ["ls-remote", "--tags", "https://github.com/adair007/ItemRadar.git"]) else {
            return nil
        }
        var versions = Set<String>()
        for line in output.split(separator: "\n") {
            guard let ref = line.split(separator: "\t").last else { continue }
            var name = String(ref)
            guard name.hasPrefix("refs/tags/") else { continue }
            name = String(name.dropFirst("refs/tags/".count))
            if name.hasSuffix("^{}") { name = String(name.dropLast(3)) }
            guard name.hasPrefix("v") else { continue }
            versions.insert(String(name.dropFirst()))
        }
        var latest: String?
        for v in versions {
            if latest == nil || isNewer(v, than: latest!) {
                latest = v
            }
        }
        return latest
    }

    // MARK: - 工具

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 判断 remote 是否比 current 更新（按「.」分段比较数字）。
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let n = max(r.count, c.count)
        for i in 0..<n {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
