# spec-007：外观与使用偏好

## 文件与职责

以下Swift路径相对 apps/ilaunchpad/Sources/iLaunchPad/；其余显式路径相对项目根。不得为整理文档修改代码或已安装应用。

- LaunchpadSettingsView.swift：设置窗口/键值
- LaunchpadRootView.swift：偏好消费与页码
- PagingSurface.swift、Tests/iLaunchPadTests/InteractionRegressionTests.swift：打开前原生分页无动画定位，首页/记忆页/中途翻页取消定向验证
- LaunchpadDesign.swift：GridMetrics和减少动态效果
- WallpaperBackdropView.swift：壁纸与模糊缓存
- FolderOverlay.swift：只有偏好作用范围确认后统一组内规则
- AppIconCatalog.swift、AppMain.swift：消费稳定图标 ID、资源读取、启动恢复、缺失回退及默认偏好注册
- LaunchpadSettingsView.swift：展示图标目录、选中反馈与辅助功能标签

## 实施/复原顺序

1. 复原同一组偏好键与默认值，不重置现有设置。
2. 确认主页与组内作用范围，统一标签、实际几何和命中。
3. 验证当前屏壁纸/失败回退及减少动态效果，不通过复制素材伪造系统玻璃。
4. 在七个板块各自验收基础上执行U01～U17必要组合，逐项保留缺口，不签收未实现功能。

## 登录启动设置与性能收口切片

1. LaunchpadSettingsView.swift 在现有交互区域接入002的服务状态及原生Toggle/错误说明/系统设置按钮；遵守原型文案，不在视图初始化时注册登录项。
2. WallpaperBackdropView.swift 接入003共享位图缓存，保持现有全屏背景和组外磨玻璃不变；跨屏和同路径壁纸替换必须重新请求正确资源。
3. 按check进行冷启动/磁盘热启动/常驻打开、120Hz内屏和60Hz外屏、减少动态效果/系统节能、快速跨组拖拽的相关收口；记录未执行范围。
4. 仅应用代码完成必要构建后，按已有授权备份并自动安装新版；文档方案阶段不构建、不安装、不更改登录项。

## 执行约束

本计划服务于该功能板块，不是每个缺陷另开一次规格。修改前先在tasks记录受影响功能ID、复现及正常对照；只改所需文件。涉及未决产品规则、外部接受定义或架构边界时先回到方案评审。保持已有用户排序、偏好和备份；不读写用户真实导入源作为自动化fixture。

## 验证与交付

按check选择与改动相关的检查，不跑无关全量验证。代码修改需必要构建和定向回归；真实AppKit交互另验。当前Swift Testing模块不可用时须明确替代入口及覆盖，不声称swift test通过。应用变更构建成功后按项目授权备份并安装；仅文档变更不构建/安装。
