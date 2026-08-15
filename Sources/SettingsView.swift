import SwiftUI
import AppKit

// MARK: - 设置小窗

struct SettingsView: View {
    @EnvironmentObject var store: ProjectStore
    let onDismiss: () -> Void

    @State private var roots: [String] = []
    @State private var scanHomeTopLevel = true
    @State private var autoLaunch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.headline)
            Text("在这里选择「获取项目」时要扫描哪些文件夹。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("扫描的文件夹")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("添加文件夹…", action: pickRoot)
                    .controlSize(.small)
            }

            if roots.isEmpty {
                Text("还没有扫描文件夹，点「添加文件夹…」添加。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(roots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            Text(root)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                store.removeRoot(root)
                                roots.removeAll { $0 == root }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                            .help("移除该文件夹")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            Toggle("额外扫描用户目录顶层（如 ~/code、~/github）", isOn: Binding(
                get: { scanHomeTopLevel },
                set: { newValue in
                    scanHomeTopLevel = newValue
                    store.setScanHomeTopLevel(newValue)
                }
            ))

            Divider()

            Toggle("开机自启动（登录时自动运行）", isOn: Binding(
                get: { autoLaunch },
                set: { newValue in
                    autoLaunch = newValue
                    store.setAutoLaunch(newValue)
                }
            ))

            HStack {
                Spacer()
                Button("完成", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            roots = store.currentRoots
            scanHomeTopLevel = store.isScanHomeTopLevel
            autoLaunch = store.isAutoLaunchEnabled()
        }
    }

    private func pickRoot() {
        if let path = DirectoryPicker.pick(message: "选择要扫描的文件夹") {
            guard !roots.contains(where: { store.makeRelative($0) == store.makeRelative(path) }) else { return }
            store.addRootAndRefresh(path)
            roots.append(store.makeRelative(path))
        }
    }
}
