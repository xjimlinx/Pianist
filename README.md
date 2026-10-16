# Pianist

Pianist 是面向 KDE Plasma 6 的本地待办、便签与目标路线小部件。它作为 Plasmoid
直接嵌入桌面或面板，由 Plasma 管理位置、尺寸和生命周期，不需要独立后台进程。

## 功能

- 待办的添加、编辑、排序、完成、恢复、删除与撤销
- 桌面便签及多便签管理
- 带多前置条件的大目标路线和科技树式节点
- 多个大目标同时显示并独立折叠
- 节点形状、尺寸和手动拖动位置
- 到点提醒和可选的提前提醒
- Plasma 原生主题、自适应颜色、半透明玻璃卡片与光晕
- 字体、界面比例、透明度、圆角、边框和阴影设置
- JSON 导入、导出及导入前备份
- 多个桌面或面板实例自动关联同一份记录

## 安装

需要 KDE Plasma 6、`kpackagetool6`、Node.js，以及用于开发检查的 Qt 6 QML 工具。

```bash
git clone https://github.com/xjimlinx/Pianist.git
cd Pianist
make install
```

然后在 Plasma 的“添加小部件”窗口中搜索 `Pianist`。

日常开发更新使用：

```bash
make deploy
```

该命令会升级 Plasmoid 并安全重启 `plasmashell`。桌面和面板会短暂消失，然后自动恢复。

其他常用命令：

```bash
make test       # 运行 QML、JavaScript 和重启脚本测试
make preview    # 在 plasmawindowed 中预览
make reload     # 仅重启 plasmashell 重新加载 QML
make uninstall  # 卸载 Plasmoid，不删除记录
```

卸载也可以直接执行：

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.xjimlinx.pianist
```

## 数据存储与多实例

待办、便签、目标和通知记录统一保存在：

```text
~/.config/Pianist.conf
```

所有 Pianist 实例都会读取这份共享记录。插拔显示器、切换布局或重新添加小部件时，
新实例会自动关联已有数据；运行中的多个实例会定期同步。

折叠状态、节点拖动位置和外观设置按实例保存在 Plasma 配置中，以适应不同屏幕尺寸。
不要直接编辑配置文件，迁移和备份请使用右上角菜单中的“JSON 导入 / 导出”。

## 目标路线

“目标”页会纵向展示所有大目标。每个大目标包含一组小目标节点：

1. 创建大目标并填写最终成果。
2. 添加不需要前置条件的起始节点。
3. 为后续节点选择一个或多个前置节点。
4. 前置节点全部完成后，后续节点自动解锁。

依赖关系保存前会检测回环。节点卡片不会因误触直接完成，必须点击明确的完成按钮。
路线超出可见宽度时可以拖动空白区域横向浏览；节点也可通过拖动图标调整位置。

## 提醒

提醒时间使用本地时间：

```text
2026-09-09 19:00
```

提醒由 `plasmashell` 中的定时器检查，并通过 KDE 通知系统显示。会话恢复后，错过的
到点提醒会补发。

## Plasma 安全重启

`make deploy` 和 `make reload` 使用独立看门狗检查新启动的 Plasma：

- 持续验证 D-Bus 响应
- 检测 2 GiB 内存硬上限
- 检测观察期内超过 512 MiB 的异常增长
- 检测持续高 CPU 与内存增长的组合故障

如果检查失败，脚本会打印判定原因和最近的 Plasma/QML 日志，停止失控进程，隔离
本次插件包，然后重新启动桌面。记录文件位于插件目录之外，不会随隔离操作丢失。

默认观察 10 秒，可临时调整为 1–60 秒：

```bash
PIANIST_WATCHDOG_SECONDS=20 make deploy
```

## 项目结构

```text
package/
├── metadata.json
└── contents/
    ├── code/Store.js             数据校验、迁移、目标规则与提醒逻辑
    ├── config/                   Plasma 配置定义
    └── ui/
        ├── main.qml              主界面、共享存储与通知集成
        ├── GoalTree.qml          目标依赖布局、连线与节点卡片
        └── configAppearance.qml  外观设置
scripts/
└── restart-plasma.sh             带故障隔离的 Plasma 重启脚本
tests/
├── fixtures/                     数据模型夹具
├── qml/                          可视化测试宿主
├── store.test.js                 数据模型测试
├── tst_goal_tree.qml             目标树运行测试
├── tst_shared_settings.qml       多实例存储测试
└── restart-plasma.test.sh        看门狗测试
```

## 许可

Pianist 使用 MIT 许可证。
