# HnsSkin v2.01 — 纯标准字段方案（独立版当前推荐）

> 独立皮肤系统当前推荐版本。本目录为该版本源码备份，与仓库根目录 `HnsSkin.sma` 保持一致。

- **版本号**：`2.01`
- **发布日期**：2026-08-12
- **插件标识**：`HnsSkin Skin System`（`#define PLUGIN_VERSION "2.01"`）
- **文件清单**：
  - `HnsSkin.amxx` — 编译插件（可直接部署）
  - `HnsSkin.sma` — 完整源码（2682 行）
- **协议**：GPLv3

---

## 版本沿革

- `v2.0.0`：WPM 第三人称刀皮方案（依赖 `api_weapon_player_model` / `addon_weapon_player_model.amxx`）。
- `v2.01`（本版）：移除 WPM 依赖，改用 CS 引擎原生标准字段，并修复插件加载失败导致皮肤不显示的问题；同时**收紧皮肤发放/收回权限，仅认官方认证管理员**。

> 说明：`v2.01` 是在 `v2.0.0` 基础上的修复增强版（版本号 +0.1），采用纯标准字段方案。

---

## 更新内容（关键）

| 更新 | 说明 |
|------|------|
| **彻底移除 WPM 依赖** | 不再调用任何 WPM 原生函数（`api_wpn_player_model_*`），不再依赖 `addon_weapon_player_model.amxx` 与 `api_weapon_player_model.inc` |
| **改用 CS 引擎原生标准字段** | 刀/手枪皮肤直接写到武器实体上，全服务器兼容 |
| **第一人称刀皮** | 武器实体 `pev_viewmodel`（`v_knife.mdl`） |
| **第三人称刀皮** | 武器实体 `pev_weaponmodel`（`p_knife.mdl`），仅当 `p_` 模型存在时设置 |
| **枪械皮肤** | 武器实体 `pev_viewmodel`（`v_usp.mdl` 等） |

## 修复内容

| 修复 | 说明 |
|------|------|
| 插件加载失败导致皮肤完全不显示 | 旧版调用 WPM 原生函数，若服务器未加载 WPM 插件，AMXX 加载时找不到原生函数使整个插件加载失败；本版彻底移除该依赖 |
| 换手 / 切回刀后皮肤变默认 | `Ham_Item_Deploy`(post) + `CurWeapon` 消息重新套用刀皮 |
| 切到手雷等武器出现左手、模型丢失 | 不再触碰玩家实体/武器扩展字段，手雷等武器渲染完全正常 |

## 安全加固（发放/收回权限）

| 项 | 说明 |
|------|------|
| **仅官方认证管理员可发放/收回皮肤** | 皮肤发放（`/giveskin`、`/giveallskins`、`/giveskinid`）只认 `users.ini` 官方认证数据库里登记的管理员 |
| **不再信任运行时权限** | 不再用 `get_user_flags`（可被其他插件 `set_user_flags` 运行时越权授予管理），杜绝"其他插件任命服主"即可发放皮肤的漏洞 |
| **不再使用自定义权限等级** | 移除发放权限对 nvault 自定义等级（`skinsys_perm_level`）的依赖，底层自定义管理无法再越权发放/收回 |
| **判定方式** | 启动时解析 `configs/users.ini`，按玩家 SteamID / IP（支持 `*` 通配符）匹配；未在 users.ini 登记的管理一律无法发放 |

> 部署注意：请确保服务器的 `addons/amxmodx/configs/users.ini` 中已正确登记需要发放皮肤的管理员账号。

## 第三人称显示规则

- 刀模型同时存在 `v_knife.mdl` 与 `p_knife.mdl` → 两处都显示
- 只有 `v_` 没有 `p_` → 第一人称显示，第三人称保持默认
- 模型启动时预加载（`file_exists` + `precache` 保护），不会崩服

---

## 编译依赖

- `amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`、`engine`

> 无需加载 `addon_weapon_player_model.amxx`，无需 `api_weapon_player_model.inc` 头文件。

## 部署

- 仅替换 `HnsSkin.amxx` 即可（`plugins.ini` 中启用）。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。