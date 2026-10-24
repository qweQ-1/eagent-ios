import Foundation
import UIKit
import Photos
import EventKit

/// 相册 / 日历 / 提醒事项类工具。
@MainActor
enum MediaTools {

    /// 保存到相册：给图片文件路径，或者给一段文字（渲染成图片再存）
    static func saveToPhotos(workspace: Workspace, call: ToolCall) async -> ToolResult {
        let path = call.string("path").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = call.string("text")

        var imageData: Data?
        var description = ""

        if !path.isEmpty {
            guard let url = workspace.resolve(path) else {
                return .failure("路径「\(path)」超出了工作区范围。")
            }
            guard let data = try? Data(contentsOf: url) else {
                return .failure("读不到文件：\(path)")
            }
            imageData = data
            description = path
        } else if !text.isEmpty {
            guard let data = renderTextImage(text: text) else {
                return .failure("文字渲染成图片失败。")
            }
            imageData = data
            description = "文字图片"
        } else {
            return .failure("save_to_photos 需要 path 或 text 其中之一。")
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .failure("没有拿到相册写入权限（状态 \(status.rawValue)）。")
        }

        guard let imageData else { return .failure("没有可保存的内容。") }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
            }
            return ToolResult(ok: true, summary: "已保存到相册（\(description)）。")
        } catch {
            return .failure("保存到相册失败：\(error.localizedDescription)")
        }
    }

    /// 把一段文字渲染成图片
    static func renderTextImage(text: String) -> Data? {
        let size = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 12
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: 80, y: 80, width: size.width - 160, height: size.height - 160)
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}

/// 日历与提醒事项。
@MainActor
enum CalendarTools {

    static func addEvent(call: ToolCall) async throws -> ToolResult {
        let title = call.string("title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ToolError("calendar_add 需要 title。") }
        let store = EKEventStore()
        let granted = await requestCalendarAccess(store: store)
        guard granted else {
            return .failure("没有拿到日历权限，用户需要在系统设置里允许 iAgent 访问日历。")
        }
        let startText = call.string("start").trimmingCharacters(in: .whitespacesAndNewlines)
        let start = ISO8601DateFormatter().date(from: startText) ?? Date()
        let minutes = call.int("duration_minutes") ?? 60
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        let notes = call.string("notes").trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { event.notes = notes }
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return ToolResult(ok: true,
                          summary: "已添加日历事件「\(title)」：\(start.formatted(date: .abbreviated, time: .shortened)) 起 \(minutes) 分钟。")
    }

    static func addReminder(call: ToolCall) async throws -> ToolResult {
        let title = call.string("title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ToolError("reminder_add 需要 title。") }
        let store = EKEventStore()
        let granted = await requestReminderAccess(store: store)
        guard granted else {
            return .failure("没有拿到提醒事项权限，用户需要在系统设置里允许 iAgent 访问提醒事项。")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        let notes = call.string("notes").trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { reminder.notes = notes }
        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
        return ToolResult(ok: true, summary: "已添加提醒事项「\(title)」。")
    }

    private static func requestCalendarAccess(store: EKEventStore) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        // 写入日历只要 fullAccess 或 writeOnly 即可
        if status == .fullAccess || status == .writeOnly { return true }
        if status == .denied || status == .restricted { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private static func requestReminderAccess(store: EKEventStore) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { return true }
        if status == .denied || status == .restricted { return false }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }
}
