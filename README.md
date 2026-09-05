# Codex Usage for macOS

轻量的 macOS 菜单栏应用，显示 Codex 账户的剩余额度。

菜单栏仅显示 **Codex 图标 + 百分比**。文字使用系统菜单栏字体，字号比系统默认小 1 pt；图标和文字由原生状态栏按钮统一排版。默认每 30 秒自动刷新，点击图标可查看重置时间、重置卡数量、其他额度和刷新频率。

## 打开、关闭、删除

1. **安装和打开**：从本仓库 Releases 下载 `Codex-Usage-macOS-arm64.zip`，解压后把 `Codex Usage.app` 拖进“应用程序”，双击打开。应用会展开用量面板，并常驻屏幕右上角。
2. **关闭**：点击菜单栏图标，选择“退出应用”。没有 Dock 图标；关闭弹出面板会继续监测，选择“退出应用”才结束程序。
3. **删除**：先退出，在 Finder 中把 `Codex Usage.app` 移到废纸篓。

本应用不安装后台守护进程，不自动设置开机启动。再次双击应用可以重新打开面板。

## 运行要求

- Apple Silicon Mac，macOS 14 或更新版本。
- 已安装并登录 ChatGPT/Codex 桌面应用；也支持常见 Homebrew 路径中的 Codex CLI。
- 不需要 Python、API Key、浏览器扩展或辅助功能权限。

当前发布包使用本地签名，未使用 Apple Developer ID 公证。从 GitHub 下载到其他 Mac 后，macOS 可能要求手动确认打开。

## 显示与用量规则

- 优先读取 `rateLimitsByLimitId`；不存在时兼容旧的 `rateLimits`。
- 剩余比例按 `100 - usedPercent` 计算，限制在 0–100%。缺失数据展示为 `—`。
- 主数字显示 Codex 主额度中剩余比例最低的周期；周期长度来自服务返回值。
- 支持 15 / 30 / 60 秒刷新和立即刷新。休眠唤醒后重新同步。
- 断网保留最近成功数据，在百分比后显示提示点，详情中明确提示旧数据。
- 重置时间已过时显示“等待额度更新”，不会自行假设已经恢复为 100%。

“其他额度”整行都能点击展开和折叠。面板采用紧凑布局，顶部固定，展开内容向下增加，取消了窗口缩放动画。

## 从源码构建

安装支持 Swift 6 的 Xcode Command Line Tools。项目没有第三方 Swift 包依赖。

```sh
./script/check.sh                  # 11 项额度逻辑检查，无需完整 Xcode
./script/build_and_run.sh          # 构建并运行
./script/build_and_run.sh --build-only
./script/package.sh                # 在 dist/ 生成 app、ZIP 和 SHA-256
```

构建目录为 `.build/local`，也可以用 `CODEX_USAGE_BUILD_ROOT` 指定其他位置。Codex 项目里的 Run 动作指向同一个构建入口。

## 结构

- `App/`：应用入口、启动和退出生命周期。
- `Services/StatusItemController.swift`：原生菜单栏按钮和 SwiftUI 弹出面板之间的边界。
- `Services/CodexConnection.swift`：串行管理只读 Codex app-server 连接。
- `Stores/UsageStore.swift`：刷新、错误和数据时效状态。
- `Models/`：额度模型与展示规则。
- `Views/`：用量详情界面。

上述代码目录均位于 `Sources/CodexUsage/`。

## 隐私与范围

只调用本机 Codex 程序的初始化和 `account/rateLimits/read`，不发起模型请求、不兑换重置券、不购买额度、不修改登录、不读取对话。认证由 Codex 自己处理，应用不读取或复制登录凭据。

额度仅留在内存中。独立运行状态位于当前用户缓存目录的 `local.codexusage.menubar` 中；删除这个工具不会删除或退出你的 Codex 账户。

本项目是个人工具，并非 OpenAI 官方应用。Codex 图标资源的归属见 [Assets/README.md](Assets/README.md)。
