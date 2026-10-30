# spec-001：实现计划

## 文件清单

- [ ] `apps/ilaunchpad/Resources/AppIconInitial.png` — 当前海蓝包图标母图
- [ ] `apps/ilaunchpad/Resources/AppIconSources/*.png`、`prompts.json` — 四款原稿与来源说明
- [ ] `apps/ilaunchpad/Resources/AppIcons/*.png` — 四款连续圆角发布图
- [ ] `apps/ilaunchpad/Resources/AppIcon-preview.png` — README/文档预览
- [ ] `apps/ilaunchpad/Tools/prepare_app_icons.swift` — 统一发布封装
- [ ] `apps/ilaunchpad/Sources/iLaunchPad/AppIconCatalog.swift` — 稳定目录契约
- [ ] `apps/ilaunchpad/Scripts/build-app.sh` — 打包图标目录并生成初始 icns

## 实现顺序

1. 保留冲刺 1 初始包图标的历史边界，将当前包图标切换为海蓝版。
2. 确认火箭轮廓、比例、默认色和四款 ID/名称。
3. 生成并人工检查原稿，记录提示与来源。
4. 使用统一脚本封装发布图，检查尺寸、透明边缘和小尺寸表现。
5. 对齐目录、设置预览和构建打包。
6. 构建后分别验收访达、Dock、应用切换器、选择和重启回退。

## 测试计划

资源完整性与唯一性可以脚本检查；视觉比例、小尺寸、系统呈现和品牌原创性必须人工验收。构建通过只证明可打包。
