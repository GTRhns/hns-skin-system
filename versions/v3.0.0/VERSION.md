# HnsSkin+IC v3.0.0 — 皮肤 × IC 积分融合版（当前推荐）

> 融合版当前推荐版本。本目录为该版本源码备份，与仓库根目录 `HnsSkin.sma` 保持一致。
> 完整发行版（含 DLC）见 GitHub Release `v3.0.0`。

- **版本号**：`3.0.0`
- **发布日期**：2026-08-13
- **插件标识**：`HnsSkin+IC Skin System`（`#define PLUGIN_VERSION "3.0.0"`）
- **文件清单**：
  - `HnsSkin.amxx` — 编译插件（可直接部署）
  - `HnsSkin.sma` — 完整源码（皮肤 + IC 积分融合）
  - `ic_points.inc` — IC 点对外接口头文件（供比赛系统对接）
- **协议**：GPLv3

---

## 融合说明

本版将独立版 `HnsSkin`（皮肤系统）与 `HnsICPointMenu`（IC 点系统）**合二为一**，取各自长处：

| 来源 | 保留的长处 |
|------|-----------|
| 皮肤系统 | 多类型皮肤（T/CT/刀/USP）、共享皮肤模式、管理员发放/收回、选择持久化、纯标准字段方案 |
| IC 点系统 | IC 积分体系、积分兑换皮肤、对外 native 接口（`ic_add_points` / `ic_get_points`）、管理员直接给予 |

**整合点**：

- `/skin` 主菜单增加「IC积分兑换」「查看积分」入口，实时显示当前积分。
- 用 IC 分兑换的皮肤直接解锁为玩家已拥有皮肤（永久），走皮肤系统统一流程。
- 皮肤与 IC 积分共用同一个 nvault 存档，零额外依赖。

---

## 命令一览

| 命令 | 功能 | 权限 |
|------|------|------|
| `/skin` `/skins` `/models` `/model` | 皮肤主菜单（含 IC 兑换） | 所有人 |
| `/skin_t` `/skin_ct` `/skin_knife` `/skin_usp` | 直达对应皮肤 | 所有人 |
| `/ic` `/icpoint` 或 **N 键** | IC 点菜单 | 所有人 |
| `/givetic` `/giveic` `/addic` `<玩家\|@ALL> <数量>` | 直接给予 IC 点 | 管理员 |
| `/giveskin` `/giveskinmenu` | 菜单发放皮肤 | 管理员 |
| `/giveallskins` `<玩家> <T/CT/Knife/USP/all>` | 批量发放皮肤 | 管理员 |
| `/giveskinid` `<玩家> <类型> <皮肤名>` | 命令行发放皮肤 | 管理员 |
| `/take` `<玩家> <类型> <皮肤名>` | 收回皮肤 | 服主（`o` 权限） |

---

## CVAR

| CVAR | 默认 | 说明 |
|------|------|------|
| `skinsys_shared` | `1` | 共享皮肤模式（CT/T 共用人物皮肤），`0` = 关闭 |
| `skinsys_advanced` | `1` | 高级菜单开关 |
| `ic_skin_person` | `500` | 兑换人物皮肤所需积分 |
| `ic_skin_knife` | `300` | 兑换刀皮肤所需积分 |

---

## 编译依赖

`amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`、`engine`（全部内置，无外部依赖）

## 部署

- 仅替换 `HnsSkin.amxx` 即可启用融合版（皮肤 + IC 积分），无需再安装 `HnsICPointMenu.amxx`。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。
- 旧服若同时装了独立版皮肤与 IC 点插件，请从 `plugins.ini` 移除旧插件，只保留融合版。
- 完整部署 / 使用 / 对接教程见 [《融合版使用教程》](../../docs/融合版使用教程.md)。
