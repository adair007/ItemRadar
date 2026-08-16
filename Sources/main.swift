import Foundation
import AppKit

// === 命令行工具模式（不启动 GUI） ===
// 支持：
//   ItemRadar --scan                    打印已发现的项目
//   ItemRadar --start  <path-or-name>   启动项目
//   ItemRadar --stop   <path-or-name>   停止项目
//   ItemRadar --status <path-or-name>   查看项目运行状态

let args = CommandLine.arguments

// URL 探测自测：ItemRadar --test-url "<command>"
if let idx = args.firstIndex(of: "--test-url"), idx + 1 < args.count {
    let command = args[idx + 1]
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("pb-test-\(UUID().uuidString.prefix(6))")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let pm = ProcessManager(
        stateURL: tmp.appendingPathComponent("state.json"),
        logsDir: tmp.appendingPathComponent("logs")
    )
    do {
        let info = try pm.start(path: tmp.path, command: command)
        let semaphore = DispatchSemaphore(value: 0)
        var detectedURL: URL?
        URLDetector.detect(manualURL: nil, logFile: info.logFile, pid: info.pid, timeout: 8) { url in
            detectedURL = url
            semaphore.signal()
        }
        semaphore.wait()
        print("DETECTED: \(detectedURL?.absoluteString ?? "(none)")")
        pm.stop(path: tmp.path)
    } catch {
        print("测试失败: \(error.localizedDescription)")
    }
    exit(0)
}

if args.contains("--scan") || args.contains("--start") || args.contains("--stop") || args.contains("--status") {
    let configManager = ConfigManager()
    let config = configManager.load()
    let projects = ProjectScanner.scan(config: config, expandTilde: configManager.expandTilde)

    if args.contains("--scan") {
        for project in projects {
            let cmd = project.command ?? "-"
            print("\(project.name)\t\(project.path)\t\(cmd)")
        }
        exit(0)
    }

    let dir = configManager.directoryURL
    let pm = ProcessManager(
        stateURL: dir.appendingPathComponent("state.json"),
        logsDir: dir.appendingPathComponent("logs")
    )

    let actionFlag: String
    if args.contains("--start")  { actionFlag = "--start" }
    else if args.contains("--stop")    { actionFlag = "--stop" }
    else                               { actionFlag = "--status" }

    guard let flagIdx = args.firstIndex(of: actionFlag), flagIdx + 1 < args.count else {
        print("用法：ItemRadar \(actionFlag) <项目路径或名称>")
        exit(1)
    }

    let target = args[flagIdx + 1]
    // 按路径匹配，其次按名称匹配
    let matched = projects.filter {
        $0.id == target || $0.name == target
    }

    if matched.isEmpty {
        print("未找到项目「\(target)」")
        exit(1)
    }

    for project in matched {
        switch actionFlag {
        case "--start":
            guard let command = project.command else {
                print("\(project.name)\t无可用启动命令，请在配置文件中手动指定")
                continue
            }
            do {
                let info = try pm.start(path: project.id, command: command)
                print("\(project.name)\t已启动 (PID \(info.pid))")
            } catch {
                print("\(project.name)\t启动失败: \(error.localizedDescription)")
            }
        case "--stop":
            pm.stop(path: project.id)
            print("\(project.name)\t已停止")
        default: // --status
            let running = pm.isRunning(path: project.id)
            print("\(project.name)\t\(running ? "运行中" : "已停止")")
        }
    }
    exit(0)
}

// === GUI 模式 ===

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = ProjectStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "terminal",
                accessibilityDescription: "ItemRadar"
            )
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let contentView = ContentView(onReopenPopover: { [weak self] in
            self?.showPopover()
        }, onManualRefresh: { [weak self] in
            self?.store.refresh()
        }).environmentObject(store)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
