# Codex Usage for macOS

简体中文 · [English](README.en.md)

在 Mac 顶部菜单栏查看 Codex 剩余额度、重置时间和重置卡到期日期。

**当前推荐版本：1.6.2（build 11）**。2026-10-30 恢复为最新正式版；1.7.0 和 1.7.1 的 Token 统计与金额估算方案已弃用。主分支恢复到 1.6.2 的应用代码与截图，保留 MIT 许可证。

**[下载最新版](https://github.com/ccrrfftt/codex-usage-menubar/releases/latest)**

<p align="center">
  <img src="Assets/screenshot.png" alt="Codex Usage 菜单栏应用：剩余额度、重置时间及每张重置卡的到期日期" width="360">
</p>

截图仅使用虚构演示数据。

- **圆环显示剩余额度**：弧长随剩余比例变化，低于 20% 变红；旁边保留百分比，点击展开详情。
- **查看重置卡**：显示可用数量，以及每张卡的到期时间。
- **中英文切换**：在面板右上角点击「EN / 中文」，自动记住上次选择。
- **按供电状态刷新**：插电每 1 分钟，电池每 5 分钟；休眠、离线时暂停。

## 安装

需要 **Apple Silicon Mac、macOS 14+**，并已安装、登录 Codex / ChatGPT 桌面应用。

1.6.2 已验证兼容 Codex 26.928.20755 / CLI 0.159.0，支持系统和个人「应用程序」目录。服务端限制常规用量时，会显示明确提示。

1. 下载并解压最新版的 `Codex-Usage-版本号-macOS-arm64.zip`。
2. 把 `Codex Usage.app` 拖进「应用程序」，双击打开。

**升级**：先退出旧版，再替换 App。**退出**：点击面板中的「退出应用」。**删除**：退出后把 App 移到废纸篓。

当前安装包使用本地签名，尚未经过 Apple 公证。

原生应用，无需网页、Python 或 API Key；只读查询额度，不发起模型请求、不使用重置卡。不自动设置开机启动。

---

[开发说明](DEVELOPMENT.md) · [更新记录](CHANGELOG.md) · [图标来源](Assets/README.md)

个人项目，非 OpenAI 官方应用。

## 许可证

本项目的原创源码和文档采用 [MIT 许可证](LICENSE)。OpenAI 名称、图标等第三方素材（包括截图中的相关标识）不在该许可的授权范围内，详见[图标来源](Assets/README.md)。
