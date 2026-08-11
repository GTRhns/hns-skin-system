# HnsMatchSkin v5.0.0 — 比赛版皮肤系统（含 WPM 第三人称集成）

> 服务器实际使用的皮肤系统（比赛版）。本目录为历史版本源码备份，仅供查阅与回滚使用。

- **版本号**：`5.0.0`
- **插件标识**：`HNS Match Skin`
- **源码文件**：`HnsMatchSkin.sma`（94984 字节）
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
| **WPM 第三人称刀皮** | 接入 Weapon Player Model API，独立 follow 实体渲染刀皮 |

---

## 更新 / 更改 / 修复内容

**更新（新增）**
- 接入 WPM API（`api_wpn_player_model_set`），第三人称刀皮独立实体渲染，解决自定义人物模型下刀皮失效。
- 换队即时换肤：`TeamInfo` 事件捕获，延迟 0.2 秒刷新模型。

**更改**
- 默认皮肤玩家换队后用 `rg_reset_user_model(id, true)` 重置模型，避免残留上一阵营模型。

**修复**
- 换队后皮肤不跟随阵营（旧阵营模型残留）。
- 切刀 / 切武器后视角内皮肤丢失。

---

## 编译依赖

- `amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`
- `hns_matchsystem`（比赛系统头文件）
- `api_weapon_player_model`（WPM API 头文件，见仓库 `include/`）

> 需同时加载 `addon_weapon_player_model.amxx`（WPM 依赖插件），源码见仓库 `scripting/addon_weapon_player_model.sma`。