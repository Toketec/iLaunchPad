# spec-001：应用目录、布局保存与多来源导入

## 产品依据与架构落地边界

- 细功能：DATA-01～14，逐项定义见 [功能清单](../../docs/functional-overview.md)；业务规则见 [SPRINT-features](../../docs/SPRINT-features.md)。
- 架构基线：[模块职责](../../../../architecture/architecture.md)、[数据模型](../../../../architecture/data-model.md)、[运行与偏好](../../../../architecture/runtime.md)。
- 进入状态：已有本机应用扫描、JSON 读取保存和 LaunchOS 固定路径只读导入。本次增加旧版系统遗留数据库与 LaunchNext JSON 的明确入口；覆盖前自动备份与完整结果摘要仍未实现。
- 实现边界：存量与新增切片在同一功能板块维护；执行、差距与验收证据见tasks/check，不由接口存在推断全部能力完成。
- 退出目标：能够稳定发现应用、保留/恢复布局，明确选择 LaunchOS、LaunchNext JSON 或 macOS 26 以前系统 Launchpad 来源；校验后安全替换，失败不损坏原布局。三类来源各自有接受定义，新增两类具有隔离样本检查。

## Context Contract

- 无上游功能规格；采用 architecture 三文件中的单进程、MainActor、LaunchLayout 基线。
- Models.swift 是自身 JSON 类型权威；三类外部来源分别使用独立接受定义，不互相复用字段关系。

## 局部设计与复原约束

### 目录和身份

ApplicationScanner 扫描 /Applications、/System/Applications、当前用户 Applications；跳过隐藏文件和 .app 包内部，读取 Bundle ID/显示名，按本地化名称排序。LayoutStore.normalize 按非空 Bundle ID、否则 App ID 去重。普通组/文件夹/页的身份与 App ID 分开；数组次序代表排序。

LayoutStore.groups(on:)、allApps()、group(id:) 是消费者入口；resolvedURL 先检查路径，再由 NSWorkspace 按 Bundle ID 解析。刷新只补未见 Bundle ID/路径的 App，不改旧位置；逐个追加到首个不足35格的页面末尾，全部满才新增页。ApplicationDirectoryMonitor以原生FSEvents监听三个扫描根目录及子目录，主队列接收事件、1秒去抖后台扫描，并在5秒后补一次核对以覆盖安装过程；目录事件同时失效图标内存/磁盘缓存，现有网格收到通知后按资源指纹重新取图。每次唤起补充核对（20秒节流，扫描中不重启），呈现时优先读取运行中应用的当前图标。仅生产Store启动监听，隔离测试不监听真实目录；仍沿用代次及拖拽延后合并。外部卸载同步不属于此次补入能力。

### 自有布局与保存

Models.swift 的 LaunchLayout/LaunchPage/LaunchGroup/LaunchApp 是可执行序列化事实。自身有效 JSON 优先；当前失败后仍只自动尝试 LaunchOS，再建立空页、normalize、扫描和保存。旧版系统与 LaunchNext 为用户主动选择，避免多来源静默覆盖。此链路会覆盖不可解码的旧文件，不满足 DATA-14 的保留要求。

save 使用 JSON 编码和原子替换；预览期间禁止保存，快照/拖拽事务的具体实现归 spec-005。导入成功、命名、隐藏、移除等共同使用唯一保存入口。不得把原子文件写入描述成文件系统与应用卸载的跨操作事务。

### 三种来源的边界

- LaunchOS 当前输入与字段以 [唯一接受定义](../../../../assets/interfaces/launchos-layout-import.md) 为准，保持只读。现有 SQLite 循环未检查中途读取失败，完整性处理需补齐。
- macOS 26 以前系统 Launchpad 当前读取 `DARWIN_USER_DIR` 下的升级遗留 SQLite，只接受 apps/groups/items 传统结构；页、文件夹与应用映射见 [接受定义](../../../../assets/interfaces/legacy-launchpad-layout-import.md)。源不存在或结构不兼容时拒绝恢复，不修改系统库。
- LaunchNext 当前只接受用户选择的官方 JSON 导出，兼容 `launchNext.layout/items` 与较早 `pages` 两种投影；映射与空槽边界见 [接受定义](../../../../assets/interfaces/launchnext-layout-import.md)。不直接读取其 SwiftData 存储。
- 三来源先独立解析为候选 LaunchLayout，再进入现有 normalize、保存与后台扫描链路。主动导入均先确认覆盖；解析失败或取消不得触碰当前布局。覆盖前自动恢复副本、无法匹配摘要仍是 DATA-11/12 缺口。

### 本规格实现程度与边界

本规格统一覆盖存量和缺口；三类导入器与入口可由当前代码复原，自动恢复副本、坏文件隔离及完整结果摘要仍待收口。无云同步、不修改 Dock 数据库、不做系统权限绕过、不清理用户应用。

### 启动扫描的响应性

DATA-01/04/05 的扫描移到后台，仅返回不可变应用描述；已有有效布局先提供给窗口。结果在 MainActor 合并到当时的最新布局，保留用户期间完成的排序，不能赋回扫描开始时的旧快照。一次只允许一个有效扫描代次；刷新/导入后忽略旧结果。拖拽期间延迟合并到提交或取消收尾后，避免被拖拽快照覆盖。新进程仍进行后台核对，不将上次扫描缓存冒充当前安装状态。

## 临时边界与收口

没有新增Mock、后台服务或临时工具。存量实现保留；未实现/未决部分由本规格负责补齐，具体局部方案经评审后才能编码。用户已确认7个板块的拆分，不等于全部缺口技术方案已批准。不会用新bug规格绕开本板块维护。

## 验收出口

逐项执行 check.md，并完成场景 U12、U13、U14。实现事实、隔离测试、真实系统交互和用户确认分别记录。任何未实现基础功能、未确认边界或未执行验收都不能标整板块完成。
