import SwiftUI

/// 系统分享面板的协调器：把「分享」工具的调用桥到 UIActivityViewController。
@MainActor
final class ShareBroker: ObservableObject {
    struct Payload: Identifiable {
        let id = UUID()
        let text: String
        let fileURL: URL?
    }

    @Published var payload: Payload?

    private var continuation: CheckedContinuation<Bool, Never>?

    /// 弹出分享面板，等用户完成或取消
    func present(text: String, fileURL: URL?) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.payload = Payload(text: text, fileURL: fileURL)
        }
    }

    /// 分享结束
    func finish(_ completed: Bool) {
        payload = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: completed)
    }
}

/// UIActivityViewController 的 SwiftUI 包装
struct ActivityShareView: UIViewControllerRepresentable {
    var items: [Any]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
