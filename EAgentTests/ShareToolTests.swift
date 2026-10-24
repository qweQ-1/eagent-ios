import XCTest
@testable import EAgent

/// 分享工具的单元测试：不依赖真实 UI，只验证 ToolExecutor 与 AgentEngine 的接线。
@MainActor
final class ShareToolTests: XCTestCase {

    private func makeSettings(folder: String) -> AppSettings {
        var settings = AppSettings()
        settings.autoApproveReadOnly = true
        settings.extraDelayMinSeconds = 0
        settings.extraDelayMaxSeconds = 0
        settings.maxToolSteps = 5
        settings.workspaceFolder = folder
        return settings
    }

    /// share 属于 mutating 工具，测试里统一先放行审批。
    private func makeExecutor(folder: String) -> ToolExecutor {
        let executor = ToolExecutor(workspace: Workspace(folderName: folder), autoApproveReadOnly: true)
        executor.approvalHandler = { _ in true }
        return executor
    }

    /// 没有注入分享面板时，工具要明确报错，而不是崩溃。
    func testShareWithoutPresenterFails() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = makeExecutor(folder: folder)

        let result = await executor.execute(ToolCall(name: "share", args: ["text": "你好"]))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.summary.contains("没有可用的分享面板"))

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    /// 注入分享面板后，文字要原样传过去，路径要按工作区解析成真实 URL。
    func testSharePassesTextAndPathToPresenter() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = makeExecutor(folder: folder)
        let workspace = Workspace(folderName: folder)
        try workspace.writeFile("notes/a.txt", content: "内容")

        var receivedText: String?
        var receivedURL: URL?
        executor.sharePresenter = { text, url in
            receivedText = text
            receivedURL = url
            return true
        }

        let result = await executor.execute(
            ToolCall(name: "share", args: ["text": "分享这段", "path": "notes/a.txt"])
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(receivedText, "分享这段")
        XCTAssertEqual(receivedURL?.lastPathComponent, "a.txt")
        XCTAssertTrue(receivedURL?.path.hasPrefix(workspace.root.path) == true)

        try? FileManager.default.removeItem(at: workspace.root)
    }

    /// path 为空时传 nil，交给 UI 层只分享文字。
    func testShareWithoutPathPassesNil() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = makeExecutor(folder: folder)

        var receivedURL: URL? = URL(fileURLWithPath: "/not-nil")
        executor.sharePresenter = { _, url in
            receivedURL = url
            return true
        }

        let result = await executor.execute(ToolCall(name: "share", args: ["text": "只有文字"]))
        XCTAssertTrue(result.ok)
        XCTAssertNil(receivedURL)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    /// 越界路径要直接拒绝，不能把工作区外的文件分享出去。
    func testShareRejectsPathOutsideWorkspace() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = makeExecutor(folder: folder)
        var presented = false
        executor.sharePresenter = { _, _ in
            presented = true
            return true
        }

        let result = await executor.execute(
            ToolCall(name: "share", args: ["text": "越界", "path": "../../etc/passwd"])
        )
        XCTAssertFalse(result.ok)
        XCTAssertFalse(presented)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    /// 用户取消分享时，工具结果应该是失败，让模型知道没分享成功。
    func testShareCancelledReportsFailure() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = makeExecutor(folder: folder)
        executor.sharePresenter = { _, _ in false }

        let result = await executor.execute(ToolCall(name: "share", args: ["text": "取消"]))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.summary.contains("取消"))

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    /// 分享工具属于 mutating，未获批准时不该执行。
    func testShareRequiresApproval() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let executor = ToolExecutor(workspace: Workspace(folderName: folder), autoApproveReadOnly: true)
        executor.approvalHandler = { _ in false }
        var presented = false
        executor.sharePresenter = { _, _ in
            presented = true
            return true
        }

        let result = await executor.execute(ToolCall(name: "share", args: ["text": "不该分享"]))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.summary.contains("拒绝"))
        XCTAssertFalse(presented)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }

    /// 引擎这一层要把 shareHandler 接到执行器上，否则分享工具永远不可用。
    func testEngineWiresShareHandlerToExecutor() async throws {
        let folder = "AgentWorkspaceShareTests-\(UUID().uuidString)"
        let settings = makeSettings(folder: folder)
        let engine = AgentEngine(settings: settings)

        var called = false
        engine.shareHandler = { _, _ in
            called = true
            return true
        }

        // 通过引擎跑一次分享工具
        var upstreamCalls = 0
        engine.upstreamHandler = { _ in
            upstreamCalls += 1
            if upstreamCalls == 1 {
                return ("""
                <iagent-tool>
                {"tool":"share","args":{"text":"引擎分享"}}
                </iagent-tool>
                """, "", nil)
            }
            return ("分享好了。", "", nil)
        }

        engine.send("分享点东西", settings: settings)

        // 分享是 mutating 工具，引擎会先挂起等确认
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && engine.pendingApproval == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let request = engine.pendingApproval else {
            return XCTFail("没有产生审批请求")
        }
        XCTAssertEqual(request.call.name, "share")
        engine.resolveApproval(id: request.id, approved: true)

        while Date() < deadline && (engine.toolCount == 0 || engine.status.isBusy) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(called)
        let toolMessages = engine.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.first?.toolOK, true)

        try? FileManager.default.removeItem(at: Workspace(folderName: folder).root)
    }
}
