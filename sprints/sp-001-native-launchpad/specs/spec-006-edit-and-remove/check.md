# spec-006：编辑模式与应用管理

## 逐项检查

每行按功能清单的输入和结果执行；组合操作见 [用户场景](../../docs/user-scenarios.md) 的 U09、U10、U11。没有写明已执行的项目都未在本次文档整理中运行。源码存在不等于测试通过。

| 功能 | 检查对象 | 预期结果 | 当前证据 / 人工验收边界 |
|:---|:---|:---|:---|
| EDIT-01 | 长按编辑 | 按住 App → 图标抖动，仍可继续拖拽 | 仅核对存量/目标边界；待定向验证及用户验收 |
| EDIT-02 | 编辑态操作 | 可整理/进出组，点击 App 不启动；叉号独立命中并随图标同步抖动 | 已改为同一动画容器且发布构建通过；真实视觉待用户复验 |
| EDIT-03 | 结束编辑 | 完成/Esc/空白/关闭 → 停止抖动和叉号，恢复普通操作 | 仅核对存量/目标边界；待定向验证及用户验收 |
| EDIT-04 | 资格提示 | 系统/自身/helper/重定向受保护，Apple独立应用不一律禁用 | 隔离策略及4个本机只读资格断言通过；已观察首页系统应用无叉，Pages/Numbers/Keynote/GarageBand/iMovie有叉 |
| EDIT-05 | 二次确认 | 统一说明移到废纸篓和只删除应用包的范围；取消不改文件或布局 | 代码与构建通过；新版弹窗/取消待实机复验 |
| EDIT-06 | 确认后复验 | 路径/身份/删除权限改变或仍运行 → 拒绝并反馈 | 资格策略断言通过；完整弹窗期间变化待验 |
| EDIT-07 | 废纸篓卸载 | 所有可卸载App统一trashItem；成功才清布局，取消/失败保留 | 构建通过；真实移动只待可丢弃样本验收 |
| EDIT-08 | 隐藏与恢复 | 顶层 App 隐藏/全部恢复只改可见性，不卸载 | 仅核对存量/目标边界；待定向验证及用户验收 |
| EDIT-09 | 访达定位 | 右键定位对应应用包，不进入卸载流程 | 仅核对存量/目标边界；待定向验证及用户验收 |
| EDIT-10 | 菜单移出组 | 移到当前页；组收尾遵循文件夹规则 | 仅核对存量/目标边界；待定向验证及用户验收 |

## 验收方法

使用隔离样本覆盖正常、取消、错误和快速连续操作。模型层比对唯一性/顺序/保存，原生交互观察真实接收和最终界面，视觉检查图标/文字/材质/过渡中间态。缺失功能先记录未实现，不允许把未执行用例勾为通过。本次仅文档整理，不重新运行构建或真实操作。

## 本机卸载资格调查（2026-10-30）

环境：macOS 27.2，build 26B123。只读检查 /Applications、当前用户 Applications 与 /System/Applications 下非嵌套应用的 Info.plist、实际路径和 Contents/_MASReceipt/receipt 是否存在；另核对自身布局中的 Apple 应用路径。没有启动卸载器、点击系统删除按钮或执行卸载。本次属于 EDIT-04～07 的实现前调查，不是卸载成功验收。

### 明确应隐藏卸载入口的系统组件

本机 /System/Applications（含 Utilities）发现64个 Apple应用。该系统目录中的应用按系统组件保护，不提供本产品卸载按钮。Apple 官方储存空间说明将系统应用排除在可管理的“应用程序”类别之外，归入不能选择删除的 macOS 类别。

本机应用包名清单：

- Siri、Music、FindMy、QuickTime Player、Chess、Games、Photo Booth、Books、Weather、Notes、Image Capture、Home、Freeform、Siri AI、Passwords、Preview。
- News、TextEdit、Podcasts、System Settings、TV、Apps、Mail、Dictionary、Contacts、Time Machine、Font Book、FaceTime、Shortcuts、Maps、Mission Control、Stickies。
- Photos、Messages、iPhone Mirroring、Calculator、VoiceMemos、Journal、Image Playground、Reminders、App Store、Phone、Clock、Automator、Tips、Calendar。
- Utilities：AirPort Utility、VoiceOver Utility、Terminal、Activity Monitor、Screenshot、Grapher、Audio MIDI Setup、Screen Sharing、System Information、Print Center、Migration Assistant、Script Editor、ColorSync Utility、Console、Disk Utility、Bluetooth File Exchange、Digital Color Meter、Magnifier。

Safari 是另外一个明确保护项：/Applications/Safari.app 是带 restricted 标记的符号链接，指向 /System/Cryptexes/App/System/Applications/Safari.app；实际解析及布局记录为 /System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app。不能因表面位于 /Applications 而给它删除入口。此次共确认65个应保护的安装项；这不是所有 macOS 版本通用的固定数量或仅凭 Bundle ID 的黑名单。

### App Store 路径候选（尚未确认系统按钮）

以下19个应用包均在 /Applications，且存在 _MASReceipt/receipt。收据存在是来源线索，不是收据签名验证，也不是系统允许删除、卸载器存在或残留清理完整性的证明。

| 本机应用包 | Bundle ID | 分类证据 |
|:---|:---|:---|
| Pages Creator Studio | com.apple.Pages | Apple独立应用；有收据 |
| Numbers Creator Studio | com.apple.Numbers | Apple独立应用；有收据 |
| Keynote Creator Studio | com.apple.Keynote | Apple独立应用；有收据 |
| iMovie | com.apple.iMovieApp | Apple独立应用；有收据 |
| GarageBand | com.apple.garageband10 | Apple独立应用；有收据 |
| Xcode | com.apple.dt.Xcode | Apple独立应用；有收据 |
| Xmind | net.xmind.vana.app | 有收据 |
| iBar | cn.better365.iBar | 有收据 |
| Termius | com.termius.mac | 有收据 |
| 抖音 | com.bytedance.douyin.desktop | 有收据 |
| wpsoffice | com.kingsoft.wpsoffice.mac | 有收据 |
| Windows App | com.microsoft.rdc.macos | 有收据 |
| 汽水音乐 | com.soda.music | 有收据 |
| DevCleaner | com.oneminutegames.XcodeCleaner | 有收据 |
| WeChat | com.tencent.xinWeChat | 有收据 |
| 企业微信 | com.tencent.WeWorkMac | 有收据 |
| The Unarchiver | cx.c3.theunarchiver | 有收据 |
| NeteaseMusic | com.netease.163music | 有收据 |
| QQ | com.tencent.qq | 有收据 |

分流实施前的 ApplicationRemoval.permittedPath 一律拒绝 com.apple.*，因此上述6个 Apple 独立应用也被拦截；本次实现已取消此一刀切规则。该旧判断不能作为“系统禁止卸载”的证据。一次文件写权限检查也不能代替系统卸载资格：系统管理界面可能采用不同的授权流程。

### 入口证据与待完成检查

- [Apple《安装和卸载从 App Store 购买的 App》](https://support.apple.com/guide/app-store/install-and-reinstall-purchased-apps-fir0fb69db23/mac)（本次返回 macOS 27 指南）：官方明确支持卸载通过 Apple Account 购买的应用；给出的系统入口是 Dock 中的 Apps → 长按目标直到抖动 → 关闭按钮，也允许通过 Finder 移到废纸篓。页面图标的替代文本明确为“the Apps icon”，不是据旧 Launchpad 文案猜测入口。此证据说明系统确有面向该类应用的卸载交互，不证明 iLaunchPad 已能调用对应的内部删除动作。
- 同一官方指南明确 macOS 组成部分不能卸载，点名 Safari 和 Mail。《删除或卸载 Mac 上的 App》另外列举 Mail、Music、Books、Notes、Podcasts、Maps、News、Stocks，并覆盖 System 目录内的应用。不能把“Apple 出品”与“macOS 必需组成部分”画等号。
- [Apple 储存空间设置说明](https://support.apple.com/guide/mac-help/storage-settings-on-mac-mchl3d437fbc/mac)：系统设置的储存空间“应用程序”类别提供选中应用后删除的入口，并明确排除系统应用。它不是仅对 App Store 应用开放的专用入口，也不证明存在可供第三方调用的一键卸载 API。
- [Apple 卸载说明](https://support.apple.com/en-us/102610)：应用提供卸载器时优先使用，其他普通应用可移到废纸篓；系统必需应用不能删除。不从这些说明推导“App Store卸载必然清除所有数据”。
- 系统界面调查最初因锁屏中断；解锁后检查结果见下方定向验证。19个候选的系统“删除”按钮状态仍未逐项核对，不标为已确认可卸载。
- 上述调查阶段只记录分类证据；后续按用户授权实施分流。不能把本表候选直接变成永久白名单，系统升级、应用位置/身份变化后需重新判断。

官方依据与本机结论需分层使用：

| 判断 | 官方依据 | 本机落实与证据边界 |
|:---|:---|:---|
| 系统必需组件不提供卸载按钮 | Apple明确禁止卸载macOS组成部分；系统目录受保护 | 前述64个系统目录应用及Safari有本机路径证据，不依赖等待系统界面才决定保护 |
| App Store购买/下载的非系统应用属于官方支持卸载的类别 | 官方给出Apps长按删除及Finder路径 | 19个本机收据候选可归入来源调查；其安装身份、管理限制和当前可操作性仍须核对，不能把未核对写成逐个卸载成功 |
| Apple独立应用不按标识前缀一律禁用 | 官方禁止的是系统组成部分，不是全部Apple软件 | Pages、Numbers、Keynote、iMovie、GarageBand、Xcode的非系统安装位置与收据支持将它们与必需组件分开；这是结合本机证据的分类，不是官方逐个列出的六项白名单 |
| 不承诺“更彻底” | 官方没有保证删除应用包会清掉全部残留，且说明用户创建的文稿等不随卸载删除 | 当前统一废纸篓路线只移动应用包；不得自动删除共享容器或个人资料 |

解锁后的只读验证应优先核对官方指明的 Apps 长按删除入口，再核对储存空间管理入口；不点击删除或确认。是否有公共API能直接触发该流程，属于后续实现调查，不从使用手册推导。

## 统一废纸篓实现的定向验证

- 用户确认统一路线后，发布构建与应用包签名校验通过。标准Swift Testing因环境缺少Testing模块，不能称标准测试通过。
- 直接将当前生产ApplicationRemovalPolicy与临时断言入口编译执行：8项通过，覆盖Pages/Xcode独立Apple应用允许、Safari/Mail保护、自身、嵌套helper、相似根目录及非.app拒绝。验证工件位于/tmp/ilaunchpad-unified-trash-tests/，不作为持久规格来源。
- 本机只读确认Pages与Xcode文件可删除；Safari表面路径虽报告可删除，但因符号链接解析后路径不一致仍被资格规则拒绝；Mail位于系统目录且不可删除。
- ApplicationRemoval已移除App Store收据、系统Apps/Settings交接、卸载器发现/签名校验和外部待核对状态。确认后只调用FileManager.trashItem，成功才调用removeUninstalledApplication。
- NativeLaunchGrid已将图标、名称、文件夹材质和叉号放在同一个contentView中，只对该共同容器添加editingWiggle；发布编译通过。真实相位与命中仍待用户复验。
- 已备份并替换/Applications/iLaunchPad.app后启动新版；安装备份位于/Users/wst/Library/Application Support/iLaunchPad-install-backup.pXT2Ml/，产物与安装二进制一致。安装前后布局差异仅为本机应用清单变化：/Applications/Trae.app已不存在，对应TraeCode项消失；19:22新出现的/Applications/Doubao.app以豆包追加到末页。未用旧备份覆盖当前真实清单。
- 待人工验收：新版统一确认框、取消、运行中拒绝、可丢弃样本成功移入废纸篓和容器收尾；不对用户现有软件执行破坏性验证。

## 签收

用户另行授权的第三方应用清理使用独立原生废纸篓操作，不计为本规格UI验收通过。现行统一废纸篓实现及验证以上文为准。

本板块未整体签收。具体用户确认只覆盖其明确复验的场景，不能推导整冲刺完成。
