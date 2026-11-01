# 旧版 macOS LaunchPad 布局导入接受定义

生产方是 macOS 25 及更早版本的 LaunchPad；消费方是 iLaunchPad 的 `LegacyLaunchpadImporter`。系统升级后若遗留数据库仍存在，iLaunchPad 只读打开 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`；不会写入、迁移或重建系统数据库。

当前接受传统 SQLite 投影：`apps(item_id,title,bundleid)`、`groups(item_id,title)`、`items(rowid,type,parent_id,ordering)`。`items` 以 type 1 根节点、type 3 页面/槽位容器、type 2 文件夹、type 4 应用表达层级；同一父节点按 `ordering` 排序。应用用 `apps.item_id = items.rowid` 取名称和 Bundle ID，文件夹用 `groups.item_id = items.rowid` 取名称。

源文件缺失、三表不全、无法只读打开或没有可恢复页面时拒绝导入并保留当前布局。当前入口读取本机升级遗留数据库，不读取任意压缩归档；空槽位不会进入 iLaunchPad 的紧凑布局模型。该结构依据公开的 LaunchNext 原生导入实现与隔离 SQLite 样本核对，不承诺兼容 Apple 未公开的其他版本结构。
