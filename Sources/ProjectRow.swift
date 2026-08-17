import SwiftUI
import AppKit

// MARK: - 单行项目

struct ProjectRow: View {
    let project: Project
    let running: Bool
    let starting: Bool
    let stopping: Bool
    let onToggle: () -> Void
    let onOpenBrowser: () -> Void
    let onReveal: () -> Void
    let onOpenLog: () -> Void
    let onRemove: () -> Void
    let onUpdateCommand: (String) -> Void
    let onUpdateURL: (String) -> Void
    let onUpdateName: (String) -> Void
    let onUpdateOpenBrowser: (Bool) -> Void
    let onCopyCommand: () -> Void

    private enum EditField: Hashable { case command, url, name }

    @State private var editing: EditField?
    @State private var editText = ""
    @State private var showRemoveAlert = false
    @FocusState private var editFieldFocused: EditField?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if running {
                            Text("运行中")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                    Text(project.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if running {
                    Button(action: onOpenBrowser) {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.borderless)
                    .help("在浏览器打开")
                }

                Button(action: onToggle) {
                    if starting {
                        Text("启动中…")
                            .frame(minWidth: 60)
                    } else if stopping {
                        Text("停止中…")
                            .frame(minWidth: 60)
                    } else {
                        Text(running ? "停止" : "启动")
                            .frame(minWidth: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(starting ? .orange : (stopping ? .gray : (running ? .red : .accentColor)))
                .disabled(starting || stopping)
            }

            if let field = editing {
                HStack(spacing: 6) {
                    TextField(field == .name ? "名称" : (field == .command ? "启动命令" : "网页地址"), text: $editText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($editFieldFocused, equals: field)
                        .onAppear { editFieldFocused = field }
                        .onSubmit { saveEdit() }
                    Button("保存") { saveEdit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("取消") { editing = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if let command = project.command {
                        Text("启动命令：\(command)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let url = project.url {
                        Text("网页地址：\(url)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .contextMenu {
            Button("在 Finder 中显示", action: onReveal)
            if running {
                Button("打开日志", action: onOpenLog)
                Button("在浏览器打开", action: onOpenBrowser)
            }
            Divider()
            Button("编辑名称…") {
                startEdit(.name, project.name)
            }
            Button("编辑启动命令…") {
                startEdit(.command, project.command ?? "")
            }
            Button("复制启动命令", action: onCopyCommand)
            Button("编辑网页地址…") {
                startEdit(.url, project.url ?? "")
            }
            Button(project.openBrowser ? "✓ 自动打开浏览器" : "自动打开浏览器") {
                onUpdateOpenBrowser(!project.openBrowser)
            }
            Divider()
            Button("从列表中移除", role: .destructive) {
                showRemoveAlert = true
            }
        }
        .alert("移除项目", isPresented: $showRemoveAlert) {
            Button("取消", role: .cancel) { }
            Button("移除", role: .destructive, action: onRemove)
        } message: {
            Text("「\(project.name)」将不再显示在列表中，也不参与自动扫描。\n（可在配置文件中重新启用）")
        }
    }

    private func startEdit(_ field: EditField, _ initial: String) {
        editing = field
        editText = initial
    }

    private func saveEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if editing == .name {
            onUpdateName(trimmed)
        } else if editing == .command {
            onUpdateCommand(trimmed)
        } else if editing == .url {
            onUpdateURL(trimmed)
        }
        editing = nil
    }

    private var statusColor: Color {
        running ? .green : .gray
    }
}

