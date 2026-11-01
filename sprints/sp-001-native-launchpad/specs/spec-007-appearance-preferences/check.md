# spec-007：外观与使用偏好

## 逐项检查

每行按功能清单的输入和结果执行；组合操作见 [用户场景](../../docs/user-scenarios.md) 的 U15及U01～U17组合收口。没有写明已执行的项目都未在本次文档整理中运行。源码存在不等于测试通过。

| 功能 | 检查对象 | 预期结果 | 当前证据 / 人工验收边界 |
|:---|:---|:---|:---|
| PREF-01 | 设置入口 | 更多/背景菜单打开原生设置，不混入拖拽输入 | 仅核对存量/目标边界；待定向验证及用户验收 |
| PREF-02 | 图标大小 | 滑块更新主网格，布局和命中同步，不丢排序 | 仅核对存量/目标边界；待定向验证及用户验收 |
| PREF-03 | 名称显示 | 按声明范围显示/隐藏名称；是否统一作用组内需明确 | 仅核对存量/目标边界；待定向验证及用户验收 |
| PREF-04 | 壁纸模糊 | 当前屏壁纸及模糊档位；读取失败有背景回退 | 仅核对存量/目标边界；待定向验证及用户验收 |
| PREF-05 | 起始页 | 未配置回首页，显式关闭后记忆上次页；页数变少时不越界；回首页不播放横向翻页 | launchpadWillPresent 在展示前锁定 NativePagingView 目标页；回归用例补充“旧 AppStorage 页码刷新不得触发分页动画”。标准测试入口缺Testing模块；release构建、签名和自动安装完成，安装前后布局SHA256一致，真实翻页重开待用户复验 |
| PREF-06 | 减少动态效果 | 跟随系统降低运动/抖动，不丢功能或结束回调 | 仅核对存量/目标边界；待定向验证及用户验收 |
| PREF-07 | 应用标识选择 | 消费四款目录；Dock、访达、应用切换器和启动台内图标即时一致；退出/重启保持；默认或资源缺失回退海蓝 | 代码使用 NSWorkspace 文件图标元数据而非改签名资源；release 构建后需实机切换非默认图标、退出并观察 Dock/访达，再恢复 ocean |
| PREF-08 | 登录启动设置 | 预期规则见功能清单与本规格要求 | 已通过原生界面打开设置→交互，确认登录开关关闭和状态说明；安装前后布局SHA256完全一致。系统返回notFound（未识别服务），没有执行注册；不能将UI呈现称为实际登录启动成功。 |

## 验收方法

使用隔离样本覆盖正常、取消、错误和快速连续操作。模型层比对唯一性/顺序/保存，原生交互观察真实接收和最终界面，视觉检查图标/文字/材质/过渡中间态。缺失功能先记录未实现，不允许把未执行用例勾为通过。只执行本次切片相关检查；已执行范围以“本次实施验收边界”为准，其余仍待验收。

## 实施前的原生实现与高刷审查证据

源码审查范围覆盖窗口、网格、图标、搜索、文件夹、分页、设置、壁纸和拖拽循环，不是已运行帧时验收。

| 区域 | 当前实现 | 判定 |
|:---|:---|:---|
| 窗口与网格 | AppMain 的 NSWindow；NativeLaunchGrid 的 NSCollectionView/NSScrollView/NSImageView/NSTextField/NSButton | 关键高频区域已大量使用 AppKit |
| 输入与玻璃 | NSSearchField、原生命名 NSTextField、NSGlassEffectView、NSVisualEffectView、系统菜单/确认框 | 原生组件，不是网页或绘制的仿制控件 |
| 主要过渡 | FolderMorphSurface 的 CAAnimationGroup；网格 CABasicAnimation/CAKeyframeAnimation；PagingSurface 的 NSAnimationContext/animator | 大部分局部过渡已使用系统动画；仍需帧时测量 |
| SwiftUI保留区 | RootView编排/开场scale与opacity、NSHostingView、FolderOverlay组合、设置TabView/Form | SwiftUI也是原生；低频设置无证据需要重写，开场和页面刷新是优化对象 |
| 首次资源 | ApplicationIconCache仅内存NSCache；RootView主线程遍历预热；WallpaperBackdropView同步处理且新建CIContext | 缺跨进程位图缓存，Task.yield未移走解码负载 |
| 初始工作量 | LayoutStore初始化同步扫描；RootView一次创建全部页面 | 已定位可优化链路；尚未证明每项占比 |
| 拖拽时钟 | NativeLaunchGrid:395 固定1/60秒Timer，原生拖拽事件并行更新位置 | 未完整适配显示同步，不等于所有动画仅60fps |

本机NSScreen查询：内置屏 maximumFramesPerSecond=120、scale=2；24B2N3200外屏 maximumFramesPerSecond=60、scale=1。这是屏幕能力，不是应用实测帧率。

已有独立辅助进程微基准：扫描约203ms，123个图标获取约68ms、首次栅格化约2361ms，壁纸处理约204ms。它们不是端到端启动采样，不能相加作为启动时长，也不能据此承诺提速倍数。辅助入口在 /tmp/ilaunchpad-startup-probe.kKtx3y，可能被系统清理；源码热点与上述边界为可复查依据。

待实施后的收口：记录相同布局/屏幕下无缓存新进程、磁盘缓存新进程、常驻唤起各至少10次；分别报告可交互时间、p50/p95/p99帧时、最长主线程停顿及样本数。少量启动样本只报中位数和范围，不夸大尾延迟精度。使用系统性能工具记录真实呈现/卡顿与主线程，显示回调次数仅用于检查时钟。另覆盖多屏、系统节能/减少动态效果、缓存失效和跨容器真实拖拽；不以视觉降级换分数。当前这些性能收口未执行。

平台依据：[SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)、[NSWindow.displayLink](https://developer.apple.com/documentation/appkit/nswindow/displaylink(target:selector:))、[preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)。登录项是用户登录后启动，不是登录前系统守护服务；显示同步受系统刷新率、负载与节能策略约束。

## 本次实施验收边界

已通过原生界面打开设置→交互，确认登录开关关闭和状态说明；安装前后布局SHA256完全一致。系统返回notFound（未识别服务），没有执行注册；不能将UI呈现称为实际登录启动成功。

同源隔离入口共48项通过，包含既有拖拽/临时组、分页/原生编辑、后台扫描、缓存、登录服务替身及显示时钟；标准swift test缺Testing模块，未通过标准入口。release构建和签名通过，已安装 /Applications/iLaunchPad.app。旧包与布局备份位于 /tmp/ilaunchpad-startup-cache.CyvxfL，临时目录可能被系统清理。包标识保持2.3.2/build12，未重置或导入真实排序。

## 签收

### 初始标识与默认首页定向证据

冲刺 1 的白底石墨火箭只承担历史里程碑的初始识别。当前海蓝包图标及四款个性化图标的原稿、配色、发布封装与视觉验收归冲刺 2 spec-001，本规格只验选择、恢复与显示同步。

未配置默认true、显式false不覆盖的隔离偏好检查通过。打开路径已在窗口显示前同步RootView与原生分页位置，再播放既有spread；release构建并已自动安装启动，安装前后布局SHA256一致。原生界面能读取首页应用；不将图标点击切换/重启保持及真实翻页重开记作实机通过。旧包位于本次安装输出的临时备份目录，可能被系统清理。

本板块未整体签收。具体用户确认只覆盖其明确复验的场景，不能推导整冲刺完成。
