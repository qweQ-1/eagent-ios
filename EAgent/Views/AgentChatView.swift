import SwiftUI

/// 聊天页：Agent 的主界面。
struct AgentChatView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: AgentEngine
    @EnvironmentObject private var shareBroker: ShareBroker

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                Divider()
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("iAgent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        engine.reset()
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    .accessibilityLabel("新对话")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if engine.status.isBusy {
                        Button {
                            engine.stop()
                        } label: {
                            Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                        }
                        .accessibilityLabel("停止")
                    }
                }
            }
            .sheet(item: Binding(
                get: { engine.pendingApproval },
                set: { value in
                    if value == nil, let pending = engine.pendingApproval {
                        engine.resolveApproval(id: pending.id, approved: false)
                    }
                }
            )) { request in
                ApprovalSheet(request: request) { approved in
                    engine.resolveApproval(id: request.id, approved: approved)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $shareBroker.payload) { payload in
                ActivityShareView(items: shareItems(for: payload)) { completed in
                    shareBroker.finish(completed)
                }
            }
            .onAppear {
                engine.shareHandler = { [weak shareBroker] text, path in
                    guard let shareBroker else { return false }
                    let url = path.flatMap { Workspace().resolve($0) }
                    return await shareBroker.present(text: text, fileURL: url)
                }
            }
        }
    }

    // MARK: - 状态条

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !store.tokenPresent {
                Label("未登录", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("对话 \(engine.turnCount) · 工具 \(engine.toolCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusColor: Color {
        switch engine.status {
        case .idle: return .secondary
        case .failed: return .red
        case .waitingReply: return .blue
        case .waitingApproval: return .orange
        case .runningTool: return .purple
        }
    }

    private var statusText: String {
        switch engine.status {
        case .idle: return "待命"
        case .waitingReply: return "DeepSeek 正在思考…"
        case .waitingApproval(let request): return "等待你确认：\(request.spec.displaySummary)"
        case .runningTool(let name): return "正在执行：\(name)"
        case .failed(let message): return "出错：\(message)"
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if engine.messages.isEmpty {
                        welcomeCard
                    }
                    ForEach(engine.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: engine.messages.count) { _, _ in
                if let last = engine.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iAgent · 让 DeepSeek 动手操作这台 iPhone")
                .font(.headline)
            Text("""
            你可以直接说：
            · 「在 notes 里写一份今天的会议纪要」
            · 「列出工作区里有哪些文件」
            · 「把剪贴板内容存成 txt」
            · 「截个屏看看现在是什么界面」
            · 「添加一个一小时后的提醒事项」
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("改设备的动作会先弹出确认框，你可以随时拒绝。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 输入区

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("让 DeepSeek 帮你做点什么…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .focused($inputFocused)

            Button {
                send()
            } label: {
                Image(systemName: engine.status.isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend && !engine.status.isBusy)
            .accessibilityLabel(engine.status.isBusy ? "停止" : "发送")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engine.status.isBusy
    }

    private func send() {
        if engine.status.isBusy {
            engine.stop()
            return
        }
        let text = input
        input = ""
        inputFocused = false
        engine.send(text, settings: store.settings)
    }

    private func shareItems(for payload: ShareBroker.Payload) -> [Any] {
        var items: [Any] = []
        if !payload.text.isEmpty { items.append(payload.text) }
        if let url = payload.fileURL { items.append(url) }
        if items.isEmpty { items.append("iAgent") }
        return items
    }
}

/// 一条消息的气泡
struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            switch message.role {
            case .user:
                bubble {
                    Text(message.text).font(.body)
                }
                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))

            case .assistant:
                VStack(alignment: .leading, spacing: 6) {
                    if !message.thinking.isEmpty {
                        DisclosureGroup("深度思考") {
                            Text(message.thinking)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                    if !message.text.isEmpty {
                        bubble {
                            Text(message.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .tool:
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(message.toolName)
                    } icon: {
                        Image(systemName: message.toolOK == false ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(message.toolOK == false ? .red : .green)
                    }
                    .font(.caption.weight(.semibold))

                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            case .system:
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private func bubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

/// 工具执行确认弹窗
struct ApprovalSheet: View {
    let request: ToolApprovalRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(request.spec.displaySummary)
                        .font(.headline)
                    Text("DeepSeek 想执行这个动作，你确认一下。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("参数") {
                    if request.call.args.isEmpty {
                        Text("无参数").foregroundStyle(.secondary)
                    } else {
                        ForEach(request.call.args.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(request.call.args[key] ?? "")
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Section {
                    Text("工作区里的改动随时可以在「工作区」标签里查看或撤销。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认执行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("拒绝", role: .destructive) { onDecision(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("允许") { onDecision(true) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
