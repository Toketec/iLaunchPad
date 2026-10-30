# spec-006：编辑模式与应用管理

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。EDIT-02、EDIT-04～07的统一废纸篓方案及同步抖动已获用户实施确认；仅文档整理仍不触发构建或安装。

- NativeLaunchGrid.swift：longPress、编辑显示、命中、右键菜单；叉号与图标使用同相位抖动
- ApplicationRemoval.swift：资格、统一确认、确认后复验及系统废纸篓操作
- ApplicationRemovalPolicy.swift：纯路径与系统保护策略
- AppMain.swift：不再维护外部卸载返回核对入口
- LayoutStore.swift：isEditing、隐藏/恢复、移除布局、菜单移出
- LaunchpadRootView.swift：完成/返回和激活互斥
- Tests/iLaunchPadTests/EditingRegressionTests.swift：可复用模型断言
- Tests/iLaunchPadTests/ApplicationRemovalTests.swift：隔离路径与系统保护资格

## 实施/复原顺序

1. 复原编辑态与长按/拖动协调，保持003普通激活语义。
2. 复原静态资格、统一废纸篓确认和确认后复验；安全拒绝用隔离路径用例先行。
3. 按004统一容器收尾，补隐藏项恢复和菜单作用域。
4. 在用户授权的可删除样本上验证取消/成功/运行中/路径变化，不操作真实个人应用。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
