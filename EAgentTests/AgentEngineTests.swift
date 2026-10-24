import XCTest
@testable import EAgent

@MainActor
final class AgentEngineTests: XCTestCase {

    private func makeSettings(folder: String) -> AppSettings {
        var settings = AppSettings()
        settings.autoApproveReadOnly = true
        settings.extraDelayMinSeconds = 0
        settings.extraDelayMaxSeconds = 0
        settings.maxToolSteps = 5
        settings.workspaceFolder = folder
        return settings
    }

    private func waitUntil(_ timeout: TimeInterval = 15,
                           _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("等待超时")
    }

    func testRunsReadOnlyToolAndFeedsResultBack() async throws {
        let folder = "AgentWorkspaceTests-\(UUID().uuidString)"
        let settings = makeSettings(folder: folder)
        let engine = AgentEngine(settings: settings)

        var upstreamCalls = 0
        engine.upstreamHandler = { _ in
            upstreamCalls += 1
            if upstreamCalls == 1 {
                return ("""
                我先列一下工作区。
                <iagent-tool>
                {"tool":"list_files","args":{}}
                </iagent-tool>
                """, "", nil)
            }
            return ("工作区现在是空的，我看完就这些。", "", nil)
        }

        engine.send("看看工作区", settings: settings)

        try await waitUntil { engine.toolCount == 1 && !engine.status.isBusy }

        XCTAssertEqual(upstreamCalls, 2)
        let toolMessages = engine.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)
        XCTAssertEqual(toolMessages.first?.toolOK, true)

        // 第二轮把工具结果回喂给了模型
        XCTAssertTrue(engine.messages.contains { $0.role == .assistant && $0.text.contains("工作区现在是空的") })

        // 清理测试工作区
        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    func testMutatingToolRequiresApproval() async throws {
        let folder = "AgentWorkspaceTests-\(UUID().uuidString)"
        var settings = makeSettings(folder: folder)
        settings.autoApproveReadOnly = false

        let engine = AgentEngine(settings: settings)
        var upstreamCalls = 0
        engine.upstreamHandler = { _ in
            upstreamCalls += 1
            if upstreamCalls == 1 {
                return ("""
                <iagent-tool>
                {"tool":"write_file","args":{"path":"hello.txt","content":"你好"}}
                </iagent-tool>
                """, "", nil)
            }
            return ("已经写好了。", "", nil)
        }

        engine.send("写个 hello.txt", settings: settings)

        // 引擎会挂起等待确认
        try await waitUntil { engine.pendingApproval != nil }
        guard let request = engine.pendingApproval else {
            return XCTFail("没有产生审批请求")
        }
        XCTAssertEqual(request.call.name, "write_file")
        XCTAssertEqual(request.spec.risk, .mutating)

        engine.resolveApproval(id: request.id, approved: true)

        try await waitUntil { engine.toolCount == 1 && !engine.status.isBusy }

        let workspace = Workspace(folderName: folder)
        let content = try workspace.readFile("hello.txt")
        XCTAssertEqual(content, "你好")

        try? FileManager.default.removeItem(at: workspace.root)
    }

    func testRejectedToolIsReportedBackToModel() async throws {
        let folder = "AgentWorkspaceTests-\(UUID().uuidString)"
        var settings = makeSettings(folder: folder)
        settings.autoApproveReadOnly = false

        let engine = AgentEngine(settings: settings)
        var secondPrompt = ""
        var upstreamCalls = 0
        engine.upstreamHandler = { prompt in
            upstreamCalls += 1
            if upstreamCalls == 1 {
                return ("""
                <iagent-tool>
                {"tool":"write_file","args":{"path":"x.txt","content":"y"}}
                </iagent-tool>
                """, "", nil)
            }
            secondPrompt = prompt
            return ("好的，我不写了。", "", nil)
        }

        engine.send("写个文件", settings: settings)
        try await waitUntil { engine.pendingApproval != nil }
        guard let request = engine.pendingApproval else {
            return XCTFail("没有产生审批请求")
        }
        engine.resolveApproval(id: request.id, approved: false)

        try await waitUntil { engine.toolCount == 1 && !engine.status.isBusy }

        XCTAssertTrue(secondPrompt.contains("用户拒绝") || secondPrompt.contains("\"ok\":false"))
        let toolMessages = engine.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.first?.toolOK, false)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    func testUnknownToolReturnsFailure() async throws {
        let folder = "AgentWorkspaceTests-\(UUID().uuidString)"
        let settings = makeSettings(folder: folder)
        let engine = AgentEngine(settings: settings)
        var upstreamCalls = 0
        engine.upstreamHandler = { _ in
            upstreamCalls += 1
            if upstreamCalls == 1 {
                return ("""
                <iagent-tool>
                {"tool":"launch_missiles","args":{}}
                </iagent-tool>
                """, "", nil)
            }
            return ("没有这个工具。", "", nil)
        }

        engine.send("来一发", settings: settings)
        try await waitUntil { engine.toolCount == 1 && !engine.status.isBusy }

        let toolMessages = engine.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.first?.toolOK, false)
        XCTAssertTrue(toolMessages.first?.text.contains("没有名为") ?? false)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    func testSystemPromptIsSentOnFirstTurn() async throws {
        let folder = "AgentWorkspaceTests-\(UUID().uuidString)"
        let settings = makeSettings(folder: folder)
        let engine = AgentEngine(settings: settings)

        var firstPrompt = ""
        engine.upstreamHandler = { prompt in
            firstPrompt = prompt
            return ("好的", "", nil)
        }

        engine.send("你好", settings: settings)
        // 等上游真的被调用过再断言，否则会读到还没填好的 prompt
        try await waitUntil { !firstPrompt.isEmpty && !engine.status.isBusy }

        XCTAssertTrue(firstPrompt.contains("<iagent-tool>"))
        XCTAssertTrue(firstPrompt.contains("list_files"))
        XCTAssertTrue(firstPrompt.contains("你好"))

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }
}
