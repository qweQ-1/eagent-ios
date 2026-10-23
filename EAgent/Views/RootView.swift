import SwiftUI

/// 主界面：四个标签页
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: AgentEngine

    var body: some View {
        TabView {
            AgentChatView()
                .tabItem { Label("对话", systemImage: "bubble.left.and.text.bubble.right") }

            WorkspaceView()
                .tabItem { Label("工作区", systemImage: "folder") }

            AgentSettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }

            LogView()
                .tabItem { Label("日志", systemImage: "list.bullet.rectangle") }
        }
        .tint(.accentColor)
    }
}

/// 日志页
struct LogView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if store.log.isEmpty {
                    ContentUnavailableView("还没有日志", systemImage: "doc.text.magnifyingglass",
                                           description: Text("运行过程中的提示会出现在这里。"))
                } else {
                    List(store.log) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(line.level.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: line.level))
                                Text(line.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(line.text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("日志")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") { store.clearLog() }
                }
            }
        }
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .ok: return .green
        case .warn: return .orange
        case .error: return .red
        }
    }
}
