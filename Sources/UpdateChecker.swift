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

/// 检查 GitHub 上的最新 Release，比较版本号，并缓存「每天首次检查」的结果。
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

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            status = .failed
            completion?(.failed)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("ItemRadar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.defaults.set(Self.dateString(Date()), forKey: self.lastCheckKey)

                guard error == nil,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.status = .failed
                    completion?(.failed)
                    return
                }

                let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if Self.isNewer(remote, than: AppInfo.currentVersion) {
                    self.latestVersion = remote
                    self.releaseURL = json["html_url"] as? String
                    self.defaults.set(remote, forKey: self.latestVersionKey)
                    if let html = self.releaseURL { self.defaults.set(html, forKey: self.releaseURLKey) }
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
        }.resume()
    }

    /// 打开发布页面。
    func openReleasePage() {
        let url = releaseURL.flatMap { URL(string: $0) }
            ?? URL(string: "https://github.com/\(repo)/releases")
        if let url { NSWorkspace.shared.open(url) }
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
