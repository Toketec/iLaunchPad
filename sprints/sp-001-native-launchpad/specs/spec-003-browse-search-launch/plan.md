# spec-003：浏览、分页、搜索与启动

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- LaunchpadRootView.swift：页面/搜索/选择/启动编排
- NativeLaunchGrid.swift：网格与命中/激活；不得顺手改拖拽算法
- PagingSurface.swift：单裁剪面和落页
- NativeSearchField.swift、ApplicationSearchEntry.swift：输入与索引
- AppMain.swift：局部键盘/滚轮通知
- Tests/iLaunchPadTests/InteractionRegressionTests.swift：分页和命中用例

## 实施/复原顺序

1. 按现有原型复原网格、单容器分页与尺寸；接入统一输入通知。
2. 复原索引、原生输入、结果与空态，覆盖输入法和大量结果。
3. 串通点击、回车、右键启动及失败反馈，统一隐藏项过滤。
4. 用普通翻页/快速反向/动画中点击/搜索/组展开/编辑状态组合验证。

## 缓存与首屏实施切片（FIND-15）

1. 在 LaunchpadDesign.swift 的 ApplicationIconCache 与新增 VisualResourceCache.swift 实现可注入缓存目录、指纹、预算、失效代次及去重队列；在 Tests/iLaunchPadTests/VisualResourceCacheTests.swift 用临时文件覆盖命中、失效、损坏、淘汰与迟到结果。不能以用户真实布局为fixture。
2. NativeLaunchGrid.swift 的图标/缩略图绑定消费内存命中和按身份校验的异步结果，避免复用单元格串图；不能改重复内容抑制和原生拖拽影像。
3. WallpaperBackdropView.swift 通过同一派生缓存服务获取已处理背景，后台复用CIContext；屏幕、文件、档位变化取消过期更新，保留007现有玻璃层级。
4. LaunchpadRootView.swift / PagingSurface.swift 优先当前页和邻页，其他页保持几何占位；保留拖拽源与目的页，不因离开可见范围拆掉仍在路由的原生接收器。Tests/iLaunchPadTests/InteractionRegressionTests.swift 补切页/快速反向/关闭重开检查。
5. 接入001的后台扫描和002的静默准备；首次资源缺失使用稳定占位并局部更新，不以空白画面冒充启动提速。必要时在上述源文件加入可关闭的 os_signpost 阶段测量。
6. 分别记录无缓存冷启动、磁盘热缓存新进程、常驻唤起的可交互时间与主线程长任务；与同布局/屏幕基线比较。007收口帧时与视觉验收，不能用微基准相加当作端到端耗时。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
