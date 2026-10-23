import Foundation

/// 一次工具调用。
///
/// 模型用固定标记块表达调用意图：
/// ```
/// <iagent-tool>
/// {"tool":"write_file","args":{"path":"notes/a.md","content":"hello"}}
/// </iagent-tool>
/// ```
struct ToolCall: Equatable {
    /// 工具名
    var name: String
    /// 参数表
    var args: [String: String]
    /// 原始 JSON 文本（写日志用）
    var rawJSON: String

    init(name: String, args: [String: String] = [:], rawJSON: String = "") {
        self.name = name
        self.args = args
        self.rawJSON = rawJSON
    }

    func string(_ key: String, default defaultValue: String = "") -> String {
        args[key] ?? defaultValue
    }

    func int(_ key: String) -> Int? {
        args[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = args[key]?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch raw {
        case "true", "1", "yes", "是": return true
        case "false", "0", "no", "否": return false
        default: return nil
        }
    }

    /// 给用户看的参数摘要
    var preview: String {
        args.map { "\($0.key)=\($0.value.prefix(120))" }.joined(separator: "\n")
    }
}

/// 工具调用解析器（纯逻辑，方便单测）。
enum ToolCallParser {
    static let openTag = "<iagent-tool>"
    static let closeTag = "</iagent-tool>"
    static let resultOpenTag = "<iagent-result>"
    static let resultCloseTag = "</iagent-result>"

    /// 从模型回复里解析出所有工具调用
    static func parse(_ text: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        var remainder = Substring(text)

        while let openRange = remainder.range(of: openTag) {
            let afterOpen = remainder[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: closeTag) else { break }
            let body = String(afterOpen[..<closeRange.lowerBound])
            if let call = parseBlock(body) {
                calls.append(call)
            }
            remainder = afterOpen[closeRange.upperBound...]
        }
        return calls
    }

    /// 解析一个工具块的内容
    static func parseBlock(_ body: String) -> ToolCall? {
        let cleaned = stripCodeFence(body.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.isEmpty else { return nil }

        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard let dict = object as? [String: Any] else { return nil }

        var name = ""
        if let raw = dict["tool"] as? String { name = raw }
        else if let raw = dict["name"] as? String { name = raw }
        else if let raw = dict["tool_name"] as? String { name = raw }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var args: [String: String] = [:]
        let reserved: Set<String> = ["tool", "name", "tool_name", "args", "arguments", "parameters"]

        if let nested = dict["args"] as? [String: Any] ?? dict["arguments"] as? [String: Any]
            ?? dict["parameters"] as? [String: Any] {
            for (key, value) in nested {
                args[key] = stringify(value)
            }
        }
        // 也允许把参数平铺在顶层
        for (key, value) in dict where !reserved.contains(key) {
            if args[key] == nil { args[key] = stringify(value) }
        }
        return ToolCall(name: name, args: args, rawJSON: cleaned)
    }

    /// 把 JSON 值转成字符串参数（数字/布尔保留可识别形态）
    static func stringify(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            if number.doubleValue == number.doubleValue.rounded(),
               abs(number.doubleValue) < 1e15 {
                return String(format: "%.0f", number.doubleValue)
            }
            return number.stringValue
        case is NSNull:
            return ""
        case let array as [Any]:
            return (try? JSONSerialization.data(withJSONObject: array, options: []))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        case let dict as [String: Any]:
            return (try? JSONSerialization.data(withJSONObject: dict, options: []))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        default:
            return String(describing: value)
        }
    }

    /// 去掉模型爱加的 ```json 围栏
    static func stripCodeFence(_ text: String) -> String {
        var result = text
        if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
            if let newline = result.firstIndex(of: "\n") {
                let firstLine = String(result[..<newline]).trimmingCharacters(in: .whitespaces)
                // 形如 ```json / ```tool_call / ``` 的语言标注
                if firstLine.isEmpty || firstLine.allSatisfy({ $0.isLetter || $0 == "_" || $0 == "-" }) {
                    result = String(result[result.index(after: newline)...])
                }
            }
        }
        while result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把工具结果包成回传给模型的文本
    static func wrapResult(tool: String, ok: Bool, summary: String, detail: String?) -> String {
        var payload: [String: Any] = ["tool": tool, "ok": ok, "summary": summary]
        if let detail, !detail.isEmpty { payload["detail"] = detail }
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: []))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "\(resultOpenTag)\n\(json)\n\(resultCloseTag)"
    }
}
