# Repository Guidelines

本文件适用于仓库根目录及其全部子目录。始终使用简体中文回答，代码、命令、专有名词和需要保留的原文除外。

## 项目目标与技术基线

Newer 是一个面向 macOS 14+ 的文件模板工具。主应用负责管理模板、目录授权和运行日志，Finder Sync 扩展在 Finder 右键菜单中读取同一份配置并从模板创建新文件。

- 使用 Swift 6、SwiftUI、AppKit 和 FinderSync，不依赖第三方包
- `Newer.xcodeproj` 是唯一工程配置来源，不使用 XcodeGen 或其他工程生成器
- `Newer` 是主应用 target，`NewerFinder` 是 Finder Sync 扩展 target
- 共享 scheme 为 `Newer`，负责构建主应用并嵌入扩展
- 工程使用文件系统同步目录。新增源码通常只需放入对应目录，不要为普通文件手工编辑 `project.pbxproj`
- Debug 和 Release 的最低系统版本均为 macOS 14.0，项目级 Swift 语言版本为 6.0

## 目录与职责

- `Newer/App`：主应用入口和生命周期
- `Newer/Views`：SwiftUI 界面及必要的 AppKit bridge
- `Newer/Models`：仅供主应用展示和交互使用的状态类型
- `Newer/Services`：主应用的状态协调、目录监控和日志适配
- `Newer/Resources`：主应用的 `Info.plist`、entitlements、本地化和图标
- `NewerFinder/FinderSync`：Finder 扩展入口、菜单构建和扩展日志适配
- `NewerFinder/Resources`：扩展的 `Info.plist`、entitlements 和本地化
- `Shared/Models`：主应用和扩展共同使用的数据模型
- `Shared/Services`：共享存储、授权解析、目标目录解析、模板发现、文件创建和运行日志
- `Config/Version.xcconfig`：`MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 的唯一维护位置
- `Scripts/build.sh`：Developer ID 归档、导出、公证、装订和产物校验
- `Scripts/dmg.sh`：将已签名且已公证的 App 打包为 DMG

## 核心数据流与不变量

主应用与 Finder 扩展通过 App Group `group.app.zabrian.newer` 共享状态。`UserPaths` 当前定义以下持久化位置：

- `Templates/`：模板目录
- `configuration.json`：模板顺序、显示名称和启用状态
- `directory-authorizations.plist`：用户授予的 security-scoped bookmark
- `runtime.log`：主应用和 Finder 扩展共用的运行日志

修改这些路径、文件格式、编码字段或配置版本前，必须先检查主应用和扩展的读写行为。文件创建链路必须继续满足以下约束：

- 只接受合法的模板相对路径，不允许绝对路径、`.`、`..` 或越界访问
- Finder 目标必须是实际目录，并位于有效授权范围内
- 授权匹配必须考虑独立挂载卷的文件系统边界，不能仅依赖字符串路径前缀
- security-scoped resource 的访问必须成对开始和结束，不能丢失 bookmark 解析得到的临时 sandbox extension
- 创建时不得覆盖已有目标；同名冲突、临时文件、独占发布和失败清理逻辑必须保持原子性及可恢复性
- 模板只接受普通文件。目录只用于组织菜单层级，隐藏文件、alias、symlink 和 package 按 `TemplateCatalog` 的现有规则跳过
- 模板相对路径和目录层级限制由 `TemplateItem` 统一定义，不能在调用方建立另一套校验规则

## 实现原则

- 先从现有代码、工程配置和脚本确认事实，再修改实现；不要让文档或假设覆盖源码事实
- 优先在现有类型职责内完成改动，不为小改动增加中间层、依赖、空目录或平行实现
- 只供主应用使用的 UI 状态放在 `Newer`；主应用与扩展共同依赖的模型和文件系统逻辑放在 `Shared`
- 修改 `Shared` 后同时检查 `Newer` 和 `NewerFinder` 的编译及行为
- 主应用 target 默认使用 `MainActor` 隔离。需要跨 actor 使用的共享值类型应显式满足 `Sendable`，并按现有模式声明 `nonisolated`
- 不使用 `@unchecked Sendable`、全局可变状态或关闭并发检查来掩盖隔离问题
- 用户可见文本使用字符串目录和稳定的本地化 key；主应用与扩展分别维护各自 target 的 `Localizable.xcstrings`
- 日志通过 `RuntimeLogger` 及对应适配层写入，新增日志字段不得包含 bookmark 数据或其他敏感内容
- 保持 App Sandbox、Hardened Runtime、App Group、bookmark entitlement 和用户选择文件读写权限的一致性
- 不改变现有 Bundle ID、App Group、签名 team、持久化路径或 entitlements，除非任务明确要求且影响已经确认
- 版本信息只修改 `Config/Version.xcconfig`，主应用图标只维护 `Newer/Resources/AppIcon.icon`

任何兼容性决策都必须先询问用户，不得自行选择。包括但不限于持久化 key 或文件格式变更、旧数据迁移或丢弃、配置版本升级、书签失效处理、主应用与旧扩展并存、最低系统版本调整以及 Bundle ID 或 App Group 变更。询问时应说明影响范围、可选方案、迁移成本和失败后的表现。

## 写作风格

代码、代码注释和项目文档使用彼此独立的规则，不得把一类内容的标点约定直接套用到另一类内容。提交信息由 Git 规范单独约束。

### 代码和注释

代码和注释统一遵守：

- 禁止使用中文标点，一律使用半角标点
- 句中停顿和并列项使用空格或者逗号，顿号的位置也用空格或者逗号
- 分号只用来断开完整句子，相当于句号；拿不准就把它换成句号读一遍，两边都能独立成句才保留
- 行末禁止使用标点
- 行内标点后如果还有文字，间隔一个英文空格
- 注释中引用类型、成员、参数或命令后尽量不要紧跟标点，需要断句时补一个词或者使用空格再断
- 一个注释段只解释一件事，需要说明多个独立主题时拆成多个注释段

注释保持克制，只解释非显然的系统约束、文件系统安全边界、生命周期、actor 隔离或实现原因，不复述代码行为。

### 项目文档

项目文档统一遵守：

- 代码标识符、命令、路径、配置键、原始字段值和需要精确复制的版本号使用行内代码
- 中文正文使用全角中文标点，包括 `，` `。` `；` `：` `！` `？` `“”` 和 `（）`
- 中文短词或短语的并列使用 `、`；能独立表达语义的分句使用 `，`，两边都能独立成句时才考虑 `；`
- 中文标点前后不加空格；中文与英文、数字或行内代码之间按词语边界保留一个半角空格
- 不机械替换特殊内容中的英文标点。数字序列、行内代码序列或英文术语并列时，如果英文标点观感更好，使用英文标点并在其后保留一个半角空格
- 普通正文行末使用与语义匹配的中文标点；引出列表、表格或代码块的正文使用 `：`
- 标题、独立列表项、编号项和表格单元格行末不加标点
- 如果一行以 Markdown 格式的链接或行内代码结尾，后面不加任何标点；链接或行内代码位于句中时仍按句子结构使用中文标点
- Markdown 语法、代码块、命令、路径、URL、版本号和程序标识符内部的符号保持原样
- 如果某句话的作用只是防止被质疑，而不是推进论证，请删除这句话
- 文档只描述当前行为，不记录或者强调变更过程，同时删除没有实质信息的防御性表述

## 验证要求

验证范围应与改动风险匹配。不要声称执行过未实际执行的命令；如果受签名、系统权限或 Finder 状态限制，应明确列出未验证项。

### 静态检查

Swift 源码变更至少执行：

```bash
swiftformat --lint --cache ignore .
swiftlint lint --strict --no-cache
```

需要自动整理格式时执行 `swiftformat .`，然后重新检查 diff，避免改动无关文件。

### 构建

日常 Debug 构建使用：

```bash
xcodebuild -project Newer.xcodeproj -scheme Newer -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/NewerDerivedData CODE_SIGNING_ALLOWED=NO build
```

涉及优化行为、条件编译或发布配置时，再补充 Release 构建。

### 手动验证

以下改动不能只以构建通过作为验收：

- 模板管理：验证新增、删除、重命名、启用、禁用、拖拽排序、目录层级和外部文件变更刷新
- 目录授权：验证普通目录、外置卷、授权移除、bookmark 失效和重新授权
- Finder 扩展：验证启用状态、Finder 右键菜单、当前目录解析、未授权提示以及主应用与扩展读取同一配置
- 文件创建：验证普通文件模板、同名冲突、扩展名保留、失败清理和越界路径拒绝
- 日志：验证主应用与扩展写入、轮转或截断、刷新和清空行为
- 本地化或界面：验证简体中文和英文显示、窗口最小尺寸、长文本和 VoiceOver label

`Scripts/build.sh` 会使用 Developer ID 签名、访问 Apple 公证服务并覆盖 `Build/Newer.app`；`Scripts/dmg.sh` 只接受已签名且已公证的 App。除非用户明确要求发布产物，否则不要把这两个脚本作为日常验证命令。

## Git 与交付

- 保留用户已有的未提交修改，不回滚、不覆盖、不清理无关文件
- 未经明确要求，不创建 commit、tag 或 push
- 用户只要求提交时，只提交任务范围内的现有改动，不顺带格式化或修改其他文件
- 交付时概括行为变化、实际执行的验证和仍需人工验证的项目

提交信息必须从完整 diff 提炼核心目的，而不是罗列文件或函数。标题使用 `<type>: <中文描述>`，常用 type 为 `feat`、`fix`、`chore`、`refactor` 和 `docs`。标题与 body 之间空一行；修复类提交需要 body，body 中的 bullet 连续排列并缩进 4 个空格。提交信息不写版本号、Release 标记或发布过程。

创建版本 tag 时，从 `Config/Version.xcconfig` 读取 `MARKETING_VERSION`，使用附注 tag：

```bash
git tag -a v3.x.y -m "Release v3.x.y"
```
