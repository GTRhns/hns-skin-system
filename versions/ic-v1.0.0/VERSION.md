# HNS IC 点系统 v2.0.0（完全独立版）

- 发布位置：皮肤系统 DLC（`dlc/`）。
- 完全自包含：不依赖任何比赛系统 / PersistentDataStorage。
- 仅依赖 AMXX 内置模块：reapi / nvault。

## 功能
- N 键（nightvision）打开 IC 点菜单（优先级高于 menu new）。
- 管理员给予 IC 点：`/givetic <玩家名|@ALL> <数量>`（需 admin 权限）。
- 积分兑换皮肤：人物 500 / 刀 300（CVAR 可配置）。
- 兑换皮肤直接应用模型，30 天自动清除。
- 积分与已兑换皮肤持久化（nvault）。

## 对外接口（供比赛系统对接）
本插件不内置比赛逻辑，把发分接口开放给外部比赛系统：
```
#include <ic_points>
ic_add_points(id, 10);        // 给玩家 +10 IC 点
new pts = ic_get_points(id);  // 查询玩家当前 IC 点
```
发分时机/条件由对接方自行决定。

> 📖 **零基础对接教程**：即使完全不会写代码，也请阅读
> [《IC 点系统对接教程》](../../docs/IC点系统对接教程.md)，
> 我们从"插插头"讲起，分三条路（零代码 / 接线 / 全自动）带你接入任意比赛规则。

## 文件
- `HnsICPointMenu.sma` — 插件源码
- `HnsICPointMenu.amxx` — 编译产物
- `ic_points.inc` — 对外 native 头文件

## CVAR
| CVAR | 默认 |
|------|------|
| ic_skin_person | 500 |
| ic_skin_knife | 300 |