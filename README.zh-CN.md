# QuotaRing

> 面向 **macOS** 与 **Windows** 的极简同心双环 AI 配额监控工具 —— **零凭据、零联网、纯本地只读**。

简体中文 | [English](./README.md)

---

## 为什么做 QuotaRing？

市面上不少 AI 配额监控工具会去读取系统钥匙串（Keychain）、抓取浏览器 Cookie 或高频轮询未公开内部接口，既存在隐私安全隐患，也可能触及平台服务条款风险。

**QuotaRing 坚持严格的“纯本地、零凭据”原则：**

- **零凭据、零网络请求**：不读钥匙串、不抓浏览器 Cookie、不代理 API、不发任何外网请求。
- **同心双环极简视觉**：
  - **外圈** —— 剩余可用额度（`0%–100%`）
  - **内圈** —— 距离重置的剩余倒计时
  - **`5` / `W` / `M` 自适应双环**：自动按平台实际周期展示 5 小时（`5`）、周（`W`）、月（`M`）或自定义周期双环；macOS 菜单栏默认紧凑横排，Windows 右下角托盘展示高清自适应同心双环。
- **多品牌统一查看**：
  - **Antigravity**：通过官方 `agy` CLI `statusLine` 钩子同步快照（内置跨平台 Antigravity 侧边栏插件）。
  - **OpenAI Codex**：纯本地自动解析 `~/.codex/sessions/**/*.jsonl` 中的最新 `rate_limits`。
  - **开放插槽（Cursor / GrokBot / Claude 等）**：往 `~/.config/quota-bar/providers/` 放入任意 `*.json` 文件即可自动以同款双环展示。
- **原生极致轻量**：
  - **macOS**：纯 Swift + AppKit 编写（约 1 MB，无 Electron，自动适配深/浅色菜单栏）。
  - **Windows**：纯 .NET 8 WinForms 原生托盘应用（零第三方依赖，单文件 `.exe`，自动适配 Windows 深/浅色任务栏）。

---

## 目录结构

```text
QuotaRing/
├── apps/
│   ├── macos/                  # macOS 原生 Swift / AppKit 菜单栏应用
│   └── windows/                # Windows 原生 .NET 8 WinForms 系统托盘应用
├── plugin/
│   └── quota-monitor/          # 跨平台 Antigravity MCP App 插件 + agy statusLine 钩子
├── providers/                  # 开放插槽 JSON Schema 与示例（Cursor、GrokBot 等）
└── .github/workflows/          # GitHub Actions 双端自动编译与发版
```

---

## 快速上手

### 1. macOS（顶部菜单栏版）

环境要求：macOS 13.0+ 与 Xcode 命令行工具（`xcode-select --install`）。

```bash
git clone https://github.com/Zi-Chung/QuotaRing.git
cd QuotaRing
./apps/macos/install.sh
```

也可以直接从 **GitHub Releases** 下载打包好的通用版 `QuotaRing-macOS.zip`，解压后拖入 `/Applications`。

### 2. Windows（系统托盘版）

源码编译要求：Windows 10/11 与 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)。

```powershell
git clone https://github.com/Zi-Chung/QuotaRing.git
cd QuotaRing
.\apps\windows\build.ps1
.\apps\windows\publish\QuotaRing.exe
```

也可以直接从 **GitHub Releases** 下载单文件版 `QuotaRing-win-x64.exe` 双击运行。

### 3. 安装 Antigravity 官方 `statusLine` 与侧边栏插件（Mac / Windows 通用）

```bash
cd plugin/quota-monitor
npm install
npm run build
node scripts/install-plugin.mjs
```

安装完成后，在终端运行一次 `agy` 即可把官方配额快照同步至 `~/.gemini/antigravity-cli/quota-snapshot.json`，菜单栏/托盘和 Antigravity 侧边栏面板都会自动更新。

---

## 开放插槽接入（Cursor / GrokBot / 其他平台）

QuotaRing 会自动监听 `~/.config/quota-bar/providers/*.json`（Windows 路径：`%USERPROFILE%\.config\quota-bar\providers\*.json`）。

任何你信任的官方脚本（如团队 Admin API）或外部工具，只需写入一个标准 JSON 文件即可自动接入：

```json
{
  "id": "cursor",
  "name": "Cursor",
  "shortBadge": "Cu",
  "planTier": "Pro",
  "updatedAt": "2026-11-24T10:40:00Z",
  "monthly": {
    "label": "月额度",
    "remainingPercent": 80,
    "resetTime": "2026-12-24T10:40:00Z",
    "windowMinutes": 43200
  }
}
```

完整字段说明见 [providers/README.md](./providers/README.md) 与 [providers/schema.json](./providers/schema.json)。

---

## 安全与隐私承诺

- **零网络代码**：macOS 与 Windows 客户端均不包含任何网络请求或遥测上报代码。
- **零凭据读取**：绝不访问钥匙串、浏览器 Cookie、凭据管理器或第三方应用内部认证数据库。
- **纯本地只读**：仅读取公开/本地快照文件（`quota-snapshot.json`、`~/.codex/sessions/*.jsonl`、`~/.config/quota-bar/providers/*.json`）。

---

## 开源协议

[MIT License](./LICENSE)
