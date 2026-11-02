<p align="center">
  <img src="apps/ilaunchpad/Resources/AppIcon-preview.png" alt="iLaunchPad" width="148">
</p>

<h1 align="center">iLaunchPad</h1>

<p align="center"><strong>应用，各就其位。</strong></p>

<p align="center">
  面向现代 macOS 的本地原生应用启动台。<br>
  用分页、搜索、文件夹和连续拖拽，把熟悉的空间记忆带回来。
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-2D2D2D?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-1677FF"></a>
</p>

<p align="center">
  <a href="https://toketec.github.io/iLaunchPad/"><strong>官方网站</strong></a>
  · <a href="https://github.com/Toketec/iLaunchPad/releases/latest"><strong>下载最新版本</strong></a>
  · <a href="#从源码构建">从源码构建</a>
  · <a href="#功能与进度">开发进度</a>
  · <a href="#参与贡献">参与贡献</a>
</p>

> [!IMPORTANT]
> iLaunchPad 目前是开发预览版。核心功能已有可运行实现，但真实连续拖拽、登录启动和高刷新率表现仍有待完整验收。发布包采用本地签名，尚未进行 Developer ID 签名或 Apple 公证。

## 为什么是 iLaunchPad

| 找得快 | 整理不断手 | 数据留在本机 |
|:---:|:---:|:---:|
| 名称与拼音搜索、键盘选择、分页浏览 | 同页换位、跨页、进出文件夹、重叠创建新组 | 独立保存布局，不需要账户、订阅或云端应用清单 |

- **打开即用**：Option-Space 或 F4 唤起，启动应用后自动收起。
- **连续整理**：拖动中的预览、换位、切页、文件夹展开与落位保持在同一次交互里。
- **原生质感**：AppKit 应用网格、系统搜索框、玻璃材质与原生确认弹窗。
- **兼容迁移**：可只读导入旧版 macOS LaunchPad、LaunchOS 与 LaunchNext 布局；导入后完全使用 iLaunchPad 自己的数据。
- **没有旧布局也能开始**：无可导入数据时按当前已安装应用生成 Apple 默认风格布局，设置中也可随时重新初始化。
- **本地布局快照**：最多保存 3 份命名备份，恢复时自动清理已卸载项并补入新应用。
- **安全管理**：系统组件不显示移除入口；其他符合条件的应用经确认后只移到废纸篓。
- **性能优先**：后台扫描、图标与壁纸缓存、按页准备资源，并尊重“减少动态效果”。

## 下载与安装

从 [Releases](https://github.com/Toketec/iLaunchPad/releases/latest) 下载最新 ZIP，解压后将 `iLaunchPad.app` 拖入“应用程序”。

当前发布包面向 **Apple Silicon**，最低系统版本为 **macOS 26**。首次打开若被系统阻止，请在“系统设置 → 隐私与安全性”中查看系统给出的处理选项；本项目不建议关闭系统安全保护。

### 从源码构建

需要包含匹配 macOS SDK 的 Swift 6 工具链。在项目根目录执行：

```sh
./apps/ilaunchpad/Scripts/build-app.sh
open apps/ilaunchpad/dist/iLaunchPad.app
```

产物位于 `apps/ilaunchpad/dist/iLaunchPad.app`。构建脚本只生成 arm64 应用并采用 ad-hoc 签名。

## 日常使用

| 操作 | 方式 |
|:---|:---|
| 显示 / 隐藏 | Option-Space 或 F4（是否需要 Fn 取决于键盘设置） |
| 切换页面 | 双指横向滑动、点击页点或 Command-左右方向键 |
| 查找 / 启动 | 输入名称或拼音，方向键选择，Return 打开 |
| 整理应用 | 拖动图标；长按进入编辑模式 |
| 取消 / 返回 | Esc：依次取消拖拽、编辑、文件夹、搜索或窗口 |
| 调整偏好 | 设置中调整图标大小、名称、壁纸模糊、起始页、布局备份与登录启动 |

## 四款原创玻璃图标

<p align="center">
  <img src="apps/ilaunchpad/Resources/AppIcons/ocean.png" alt="玻璃蓝" width="112">
  &nbsp;&nbsp;
  <img src="apps/ilaunchpad/Resources/AppIcons/violet.png" alt="玻璃紫" width="112">
  &nbsp;&nbsp;
  <img src="apps/ilaunchpad/Resources/AppIcons/obsidian.png" alt="玻璃黑亮底" width="112">
  &nbsp;&nbsp;
  <img src="apps/ilaunchpad/Resources/AppIcons/porcelain.png" alt="玻璃白暗底" width="112">
</p>

设置中的“应用图标”可以即时切换四款主题。玻璃蓝是默认与安全回退样式；选择会持久化，并同步刷新 Dock、访达与 iLaunchPad 自己的应用目录，退出后不会回落。

## 你的布局，留在本机

```text
~/Library/Application Support/iLaunchPad/layout.json
~/Library/Application Support/iLaunchPad/layout-backups.json
```

`layout.json` 是当前布局，`layout-backups.json` 保存设置中创建的最多 3 份命名快照。恢复快照时会重新扫描应用目录：已卸载应用从当前布局移除，新安装应用追加到最靠近首页的空位；原快照不会被反写。图标和壁纸缓存可以重建，不属于布局数据。

### 从其他启动台迁移

如果本机尚无 iLaunchPad 布局、但存在兼容的 LaunchOS 数据库，首次打开会只读复制页面、文件夹与应用顺序。应用菜单也可分别恢复系统升级后遗留的旧版 macOS LaunchPad 数据，或选择 LaunchNext 导出的 JSON。若不存在任何可导入数据，iLaunchPad 会根据当前已安装应用生成 Apple 默认风格布局；之后也能在设置中确认后重新初始化。来源启动器无需继续安装或运行；兼容能力只处理数据，不复制对方代码、素材、文案或品牌设计。

### “卸载”会删除什么？

符合移除资格的应用会统一提示“移到废纸篓”。确认后只移动当前 `.app` 应用包；成功才从布局移除，取消或失败均保留。iLaunchPad 不自行清理文稿、设置、缓存、共享容器或辅助文件，也不会取消订阅。

## 不只公开代码，也公开开发依据

一个启动台看起来只是几页图标，真正困难的是让拖动、换位、进组、出组、切页和最终落位成为一次连贯操作。

iLaunchPad 使用 [SpecRocket](https://github.com/Toketec/SpecRocket) 管理产品规则、实现边界和验收证据：

```text
功能清单 → 交互规则 → 模块规格 → 实现 → 验收证据
```

建议从 [冲刺 1 功能总览](sprints/sp-001-native-launchpad/docs/functional-overview.md) 开始，再查看 [连续拖拽规格](sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/requirements.md) 与 [验收记录](sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/check.md)。规格让“目标、实现、自检和人工验收”保持可区分，而不是替项目宣称没有 bug。

## 功能与进度

以下“已有”表示代码中存在实现，不等于该板块已经完成整体验收。

| 板块 | 当前状态 |
|:---|:---|
| 应用目录 / 布局 / 导入 | 已有完整目录对账、Apple 默认风格初始化、最多 3 份本地快照，以及旧版 macOS LaunchPad、LaunchOS、LaunchNext 只读迁移；真实来源样本与设置交互仍需人工验收 |
| 唤起与系统集成 | 已有快捷键、全屏窗口、Dock 与登录启动接线；登录启动仍待真实环境复验 |
| 浏览 / 分页 / 搜索 / 启动 | 主要链路、后台位图缓存与按页准备已实现；完整帧时和输入组合待验 |
| 文件夹管理 | 已有单层组、玻璃开合、命名、单成员自动解散与临时合组 |
| 连续拖拽 / 排序 | 进出组、展开换位、拖出撤销与松手命名已实现；满页和组合回归仍需收口 |
| 编辑 / 应用管理 | 已有长按抖动、系统保护、移到废纸篓、隐藏和访达定位 |
| 外观偏好 | 已有图标、名称、壁纸、起始页与登录启动设置；四款图标可即时切换 |

当前版本为 **2.3.6 / build 15**。发布构建已通过；标准 `swift test` 仍受开发环境缺少 Swift Testing 模块影响，不能用局部检查替代真实登录、连续鼠标操作或高刷呈现验收。

## 参与贡献

欢迎提交真实使用中的卡顿、交互偏差和边界问题，也欢迎补充复现、测试与文档。

- 报告问题时请提供系统版本、屏幕配置、起始布局和完整操作顺序。
- 拖拽问题尤其需要说明是否松手、停留位置和文件夹是否已展开。
- 附截图或录屏时请遮盖个人信息；通常不需要上传真实布局文件。
- 行为变化应回到所属功能规格；实现、自检与人工验收分别记录。

测试入口（需要包含 Swift Testing 的工具链）：

```sh
swift test --package-path apps/ilaunchpad
```

## 项目地图

- [产品官网](https://toketec.github.io/iLaunchPad/) · [官网规格](sprints/sp-002-brand-and-website/specs/spec-002-product-website/requirements.md)
- [产品概览](docs/product-overview.md) · [非功能约束](docs/non-functional-reqs.md) · [视觉语言](docs/visual-design.md)
- [冲刺 1：启动台功能](sprints/sp-001-native-launchpad/docs/functional-overview.md) · [业务规则](sprints/sp-001-native-launchpad/docs/SPRINT-features.md)
- [冲刺 3：默认布局与本地备份](sprints/sp-003-layout-backups/docs/functional-overview.md) · [实现规格](sprints/sp-003-layout-backups/specs/spec-001-layout-profiles/requirements.md)
- [用户场景](sprints/sp-001-native-launchpad/docs/user-scenarios.md) · [业务流程](sprints/sp-001-native-launchpad/docs/business-flows.md) · [界面结构](sprints/sp-001-native-launchpad/docs/prototypes/prototypes.md)
- [模块职责](architecture/architecture.md) · [数据模型](architecture/data-model.md) · [运行恢复](architecture/runtime.md)
- [构建与恢复手册](assets/manuals/build-and-recovery.md) · [协作规则](AGENTS.md)

## 许可与致谢

[MIT License](LICENSE)。欢迎使用、修改、分发与商业使用；请保留版权和许可声明。

iLaunchPad 是独立开源项目，不隶属于 Apple 或任何第三方启动器，也不获得其授权或背书。应用中展示的第三方品牌、图标和系统组件权利归各自权利人，不因本项目采用 MIT 而重新授权。

如果这个项目帮你找回了熟悉的使用习惯，欢迎点亮 Star、分享给朋友，或用一份清楚的复现帮助它继续变好。
