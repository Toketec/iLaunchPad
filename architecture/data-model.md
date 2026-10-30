# 当前数据模型

## 数据权威与归属

| 数据 | 所有者/事实源 | 用途与写入边界 |
|:---|:---|:---|
| 本机布局 | LayoutStore；Library/Application Support/iLaunchPad/layout.json | 唯一持久化布局，应用自行读写 |
| LaunchOS 排序 | 第三方 LaunchOS.sqlite | 可选的一次性只读迁移来源；不是导入后实时同步源 |
| 应用安装、名称、路径、Bundle ID | 文件系统、Bundle 与 NSWorkspace | 扫描补充/启动解析；布局缓存信息不代表应用仍存在 |
| 偏好与最后页面 | UserDefaults / AppStorage | 独立于布局文件；键与默认值见 runtime.md |
| 搜索索引、文件存在性 | 内存派生数据 | 可重新计算，不作为持久化事实 |
| 图标、处理后壁纸 | 内存与用户Caches的派生PNG | 指纹失效、容量淘汰，不能恢复或覆盖排序 |
| 登录启动配置 | macOS SMAppService.mainApp | 用户主动注册/注销，界面读系统状态，不存第二份布尔值 |
| 拖拽快照、目的地、计时 | LayoutStore 与 Coordinator | 进程内临时状态，不写文件 |

## 实体与关系


LaunchLayout 包含有序 LaunchPage；每页包含有序 LaunchGroup；每组包含有序 LaunchApp。无嵌套文件夹。普通组通常只有一个 App，文件夹有多个 App；成员移动后受影响文件夹剩一项转普通组，零项移除；起拖快照保留恢复身份。数组顺序就是展示顺序，不另维护 order 字段。

LaunchApp 的 id 是布局身份，Bundle ID 用于系统解析与去重，path 支持普通路径和 file URL，hidden 控制隐藏。Group ID 与 App ID 不可互换；外部导入的回退 ID 仅用于稳定身份，扫描新增 App 使用 installed-BundleID，组/页可使用 UUID。

LaunchLayout.version 当前默认 1，importedFrom/importedAt 只表示导入来源与时间，不是操作日志。字段、类型、必选性以 [Models.swift](../apps/ilaunchpad/Sources/iLaunchPad/Models.swift) 为可执行定义；不另外维护重复字段 schema。

## 初始读取与导入

有可解码自身 JSON 时使用之；否则尝试 LaunchOS 只读迁移；失败则建立至少一张空页。normalize 按非空 Bundle ID、否则 App ID 全局去重，删除空组；扫描 /Applications、/System/Applications、用户 Applications 中 Bundle ID 未见且路径未见的 App，逐个追加至最靠近首页且不足35格的页面末尾，全部满才新建页，不移动已有项。

[LaunchOS 投影](../assets/interfaces/launchos-layout-import.md)只描述当前已接入的兼容源。菜单手动恢复会二次确认，然后替换布局、normalize 并保存；不是合并当前排序。扫描后台执行，只追加新增应用，不自动清除失效记录。结果按最新布局去重合并，拖拽期间暂存，提交/取消完成后再追加保存；刷新/成功导入更新代次，旧结果不生效。

旧系统 Launchpad 数据属于另一个外部来源；当前没有适配器或经验证的接受定义。支持目标（macOS 26 以前的本机遗留数据/备份）在 [spec-001](../sprints/sp-001-native-launchpad/specs/spec-001-app-library-layout/requirements.md)，不将目标解析关系写成本文件的当前运行模型。

## 预览事务与状态

静止 → beginDragPreview 保留布局值快照并生成 sessionID → 持续修改内存布局 → finishDragPreview：
- commit=true：清除快照，通知所有网格结束，再清理空组/空页并原子保存。
- commit=false：清除快照并通知结束，再恢复起始快照。
- 没有快照时再次 finish 不产生效果；保存和 cleanAndSave 在预览期间直接返回。

DragPayload 记录起始来源；draggedAppID 从快照解析顶层普通组的 App，允许原组已经因跨容器移动消失。previewMove 先从全部组移除该 App，再插入目标文件夹；previewMoveToPage 在 App 已是普通组时返回当前组，否则移出文件夹并创建普通组。组外起源复用原 Group ID，组内起源使用 drag-AppID。文件夹内移动按 App ID 排序，组外按当前 Group ID 排序。

跨容器移动使用布局副本完成移除、源组收尾和目标插入，再发布完整预览；受影响源组零项移除、一项转换为同一 Group ID 的普通组，剩余 App 保持原组位置。菜单移出和卸载成员后的收尾使用同一规则；同组重排不在中间移除时解散。取消还原起拖快照。不在启动时批量改写未参与操作的历史单成员组。

beginMergePreview 保存本次合组前的当前预览作为局部检查点，在目标位置原子创建临时两项组，同时保留展开源矩形。discardMergePreview 只还原该检查点，保留此前已完成的预览换位；全局取消仍使用起拖快照。临时组内合法松手后清除临时元数据、提交布局，发布一次带 sessionID/folderID 的命名请求；消费后清除，新拖拽使旧请求失效。临时记录及命名请求均不持久化。

## 持久化、一致性与审计

LayoutStore 是 MainActor 单一写入口。JSON 使用 prettyPrinted/sortedKeys、ISO8601 日期，Data.write(.atomic) 替换文件；无数据库、SQL migration、事务日志、跨进程文件锁或多实例冲突合并。原子写不等于多进程事务。

目标不变量是 App 唯一归属，normalize 在启动和手动导入执行，不是每次拖拽帧去重器。跨容器视觉状态以会话和稳定 App ID 单独管理，不能把鼠标影像与网格重复绘制直接推断为数据重复。测试与实机证据归 spec-005/check。内存预览可撤销，但崩溃后仅保留上次已保存布局。

卸载先通过系统废纸篓 API 移动应用包，成功后才清除模型记录并保存；取消、资格复验失败或移动失败均不改布局。文件系统与 JSON 不是同一个事务；布局写失败时记录 lastError，没有自动补偿把应用包移回原位。无用户操作审计记录，只有导入来源元信息。

## 演进与恢复

Codable 是现有序列化基线；没有按 version 分发的迁移器或明确拒绝未来版本逻辑。新增必需字段、重命名字段和改变 ID 语义前必须补兼容读取策略并在负责规格中验收。未知字段可能被忽略；缺少必需字段会解码失败。

当前启动读取失败会走导入/扫描并保存，因此坏文件可能被新的结果覆盖；没有自动隔离坏文件。恢复操作前应先退出应用并备份 layout.json 与偏好；恢复有效 JSON 后重启，或由用户明确选择 LaunchOS 恢复。不要把迁移工程目录与迁移用户布局混为一谈。
