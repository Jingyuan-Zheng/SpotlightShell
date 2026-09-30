# SpotlightShell

[English](README.md) · [MIT 许可证](LICENSE)

SpotlightShell 是一个原生 macOS 26+ 小工具：通过 **Spotlight** 或 **快捷指令**执行即时输入的 shell 命令。它不维护命令清单，没有 Dock 常驻图标、后台辅助进程或第三方依赖。

![Spotlight 中发现动作](Screenshots/spotlight-discovery.png)

## 安装与使用

从最新 [Release](https://github.com/Jingyuan-Zheng/SpotlightShell/releases) 下载 DMG，把 **SpotlightShell** 拖到 Applications，并打开一次。图标启动会显示 macOS 原生的“关于 SpotlightShell”面板；关闭它会退出该无 Dock 常驻的工具。

按 Command-Space，再按 Command-3 进入“操作”。搜索并选择 **Run Shell Command**，输入命令，选择运行方式，然后选择 **Run Shell Command** 这一行（或右侧播放按钮）执行。

![Auto、Background 和 Terminal 的交互式选择器](Screenshots/mode-picker.png)

`Auto` 有意保留为可交互参数。Spotlight 正在编辑参数时，Return 可能只保留在编辑界面而不提交动作；请选择动作行或播放按钮运行。这样偶尔要改运行方式时无需再打开设置。

例如，在 Auto 下输入 `printf "Hello from SpotlightShell\\n"`，结果会直接显示在 Spotlight 中。

![Spotlight 中的命令结果](Screenshots/result.png)

### 三种运行方式

- **Auto**：普通短命令在后台执行；已知需要交互或长时间运行的命令交给 Terminal。
- **Background**：使用 `/bin/zsh -lc` 执行，返回 stdout、stderr 和状态；没有终端或 stdin，20 秒后停止。
- **Terminal**：在 Apple Terminal 中执行交互命令，可能要求授予自动化权限；输出保留在 Terminal。

Working Directory 可填绝对路径、`~` 或 `~/…`；留空即使用当前用户的主目录。

## 隐私与安全

SpotlightShell 不含分析、网络代码、命令历史或命令/输出持久化。它以当前用户身份执行命令，因此不是安全隔离层：只运行你理解的命令。Background 不需要自动化权限；Terminal 只请求将命令交给 Apple Terminal 所需的 Apple Events 权限。

## 从源码构建

需要 Xcode 26+ 和 macOS 26 SDK；请在 Xcode 选择自己的开发签名团队。使用真实开发签名可可靠刷新 App Shortcut。

```sh
xcodebuild -project SpotlightShell.xcodeproj -scheme SpotlightShell \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build build
```

## 许可证

Copyright © 2026 Jingyuan Zheng，采用 [MIT 许可证](LICENSE) 发布。
