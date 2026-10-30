# spec-005：连续拖拽与排序

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- LayoutStore.swift：会话/快照/身份/previewMove/finish
- NativeLaunchGrid.swift：源保活、位置路由、意图、网格接收、内容显示
- DragTracking.swift：身份验证、geometry→moved、最终drop
- FolderDragBoundary.swift：进入/退出几何
- FolderMorphSurface.swift、FolderOverlay.swift：实际面板/转交接收
- LaunchpadRootView.swift、LaunchpadDesign.swift：当前容器/几何/阈值
- Tests/iLaunchPadTests/DragTrackingTests.swift、EditingRegressionTests.swift：回归

## 实施/复原顺序

1. 固定可恢复的生产源码与隔离布局；先明确原路径和正常对照。
2. 按001/004接口复原模型事务、连续位置监听、意图和容器切换。
3. 接入会话级内容显示，不改root item透明度或无关重排算法。
4. 接入真实原生网格/面板接收及保留页面回调转交；身份和实际边界校验后同步提交。
5. 确认D4后补新页/容量策略；测试首末页、满页以及取消回退。
6. 用隔离断言、真实鼠标连续路径和用户确认分别记录结果；应用代码修改构建成功才按授权安装。

## 本次临时合组实施顺序

1. 保留已解决的连续进出组及回调转交作为正常对照；先在既有 DragTrackingTests.swift、EditingRegressionTests.swift 添加临时建组/退出/最终提交/全局取消的隔离用例。
2. LayoutStore.swift 添加临时组记录、建组前局部检查点和原子预览创建/撤销。与004的完整成员操作收尾共同执行，禁止中间状态触发单成员解散；不新增持久字段，不保存临时布局。
3. NativeLaunchGrid.swift 将普通 App 中心合组与外围换位设为互斥候选；稳定目标身份而非 indexPath 决定计时。中心120ms反馈、800ms创建，顶层外围350ms换位、组内160ms为已确认参数；已有文件夹选中/展开参数不改。
4. NativeLaunchGrid.swift / LaunchpadRootView.swift 在创建前测量目标位置并自动展开新组。沿用 FolderMorphSurface.swift 的真实面板接收和主页转交；FolderDragBoundary.swift / DragTracking.swift 在真正离开临时组时走局部撤销，再路由当前鼠标点。
5. DragTracking.swift 最终 drop 重算当前几何与目的地，临时组内提交一次再通知004命名；其他落点先还原临时合组。清理旧 merge 分支，避免同次释放二次建组；现有源保活、身份校验和取消兜底不放宽。
6. 核对异步展开/关闭/命名请求的会话和代次，确保已结束会话不再变更布局。临时组解散后重复悬停同一目标能重新开始。
7. 按check执行本次模型回归与生产UI隔离拖拽；通过必要构建后备份真实布局和已安装App，自动安装启动供用户验收。不顺带实现新页/容量、导入或其他板块缺口。

## 显示同步实施切片

NativeLaunchGrid.swift 中将会话 Timer 替换为窗口级 displayLink，必要的生命周期封装放在 DragTracking.swift；仍使用原接收、源保活与最后drop链路。显示回调仅驱动位置/意图检查，不把当前60Hz参数直接改成120Hz Timer。DragTrackingTests.swift 补时钟替身与重复通知、静止停留、源移出可视树、结束失效和迟到回调用例；高刷实机与真实跨组松手由check验收。禁止顺带调整用户已确认的意图参数和接收语义。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
