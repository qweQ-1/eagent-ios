import Foundation

/// 文件类工具：列目录、读写、删除、移动、搜索。
///
/// 文件 IO 放到后台线程，避免卡住主线程。
enum FileTools {

    static func list(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let path = call.string("path")
        let entries = try await Task.detached { try workspace.listFiles(path) }.value
        guard !entries.isEmpty else {
            return ToolResult(ok: true, summary: "目录「\(path.isEmpty ? "." : path)」是空的。")
        }
        var lines: [String] = []
        for entry in entries {
            if entry.isDirectory {
                lines.append("📁 \(entry.path)/")
            } else {
                lines.append("📄 \(entry.path)  (\(entry.size) 字节)")
            }
        }
        return ToolResult(ok: true,
                          summary: "共 \(entries.count) 项。",
                          detail: lines.joined(separator: "\n"))
    }

    static func read(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let path = call.string("path")
        guard !path.isEmpty else { throw ToolError("read_file 需要 path 参数。") }
        let maxBytes = call.int("max_bytes") ?? 200_000
        let text = try await Task.detached { try workspace.readFile(path, maxBytes: maxBytes) }.value
        return ToolResult(ok: true,
                          summary: "已读取 \(path)（\(text.count) 字符）。",
                          detail: text)
    }

    static func write(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let path = call.string("path")
        guard !path.isEmpty else { throw ToolError("write_file 需要 path 参数。") }
        let content = call.string("content")
        let bytes = try await Task.detached { try workspace.writeFile(path, content: content) }.value
        return ToolResult(ok: true, summary: "已写入 \(path)（\(bytes) 字节）。")
    }

    static func delete(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let path = call.string("path")
        guard !path.isEmpty else { throw ToolError("delete_file 需要 path 参数。") }
        try await Task.detached { try workspace.deleteFile(path) }.value
        return ToolResult(ok: true, summary: "已删除 \(path)。")
    }

    static func move(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let from = call.string("from")
        let to = call.string("to")
        guard !from.isEmpty, !to.isEmpty else {
            throw ToolError("move_file 需要 from 和 to 两个参数。")
        }
        let newPath = try await Task.detached { try workspace.moveFile(from: from, to: to) }.value
        return ToolResult(ok: true, summary: "已把 \(from) 移到 \(newPath)。")
    }

    static func search(workspace: Workspace, call: ToolCall) async throws -> ToolResult {
        let query = call.string("query")
        guard !query.isEmpty else { throw ToolError("search_files 需要 query 参数。") }
        let path = call.string("path")
        let hits = try await Task.detached { try workspace.searchFiles(query: query, in: path) }.value
        guard !hits.isEmpty else {
            return ToolResult(ok: true, summary: "没有找到包含「\(query)」的文件。")
        }
        let detail = hits.prefix(80).map { "\($0.path):\($0.line)  \($0.preview)" }.joined(separator: "\n")
        return ToolResult(ok: true,
                          summary: "找到 \(hits.count) 处匹配。",
                          detail: detail)
    }
}
