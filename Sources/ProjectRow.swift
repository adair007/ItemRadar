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
    let onEdit: () -> Void
    let onUpdateOpenBrowser: (Bool) -> Void
    let onCopyCommand: () -> Void

    @State private var showRemoveAlert = false

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
            Button("编辑…", action: onEdit)
            Button("复制启动命令", action: onCopyCommand)
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

    private var statusColor: Color {
        running ? .green : .gray
    }
}
