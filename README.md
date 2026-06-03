# Codex Quota Touch Bar

一个 macOS 菜单栏 + Touch Bar 小应用，用本机 Codex app-server 读取额度，并把 5 小时额度、周额度显示成常驻分段电量条。

## 功能

- 菜单栏显示剩余额度百分比。
- Touch Bar 常驻显示两行分段电量条：5 小时额度和周额度。
- 点击菜单栏 `Codex` 后显示弹窗，包含 5 小时额度、周额度、重置时间、更新时间。
- 电量条颜色按剩余额度变化：绿色 51%-100%，黄色 21%-50%，红色 0%-20%。
- 刷新失败时保留上一次成功数据，避免界面空白；有缓存数据时只显示灰色提示。

## 要求

- macOS 12 或更新版本。
- 带 Touch Bar 的 MacBook Pro，或支持 Touch Bar 的系统环境。
- 已安装 Codex Desktop，且本机存在：

```sh
/Applications/Codex.app/Contents/Resources/codex
```

## 构建

```sh
./scripts/build-app.sh
```

构建产物会出现在：

```sh
.build/CodexQuotaTouchBar.app
```

## 运行

```sh
open .build/CodexQuotaTouchBar.app
```

如果从 GitHub Release 下载 `.app`，它使用临时签名，没有 Apple 公证。macOS 首次打开时可能需要在“系统设置 -> 隐私与安全性”中允许打开，或右键点击 App 后选择“打开”。

## 本地协议

应用会启动：

```sh
/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://
```

然后通过 JSON-RPC 调用：

```text
initialize
account/rateLimits/read
```

## 隐私和安全

这个工具只和本机 Codex app-server 通信，不抓网页，不上传额度数据，不保存令牌、账号数据或额度快照。

## 许可证

MIT
