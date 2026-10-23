import Foundation
import SwiftUI

/// 日志行
struct LogLine: Identifiable, Equatable {
    enum Level: String {
        case info = "信息"
        case ok = "成功"
        case warn = "警告"
        case error = "错误"
    }

    let id = UUID()
    let level: Level
    let text: String
    let date = Date()
}

/// 全局状态：设置、凭证、日志。
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if oldValue != settings { settings.save() }
        }
    }

    @Published private(set) var log: [LogLine] = []
    @Published private(set) var tokenPresent = false
    @Published private(set) var cookiePresent = false
    @Published var statusMessage: String?

    init() {
        settings = AppSettings.load()
        refreshCredentialState()
    }

    // MARK: - 凭证

    func refreshCredentialState() {
        tokenPresent = !KeychainStore.read(.accessToken).isEmpty
        cookiePresent = !KeychainStore.read(.sessionCookie).isEmpty
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(.accessToken)
        } else {
            KeychainStore.save(trimmed, for: .accessToken)
        }
        refreshCredentialState()
        append(.ok, trimmed.isEmpty ? "已清除 access token" : "已保存 access token")
    }

    func saveCookie(_ cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(.sessionCookie)
        } else {
            KeychainStore.save(trimmed, for: .sessionCookie)
        }
        refreshCredentialState()
        append(.ok, trimmed.isEmpty ? "已清除 session cookie" : "已保存 session cookie")
    }

    func accessToken() -> String { KeychainStore.read(.accessToken) }
    func sessionCookie() -> String { KeychainStore.read(.sessionCookie) }

    // MARK: - 日志

    func append(_ level: LogLine.Level, _ text: String) {
        let line = LogLine(level: level, text: text)
        DispatchQueue.main.async {
            self.log.insert(line, at: 0)
            if self.log.count > 400 {
                self.log.removeLast(self.log.count - 400)
            }
        }
    }

    func clearLog() {
        log.removeAll()
    }
}
