# spec-002：唤起、关闭与系统集成

## 产品依据与架构落地边界

- 细功能：SHELL-01～11，逐项定义见 [功能清单](../../docs/functional-overview.md)；业务规则见 [SPRINT-features](../../docs/SPRINT-features.md)。
- 架构基线：[模块职责](../../../../architecture/architecture.md)、[数据模型](../../../../architecture/data-model.md)、[运行与偏好](../../../../architecture/runtime.md)。
- 进入状态：已有无边框窗口、Option-Space/F4、Dock presentationOptions、失焦关闭和窗口内 magnify。没有向 Dock 导出应用或全局捏合唤起实现。
- 实现边界：存量与新增切片在同一功能板块维护；执行、差距与验收证据见tasks/check，不由接口存在推断全部能力完成。
- 退出目标：常规显示/关闭、焦点和 Dock 恢复可靠，支持的多屏与输入入口可验收；Dock 导出有明确安全方案，深度系统集成范围经决定。

## Context Contract

- 依赖 spec-001 的 LayoutStore、错误反馈与持久布局；窗口只消费，不自存排序。
- 关闭发出 launchpadDismissed；拖拽存在时由其事务所有者撤销。
- 偏好键/默认值先按 runtime 使用，设置入口最终由 spec-007 收口。

## 局部设计与复原约束

### 窗口和生命周期

AppMain 中 LaunchpadWindowController 选择鼠标所在 NSScreen（回退 main），创建透明无边框窗口，覆盖屏幕 frame；窗口重用，collectionBehavior 保留跨 Space/全屏辅助能力，不能据此声称所有 Space 已验收。

show 保存 NSApp.presentationOptions，临时 hideDock、激活窗口并通知 launchpadPresented。hide 在正常动画后或失焦立即 orderOut，再恢复原配置；动画 completion 使用代次防止旧关闭覆盖新显示。退出也恢复配置，不能永久修改 Dock 偏好。

AppDelegate 处理再次打开、F4/Option-Space、退出和失焦。快捷键注册失败目前没有用户提示；系统冲突与特殊键盘必须单测，不能由注册调用存在推断成功。

### 输入与分层返回

仅截获本启动台窗口输入，模态框与输入法 marked text 优先；Command-左右用于翻页，其他 Command 快捷键交系统。RootView 的 escape/backgroundTapped 按业务优先级返回；仅键盘选择不关闭。

窗口内 magnify 可交互关闭并在取消时恢复；beginInteractiveReveal 等辅助函数存在不代表已有全局触控板入口。全局手势/热角属 D1，未决前不添加全局监听或申请权限。

### Dock 外部接收

SHELL-09 是基础对照缺口。当前原生拖拽仅 local move 和内部文本 token，且打开时隐藏 Dock，不能直接实现跨进程添加。后续必须确认 Dock 呈现时机、外部载荷、源布局保持及取消语义，再评审该板块方案；不能把内部跨组移动变成删除/搬走应用。此处不伪造 Dock 接收契约。

### 登录启动与后台待命

SHELL-11 使用 ServiceManagement.SMAppService.mainApp 注册/注销当前应用的登录项，不手写 LaunchAgent、不安装守护进程、不申请管理员权限。仅用户明确打开设置开关时注册；系统状态为唯一事实，不添加一个可能失真的 UserDefaults 开关。

新增 LoginItemController.swift 提供状态读取、异步设置、失败反馈和打开系统登录项设置的入口。状态区分 enabled、notRegistered、requiresApproval、notFound；启动、操作结束和应用重新激活时读取，注册失败保持真实状态。更换安装包或签名后可能需要系统重新批准，必须反馈，不绕过。

AppDelegate 从系统启动事件识别登录启动原因；不能用“已开启登录项”判断本次是否静默，也不使用父进程猜测。登录启动初始化服务与后台资源准备，但不调用显示/激活窗口、不修改 Dock presentationOptions。普通启动/再次打开沿用现有显示入口。若当前 SDK 无法可靠识别启动原因，暂停该路径并回到评审，不能交付手动打开也不显示的版本。关闭窗口仍复用进程，显式退出后不自动拉起。

## 临时边界与收口

没有新增Mock、后台服务或临时工具。存量实现保留；未实现/未决部分由本规格负责补齐，具体局部方案经评审后才能编码。用户已确认7个板块的拆分，不等于全部缺口技术方案已批准。不会用新bug规格绕开本板块维护。

## 验收出口

逐项执行 check.md，并完成场景 U01、U08、U15、U16、U17。实现事实、隔离测试、真实系统交互和用户确认分别记录。任何未实现基础功能、未确认边界或未执行验收都不能标整板块完成。
