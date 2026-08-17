import SwiftUI
import AppKit

// MARK: - 主面板

struct ContentView: View {
    @EnvironmentObject var store: ProjectStore
    var onReopenPopover: (() -> Void)? = nil
    var onManualRefresh: (() -> Void)? = nil
    var onEdit: ((Project) -> Void)? = nil
    var onCheckUpdate: (() -> Void)? = nil

    @State private var showAddProject = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 400)
        .sheet(isPresented: $showAddProject, onDismiss: { onReopenPopover?() }) {
            AddProjectView(
                onSave: { name, path, command, url, openBrowser in
                    store.addManualProject(name: name, path: path, command: command, url: url, openBrowser: openBrowser)
                    showAddProject = false
                },
                onCancel: { showAddProject = false }
            )
        }
        .sheet(isPresented: $showSettings, onDismiss: { onReopenPopover?() }) {
            SettingsView(onDismiss: { showSettings = false })
                .environmentObject(store)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .foregroundColor(.accentColor)
            Text("ItemRadar")
                .font(.headline)
            Spacer()
            Button {
                selectDirectory()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .quickHelp("从指定文件夹获取项目")
            Button {
                onManualRefresh?()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .quickHelp("刷新项目列表")
            Button {
                onCheckUpdate?()
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .buttonStyle(.borderless)
            .quickHelp("检查更新")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .quickHelp("设置扫描范围")
        }
        .padding(12)
    }

    // MARK: 列表

    @ViewBuilder
    private var list: some View {
        if let error = store.lastError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error)
                    .lineLimit(2)
                Spacer()
                Button {
                    store.dismissError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.white)
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85))
        }
        if store.projects.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("还没有发现可启动的项目")
                    .font(.callout)
                Text("把项目放到「下载 / 桌面 / 文档」，会自动出现在这里；\n找不到就点右上角「从指定文件夹获取」选择文件夹，或点下方「手动添加」。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
            .padding(24)
        } else {
            VStack(spacing: 0) {
                Text("拖动条目可调整顺序")
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                List {
                    ForEach(store.projects) { project in
                        ProjectRow(
                            project: project,
                            running: store.isRunning(project),
                            starting: store.isStarting(project),
                            stopping: store.isStopping(project),
                            onToggle: {
                                store.isRunning(project)
                                    ? store.stop(project)
                                    : store.start(project)
                            },
                            onOpenBrowser: { store.openBrowser(project) },
                            onReveal: { store.reveal(project) },
                            onOpenLog: { store.openLog(project) },
                            onRemove: { store.removeFromList(project) },
                            onEdit: { onEdit?(project) },
                            onUpdateOpenBrowser: { store.updateOpenBrowser(project, openBrowser: $0) },
                            onCopyCommand: { store.copyCommand(project) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(Color.clear)
                    }
                    .onMove { indices, newOffset in
                        store.moveProjects(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300, maxHeight: 560)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = store.statusMessage {
                HStack(spacing: 5) {
                    Image(systemName: store.statusIsWarning ? "exclamationmark.triangle" : "checkmark.circle")
                    Text(message)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundColor(store.statusIsWarning ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button {
                    showAddProject = true
                } label: {
                    Label("手动添加", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    /// 弹出系统文件夹选择器，把选中的目录加入扫描根目录。
    private func selectDirectory() {
        if let path = DirectoryPicker.pick(message: "选择要扫描的项目文件夹") {
            store.addRootAndRefresh(path)
            onReopenPopover?()
        }
    }
}

// MARK: - 即时 tooltip

extension View {
    /// 在鼠标移入时即时展示 tooltip，替代有系统显示延迟的 `.help(...)`。
    func quickHelp(_ text: String) -> some View {
        modifier(QuickHelpModifier(text: text))
    }
}

private struct QuickHelpModifier: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                if hovering {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                        .offset(y: 28)
                        .allowsHitTesting(false)
                }
            }
    }
}