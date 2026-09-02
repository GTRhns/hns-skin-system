# HnsSkin+IC v3.0.2 — 扩展版（适配 KZ 系统）

> HnsSkin+IC 皮肤×IC 积分融合版 · 3.0.2 扩展版。本目录为该版本源码与二进制备份，与仓库根目录 `HnsSkin.sma`、`compiled/HnsSkin.amxx` 保持一致。
> 完整发行版（含 DLC）见 GitHub Release `v3.0.2`。

- **版本号**：`3.0.2`
- **发布日期**：2026-09-02
- **插件标识**：`HnsSkin+IC Skin System`（`#define PLUGIN_VERSION "3.0.2"`）
- **定位**：适配 KZ（跳跃）服生态的皮肤系统插件扩展版
- **文件清单**：
  - `HnsSkin.amxx` — 编译插件（可直接部署）
  - `HnsSkin.sma` — 完整源码（皮肤 + IC 积分融合 + 多语言）
  - `HnsSkin.txt` — 四语词典（简体 / 繁体 / English / Русский）
  - `ic_points.inc` — IC 点对外接口头文件（供比赛系统对接）
- **协议**：GPLv3

---

## 3.0.2 扩展说明

- **新增「语言设置」**：皮肤主菜单第 6 项为黄色「语言设置」入口，内含简体 / 繁体 / English / Русский 四种语言切换；语言选择即时生效并被保存（nvault），换图/重进记住选择。
- **全菜单多语言化**：主菜单、皮肤选择菜单、IC 兑换、发放管理、帮助说明均随所选语言显示。
- **皮肤名多语言**：内置皮肤名（北极战士 / GSG-9 等）按所选语言翻译。
- **状态文字多语言**：皮肤列表中的「未获得」「已解锁」、页码/上一页/下一页等状态与导航文字全部按语言显示。
- **通用配置增强**：`player_models.ini` 增加烟雾弹 / 闪光弹皮肤分区，并支持刀皮肤第三人称展示（`p_knife.mdl`）。
- **多语言实现方式**：启动时把 `lang/HnsSkin.txt` 解析进内存字典，按玩家自选语言直接查词条，切换即时生效、不依赖 AMXX 运行时语言缓存。

---

## 命令一览

| 命令 | 功能 | 权限 |
|------|------|------|
| `/skin` `/skins` `/models` `/model` | 皮肤主菜单（含 IC 兑换 / 语言设置） | 所有人 |
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

- 仅替换 `HnsSkin.amxx` 即可启用扩展版（皮肤 + IC 积分 + 多语言）。
- 语言词条文件 `HnsSkin.txt` 需放入 `addons/amxmodx/data/lang/`。
- `player_models.ini` 放入插件配置目录（默认 `addons/amxmodx/configs/`）。
- 已有玩家皮肤 / IC 积分数据（nvault）不受影响，自动保留。