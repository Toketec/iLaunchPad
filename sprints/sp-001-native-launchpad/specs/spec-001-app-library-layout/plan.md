# spec-001：应用目录、布局保存与多来源导入

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- Models.swift：布局/页/组/App 与 Codable
- LayoutStore.swift：读取、扫描合并、normalize、保存和导入编排
- ApplicationScanner.swift：应用扫描
- ApplicationDirectoryMonitor.swift：原生FSEvents监听、去抖及安装完成后补扫
- ApplicationDiscoveryPolicy.swift：35格容量下首个空位页选择
- LaunchOSImporter.swift：LaunchOS 只读 SQL
- LegacyLaunchpadImporter.swift：旧版 macOS LaunchPad 遗留 SQLite 只读投影
- LaunchNextImporter.swift：LaunchNext 官方 JSON 导出只读投影
- AppMain.swift：三个来源的明确菜单入口、文件选择和覆盖确认
- assets/interfaces/launchos-layout-import.md、legacy-launchpad-layout-import.md、launchnext-layout-import.md
- Tests/iLaunchPadTests：补隔离导入/存储用例，不操作用户真实数据

## 实施/复原顺序

1. 核对 Models 与已有导入接受定义，补数据读取/保存的隔离 fixture。
2. 依据公开实现和隔离样本分别建立旧系统、LaunchNext 接受定义，冻结路径、字段、排序、匹配和失败边界。
3. 补来源选择与只读候选解析，接入现有 LayoutStore 唯一写入入口；恢复副本和摘要继续显式留在 DATA-11/12。
4. 补新增应用发现、失效项策略与坏布局保留；已有排序不受扫描影响。
5. 分别验证三个来源、取消/失败、持久化重开及上游源文件未变。

## 启动扫描实施切片

仅改 ApplicationScanner.swift、LayoutStore.swift 与 AppMain.swift 的启动/刷新接线；保持现有发现范围和身份规则。后台扫描，MainActor按当前布局合并；合并在拖拽收尾后执行，过期请求取消。Tests/iLaunchPadTests/EditingRegressionTests.swift 增加“扫描中整理、拖拽中结果到达、取消/提交后追加一次、主动刷新替换旧请求”隔离用例。不顺带实现旧系统导入或清理真实布局。为003提供非阻塞应用列表，布局模型与文件格式不变。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
