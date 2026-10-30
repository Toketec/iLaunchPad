# iLaunchPad

<img src="apps/ilaunchpad/Resources/AppIcon-preview.png" alt="iLaunchPad 白底石墨火箭初始图标" width="112">

**应用，各就其位。**

iLaunchPad 是一个本地运行的 Mac 应用启动器。用图标找到应用，用文件夹保留分类，用一次连续拖拽完成整理——让你已经记住的位置继续有用。

稳定的空间记忆，现代 macOS 的原生材质。不需要账户，不需要订阅，也不需要把应用列表上传到服务器。


## 为熟悉的操作，补齐细节

- **打开，找到，启动。** 全屏分页、名称与拼音搜索、键盘选择；启动应用后退出启动台，回到工作。
- **整理不中断。** 同页换位、跨页、进入与离开文件夹；拖动时预览，松手时保存。两个应用重叠停留可预览新组，拖出则撤销，放入后再命名。
- **像 Mac 一样工作。** AppKit 应用网格、原生搜索框、系统玻璃与确认弹窗，配合 SwiftUI 组织界面和偏好设置。
- **排序属于你。** 独立保存页面、文件夹与应用顺序；可一次性迁移兼容的 LaunchOS 布局，日常使用不再依赖外部启动器。
- **管理有分寸。** 长按进入编辑模式；系统组件不显示卸载按钮，可卸载应用统一确认后移到废纸篓。不偷偷清理个人数据。
- **减少重复准备。** 后台扫描、图标与壁纸缓存、按页准备资源；拖拽跟随窗口显示刷新，支持减少动态效果偏好。

> 当前为开发预览，尚未完成全部真实交互验收。macOS 26 以前系统 Launchpad 的布局导入属于规划目标，**尚未实现**；登录启动和实际高刷表现也仍有验证缺口，见下方进度。

## 快速开始

### 从源码构建

需要 Apple Silicon Mac、macOS 26 或更新系统，以及包含匹配 macOS SDK 的 Swift 6 工具链。当前打包脚本只生成 arm64 应用。

在项目根目录执行：

```sh
./apps/ilaunchpad/Scripts/build-app.sh
open apps/ilaunchpad/dist/iLaunchPad.app
```

产物位于 `apps/ilaunchpad/dist/iLaunchPad.app`。日常使用可将其复制到“应用程序”文件夹。脚本采用本地 ad-hoc 签名，不等同于 Developer ID 签名或 Apple 公证；这里不提供关闭系统安全保护的安装指引。

### 日常使用

| 操作 | 方式 |
|:---|:---|
| 显示 / 隐藏 | Option-Space 或 F4（是否需要 Fn 取决于键盘设置） |
| 切换页面 | 双指横向滑动、点击页点或 Command-左右方向键 |
| 查找 / 启动 | 输入名称或拼音，方向键选择，Return 打开 |
| 整理应用 | 拖动图标；长按进入编辑模式 |
| 取消 / 返回 | Esc：先取消拖拽，再按编辑、文件夹、搜索、窗口逐层退出 |
| 调整偏好 | 设置中调整图标大小、名称、壁纸模糊、起始页与登录启动；“应用图标”可选十款火箭 |

构建、备份与恢复细节见 [使用手册](assets/manuals/build-and-recovery.md)。

## 你的布局，留在本机

```text
~/Library/Application Support/iLaunchPad/layout.json
```

这是 iLaunchPad 自己的布局文件。已有有效布局时，应用直接读取自己的文件。备份与恢复均应先退出 iLaunchPad；目前没有自动布局备份。图标和壁纸缓存可以重建，**缓存不是布局备份**。

### 从 LaunchOS 迁移

如果本机尚无 iLaunchPad 布局、但存在兼容的 LaunchOS 数据库，首次打开会只读复制页面、文件夹与应用顺序；之后只使用 iLaunchPad 自己的 JSON，不要求原启动器继续安装或运行。应用菜单也保留“从 LaunchOS 恢复布局”，主动使用时会先确认覆盖。该能力只做数据兼容，不复制对方代码、素材、文案或品牌设计。

### “卸载”会删除什么？

系统组件、Safari、自身和嵌套辅助应用等受保护，不按 `com.apple.*` 一律拦截独立安装的 Apple 应用。其他具备文件删除资格的应用统一提示“移到废纸篓”，确认后只移动当前 `.app` 应用包；成功才从布局移除，取消或失败均保留。

iLaunchPad 不自行清理文稿、设置、缓存、共享容器或辅助文件，也不会取消订阅；清倒废纸篓前可以恢复应用包。卸载资格与安全规则见 [应用管理规格](sprints/sp-001-native-launchpad/specs/spec-006-edit-and-remove/requirements.md)。

## 不只公开代码，也公开开发依据

一个启动台看起来只是几页图标，真正难的是连续操作：拖着应用进入文件夹、等待展开、继续换位、再拖出来，最后松手。这不是五个互不相干的动作，而是一次必须保持一致的交互。


```text
功能清单 → 交互规则 → 模块规格 → 实现 → 验收证据
```

你可以沿着这条线查看“为什么这样做”，也可以检查哪些只是目标、哪些已有代码、哪些真正通过了人工验收。SpecRocket 在这里的价值是让遗漏和变更可见，而不是替项目宣称没有 bug。

建议从 [功能总览](sprints/sp-001-native-launchpad/docs/functional-overview.md) 开始，再看 [连续拖拽规格](sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/requirements.md) 与 [验收记录](sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/check.md)。

## 功能与进度

冲刺 1 的目标是补齐基础原生启动台能力。以下“已有”表示存在实现，不等于整板块完成验收。

| 板块 | 当前粗粒度进度 |
|:---|:---|
| 应用目录/布局/导入 | 已有本机扫描、安装目录自动发现、优先填入靠前空位页、保存和 LaunchOS 只读迁移；macOS 26 以前系统 Launchpad 导入未实现，已明确纳入目标 |
| 唤起与系统集成 | 已有快捷键、窗口、Dock及登录启动接线；本机服务返回notFound，未自动注册，实际开启/登录待验；拖至Dock仍有缺口 |
| 浏览/分页/搜索/启动 | 已有主要链路、后台位图缓存和按页准备；完整启动/帧时及输入组合待实机验收 |
| 文件夹管理 | 已有单层组、玻璃开合与命名；大容量导航待明确；已实现单成员自动解散和新组松手命名，待实机验收 |
| 连续拖拽/排序 | 进组展开后换位、停留松手问题已由用户确认解决；临时合组展开/拖出撤销/松手命名已实现，待实机验收；新页/满页和组合回归仍需收口 |
| 编辑/应用管理 | 已有长按、同步抖动、系统保护、统一废纸篓卸载、隐藏和访达；真实移除仍只允许用可丢弃样本验收 |

当前包标识为 **2.3.2 / build 12**。开发环境缺少 Swift Testing 模块；当前发布构建通过，本次统一废纸篓资格另执行8项生产策略断言。既有模块曾通过替代入口执行定向检查，但这不代表标准 `swift test` 已通过，也不替代真实登录、连续鼠标操作或120Hz呈现帧时验收。详见各模块 `check.md`。

全局捏合、热角、Screen Time/游戏控制器等深度集成范围尚未决定；多选批处理不在当前基础功能目标。当前没有旧系统布局解析器，不把新补的导入需求当作已支持。

## 参与贡献

欢迎反馈真实使用中的卡顿、交互偏差与边界问题，也欢迎补充复现、测试和文档。

- 报告问题时，请提供系统版本、屏幕配置、起始布局和完整操作顺序；拖拽问题尤其需要说明有没有松手、在哪停留、文件夹是否已经展开。
- 附截图或录屏时，注意遮盖个人信息；通常不需要上传包含完整应用列表的真实布局文件。
- 修改前先找到所属功能板块。行为变化同步规格，修复补充回归场景；实现、自检与人工验收分别记录。
- 新的独立功能先讨论边界，不为每个修复扩建规格。协作入口见 [AGENTS.md](AGENTS.md)。

测试入口（需要包含 Swift Testing 的工具链）：

```sh
swift test --package-path apps/ilaunchpad
```

## 文档入口

- [产品概览](docs/product-overview.md) · [非功能约束](docs/non-functional-reqs.md) · [视觉语言](docs/visual-design.md)
- [冲刺 1：启动台功能与7个规格](sprints/sp-001-native-launchpad/docs/functional-overview.md) · [业务规则](sprints/sp-001-native-launchpad/docs/SPRINT-features.md)
- [用户场景](sprints/sp-001-native-launchpad/docs/user-scenarios.md) · [流程](sprints/sp-001-native-launchpad/docs/business-flows.md) · [原生界面结构](sprints/sp-001-native-launchpad/docs/prototypes/prototypes.md)
- [模块职责](architecture/architecture.md) · [数据模型](architecture/data-model.md) · [运行恢复](architecture/runtime.md)
- [拖拽验收及已有修复证据](sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/check.md)
- [LaunchOS 兼容导入定义](assets/interfaces/launchos-layout-import.md) · [协作规则](AGENTS.md)

功能清单回答“做什么”，SPRINT-features回答“怎样表现”，规格requirements/plan回答“怎样落地”，tasks/check记录“做到哪、验证了什么”。缺陷归原功能板块；当前架构只写真实运行能力。

## 许可与致谢

[MIT License](LICENSE)。欢迎使用、修改、分发与商业使用；请保留版权和许可声明。

iLaunchPad 是独立开源项目，不隶属于 Apple 或任何第三方启动器，也不获得其授权或背书。项目公开传播只使用自身代码、文案与视觉资产。应用图标取自本机已安装的应用，相关品牌、图标和系统组件的权利归各自权利人，不因本项目采用 MIT 而重新授权。

如果这个项目帮你找回了熟悉的使用习惯，欢迎分享，也欢迎用一份清楚的复现帮助它变得更好。
