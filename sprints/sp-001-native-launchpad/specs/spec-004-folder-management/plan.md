# spec-004：文件夹管理

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- FolderOverlay.swift：内容、名称、外部点击
- FolderMorphSurface.swift：原生玻璃与形变/命中
- LaunchpadRootView.swift：源位置、当前组及开合代次
- LayoutStore.swift：建组/命名/移出/收尾；按职责与001/005/006串行修改
- LaunchpadDesign.swift、NativeLaunchGrid.swift：缩略预览与命中
- Tests/iLaunchPadTests/InteractionRegressionTests.swift：anchor与命中

## 实施/复原顺序

1. 复原单层数据和建组结果，接入统一打开/关闭回调。
2. 按原型复原组面板、within-window模糊、命名和组内导航。
3. 先按已明确的单成员自动解散规则统一容器收尾，覆盖拖拽/菜单/卸载入口；大容量导航另待D2确认。
4. 验证连续开合、动画中点击、文本输入和全部成员可访问。
5. 把实际几何和原生接收接口交给005完成连续拖拽集成。

## 本次补全顺序

1. LayoutStore.swift 提供受影响容器的统一收尾：完成一次完整成员操作后再判断零项/单项，保留幸存 App 与原组所在位置；不在启动/导入时全盘改写历史布局。菜单移出和卸载成功入口复用此规则，失败/取消不触发。
2. LaunchpadRootView.swift 与 FolderOverlay.swift 对“组删除或不再是文件夹”统一关闭；命名请求携带唯一请求标识和目标组，确认组仍存在且无活动拖拽后消费一次并聚焦选中。
3. FolderOverlay.swift 统一空白默认名、回车/失焦保存和 Esc 退出编辑；拖动期间不启动名称编辑。不得因取消拖拽/旧动画回调触发迟到命名。
4. 005 负责临时组创建、退出和最终提交后发出请求；本板块负责命名消费与单成员规则，006 仅接入移出/卸载后的同一规则，不改卸载权限策略。
5. 在 Tests/iLaunchPadTests/EditingRegressionTests.swift 加入成员收尾/取消/同组换位对照；聚焦及输入法用生产界面隔离样本验证。没有真实卸载授权时只验证隔离样本。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
