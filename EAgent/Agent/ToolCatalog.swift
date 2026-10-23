import Foundation

/// 一个工具的元信息：名字、给模型看的用法、危险等级。
struct ToolSpec {
    enum Risk {
        /// 只读，不改任何东西
        case readonly
        /// 会写入/删除/对外发送，需要用户确认
        case mutating

        var needsApproval: Bool {
            self == .mutating
        }
    }

    var name: String
    /// 给模型看的参数说明
    var usage: String
    var risk: Risk

    /// 展示给用户的用途（一行）
    var displaySummary: String {
        switch name {
        case "list_files": return "列出工作区里的文件"
        case "read_file": return "读取工作区文件"
        case "write_file": return "写入工作区文件"
        case "delete_file": return "删除工作区文件"
        case "move_file": return "移动 / 重命名文件"
        case "search_files": return "在工作区里搜索关键字"
        case "clipboard_read": return "读取剪贴板"
        case "clipboard_write": return "写入剪贴板"
        case "screenshot": return "截取当前屏幕"
        case "http_get": return "下载网页 / 接口内容"
        case "http_post": return "向服务器发送数据"
        case "open_url": return "用 Safari 打开链接"
        case "share": return "调起系统分享"
        case "save_to_photos": return "保存到相册"
        case "speak": return "朗读一段文字"
        case "location": return "获取当前位置"
        case "calendar_add": return "添加日历事件"
        case "reminder_add": return "添加提醒事项"
        case "notification": return "发一条本地通知"
        case "run_shortcut": return "运行 Apple 快捷指令"
        case "device_info": return "读取设备信息"
        default: return name
        }
    }
}

/// 全部可用工具的清单，同时负责生成系统提示词。
enum ToolCatalog {
    static let specs: [ToolSpec] = [
        ToolSpec(name: "list_files",
                 usage: #"{"tool":"list_files","args":{"path":"子目录（可留空）"}}"#,
                 risk: .readonly),
        ToolSpec(name: "read_file",
                 usage: #"{"tool":"read_file","args":{"path":"相对路径"}}"#,
                 risk: .readonly),
        ToolSpec(name: "write_file",
                 usage: #"{"tool":"write_file","args":{"path":"相对路径","content":"文件内容"}}"#,
                 risk: .mutating),
        ToolSpec(name: "delete_file",
                 usage: #"{"tool":"delete_file","args":{"path":"相对路径"}}"#,
                 risk: .mutating),
        ToolSpec(name: "move_file",
                 usage: #"{"tool":"move_file","args":{"from":"旧路径","to":"新路径"}}"#,
                 risk: .mutating),
        ToolSpec(name: "search_files",
                 usage: #"{"tool":"search_files","args":{"query":"关键字","path":"限定目录（可留空）"}}"#,
                 risk: .readonly),
        ToolSpec(name: "clipboard_read",
                 usage: #"{"tool":"clipboard_read","args":{}}"#,
                 risk: .readonly),
        ToolSpec(name: "clipboard_write",
                 usage: #"{"tool":"clipboard_write","args":{"text":"要写入的文本"}}"#,
                 risk: .mutating),
        ToolSpec(name: "screenshot",
                 usage: #"{"tool":"screenshot","args":{"note":"给这张截图的说明（可留空）"}}"#,
                 risk: .readonly),
        ToolSpec(name: "http_get",
                 usage: #"{"tool":"http_get","args":{"url":"https://...","max_bytes":"12000（可留空）"}}"#,
                 risk: .readonly),
        ToolSpec(name: "http_post",
                 usage: #"{"tool":"http_post","args":{"url":"https://...","body":"请求体","headers":"JSON 字符串（可留空）"}}"#,
                 risk: .mutating),
        ToolSpec(name: "open_url",
                 usage: #"{"tool":"open_url","args":{"url":"https://..."}"#,
                 risk: .mutating),
        ToolSpec(name: "share",
                 usage: #"{"tool":"share","args":{"text":"要分享的文字（可留空）","path":"要分享的文件（可留空）"}}"#,
                 risk: .mutating),
        ToolSpec(name: "save_to_photos",
                 usage: #"{"tool":"save_to_photos","args":{"path":"工作区里的图片文件（可留空）","text":"要存成图片的文字（可留空）"}}"#,
                 risk: .mutating),
        ToolSpec(name: "speak",
                 usage: #"{"tool":"speak","args":{"text":"要朗读的文字"}}"#,
                 risk: .mutating),
        ToolSpec(name: "location",
                 usage: #"{"tool":"location","args":{}}"#,
                 risk: .readonly),
        ToolSpec(name: "calendar_add",
                 usage: #"{"tool":"calendar_add","args":{"title":"标题","start":"ISO8601 时间","duration_minutes":"60","notes":"备注（可留空）"}}"#,
                 risk: .mutating),
        ToolSpec(name: "reminder_add",
                 usage: #"{"tool":"reminder_add","args":{"title":"要提醒的事","notes":"备注（可留空）"}}"#,
                 risk: .mutating),
        ToolSpec(name: "notification",
                 usage: #"{"tool":"notification","args":{"title":"通知标题","body":"通知正文"}}"#,
                 risk: .mutating),
        ToolSpec(name: "run_shortcut",
                 usage: #"{"tool":"run_shortcut","args":{"name":"快捷指令名称"}}"#,
                 risk: .mutating),
        ToolSpec(name: "device_info",
                 usage: #"{"tool":"device_info","args":{}}"#,
                 risk: .readonly)
    ]

    static func spec(named name: String) -> ToolSpec? {
        specs.first { $0.name == name }
    }

    /// 工具目录文本，插进系统提示词里
    static func catalogText() -> String {
        specs.map { spec in
            let flag = spec.risk.needsApproval ? "【会改动设备，执行前需用户确认】" : "【只读】"
            return "- \(spec.name) \(flag)\n  用法：\(spec.usage)"
        }.joined(separator: "\n")
    }

    /// 组装系统提示词
    static func systemPrompt(workspacePath: String,
                             extraPrompt: String,
                             autoApproveReadOnly: Bool,
                             maxSteps: Int) -> String {
        let approvalNote = autoApproveReadOnly
            ? "只读工具会自动执行；会改动设备的工具（写文件、删除、联网发送、打开链接、分享、保存相册、朗读、添加日历提醒、发通知、运行快捷指令）必须先得到用户同意，用户拒绝时你会收到 ok=false 的结果。"
            : "所有工具在执行前都要用户确认；用户拒绝时你会收到 ok=false 的结果。"

        var prompt = """
        你是 iAgent —— 运行在用户 iPhone 上的智能助手。你和用户通过聊天协作，并且可以通过工具真正"动手"操作这台手机。

        # 你的能力边界（务必遵守）
        - 你只能操作这台 iPhone 的 App 沙盒内的工作区，以及下面列出的工具能力。
        - 你**不能**执行 shell / PowerShell / 任意脚本，不能越狱，不能访问其它 App 的私有数据，不能替用户绕过系统授权。
        - 工作区路径（相对路径都基于它）：\(workspacePath)
        - 用户可以通过「文件」App 直接看到并修改工作区里的文件。

        # 工具调用格式（必须严格遵守）
        需要调用工具时，输出如下的标记块，一个工具一块，可以连续输出多块：

        <iagent-tool>
        {"tool":"工具名","args":{"参数名":"参数值"}}
        </iagent-tool>

        不要把标记块包在 Markdown 代码块里，不要在标记块外写多余解释。工具执行完，结果会以

        <iagent-result>
        {"tool":"工具名","ok":true,"summary":"结果摘要"}
        </iagent-result>

        的形式发回给你，你可以据此继续下一步。工具失败时 ok=false，请在 summary 里看原因并换一种做法。

        # 可用工具
        \(catalogText())

        # 规则
        - 一次可以调用多个互不依赖的工具；依赖前一步结果的必须分轮。
        - \(approvalNote)
        - 需要用户决定的事情（比如要删哪个文件），先在正文里问清楚，不要直接调用破坏性工具。
        - 不要臆造工具调用格式，工具不存在时会返回错误。
        - 全程最多可以连续调用 \(maxSteps) 轮工具，请规划好步骤。
        """

        if !extraPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\n# 用户自定义补充要求\n\(extraPrompt)"
        }
        return prompt
    }
}
