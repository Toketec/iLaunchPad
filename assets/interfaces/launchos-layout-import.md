# LaunchOS 布局导入接受定义

## 边界

生产方为第三方 LaunchOS；消费方为 iLaunchPad 的 `LaunchOSImporter`。本文唯一维护本项目当前接受的 SQLite 投影，与 [导入实现](../../apps/ilaunchpad/Sources/iLaunchPad/LaunchOSImporter.swift) 同步。本定义从现有 SQL 提取，不是 LaunchOS 官方公开协议，也不承诺兼容其所有版本；产品名称仅用于准确描述迁移来源。

输入为当前用户 `Library/Application Support/LaunchOS/LaunchOS.sqlite`，以 `SQLITE_OPEN_READONLY` 打开，不创建、不迁移、不修改源库。负责规格为 [应用目录与布局 spec-001](../../sprints/sp-001-native-launchpad/specs/spec-001-app-library-layout/requirements.md)。本文不适用于旧系统 Launchpad 数据库；该来源须另经样本验证接受定义，不能复用这些表名或关系。

## 当前投影

- 组表：`ZGROUPENTITY`，读取 `Z_PK`、`ZPAGE`、`ZORDER`、`ZISFOLDER`、`ZNAME`。
- 应用表：`ZAPPENTITY`，读取 `Z_PK`、`ZORDER`、`ZID`、`ZNAME`、`ZBUNDLEID`、`ZURL`、`ZHIDDEN`。
- 关联：`a.ZGROUP = g.Z_PK`，使用 `LEFT JOIN`；按页、组序、应用序升序读取。
- 同组序时以组主键排序；没有应用的组丢弃；空结果返回至少一页。

`ZNAME`、`ZID`、`ZBUNDLEID`、`ZURL` 为 NULL 时按空串读取，`ZHIDDEN` 为 NULL 时视为 0。App ID 优先非空 `ZID`，其次非空 Bundle ID，最后使用来源主键生成稳定回退 ID。`file://` URL 转成本地路径，普通路径保持原值；非零隐藏值为 true。导入结果记录只读来源路径与导入时间。

## 已知限制

当前实现只接受固定路径和上述字段，没有 schema/版本探测；读取循环尚未把非 `SQLITE_DONE` 的结束状态单独报告为错误。首次没有自身布局时会尝试自动迁移，主动恢复则先确认覆盖。源文件缺失、版本不兼容或查询失败不得破坏已有 iLaunchPad 布局。
