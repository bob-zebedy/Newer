<div align="center">

# Newer

**在 Finder 右键菜单中，用模板快速新建文件**

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/github/license/bob-zebedy/Newer?color=8957E5)](LICENSE)

[功能](#功能) | [运行要求](#运行要求) | [快速开始](#快速开始) | [从源码构建](#从源码构建)

</div>

---

Newer 是面向 macOS 14 及更高版本的原生 App，通过 Finder Sync 扩展在右键菜单中提供“新建文件”。

你可以把常用文件放入模板目录，按目录组织并决定哪些模板出现在 Finder 中。Newer 会在已授权的位置复制模板，同时保留原始内容并避免覆盖已有文件。

## 功能

### 直接在 Finder 中新建文件

- 在文件夹空白处、文件和文件夹的右键菜单中提供“新建文件”入口
- 右键单个文件夹时在该文件夹内创建，右键文件或同一目录中的多个项目时在其所在目录创建
- 完整复制模板内容，并保留文件名和扩展名
- 已有同名文件时自动使用 `名称 2.ext`、`名称 3.ext` 等可用名称
- 通过临时目录和独占发布避免覆盖现有文件或留下不完整副本

### 集中管理文件模板

- 自动创建并监听 App Group 中的模板目录
- 支持最多三层目录，用相同层级组织 App 列表和 Finder 子菜单
- 可以单独启用或停用模板，也可以通过目录勾选框批量调整
- 可以修改模板在菜单中的显示名称，并在同一层级拖拽排序
- 模板目录发生变化后自动刷新，无需重新启动 App

Newer 只收录普通文件。隐藏项目、符号链接、Finder Alias、package 和 FIFO、socket、device 等非普通文件不会进入模板列表。

### 精确控制文件访问范围

- 通过系统目录选择器授予一个或多个文件夹的访问权限
- 外部磁盘按卷单独授权和撤销，不把系统磁盘授权错误地扩展到其他挂载卷
- 使用持久化 security-scoped bookmark，让 Finder 扩展只访问用户明确授权的位置
- 在 App 中查看 Finder 扩展状态，以及每项授权当前是否可用


### 融入 macOS

- 使用 SwiftUI、AppKit 和 FinderSync 构建
- 支持简体中文和英文界面
- 主应用与 Finder 扩展均启用 App Sandbox 和 Hardened Runtime
- 不依赖第三方运行时或网络服务

## 运行要求

- macOS 14.0 或更高版本
- 在系统设置中启用 Newer Finder Extension
- 为需要创建文件的目录或外部磁盘授予访问权限

## 快速开始

1. 启动 Newer，在“权限”中点击“打开系统设置”，启用 Newer Finder Extension
2. 回到 Newer，通过“添加位置”授权需要创建文件的目录；外部磁盘需要选择 `/Volumes` 下的磁盘根目录
3. 打开“模板”，点击“打开目录”，将常用的普通文件放入模板目录
4. 在 Newer 中调整模板显示名称、启用状态和同层顺序
5. 在 Finder 中右键文件夹空白处、文件或文件夹，从“新建文件”子菜单选择模板

## 从源码构建

项目使用原生 Xcode 工程。使用 Xcode 27 打开：

```bash
open Newer.xcodeproj
```

选择 `Newer` scheme 运行。主应用和 Finder 扩展需要使用同一个 Apple Developer Team，并共享 App Group

执行静态检查和无签名 Debug 构建：

```bash
swiftformat --lint --cache ignore .
swiftlint lint --strict --no-cache
xcodebuild -project Newer.xcodeproj \
  -scheme Newer \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/NewerDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

生成 Developer ID 签名、公证并装订票据的 App，再打包 DMG：

```bash
Scripts/build.sh
Scripts/dmg.sh
```

`Scripts/build.sh` 需要预先配置 Apple 公证凭据，成功后生成 `Build/Newer.app`。`Scripts/dmg.sh` 会再次验证签名、公证票据和 Gatekeeper 状态，再生成 `Build/Newer-v<version>.dmg`

## 反馈

Bug、功能建议或使用问题欢迎通过 [GitHub Issues](https://github.com/bob-zebedy/Newer/issues) 反馈。

## 许可证

[GNU General Public License v3.0](LICENSE)
