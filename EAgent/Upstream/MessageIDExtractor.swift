import Foundation

/// 从上游 SSE 事件里提取本轮回复的 message_id。
///
/// 网页端一次只收一条 prompt，历史靠 chat_session_id + parent_message_id 串起来，
/// 所以下一轮要把这一轮返回的 message_id 当作 parent_message_id。
enum MessageIDExtractor {
    static func messageID(in event: SSEEvent) -> String? {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return findMessageID(in: json)
    }

    static func findMessageID(in json: Any) -> String? {
        if let dict = json as? [String: Any] {
            if let value = dict["message_id"] as? String, !value.isEmpty { return value }
            for key in ["biz_data", "data", "message"] {
                if let nested = dict[key] {
                    if let found = findMessageID(in: nested) { return found }
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let found = findMessageID(in: item) { return found }
            }
        }
        return nil
    }
}
