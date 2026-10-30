# 当前技术架构

## 系统责任与边界

iLaunchPad 是一个 macOS GUI 进程，负责应用浏览、搜索、启动、布局整理、文件夹和安全移除应用包。客户端工程在 apps/ilaunchpad/；Sources/iLaunchPad 下所有模块一起编译、发布。无后端、远程 API、消息队列或独立 worker。LaunchOS 仅作为可选的外部只读布局来源；macOS 提供应用发现、启动、图标、壁纸和桌面交互。

业务链路为：用户输入 → 原生窗口/SwiftUI 状态 → AppKit 集合与拖拽编排 → LayoutStore 内存布局 → 本地 JSON。启动应用、卸载、壁纸读取经系统 API 跨出客户端边界。

## 模块拓扑与职责

客户端模块路径均相对 `apps/ilaunchpad/Sources/iLaunchPad/`。

| 模块 | 所有职责与依赖方向 |
|:---|:---|
| AppMain | AppDelegate 注册菜单、Carbon 快捷键和本窗口事件；WindowController 管理全屏无边框窗口、Dock 展示选项与焦点 |
| LaunchpadRootView | 编排搜索、当前页、编辑模式、文件夹、键盘选择；消费 LayoutStore，不另持久化布局 |
| NativeLaunchGrid | NSCollectionView 数据源/代理、图标复用、长按、拖拽源和目标；调用 LayoutStore 进行预览和移动 |
| PagingSurface | 一个屏幕宽度的原生裁剪容器承载全部页面；处理位移、边缘阻尼、速度预测与落页 |
| FolderOverlay / FolderMorphSurface | 组内网格、名称编辑、原生玻璃面板和连续展开变换 |
| DragTracking / FolderDragBoundary | 先路由容器边界，再计算格子位置；离开文件夹判断、停留和最终 drop |
| LayoutStore / Models | 页面、组、应用的唯一内存模型与保存入口；快照、移动、导入、扫描合并、隐藏 |
| LaunchOSImporter / ApplicationScanner | 外部 SQLite 只读投影；扫描三个应用根目录并按 Bundle ID 去重 |
| ApplicationDirectoryMonitor / ApplicationDiscoveryPolicy | 原生FSEvents目录变化通知去抖触发后台扫描；新项追加到首个不足35格的页面，所有页满才新建页 |
| ApplicationSearchEntry | 从应用名称、拼音、首字母、Bundle ID 生成派生搜索索引 |
| LaunchpadDesign / WallpaperBackdropView / VisualEffectView / AppIconView | 网格几何、图标缓存、壁纸模糊和原生材质；部分 SwiftUI 图标组件与 DragSupport 委托是现存辅助实现，主网格走 NativeLaunchGrid |
| ApplicationRemoval / ApplicationRemovalPolicy | 系统保护、可删除性与原生确认；确认后只用系统废纸篓 API 移动应用包，成功后清理布局 |
| LaunchpadSettingsView / LoginItemController | 外观偏好走AppStorage；登录项以SMAppService.mainApp为事实源，用户切换才注册/注销 |
| VisualResourceCache | 串行actor处理图标/壁纸解码与PNG缓存；只向UI交付不可变CGImage，不拥有布局 |


## 核心链路

### 启动、搜索和退出

启动时创建 LayoutStore：读取自身 JSON，失败则尝试 LaunchOS 只读迁移，再失败则建立空布局；归一化后后台扫描，MainActor按最新布局合并；拖拽中延后到提交/取消之后，过期扫描无效。AppDelegate识别系统登录启动事件并仅后台准备；普通启动显示窗口；--import-only 也会初始化并写入布局后退出，不是只读诊断模式。

唤起选择鼠标所在屏幕，保存原 presentationOptions 并隐藏 Dock；窗口获焦并自动聚焦搜索。搜索索引在后台任务生成，按名称完全相同、前缀、包含、拼音/首字母、Bundle ID 排序。隐藏应用不进索引。NSWorkspace 启动应用后 RootView 关闭启动台；失焦也立即关闭，恢复原 Dock 展示选项。窗口关闭通知会取消拖拽。

### 页面、文件夹与拖拽

分页容器按屏幕宽度移动；网格有自身留白，但裁剪边界在屏幕边缘。文件夹或搜索打开、App 拖动期间禁止普通手势翻页。文件夹按源图标位置展开，完成后允许内容命中，背景通过 within-window 模糊覆盖。

原生拖拽开始时 LayoutStore 保存快照，绑定稳定 DragPayload，保留拖拽源的生命周期，由稳定NSWindow的displayLink同步鼠标跟踪，随屏幕刷新能力调整范围并在结束时失效；原生validateDrop仍同步更新，同帧同点轮询可合并，最终drop永远重算。DragTracking 每次先发送 geometry 事件用于切页/文件夹退出，再发送 moved 事件进行当前容器内放置。非当前页、非当前文件夹与过渡暂停期的网格不参与路由，最终松手绕过暂停。

顶层文件夹只有可见圆角图标内接受加入，外围格子用于换位：顶层稳定 350ms 换位（组内排序仍为160ms）、图标内 120ms 选中、650ms 展开；普通 App 中心候选暂停外围换位，120ms突出、800ms临时合组并自动展开；未达阈值释放只普通落位。窗口左右 48pt 边缘停留 500ms 切到已存在的相邻页，之后暂停路由 320ms。文件夹退出有 20pt 容差、进入/接近记录及 220ms 退离等待。文件夹过渡暂停约 300ms。

previewMove / previewMoveToPage 根据 App 身份查找当前位置、分离并插入目标容器；组内排序使用 App ID，顶层排序使用 Group ID。松手经 DragTracking.drop 重新计算最终点并提交一次；失败、Esc 或隐藏窗口撤销。具体事务见 data-model.md。集合视图对重排提交所有变化索引的 move。

临时组内继续使用原生网格排序；真正退出面板先恢复建组前的局部布局，再继续外部位置路由。面板外释放不会保留临时组。新组合法提交后使用系统 NSTextField 聚焦并选中默认名称，输入/失焦/回车保存，Esc只结束编辑。文件夹减少到一项自动转换成普通图标，展开视图监听文件夹类型而非仅监听是否删除。

原生起拖后 LayoutStore 以 sessionID 与稳定 App ID 登记展示身份；实际跨容器前标记跨容器状态。NativeLaunchGrid 在创建、复用、配置和结束通知时统一刷新：跨容器拖动的 App 仅隐藏网格内容（图标、名称、编辑/选择装饰），保留 item 根视图、占位和命中布局，不操作鼠标拖拽影像或修改 move 算法。结束时清除身份并立即恢复内容；未跨容器及整个文件夹拖动沿用原行为。该显示逻辑的实机验收见 [拖拽规格](../sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/check.md)，不因构建成功宣称无重复。

LaunchpadCollectionView 与 NativeFolderMorphView 直接实现原生拖入/更新/准备/执行接收，分别覆盖网格及文件夹内边距；目标不依赖实时重排前的 item 索引。源 Coordinator 保留 NativeDragIdentity（布局会话 UUID、AppKit draggingSequenceNumber、起始 payload），目标校验同进程 move、序列和粘贴板 token，并检查当前容器及实际坐标；最终统一进入 DragTracking.drop，同步提交后才返回成功。已结束会话拒绝再次 drop，旧源结束回调不能撤销新会话。原有取消及 50ms 撤销兜底保留；没有改为在鼠标释放时无条件提交。原生接收的实机验收见 [拖拽规格](../sprints/sp-001-native-launchpad/specs/spec-005-drag-and-order/check.md)。

动态展开后 AppKit 可能仍向底层主页面发送当前拖拽回调。集合入口先更新几何；若当前文件夹与集合不一致，则把真实回调转交给同一窗口和 LayoutStore 下的当前展开面板。面板弱引用登记并独立验证圆角边界和会话，不能凭过期目的地或鼠标释放直接提交。

### 资源与首屏准备

ApplicationIconCache使用64MiB成本预算的NSCache和按身份去重的请求；未命中提供稳定占位，资源完成后仅更新当前绑定该App的原生图标。刷新取消旧代并串行清理派生磁盘缓存，迟到结果不写回。文件指纹每次重新读取，不复用URL缓存属性。

VisualResourceCache在用户Caches/local.ilaunchpad.app/VisualResources/v1保存128MiB预算PNG，按使用时间淘汰，损坏/写满回退生成。NSWorkspace图标拷贝仅在资源actor内调整和栅格化；壁纸复用CIContext，以源指纹、屏幕与模糊档位作键。UI仅做最终赋值和绘制。

RootView初次实例化当前页与邻页，未访问页保留整屏几何；访问过的页面继续保活，保护拖拽源/接收与中断动画。后台预热按当前页距离排序，重新显示复核资源，搜索索引独立生成。现有玻璃和意图参数不变。

### 编辑与移除

长按 550ms 进入编辑模式；图标、名称、文件夹材质和可见叉号使用同一相位抖动，点击应用编辑态不启动。系统位置/Cryptex、官方必需系统标识、自身、嵌套helper及重定向路径不允许卸载，不按全部Apple标识禁用独立应用。

允许卸载的目标必须位于/Applications或当前用户Applications、身份与Bundle一致且文件可删除。NSAlert默认取消，统一说明只把当前应用包移入废纸篓，不清理个人文稿、设置、缓存、共享容器或辅助文件，也不取消订阅。确认后重新解析路径、Bundle ID、可删除性及运行状态；不执行外部卸载器、shell命令或私有卸载API，不提权。

FileManager.trashItem成功才删除布局并执行容器收尾；取消、资格变化、运行中或移动失败均保留布局并反馈。通用外部卸载后的失效项同步仍归DATA-06。

## 安全与跨模块约束

所有布局修改在 MainActor；视图和搜索索引是消费者。内部 Swift 类型与 NotificationCenter 通知随同一产物发布，不另建公共契约。用户布局和偏好属于当前 macOS 用户，不提供多用户共享写入协议。

卸载拒绝系统必需组件、自身、系统应用目录、嵌套 app、符号链接重定向、不可删除和运行中应用；目标只允许 /Applications 与用户 Applications 范围。外部布局只读打开，不反写来源。卸载只调用 FileManager.trashItem，不执行外部卸载程序、拼接的 shell 命令或私有卸载API。

## 外部边界与技术选择

| 边界 | 当前定义与所有者 | 兼容及责任 |
|:---|:---|:---|
| LaunchOS SQLite 文件 | [导入接受定义](../assets/interfaces/launchos-layout-import.md)；第三方拥有源 schema | 客户端只支持 SQL 所列投影；由 spec-001 记录，不保证任意版本 |
| 自有 JSON | Models.swift Codable 与 LayoutStore 编解码 | 私有存储，无外部消费者；演进约束见 data-model.md |
| macOS API 与 Bundle | Apple SDK、应用 Info.plist | AppKit/SwiftUI/Carbon/CoreImage/SQLite3；最低 26.0，实际打包 arm64 |
| 自有网络/服务契约 | 不适用 | 无网络服务、外部 SDK 或消息生产者 |

