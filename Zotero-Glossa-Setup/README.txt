Zotero + Claude / Glossa 0.2.0 安装助手

请先打开同目录 README.html，里面有完整的中文操作说明。

快速开始
1. 将整个 ZIP 解压到一个文件夹，不要在压缩包内直接运行。
2. 保存工作，并完全退出 Zotero（Mac 上用 Command+Q）。
3. Windows：双击 START-Windows.cmd。
   macOS：双击 START-macOS.command。
4. Zotero 打开后，进入“工具 → 插件”，确认 Glossa for Zotero 已出现。
   如果显示“启用”或安装确认，请点击。必要时重启 Zotero。
5. 选中文献 → 右侧 Glossa 图标 → 输入框下方的模型菜单 → 添加 API 服务。
6. 官方 Anthropic 密钥：预设选 Anthropic，协议选 Anthropic，
   地址使用 https://api.anthropic.com，粘贴密钥，获取模型列表，选择模型并保存配置。
   第三方服务商密钥：使用该服务商提供的地址、协议和模型 ID。

适用版本
仅支持 Zotero 10.0.6 及以后的正式版 10.x。
7、8、9、10.0.0–10.0.5、11 及测试版不在这个插件的兼容范围内。
可在 Zotero 的“帮助 → 关于 Zotero”查看版本；Mac 可在 Zotero 菜单查看。

自动与手动的边界
本助手部署插件文件并启动 Zotero，首次可能仍需在插件管理器中点一次启用。
它不自动填写 API 密钥，也不会调用 Claude API 进行付费测试。
本插件让你在 Zotero 内使用 Claude API 读论文，不配置 Claude 桌面应用的 MCP。

最稳妥的备用安装方式
无需运行任何脚本：打开 Zotero → 工具 → 插件，
把 payload/glossa-zotero-0.2.0.xpi 拖进插件窗口，并按提示安装。
若拖动没有反应，在齿轮菜单选择“从文件安装插件”，选择这个 XPI。
不要解压 XPI；不要把 GitHub 的 Source code ZIP 当插件安装。

脚本做什么
- 无需管理员权限、Python 或 Node.js；安装阶段无需访问 GitHub。
- 先校验插件 SHA-256，再从 profiles.ini 识别标准 Zotero 配置。
- Zotero 运行时停止操作，不强制结束进程。多个配置时让你选择。
- 仅复制 Glossa XPI。为触发插件重新扫描，只清除 prefs.js 中的
  extensions.lastAppBuildId 与 extensions.lastAppVersion 两项启动缓存标记。
- 不修改全局插件安全策略，不编辑 extensions.json，不更改文献数据库和 PDF。
- 相关原文件备份于所选配置的 glossa-setup-backups/时间戳/。
- Windows 启动器的 ExecutionPolicy Bypass 只用于本次进程，不改变系统执行策略。
- 全程不收集 API 密钥、不发送文献；之后的 API 请求由 Glossa 按你的配置发起。

旧版与撤回
- 若已有 Glossa 0.1.0，请先从 Zotero 插件管理器移除，并重启 Zotero，再安装。
- 若已有比 0.2.0 更新的版本，助手停止，避免降级。
- 卸载：在 Zotero → 工具 → 插件 中移除 Glossa，并重启。
- 需要撤回文件改动时，先完全退出 Zotero。在助手显示的备份目录内，
  previous.xpi 是旧版插件，prefs.js 是改动前的设置文件。
  仅在需要恢复本次安装前状态时还原；较晚恢复完整 prefs.js 会覆盖此后新增的设置。
  若没有 previous.xpi，说明安装前没有同名的 XPI 文件。

检查范围
插件为作者发布的原版 XPI，没有改动兼容性声明或插件代码。
已验证文件哈希、脚本语法，以及临时配置中的部署、缓存标记处理、备份、
重复运行和异常保护。未在真实 Windows/macOS 的 Zotero 界面中完成安装验证。
作者说明：插件已在 macOS 上测试，Windows/Linux 尚未实机测试。

原版来源
https://github.com/yiiwang118/zotero-glossa/releases/tag/0.2.0
https://github.com/yiiwang118/zotero-glossa/blob/0.2.0/README.zh-CN.md
https://www.zotero.org/support/plugins
原版 XPI SHA-256：
0a71b777731e856ac3ad8d1fceaf598fce6cc15a8ca6a459902bc9b74462a8c9

本安装助手由 ChatGPT 为本次请求制作，并非 Zotero 或 Glossa 作者提供的官方安装器。
Glossa 原作者为 yiiwang；原版插件按 MIT 许可证分发，见 THIRD-PARTY-LICENSE.txt。
