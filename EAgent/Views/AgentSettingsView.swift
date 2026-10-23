import SwiftUI

/// 设置页：凭证、模型、Agent 策略、工具说明。
struct AgentSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingLogin = false
    @State private var tokenInput = ""
    @State private var cookieInput = ""
    @State private var loginStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek 账号") {
                    HStack {
                        Label("access token", systemImage: store.tokenPresent ? "checkmark.seal.fill" : "xmark.seal")
                            .foregroundStyle(store.tokenPresent ? .green : .orange)
                        Spacer()
                        Text(store.tokenPresent ? "已保存" : "未设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("session cookie", systemImage: store.cookiePresent ? "checkmark.seal.fill" : "xmark.seal")
                            .foregroundStyle(store.cookiePresent ? .green : .orange)
                        Spacer()
                        Text(store.cookiePresent ? "已保存" : "未设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingLogin = true
                    } label: {
                        Label("登录 DeepSeek 网页版并自动抓取", systemImage: "safari")
                    }

                    TextField("手动粘贴 access token", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 token") {
                        store.saveToken(tokenInput)
                        tokenInput = ""
                    }

                    TextField("手动粘贴 cookie（可选）", text: $cookieInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 cookie") {
                        store.saveCookie(cookieInput)
                        cookieInput = ""
                    }
                }

                Section("模型") {
                    Picker("模型", selection: $store.settings.model) {
                        Text("deepseek-chat（默认）").tag("deepseek-chat")
                        Text("deepseek-reasoner（深度思考）").tag("deepseek-reasoner")
                        Text("deepseek-coder").tag("deepseek-coder")
                    }
                    Toggle("深度思考", isOn: $store.settings.thinkingEnabled)
                    Toggle("联网搜索", isOn: $store.settings.searchEnabled)
                    Toggle("用官方端点建立会话", isOn: $store.settings.useServerSession)
                    HStack {
                        Text("随机延迟")
                        Slider(value: Binding(
                            get: { Double(store.settings.extraDelayMinSeconds) },
                            set: { store.settings.extraDelayMinSeconds = Int($0) }
                        ), in: 0...30, step: 1)
                        Text("\(store.settings.extraDelayMinSeconds)–\(store.settings.extraDelayMaxSeconds)s")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Agent 策略") {
                    Toggle("只读工具自动执行", isOn: $store.settings.autoApproveReadOnly)
                    Stepper("最多连续工具轮数：\(store.settings.maxToolSteps)",
                            value: $store.settings.maxToolSteps, in: 1...30)
                    TextField("工作区目录名", text: $store.settings.workspaceFolder)
                    Text("工作区路径：Documents/\(store.settings.workspaceFolder)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("额外提示词") {
                    TextEditor(text: $store.settings.agentExtraPrompt)
                        .frame(minHeight: 120)
                    Text("会追加到系统提示词末尾，比如「回答一律用中文」「先给方案再动手」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("可用工具") {
                    ForEach(ToolCatalog.specs, id: \.name) { spec in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(spec.name).font(.subheadline.monospaced())
                                Spacer()
                                Text(spec.risk.needsApproval ? "需确认" : "只读")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(spec.risk.needsApproval ? Color.orange.opacity(0.2) : Color.green.opacity(0.2),
                                                in: Capsule())
                            }
                            Text(spec.displaySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关于") {
                    Text("iAgent 是 Windows 版 EAgent 的 iOS 移植思路：同样用 DeepSeek 网页版（0 token），但把「操控电脑」换成「操控这台 iPhone」。iOS 沙盒不允许执行任意脚本，所以工具都是系统公开能力。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingLogin) {
                NavigationStack {
                    LoginWebView(
                        onToken: { token in
                            store.saveToken(token)
                            store.append(.ok, "已保存 access token")
                        },
                        onCookie: { cookie in
                            store.saveCookie(cookie)
                        },
                        onStatus: { status in
                            loginStatus = status
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("登录 DeepSeek")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showingLogin = false }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Text(loginStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.bar)
                    }
                }
            }
        }
    }
}
