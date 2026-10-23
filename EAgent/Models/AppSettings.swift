import Foundation

/// App 的全部可配置项，存在 UserDefaults 里。
/// token 不在这里 —— 它单独放 Keychain（见 KeychainStore）。
struct AppSettings: Codable, Equatable {
    /// 上游模型名（DeepSeek 网页端的 model id）
    var model: String = "deepseek-chat"
    /// 是否让 DeepSeek 开启深度思考（R1 风格）
    var thinkingEnabled: Bool = false
    /// 是否让 DeepSeek 联网搜索
    var searchEnabled: Bool = false
    /// 用官方 /chat_session/create 建立真实网页端会话（而非本地随机 UUID）
    var useServerSession: Bool = true
    /// 追加到系统提示词里的自定义要求
    var agentExtraPrompt: String = ""
    /// 只读工具是否自动执行（写文件等改动设备的工具始终要确认）
    var autoApproveReadOnly: Bool = true
    /// 一轮对话最多连续调用多少轮工具
    var maxToolSteps: Int = 8
    /// 工作区目录名（在「文件」App 的 Documents/AgentWorkspace 里）
    var workspaceFolder: String = Workspace.defaultFolderName
    /// 每次发消息前的随机延迟下限（秒），用于降低被风控盯上的概率
    var extraDelayMinSeconds: Int = 0
    /// 随机延迟上限（秒）
    var extraDelayMaxSeconds: Int = 3
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
    /// 上游 base url，出问题时可切
    var baseURL: String = "https://chat.deepseek.com"
    /// 上游客户端版本头
    var clientVersion: String = "2.7.0"
    /// 设备型号（网页端要求带 x-device-model）
    var deviceModel: String = "iPhone"
    /// 客户端平台
    var clientPlatform: String = "web"
    /// 客户端 bundle id（网页端自己用的是 com.deepseek.chat）
    var clientBundleID: String = "com.deepseek.chat"
    /// 语言
    var clientLocale: String = "zh-CN"
    /// 时区偏移秒数
    var timezoneOffsetSeconds: Int = 28800

    private static let storageKey = "eagent.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        if value.maxTokens <= 0 { value.maxTokens = 4096 }
        if value.temperature < 0 { value.temperature = 0 }
        if value.temperature > 2 { value.temperature = 2 }
        if value.maxToolSteps < 1 { value.maxToolSteps = 8 }
        if value.maxToolSteps > 30 { value.maxToolSteps = 30 }
        if value.workspaceFolder.trimmingCharacters(in: .whitespaces).isEmpty {
            value.workspaceFolder = Workspace.defaultFolderName
        }
        if value.extraDelayMinSeconds < 0 { value.extraDelayMinSeconds = 0 }
        if value.extraDelayMaxSeconds < value.extraDelayMinSeconds {
            value.extraDelayMaxSeconds = value.extraDelayMinSeconds
        }
        // 旧版占位客户端版本迁移到当前官方 Web 版本。
        if value.clientVersion == "20250101.99999" { value.clientVersion = "2.7.0" }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// 稳定的设备 ID：网页端接口通常要求 x-device-id，重启 App 也要保持一致
    static var deviceID: String {
        let key = "eagent.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static func resetDeviceID() {
        UserDefaults.standard.set(UUID().uuidString, forKey: "eagent.deviceID")
    }
}
