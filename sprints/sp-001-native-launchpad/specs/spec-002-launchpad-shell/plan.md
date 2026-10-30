# spec-002：唤起、关闭与系统集成

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- AppMain.swift：WindowController、AppDelegate、热键/输入/退出
- LaunchpadRootView.swift：显示通知、分层返回
- LaunchpadDesign.swift：展示状态与动效参数
- NativeLaunchGrid.swift：仅在 Dock 外部载荷方案获评审后接入

## 实施/复原顺序

1. 复原窗口/Dock/焦点和展示通知；默认不增加权限。
2. 验证输入法、设置/确认框输入优先，以及快速关闭再显示的代次保护。
3. 为 Dock 外部拖放确定载荷和显示策略并评审，保持内部 move 与外部 copy 语义分离。
4. 按 D1 决定是否扩展入口；未决定时保持明确不支持。
5. 用多屏、已有 App 切换、取消与正常退出验证 Dock 恢复；不以崩溃恢复作无证据承诺。

## 登录启动实施切片（SHELL-11）

1. 在 LoginItemController.swift 封装系统服务状态与注册/注销；LaunchpadSettingsView 仅通过007消费，不独立持久化状态。使用 Apple SDK 原生接口，保持部署下限和现有包身份。
2. 在 AppMain.swift 处理系统提供的登录启动事件、普通启动和 reopen；隔离测试启动原因策略。后台启动不显示全屏、不抢焦点、不隐藏 Dock。003资源准备接线不得迫使窗口可见。
3. 验证当前签名/安装路径下的真实系统结果；注册失败、需批准、外部禁用都如实返回。不能为“验证”直接注册用户真实登录项；仅用户主动切换时操作。
4. 在 Tests/iLaunchPadTests/LoginItemTests.swift 添加服务替身及启动原因用例；真实登录/退出需用户参与，模拟事件不等同真实登录验收。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
