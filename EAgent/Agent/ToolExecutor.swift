import Foundation

/// 一次工具执行的结果。
struct ToolResult: Equatable {
    var ok: Bool
    var summary: String
    var detail: String?

    init(ok: Bool, summary: String, detail: String? = nil) {
        self.ok = ok
        self.summary = summary
        self.detail = detail
    }

    static func failure(_ message: String, detail: String? = nil) -> ToolResult {
        ToolResult(ok: false, summary: message, detail: detail)
    }
}

/// 工具执行器：按名字分发到具体实现，并在需要时向用户请求确认。
///
/// @MainActor：这个类要触发 UIKit 呈现（分享、授权弹窗），所以固定在主线程。
@MainActor
final class ToolExecutor {

    var workspace: Workspace
    /// 只读工具是否自动执行
    var autoApproveReadOnly: Bool
    /// 需要确认时调用它（由 UI 层提供，会挂起等待用户点「允许 / 拒绝」）
    var approvalHandler: (@MainActor (ToolCall) async -> Bool)?
    /// 呈现系统分享面板
    var sharePresenter: (@MainActor (String, String?) async -> Bool)?

    init(workspace: Workspace, autoApproveReadOnly: Bool = true) {
        self.workspace = workspace
        self.autoApproveReadOnly = autoApproveReadOnly
    }

    /// 执行一个工具调用
    func execute(_ call: ToolCall) async -> ToolResult {
        guard let spec = ToolCatalog.spec(named: call.name) else {
            return .failure("没有名为「\(call.name)」的工具。", detail: "可用工具：" + ToolCatalog.specs.map(\.name).joined(separator: ", "))
        }

        if spec.risk.needsApproval || !autoApproveReadOnly {
            let approved = await requestApproval(call, spec: spec)
            if !approved {
                return .failure("用户拒绝了执行「\(spec.displaySummary)」。")
            }
        }

        do {
            return try await run(call)
        } catch let error as ToolError {
            return .failure(error.message)
        } catch {
            return .failure("执行失败：\(error.localizedDescription)")
        }
    }

    private func requestApproval(_ call: ToolCall, spec: ToolSpec) async -> Bool {
        guard let handler = approvalHandler else { return false }
        return await handler(call)
    }

    // MARK: - 分发

    private func run(_ call: ToolCall) async throws -> ToolResult {
        switch call.name {
        case "list_files":
            return try await FileTools.list(workspace: workspace, call: call)
        case "read_file":
            return try await FileTools.read(workspace: workspace, call: call)
        case "write_file":
            return try await FileTools.write(workspace: workspace, call: call)
        case "delete_file":
            return try await FileTools.delete(workspace: workspace, call: call)
        case "move_file":
            return try await FileTools.move(workspace: workspace, call: call)
        case "search_files":
            return try await FileTools.search(workspace: workspace, call: call)

        case "clipboard_read":
            return await DeviceTools.readClipboard()
        case "clipboard_write":
            return await DeviceTools.writeClipboard(text: call.string("text"))
        case "screenshot":
            return await DeviceTools.screenshot(note: call.string("note"))
        case "speak":
            return await DeviceTools.speak(text: call.string("text"))
        case "location":
            return await DeviceTools.location()
        case "notification":
            return await DeviceTools.notify(title: call.string("title"), body: call.string("body"))
        case "device_info":
            return DeviceTools.deviceInfo()
        case "open_url":
            return await DeviceTools.openURL(urlString: call.string("url"))
        case "run_shortcut":
            return await DeviceTools.runShortcut(name: call.string("name"))
        case "share":
            let presenter = sharePresenter
            guard let presenter else {
                return .failure("当前没有可用的分享面板。")
            }
            return await presenter(call.string("text"), call.string("path").isEmpty ? nil : call.string("path"))

        case "http_get":
            return try await NetworkTools.get(call: call)
        case "http_post":
            return try await NetworkTools.post(call: call)

        case "save_to_photos":
            return await MediaTools.saveToPhotos(workspace: workspace, call: call)
        case "calendar_add":
            return try await CalendarTools.addEvent(call: call)
        case "reminder_add":
            return try await CalendarTools.addReminder(call: call)

        default:
            throw ToolError("没有名为「\(call.name)」的工具。")
        }
    }
}

/// 工具执行过程中可以抛出的、带人话的错误。
struct ToolError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}
