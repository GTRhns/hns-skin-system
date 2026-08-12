# HnsMatchSkin v5.0.0 — 比赛版皮肤系统（纯标准字段方案）

> 服务器实际使用的皮肤系统（比赛版）。本目录为历史版本源码备份，仅供查阅与回滚使用。

- **版本号**：`5.0.0`
- **插件标识**：`HNS Match Skin`
- **源码文件**：`HnsMatchSkin.sma`（96736 字节）
- **编译插件**：`HnsMatchSkin.amxx`
- **协议**：GPLv3

---

## 背景说明

本插件是 **HnsSkin 独立皮肤系统之外的另一条皮肤分支**——比赛版皮肤系统，直接集成在 HNS 比赛生态中（`#include <hns_matchsystem>`）。

与独立版 `HnsSkin` 的区别：

| 维度 | 独立版 HnsSkin | 比赛版 HnsMatchSkin |
|------|---------------|---------------------|
| 依赖 | 完全独立，不依赖比赛系统 | 依赖 HNS 比赛系统（`hns_matchsystem`） |
| 皮肤 | T / CT / 刀 / USP | 玩家皮肤 + 管理员皮肤 + M键菜单 + 皮肤发放 |
| 命令 | `/skin` | `/model` `/skin` `/menu` `/adminskin` `/give skin` `/take skin` |
| 换队换肤 | nvault 持久化 | 注册 TeamInfo 事件即时换肤 |

> 服务器 plugins.ini 中**二选一**启用：启用 `HnsMatchSkin.amxx` 时停用 `HnsSkin.amxx`，避免两个皮肤系统冲突。

---

## 功能组成

| 模块 | 说明 |
|------|------|
| 玩家皮肤系统 | 读取 `player_models.ini`，T / CT / 刀 / USP 皮肤 |
| 管理员皮肤系统 | 读取 `admin_models.ini`，AMXX 管理员权限即可使用 |
| M 键玩家菜单 | `chooseteam` 拦截 + `/menu` 命令 |
| 皮肤发放机制 | `/give skin`、`/take skin`（仅 Owner 可收回） |
| 换队即时换肤 | 注册 `TeamInfo` 事件，换队后 0.2 秒刷新皮肤模型 |

---

## 更新 / 更改 / 修复内容

**更新（关键）**
- 彻底移除 WPM 依赖，改用 CS 引擎原生标准字段，全服务器兼容：
  - 第一人称：武器实体 `pev_viewmodel`（`v_knife.mdl`）
  - 第三人称：武器实体 `pev_weaponmodel`（`p_knife.mdl`）
- 不再依赖 ReGameDLL 扩展字段（`pev_viewmodel2` / `pev_weaponmodel2`）
- 不再依赖 WPM 插件（`addon_weapon_player_model.amxx`）

**修复**
- 修复插件加载失败导致皮肤完全不显示：旧版仍调用 WPM 原生函数（`api_wpn_player_model_hide/remove`），若服务器未加载 WPM 插件，AMXX 加载时找不到原生函数使整个插件加载失败。本版已彻底移除该依赖。
- 修复换手 / 切回刀后皮肤变默认：`FM_CurWeapon` + `Ham_Item_Deploy`(post) 重新套用刀皮。
- 修复切到手雷等武器出现左手、模型丢失：不再触碰任何玩家实体/武器扩展字段，手雷等武器渲染完全正常。

## 安全加固（发放/收回权限）

| 项 | 说明 |
|------|------|
| **仅官方认证管理员可发放/收回皮肤** | 皮肤发放（`/giveskin`、`/giveallskins`、`/giveskinid`、`/adminskin`）只认 `users.ini` 官方认证数据库里登记的管理员 |
| **不再信任运行时权限** | 不再用 `get_user_flags`（可被其他插件 `set_user_flags` 运行时越权授予管理），杜绝"其他插件任命服主"即可发放/下掉皮肤的漏洞 |
| **不再使用自定义权限等级** | 移除发放/收回权限对 nvault 自定义等级（`skinsys_perm_level`）的依赖，底层自定义管理无法再越权发放/收回 |
| **判定方式** | 启动时解析 `configs/users.ini`，按玩家 SteamID / IP（支持 `*` 通配符）匹配；未在 users.ini 登记的管理一律无法发放/收回 |

> 部署注意：请确保服务器的 `addons/amxmodx/configs/users.ini` 中已正确登记需要发放皮肤的管理员账号。

**第三人称显示规则**
- 刀模型同时存在 `v_knife.mdl` 与 `p_knife.mdl` → 两处都显示
- 只有 `v_` 没有 `p_` → 第一人称显示，第三人称保持默认
- 模型启动时预加载（`file_exists` + `precache` 保护），不会崩服

---

## 编译依赖

- `amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`
- `hns_matchsystem`（比赛系统头文件）

> 无需加载 `addon_weapon_player_model.amxx`，无需 `api_weapon_player_model.inc` 头文件。