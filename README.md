# Codex Usage for macOS

轻量的 macOS 菜单栏应用，显示 Codex 账户的剩余额度。

菜单栏仅显示 **Codex 图标 + 百分比**。文字使用系统菜单栏字体，字号比系统默认小 1 pt；图标和文字由原生状态栏按钮统一排版。插电每 1 分钟更新，使用电池每 5 分钟更新；点击图标可查看重置时间、每张重置卡的到期时间和其他额度。

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
- 自动刷新频率只取决于供电状态，展开或收起菜单不改变频率，也不延后已安排的更新；仍可点击“刷新”立即更新。
- 断网保留最近成功数据，在百分比后显示提示点，详情中明确提示旧数据。
- 重置时间已过时显示“等待额度更新”，不会自行假设已经恢复为 100%。

“其他额度”整行都能点击展开和折叠。面板采用紧凑布局，顶部固定，展开内容向下增加，取消了窗口缩放动画。

## 节能运行方式

| 状态 | 自动查询频率 |
| --- | --- |
| 插电 | 每 1 分钟 |
| 使用电池 | 每 5 分钟 |
| 系统休眠、屏幕熄灭、用户会话不活跃、离线 | 暂停，恢复后更新 |

- 电源、显示器、休眠和网络变化使用系统通知，避免轮询探测。
- 删除原来每 5 秒运行的界面时钟；显示时间在查询、打开菜单和系统状态变化时更新。
- 只保留一个带时间容差的一次性查询定时器，允许系统合并唤醒。
- 每次查询结束后释放 Codex 查询子进程，菜单展开时也不保持闲置连接。
- 休眠、离线或退出会取消正在等待的查询；握手和查询共用一个 25 秒总超时。
- 查询进程优先通过关闭输入正常退出，异常不退出时采用有时限的清理；正常退出应用会等待当前查询清理完成。
- 每次查询仅在开始和完成时发布界面状态；菜单栏值未变化时跳过更新。
- 重置卡排序和额度分组只在收到新数据时计算。发布包使用 Release 优化构建。
- 反复失败时逐步延长重试，最长 30 分钟；断网期间不定时重试。
- 不保持系统唤醒，不禁用 App Nap，不更改 macOS 的电池设置。

定时器容差与系统事件监听参考 [Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)。

重置卡按最早到期顺序显示日期和时间。未返回的明细或到期时间会明确显示为未知，不推断“永久有效”，也不自动消耗卡片。

## 从源码构建

安装支持 Swift 6 的 Xcode Command Line Tools。项目没有第三方 Swift 包依赖。

```sh
./script/check.sh                  # 30 项模型检查 + 27 项运行检查，无需完整 Xcode
./script/build_and_run.sh          # 构建并运行
./script/build_and_run.sh --build-only
./script/package.sh                # 以 Release 构建，在 dist/ 生成 app、ZIP 和 SHA-256
```

构建目录为 `.build/local`，也可以用 `CODEX_USAGE_BUILD_ROOT` 指定其他位置。日常构建默认为 Debug，可用 `CODEX_USAGE_CONFIGURATION=release` 覆盖；打包始终使用 Release。Codex 项目里的 Run 动作指向同一个构建入口。

## 结构

- `App/`：应用入口、启动和退出生命周期。
- `Services/StatusItemController.swift`：原生菜单栏按钮和 SwiftUI 弹出面板之间的边界。
- `Services/CodexConnection.swift`：串行管理只读 Codex app-server 连接。
- `Stores/UsageStore.swift`：刷新、错误和数据时效状态。
- `Services/RefreshScheduler.swift`：单次定时器的创建、时间容差和取消。
- `Models/`：额度模型与展示规则。
- `Models/UsageState.swift`：一次发布的界面状态和去重后的菜单栏数据。
- `Views/`：主布局，以及额度、重置卡和其他额度三个独立视图。

上述代码目录均位于 `Sources/CodexUsage/`。

运行检查使用本地模拟查询进程，覆盖取消、超时、重连、旧结果丢弃和资源释放，不连接真实账户。设计审查与测量边界见 [REVIEW.md](REVIEW.md)。

## 隐私与范围

只调用本机 Codex 程序的初始化和 `account/rateLimits/read`，不发起模型请求、不兑换重置券、不购买额度、不修改登录、不读取对话。认证由 Codex 自己处理，应用不读取或复制登录凭据。

额度仅留在内存中。独立运行状态位于当前用户缓存目录的 `local.codexusage.menubar` 中；删除这个工具不会删除或退出你的 Codex 账户。

本项目是个人工具，并非 OpenAI 官方应用。Codex 图标资源的归属见 [Assets/README.md](Assets/README.md)。
