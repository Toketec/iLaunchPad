# 当前运行架构

## 运行单元与依赖

本地运行单元是一个 iLaunchPad.app GUI 进程，应用标识 local.ilaunchpad.app，当前包版本 2.3.6/build 15。窗口、布局、输入监听和 UI 共享故障域。另有一个独立静态产品官网，不与客户端通信。没有监听端口、后台服务、数据库服务、远程 API、队列、容器或集群部署。

运行需要 macOS 26.0 及系统 AppKit、SwiftUI、Carbon、CoreImage、SQLite3。应用读取当前用户目录、系统应用目录和桌面壁纸；外部布局只在用户选择或首次 LaunchOS 迁移时只读，来源应用无需运行。无运行密钥、账号令牌或网络依赖。

## 构建与部署

SwiftPM 工程在 apps/ilaunchpad/，swift-tools-version 6.0，链接 AppKit/Carbon/sqlite3。构建需提供 NSGlassEffectView 等 API 的 macOS SDK 与 Swift 工具链；测试另需 Swift Testing 模块。当前脚本显式构建 arm64，没有 Intel 或通用二进制发布流程。

从项目根执行 apps/ilaunchpad/Scripts/build-app.sh。脚本根据自身位置寻找工程，将 release 二进制、Info.plist、四款运行时图标和 Icon Composer 默认包图标组装到 apps/ilaunchpad/dist/iLaunchPad.app，并 ad-hoc 签名。重复构建会替换该工程 dist 内的应用包。该脚本不安装到 /Applications，不修改用户布局；没有 CI、开发者证书公证、自动更新或发布服务器。具体操作见 [手册](../assets/manuals/build-and-recovery.md)。

官网源码在 `apps/website/`，静态发布目录为 `dist/`。根仓库 `.github/workflows/pages.yml` 在 `main` 更新时上传该目录并部署到 GitHub Pages；官网无独立构建依赖、嵌套 Git 或工具专属托管清单。官网与客户端独立构建、版本和部署，真实客户端截图与系统录屏随静态资源发布。线上部署成功不等于客户端或网站已经完成人工验收。官网规格见[冲刺 2 spec-002](../sprints/sp-002-brand-and-website/specs/spec-002-product-website/requirements.md)。

## 启动、输入与同步异步路径

AppDelegate注册Option-Space/F4、菜单和窗口事件；普通启动显示，系统登录启动事件仅准备隐藏窗口和资源，不抢焦点、不隐藏Dock。SMAppService.mainApp默认不自动注册，设置读取真实状态；用户退出后没有守护进程重新拉起。无独立健康端点；进程存活只能证明进程存在，实际就绪需能显示网格与响应搜索。--import-only 初始化真实 LayoutStore 并写布局后退出，不可作为无副作用健康检查。

LayoutStore修改、JSON保存及UI在MainActor；扫描由串行ScanWorker执行，按代次合并最新布局，拖拽期间延迟。搜索索引后台生成，图标/壁纸解码与磁盘IO由VisualResourceCache actor执行。拖拽使用窗口级displayLink和原生接收，同帧同点轮询合并不影响最终drop，结束/隐藏停止。所有worker均为进程内任务；无独立后台服务。--import-only等待扫描结束再输出并退出，但仍有真实布局写入副作用，不可作为只读诊断入口。

## 配置

| UserDefaults 键 | 默认值 | 行为 |
|:---|:---|:---|
| iconScale | 1.0 | 设置范围 0.75–1.15，步长 0.05 |
| wallpaperBlur | 24.0 | 界面提供 12/24/42 三档 |
| showNames | true | 显示应用名称 |
| returnToFirstPage | true | 未配置时回首页，保留用户显式false（记忆上次页） |
| lastPage | 0 | 记住页面，显示时按实际页数校正 |
| appIconStyle | ocean | 四款应用标识的稳定 ID；未知或已删除 ID 回退 ocean；Dock、访达、应用切换器与启动台内图标保持一致，退出后保留 |

当前布局位于用户 Library/Application Support/iLaunchPad/layout.json，最多 3 份用户命名快照位于同目录 layout-backups.json；Apple 默认风格布局由代码按当前应用清单生成，不另存模板文件。可选兼容源包括同级 LaunchOS/LaunchOS.sqlite、DARWIN_USER_DIR 下旧版系统数据库和用户选择的 LaunchNext JSON。偏好走 AppStorage 即时更新。图标存在性通过刷新清空；缓存目录为用户Caches/local.ilaunchpad.app/VisualResources/v1。图标键包含身份、规范路径、版本/资源指纹、256px规格、外观及系统版本；壁纸键包含源指纹、屏幕与模糊半径。重新显示后台复核。登录开关不另存UserDefaults，requiresApproval/notFound/操作错误如实反馈。包最低系统和版本字段见工程 Resources/Info.plist。无环境变量配置模板需要填写。

## 失败与恢复

| 失败 | 当前行为 | 恢复边界 |
|:---|:---|:---|
| 自有 JSON 不存在/不可解码 | 尝试 LaunchOS 自动导入；失败则在首次完整扫描后生成 Apple 默认风格布局并保存 | 可从用户快照、外部来源或额外文件备份恢复；当前无坏文件隔离 |
| 备份目录不存在/不可解码 | 当前布局继续工作；设置显示空目录或错误 | 不覆盖当前布局；修复或移走损坏的 layout-backups.json 后重建快照 |
| 备份恢复或默认初始化时扫描为空/失败 | 拒绝替换并保留当前布局 | 应用目录恢复可读后重试 |
| LaunchOS 源缺失、无法打开或 SQL 准备失败 | 首次自动导入失败被回退逻辑吸收；手动导入显示错误 | 不修改源库；保留现有自身布局 |
| 旧版系统或 LaunchNext 源缺失、格式不兼容 | 手动导入显示错误，候选布局不赋值 | 不修改源文件；保留现有自身布局 |
| 保存失败 | lastError 弹窗，内存变化可能仍在，磁盘未更新 | 处理权限/磁盘问题后再次保存操作；无自动重试 |
| App 路径失效 | 按 Bundle ID 再解析，找不到则报错 | 用户刷新、修复安装或移除失效项 |
| 启动应用失败 | NSWorkspace 回调设置 lastError | 启动台已请求关闭；错误可在再次显示时查看 |
| 壁纸不可读 | 原图或系统背景色回退 | 可继续使用启动台 |
| 拖拽取消/失焦/关闭 | 回滚预览，停止轮询 | 重新拖动；未提交不落盘 |
| 卸载资格改变、正在运行、用户取消或移入废纸篓失败 | 拒绝删除或提示错误并保留布局 | 用户退出目标或修复权限后重新确认；不自动提权 |
| 进程异常退出 | 无进程内恢复或 watchdog | 重启，读取最后已保存布局 |

Dock 隐藏是本应用 presentationOptions，正常隐藏和退出恢复先前值，不持久修改 Dock 配置。应用崩溃不提供已验证的恢复保证，不能以普通退出逻辑推断所有异常行为。

## 容量、幂等、观测与备份

设计为单个用户会话本地使用，不支持水平扩容或多实例并发编辑。扫描按 Bundle ID 和路径避重复；finishDragPreview 在无快照时无效，防止重复结束提交。缓存降低重复图标读取，背景图缩至至多约 1800px 宽再模糊；没有大型目录专门背压或容量承诺。

正常运行有界面 lastError 和 import-only 的统计输出；诊断时可显式设置 ILAUNCHPAD_DRAG_TRACE=1，将会话、接收校验和命中层级写到标准错误，默认关闭、不上传应用清单。无遥测、性能采样、结构化审计、指标端点或滚动自动历史。应用内允许用户保存最多 3 份命名布局快照；更强恢复仍依赖额外复制 layout.json、layout-backups.json 与偏好。应用包可重新构建，用户自定义排序不能由源码恢复。被移到废纸篓的应用由用户恢复，辅助文档不删除。技术目标与实测边界见非功能约束和各功能规格 check.md。
