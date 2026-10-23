# iAgent（EAgent iOS）

把 Windows 版 [EAgent](https://github.com/YaoGaoChaoLe/EAgent) 的思路搬到 iPhone：
**用 DeepSeek 网页版（0 token、0 门槛）驱动一个能真正动手的 Agent。**

EAgent 在 Windows 上让 DeepSeek 操控电脑（PowerShell、截图、鼠标键盘）。
iOS 沙盒不允许执行任意脚本，所以 iAgent 把能力换成一组**系统公开能力**：
文件读写、剪贴板、截图、相册、定位、日历/提醒、通知、朗读、HTTP、分享、快捷指令。

## 怎么用

1. 装好 App，进「设置 → DeepSeek 账号 → 登录 DeepSeek 网页版并自动抓取」，
   在弹出的网页里登录，App 会自动从请求头 / localStorage / Cookie 里把 token 抠出来。
2. 回「对话」页直接说需求，例如：
   - 「在 notes 里写一份今天的会议纪要」
   - 「列出工作区里有哪些文件，把 todo.md 的内容念给我听」
   - 「截个屏，告诉我现在是什么界面」
   - 「帮我添加一个一小时后的提醒事项」
   - 「把这个网页的内容存成 txt」
3. 会改动设备的动作（写文件、删除、联网发送、打开链接、分享、保存相册……）会先弹确认框。
4. 工作区就是 App 的 `Documents/AgentWorkspace`，在系统「文件」App 里能直接打开编辑。

## 工作原理

- 聊天走 DeepSeek 网页端内部接口（`chat.deepseek.com/api/v0/chat/completion`）：
  PoW 工作量证明 + HIF 风控令牌 + 网页端请求头指纹，和官方网页前端一致。
- 模型想调用工具时，输出一段标记块：

  ```
  <iagent-tool>
  {"tool":"write_file","args":{"path":"a.txt","content":"你好"}}
  </iagent-tool>
  ```

- App 解析标记 → 按需请求用户确认 → 执行 → 把结果包成 `<iagent-result>` 回喂给模型 → 继续下一轮。

## 目录

```
EAgent/
  Agent/      ToolCall（协议+解析）、ToolCatalog（工具清单+系统提示词）、
              Workspace（沙盒路径）、ToolExecutor（调度）、FileTools / DeviceTools /
              NetworkTools / CalendarTools（具体实现）、AgentEngine（主循环）
  Upstream/   DeepSeekWebClient（网页端协议）、SSEParser、UpstreamEventParser、
              SHA3Digest（PoW 用）、HIFTokenProvider（风控令牌）、MessageIDExtractor
  Security/   KeychainStore、CredentialExtractor、LoginWebView（内嵌网页登录抓 token）
  Views/      AgentChatView（聊天+审批）、WorkspaceView（文件）、AgentSettingsView、RootView
  Core/       AppStore（设置/凭证/日志）
```

## 开发规则

- 本地没有 macOS，**编译和测试只走 CI**（`ios-ci-workflows` v1.1.0）。
- 工程用 XcodeGen 生成：`project.yml` 是唯一真相源，`.xcodeproj` 不入库。
- 新功能必须带测试：逻辑测试写在 `EAgentTests/`。
- 不在代码、日志、workflow 里写明文密钥；DeepSeek token 只进钥匙串。

## 声明

DeepSeek 网页端接口没有公开文档，协议随时可能变，也违反 DeepSeek 用户协议。
本项目仅供学习交流，账号风险自负。
