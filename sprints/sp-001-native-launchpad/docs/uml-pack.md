# 冲刺 1：规格依赖与状态责任

本项目只有一个客户端，不引入后端分层或额外服务。业务流程见 business-flows.md；当前数据、运行事实见 architecture 三文件。

## 功能规格依赖（ASCII）

```text
001 应用目录/布局
 └→ 002 唤起与系统
     └→ 003 浏览/搜索/启动
         └→ 004 文件夹
             └→ 005 连续拖拽/排序
                 └→ 006 编辑/移除
                     └→ 007 偏好设置与最终整体验收
```

这是可复原的实现/集成顺序，不表示每个板块只调用紧邻前一个。各 requirements 的 Context Contract 列直接依赖；多个规格会维护同一 Swift 文件，不安排并行改写。

## 状态所有权

| 状态/事实 | 唯一所有者 | 使用者与边界 |
|:---|:---|:---|
| 持久布局、应用身份、写入入口 | LayoutStore / Models（001） | 所有板块通过此入口，不能自己再存一份排序 |
| 窗口、Dock、焦点 | WindowController / AppDelegate（002） | 003/004 请求启动或关闭；不各自改 Dock |
| 当前页、搜索、键盘选择 | RootView / PagingSurface（003） | 004/005 请求切换或暂停，按实际容器路由 |
| 展开组、名称、开合代次 | RootView / FolderOverlay（004） | 005 触发悬停打开/退出，不建立第二套组状态 |
| 拖拽会话、快照、落点和显示身份 | LayoutStore / DragTracking / Coordinator（005） | 004 提供面板几何，002 的关闭发出取消 |
| 编辑态与移除确认 | LayoutStore.isEditing / ApplicationRemoval（006） | 003/004 使用状态禁止误启动 |
| 设置值 | AppStorage / UserDefaults（007） | UI 使用同一值，不能以本地默认覆盖已保存设置 |

状态所有者是当前源码职责映射，不是要新建同名模块。内部类型不是公共 API；外部布局来源的接受定义单独由 spec-001 负责。
