# 构建、运行与恢复

## 构建 / Build

从项目根目录执行：

```sh
./apps/ilaunchpad/Scripts/build-app.sh
```

产物为 apps/ilaunchpad/dist/iLaunchPad.app。脚本需要 macOS 的 Swift/SDK、Xcode `actool` 和 `codesign`，使用 Icon Composer 资源生成 macOS 26/27 原生包图标，输出 arm64 及 ad-hoc 签名应用。脚本会重建工程 dist 内同名应用包。工程源码、资源与脚本归在同一目录，独立工具域暂为空。

测试命令为：

```sh
swift test --package-path apps/ilaunchpad
```

测试依赖 Swift Testing。既有执行曾出现 no such module 'Testing'，应选择包含该模块的匹配工具链；不能把构建成功写成测试通过。目录迁移不会自动安装新应用，现有 /Applications/iLaunchPad.app 与用户数据继续使用。

## 日常操作 / Usage

Option-Space 或 F4 显示/隐藏；双指滑动、页点或 Command-左右切页；输入名称/拼音搜索，方向键选择，回车启动。输入法有 marked text 时保留输入法处理。长按进入编辑，完成按钮退出。Esc 优先取消拖拽，之后按编辑、文件夹、搜索、窗口层级退出。

设置提供图标比例、名称开关、壁纸模糊、回第一页偏好及四款应用图标。未设置起始页时回首页；显式关闭后记忆上次页。应用图标在 Dock、访达、应用切换器和启动台内即时生效，退出后仍保持；恢复默认时回到海蓝包图标。安装目录变化自动触发后台核对，新应用追加到最靠近首页且未满35格的页面末尾；所有页满才新建页。刷新应用列表还会清空图标缓存；显示全部隐藏应用恢复普通组的隐藏项。菜单提供旧版 macOS LaunchPad、LaunchOS 与 LaunchNext 三种只读恢复入口，确认后覆盖当前排序。

## 数据与恢复 / Recovery

布局位于当前用户 Library/Application Support/iLaunchPad/layout.json，偏好属于 local.ilaunchpad.app 的 UserDefaults。备份前退出应用，单独复制布局与偏好；恢复时也先退出，再用已验证的备份替换。源码目录迁移不改变这些位置。

当前没有自动备份、坏文件隔离或跨进程锁。不要用 --import-only 做只读检查：该参数会初始化并保存真实布局。若 JSON 已损坏，应在再次启动前保存原文件，避免启动回退覆盖现场。重建应用包不能恢复用户排序。

编辑模式下，系统组件不显示卸载按钮。其他具备文件删除资格的应用统一显示叉号；叉号与图标、名称同步抖动。点叉号后默认选择为“取消”，确认“移到废纸篓”前会再次核对应用身份、位置、删除权限和运行状态。

确认后只使用系统废纸篓 API 移动当前 `.app` 应用包；成功才从 iLaunchPad 布局移除，取消或失败均保留图标和布局。此操作不清理文稿、设置、缓存、共享容器或辅助文件，也不取消订阅；清倒废纸篓前可以从废纸篓恢复应用包。参考 [Apple卸载说明](https://support.apple.com/zh-cn/102610) 和 [FileManager.trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))。

任一外部布局导入成功并已有有效 layout.json 后，iLaunchPad 不需要来源启动器继续安装或运行。JSON 中的 importedFrom 是来源记录，导入生成的来源前缀 ID 是稳定标识，不是实时数据依赖。卸载旧启动器前先退出 iLaunchPad 并复制自己的布局备份；兼容导入代码只用于帮助迁移用户，不代表品牌关联或运行依赖。

## 平台观察与参考 / Platform notes

旧 README 记录：此前本机调查为 macOS 27.2，系统目录未发现 Launchpad.app，仅有 Apps.app；Apple 原 Launchpad 帮助跳至 [View and open apps on Mac](https://support.apple.com/guide/mac-help/open-apps-in-spotlight-mh35840/mac)。这是迁移前已有观察，未在本次重新检测，不能推广为所有系统版本的恢复能力结论。

视觉参考保留在 [视觉设计](../../docs/visual-design.md)。既有官网精选评价不等于独立评测；先前独立评价站点访问受限，没有据此声称完全复刻。交互缺口和验收状态见根 README 与存量 check.md。
