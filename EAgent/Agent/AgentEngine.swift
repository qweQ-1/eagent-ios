import Foundation
import SwiftUI

/// 聊天里的一条消息。
struct AgentMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
        case tool
        case system
    }

    var id = UUID()
    var role: Role
    var text: String
    /// 深度思考内容
    var thinking: String = ""
    /// 工具消息对应的工具名
    var toolName: String = ""
    /// 工具消息是否成功
    var toolOK: Bool?

    static func user(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, text: text)
    }

    static func assistant(_ text: String) -> AgentMessage {
        AgentMessage(role: .assistant, text: text)
    }

    static func tool(name: String, ok: Bool, text: String) -> AgentMessage {
        AgentMessage(role: .tool, text: text, toolName: name, toolOK: ok)
    }
}

/// 待用户确认的一次工具调用。
final class ToolApprovalRequest: Identifiable {
    let id = UUID()
    let call: ToolCall
    let spec: ToolSpec
    fileprivate var continuation: CheckedContinuation<Bool, Never>?

    init(call: ToolCall, spec: ToolSpec) {
        self.call = call
        self.spec = spec
    }
}

/// iAgent 的主引擎：把 DeepSeek 网页端变成一个能动手的 Agent。
@MainActor
final class AgentEngine: ObservableObject {

    enum Status: Equatable {
        case idle
        case waitingReply
        case waitingApproval(ToolApprovalRequest)
        case runningTool(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .failed: return false
            default: return true
            }
        }
    }

    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var toolCount = 0
    @Published private(set) var turnCount = 0
    @Published var pendingApproval: ToolApprovalRequest?

    /// 上一次上游返回的 message_id，下一轮当 parent_message_id
    private var lastMessageID: String?
    /// 网页端会话 ID
    private var chatSessionID: String?
    private var currentTask: Task<Void, Never>?
    private let hifTokens = HIFTokenProvider()
    private var executor: ToolExecutor

    /// 依赖注入，方便测试
    var upstreamHandler: ((String) async throws -> (text: String, thinking: String, messageID: String?))?

    init(settings: AppSettings) {
        let workspace = Workspace(folderName: settings.workspaceFolder)
        workspace.ensureRootExists()
        executor = ToolExecutor(workspace: workspace,
                                autoApproveReadOnly: settings.autoApproveReadOnly)
        executor.approvalHandler = { [weak self] call in
            await self?.requestApproval(call) ?? false
        }
        executor.sharePresenter = { [weak self] text, path in
            guard let handler = self?.shareHandler else { return false }
            return await handler(text, path)
        }
    }

    // MARK: - 对外接口

    /// 发送一条用户消息并跑完整个 Agent 循环
    func send(_ text: String, settings: AppSettings) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !status.isBusy else { return }

        messages.append(.user(trimmed))
        turnCount += 1
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.run(userText: trimmed, settings: settings)
        }
    }

    /// 急停：中断当前循环
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        status = .idle
        messages.append(AgentMessage(role: .system, text: "已停止。"))
    }

    /// 开一段新对话
    func reset() {
        currentTask?.cancel()
        currentTask = nil
        messages.removeAll()
        toolCount = 0
        turnCount = 0
        lastMessageID = nil
        chatSessionID = nil
        status = .idle
        pendingApproval = nil
    }

    /// 用户对审批请求作答
    func resolveApproval(id: UUID, approved: Bool) {
        guard let request = pendingApproval, request.id == id else { return }
        pendingApproval = nil
        if case .waitingApproval(let current) = status, current.id == id {
            status = .idle
        }
        request.continuation?.resume(returning: approved)
    }

    // MARK: - 审批

    private func requestApproval(_ call: ToolCall) async -> Bool {
        guard let spec = ToolCatalog.spec(named: call.name) else { return false }
        let request = ToolApprovalRequest(call: call, spec: spec)
        return await withCheckedContinuation { continuation in
            request.continuation = continuation
            pendingApproval = request
            status = .waitingApproval(request)
        }
    }

    // MARK: - 主循环

    private func run(userText: String, settings: AppSettings) async {
        let workspace = Workspace(folderName: settings.workspaceFolder)
        executor.workspace = workspace
        executor.autoApproveReadOnly = settings.autoApproveReadOnly

        let systemPrompt = ToolCatalog.systemPrompt(
            workspacePath: workspace.root.path,
            extraPrompt: settings.agentExtraPrompt,
            autoApproveReadOnly: settings.autoApproveReadOnly,
            maxSteps: settings.maxToolSteps
        )

        var nextPrompt = userText
        var isFirstTurn = true
        let maxSteps = max(1, settings.maxToolSteps)

        for step in 0..<maxSteps {
            if Task.isCancelled { return }

            // 防封号的随机延迟
            if settings.extraDelayMinSeconds > 0 {
                let upper = max(settings.extraDelayMinSeconds, settings.extraDelayMaxSeconds)
                let delay = Int.random(in: settings.extraDelayMinSeconds...upper)
                status = .waitingReply
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                if Task.isCancelled { return }
            }

            status = .waitingReply
            let fullPrompt = isFirstTurn ? "\(systemPrompt)\n\n\(nextPrompt)" : nextPrompt
            isFirstTurn = false

            let reply: (text: String, thinking: String, messageID: String?)
            do {
                reply = try await sendUpstream(prompt: fullPrompt, settings: settings)
            } catch {
                status = .failed(error.localizedDescription)
                messages.append(.assistant("请求失败：\(error.localizedDescription)"))
                return
            }

            if let messageID = reply.messageID, !messageID.isEmpty {
                lastMessageID = messageID
            }

            let assistantText = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !assistantText.isEmpty || !reply.thinking.isEmpty {
                var message = AgentMessage.assistant(assistantText)
                message.thinking = reply.thinking
                messages.append(message)
            }

            let calls = ToolCallParser.parse(reply.text)
            guard !calls.isEmpty else {
                status = .idle
                return
            }

            var resultBlocks: [String] = []
            for call in calls {
                if Task.isCancelled { return }
                let spec = ToolCatalog.spec(named: call.name)
                status = .runningTool(spec?.displaySummary ?? call.name)
                let result = await executor.execute(call)
                toolCount += 1

                let display = result.detail.map { "\(result.summary)\n\($0)" } ?? result.summary
                messages.append(.tool(name: spec?.displaySummary ?? call.name,
                                      ok: result.ok,
                                      text: display))

                resultBlocks.append(ToolCallParser.wrapResult(tool: call.name,
                                                              ok: result.ok,
                                                              summary: result.summary,
                                                              detail: result.detail))
            }

            nextPrompt = """
            工具执行结果如下，请据此继续：
            \(resultBlocks.joined(separator: "\n"))
            """
            status = .waitingReply
        }

        status = .idle
        messages.append(AgentMessage(role: .system,
                                     text: "已连续调用 \(maxSteps) 轮工具，先停在这里。需要继续的话再说一声。"))
    }

    // MARK: - 上游

    private func sendUpstream(prompt: String,
                              settings: AppSettings) async throws -> (text: String, thinking: String, messageID: String?) {
        if let handler = upstreamHandler {
            return try await handler(prompt)
        }

        let client = makeClient(settings: settings)
        let guest = !client.isLoggedIn

        async let hifHeaders = hifTokens.headers(baseHeaders: client.clientHeaderFields)

        let challenge = try await client.fetchChallenge(guest: guest)
        let answer = try challenge.solve()
        let powHeader = client.powHeaderValue(challenge: challenge, answer: answer, guest: guest)
        let riskHeaders = await hifHeaders

        if chatSessionID == nil {
            if settings.useServerSession {
                chatSessionID = try? await client.createSession()
            }
            if chatSessionID == nil {
                chatSessionID = UUID().uuidString.lowercased()
            }
        }

        var options = DeepSeekWebClient.Options()
        options.modelType = DeepSeekWebClient.upstreamModelType(settings.model)
        options.thinkingEnabled = settings.thinkingEnabled
        options.searchEnabled = settings.searchEnabled
        options.temperature = settings.temperature
        options.maxTokens = settings.maxTokens

        let request = try client.makeCompletionRequest(prompt: prompt,
                                                       options: options,
                                                       chatSessionID: chatSessionID ?? "",
                                                       parentMessageID: lastMessageID,
                                                       powHeader: powHeader,
                                                       hifHeaders: riskHeaders)

        var text = ""
        var thinking = ""
        var messageID: String?

        for try await event in client.stream(request: request) {
            if Task.isCancelled { break }
            if let id = MessageIDExtractor.messageID(in: event) {
                messageID = id
            }
            for delta in UpstreamEventParser.interpret(event) {
                switch delta {
                case let .content(chunk):
                    text += chunk
                case let .thinking(chunk):
                    thinking += chunk
                default:
                    break
                }
            }
        }

        return (text, thinking, messageID)
    }

    private func makeClient(settings: AppSettings) -> DeepSeekWebClient {
        DeepSeekWebClient(
            baseURL: URL(string: settings.baseURL) ?? URL(string: "https://chat.deepseek.com")!,
            accessToken: KeychainStore.read(.accessToken),
            sessionCookie: KeychainStore.read(.sessionCookie),
            deviceID: AppSettings.deviceID,
            deviceModel: settings.deviceModel,
            clientVersion: settings.clientVersion,
            clientLocale: settings.clientLocale,
            clientPlatform: settings.clientPlatform,
            clientBundleID: settings.clientBundleID,
            timezoneOffsetSeconds: settings.timezoneOffsetSeconds
        )
    }
}
