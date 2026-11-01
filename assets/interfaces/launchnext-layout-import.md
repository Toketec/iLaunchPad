# LaunchNext 布局导入接受定义

生产方是 LaunchNext 的 JSON 导出；消费方是 iLaunchPad 的 `LaunchNextImporter`。用户在 iLaunchPad 菜单中明确选择 JSON 文件，客户端只读取该文件，不修改 LaunchNext 数据库、偏好或导出文件。

当前接受 LaunchNext 官方开源实现的两种导出：

- 新格式以 `snapshotType: launchNext.layout` 标识，读取 `items[].kind/pageIndex/position/name/path`；文件夹读取 `items[].apps[].name/path`。
- 兼容格式读取 `pages[].kind/pageIndex/position/name/path`；文件夹读取同项的 `folderApps[]` 与 `folderAppPaths[]`。

`app/应用` 转为普通组，`folder/文件夹` 转为文件夹；页面和项目分别按 `pageIndex`、`position` 排序。空槽位与缺失应用不伪造为已安装应用；没有可导入应用时拒绝替换当前布局。应用路径不存在时仍保留导出路径和名称，后续由本机扫描与 Bundle 解析决定可启动性。
