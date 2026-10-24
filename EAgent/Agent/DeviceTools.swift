import Foundation
import UIKit
import AVFoundation
import CoreLocation
import UserNotifications
import Speech

/// 设备能力类工具：剪贴板、截图、朗读、定位、通知、设备信息、打开链接、快捷指令。
@MainActor
enum DeviceTools {

    // MARK: - 剪贴板

    static func readClipboard() async -> ToolResult {
        let text = UIPasteboard.general.string ?? ""
        if text.isEmpty {
            return ToolResult(ok: true, summary: "剪贴板是空的。")
        }
        return ToolResult(ok: true,
                          summary: "剪贴板内容（\(text.count) 字符）：",
                          detail: String(text.prefix(4_000)))
    }

    static func writeClipboard(text: String) async -> ToolResult {
        guard !text.isEmpty else { return .failure("clipboard_write 的 text 是空的。") }
        UIPasteboard.general.string = text
        return ToolResult(ok: true, summary: "已把 \(text.count) 个字符写入剪贴板。")
    }

    // MARK: - 截图

    static func screenshot(note: String) async -> ToolResult {
        guard let window = keyWindow() else {
            return .failure("找不到前台窗口，无法截图。")
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            return .failure("截图编码失败。")
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = "screenshots/shot-\(stamp).jpg"
        let workspace = Workspace()
        do {
            try workspace.writeFile(path, content: "")
            guard let url = workspace.resolve(path) else {
                return .failure("截图保存路径无效。")
            }
            try data.write(to: url, options: .atomic)
        } catch {
            return .failure("保存截图失败：\(error.localizedDescription)")
        }
        let extra = note.isEmpty ? "" : "（说明：\(note)）"
        return ToolResult(ok: true,
                          summary: "已截图并保存到工作区 \(path)\(extra)，尺寸 \(Int(image.size.width))×\(Int(image.size.height))。",
                          detail: path)
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first
    }

    // MARK: - 朗读

    static func speak(text: String) async -> ToolResult {
        guard !text.isEmpty else { return .failure("speak 的 text 是空的。") }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        SpeechCenter.shared.speak(utterance, with: synthesizer)
        return ToolResult(ok: true, summary: "已开始朗读（\(text.count) 字符）。")
    }

    // MARK: - 定位

    static func location() async -> ToolResult {
        let provider = LocationProvider()
        let result = await provider.request()
        switch result {
        case .success(let location):
            return ToolResult(ok: true,
                              summary: "当前位置：\(String(format: "%.5f", location.coordinate.latitude)), \(String(format: "%.5f", location.coordinate.longitude))，精度 ±\(Int(location.horizontalAccuracy)) 米。",
                              detail: "时间：\(ISO8601DateFormatter().string(from: location.timestamp))")
        case .failure(let message):
            return .failure(message)
        }
    }

    // MARK: - 通知

    static func notify(title: String, body: String) async -> ToolResult {
        let center = UNUserNotificationCenter.current()
        let granted = await requestNotificationPermission(center: center)
        guard granted else {
            return .failure("没有拿到通知权限，用户需要在系统设置里允许 iAgent 发送通知。")
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "iAgent" : title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        do {
            try await center.add(request)
            return ToolResult(ok: true, summary: "已发送通知「\(content.title)」。")
        } catch {
            return .failure("发送通知失败：\(error.localizedDescription)")
        }
    }

    private static func requestNotificationPermission(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    // MARK: - 设备信息

    static func deviceInfo() -> ToolResult {
        let device = UIDevice.current
        var lines: [String] = []
        lines.append("设备型号：\(device.model)")
        lines.append("系统：\(device.systemName) \(device.systemVersion)")
        lines.append("设备名：\(device.name)")
        lines.append("语言/区域：\(Locale.preferredLanguages.first ?? "未知") / \(Locale.current.region?.identifier ?? "-")")
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        if let free {
            lines.append("可用空间：\(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file))")
        }
        let workspace = Workspace()
        let stats = workspace.statistics()
        lines.append("工作区：\(stats.files) 个文件 / \(ByteCountFormatter.string(fromByteCount: Int64(stats.bytes), countStyle: .file))")
        return ToolResult(ok: true, summary: "设备信息：", detail: lines.joined(separator: "\n"))
    }

    // MARK: - 打开链接

    static func openURL(urlString: String) async -> ToolResult {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            return .failure("链接格式不对：\(urlString)")
        }
        await UIApplication.shared.open(url)
        return ToolResult(ok: true, summary: "已打开 \(url.absoluteString)。")
    }

    // MARK: - 快捷指令

    static func runShortcut(name: String) async -> ToolResult {
        guard !name.isEmpty else { return .failure("run_shortcut 需要 name 参数。") }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else {
            return .failure("无法构造快捷指令链接。")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? ToolResult(ok: true, summary: "已唤起快捷指令「\(name)」。")
            : .failure("没能打开快捷指令「\(name)」，请确认 App 里装了同名快捷指令。")
    }
}

/// 保持朗读用的 synthesizer 不被立刻释放
@MainActor
final class SpeechCenter {
    static let shared = SpeechCenter()
    private var synthesizer: AVSpeechSynthesizer?

    func speak(_ utterance: AVSpeechUtterance, with synthesizer: AVSpeechSynthesizer) {
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }
}

/// 一次性定位请求
@MainActor
final class LocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Outcome {
        case success(CLLocation)
        case failure(String)
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Outcome, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() async -> Outcome {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard CLLocationManager.locationServicesEnabled() else {
            return .failure("系统定位服务没有开启。")
        }
        manager.requestLocation()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finish(.failure("定位超时。"))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else {
            finish(.failure("没有拿到定位结果。"))
            return
        }
        finish(.success(last))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure("定位失败：\(error.localizedDescription)"))
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}
