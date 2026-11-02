# spec-001：实现计划

## 实现顺序

| 步骤 | 内容 | 文件 | 验证 |
|:---:|:----|:----|:----|
| 1 | 定义 Apple 默认布局工厂、备份文档和原子存储 | `LayoutBackups.swift` | 单元测试 |
| 2 | 提取已安装应用对账算法，让普通刷新与切换共用 | `LayoutStore.swift` | 单元测试 |
| 3 | 接入无来源首次初始化、备份新建/覆盖/重命名/删除/恢复 | `LayoutStore.swift` | 单元测试 |
| 4 | 实现原生设置布局页与切换通知收尾 | `LaunchpadSettingsView.swift`, `LaunchpadRootView.swift` | 构建+人工 |
| 5 | 更新当前架构与规格证据，构建并安装 | `architecture/*.md`, `tasks.md`, `check.md` | 构建+签名 |

## 文件清单

| 类型 | 路径 |
|:----|:----|
| 新增 | `apps/ilaunchpad/Sources/iLaunchPad/LayoutBackups.swift` |
| 修改 | `apps/ilaunchpad/Sources/iLaunchPad/LayoutStore.swift` |
| 修改 | `apps/ilaunchpad/Sources/iLaunchPad/LaunchpadSettingsView.swift` |
| 修改 | `apps/ilaunchpad/Sources/iLaunchPad/LaunchpadRootView.swift` |
| 新增 | `apps/ilaunchpad/Tests/iLaunchPadTests/LayoutBackupTests.swift` |
| 修改 | `apps/ilaunchpad/Tests/iLaunchPadTests/ApplicationDiscoveryTests.swift` |

## 重建与风险

- 使用现有 Swift 6/macOS 26 基线，不新增第三方依赖。
- 没有数据库 migration；既有 `layout.json` 保持不变，无布局来源的新用户才进入 Apple 默认风格初始化。
- 风险是扫描结果不完整时误删布局项；只在完整扫描正常返回后对账，且切换失败不发布候选布局。
- 风险是拖拽与切换争用布局；拖拽预览中不允许切换。
