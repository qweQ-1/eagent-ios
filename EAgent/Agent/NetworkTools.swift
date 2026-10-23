import Foundation

/// 网络类工具：抓取网页、发送请求。
enum NetworkTools {

    static func get(call: ToolCall) async throws -> ToolResult {
        let urlString = call.string("url").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw ToolError("http_get 的 url 不合法：\(urlString)")
        }
        let maxBytes = call.int("max_bytes") ?? 12_000

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        var status = 0
        if let http = response as? HTTPURLResponse {
            status = http.statusCode
        }
        let contentType = response.mimeType ?? "未知"
        let text = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        let truncated = data.count > maxBytes ? "（已截断，完整 \(data.count) 字节）" : ""
        return ToolResult(ok: (200..<400).contains(status),
                          summary: "GET \(url.absoluteString) → HTTP \(status)，\(contentType)，\(data.count) 字节\(truncated)",
                          detail: text)
    }

    static func post(call: ToolCall) async throws -> ToolResult {
        let urlString = call.string("url").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw ToolError("http_post 的 url 不合法：\(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let headersJSON = call.string("headers").trimmingCharacters(in: .whitespacesAndNewlines)
        if !headersJSON.isEmpty,
           let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let body = call.string("body")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        var status = 0
        if let http = response as? HTTPURLResponse {
            status = http.statusCode
        }
        let text = String(decoding: data.prefix(12_000), as: UTF8.self)
        return ToolResult(ok: (200..<400).contains(status),
                          summary: "POST \(url.absoluteString) → HTTP \(status)，响应 \(data.count) 字节",
                          detail: text)
    }
}
