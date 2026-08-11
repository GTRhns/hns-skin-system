# HnsSkin v2.0.0 — 第三人称刀皮肤 WPM 增强版

> 独立皮肤系统当前推荐版本。本目录为该版本源码备份，与仓库根目录 `HnsSkin.sma` 保持一致。

- **版本号**：`2.0.0`
- **发布日期**：2026-08-10
- **插件标识**：`HnsSkin Skin System`（`#define PLUGIN_VERSION "2.0.0"`）
- **文件清单**：
  - `HnsSkin.amxx` — 编译插件（可直接部署）
  - `HnsSkin.sma` — 完整源码（2524 行）
- **协议**：GPLv3

---

## 更新内容（新增）

| 新增 | 说明 |
|------|------|
| **第三人称刀皮肤 WPM 渲染** | 接入 Weapon Player Model API，用 `MOVETYPE_FOLLOW` 独立实体跟随玩家骨骼渲染刀皮，彻底解决"玩家套自定义模型后第三人称刀皮失效"的老问题 |
| `hns_skin_wpm` 开关 | 新增 cvar（默认 `1` 开启），可设 `0` 关闭并回退到传统 `pev_weaponmodel2` 渲染 |
| WPM 依赖文件 | 附带 `addon_weapon_player_model.amxx`、`api_weapon_player_model.inc`、`p_null.mdl`，开箱即用 |

## 更改内容

- `set_player_knife_view()` 在原有第一/第三人称设置后，追加 `api_wpn_player_model_set()` 创建 follow 实体渲染刀皮。
- `client_disconnected()` 追加 `api_wpn_player_model_remove()` 清理实体。
- 新增 `addon_weapon_player_model.amxx` 为硬依赖，需在所有皮肤插件之前加载。

## 修复内容

| 修复 | 说明 |
|------|------|
| 自定义人物模型下第三人称刀皮失效 | 通过 WPM follow 实体独立渲染，不再受玩家身体模型替换干扰 |
| 切刀后视角内模型丢失 | 复用 WPM 实体，保证切刀时第三人称刀皮稳定显示 |

---

## 部署依赖

- AMX Mod X 1.10+ / ReGameDLL 5.x
- 模块：`amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`、`api_weapon_player_model`

---

## 升级提示

- 替换 `HnsSkin.amxx` 的同时，**必须**安装 `addon_weapon_player_model.amxx`（放在 `HnsSkin.amxx` 之前加载），否则插件无法启动。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。