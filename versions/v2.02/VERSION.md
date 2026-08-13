# HnsSkin v2.02 — 皮肤系统修复版（独立版当前推荐）

> 独立皮肤系统当前推荐版本。本目录为该版本源码备份，与仓库根目录 `HnsSkin.sma` 保持一致。
> 完整发行版（含 DLC + IC 点）见 GitHub Release `v2.02`。

- **版本号**：`2.02`
- **发布日期**：2026-08-13
- **插件标识**：`HnsSkin Skin System`（`#define PLUGIN_VERSION "2.02"`）
- **文件清单**：
  - `HnsSkin.amxx` — 编译插件（可直接部署）
  - `HnsSkin.sma` — 完整源码
- **协议**：GPLv3

---

## v2.02 修复内容

| # | 修复 | 说明 |
|---|------|------|
| 1 | 主菜单未注册 | `/skin` 主菜单从未 `register_menucmd`，导致按键无效 |
| 2 | `FM_CurWeapon` 回调签名错误 | 原版写成单参数，钩子完全失效；改为 `(msgId, msgDest, entity)` |
| 3 | `TeamInfo` 使用错误玩家 ID | 换队刷新皮肤失败；改用 `get_msg_arg_int(1)` 取换队玩家 |
| 4 | USP 皮肤不持久 | 切换后丢失；补全 USP 数组的保存/加载/解析 |
| 5 | JSON 解析截断 | 拷贝长度漏 +1，最后一个元素被截断 |
| 6 | 皮肤发放不持久化 | 补全皮肤发放的持久化逻辑 |
| 7 | `/take` 命令未注册 | 补上命令注册与实现 |
| 8 | 权限等级判断缺失 | 区分管理员与服主 |
| 9 | viewmodel 字段混用 | 统一模型应用字段 |
| 10 | USP 数组内存泄漏 | 清理时销毁 USP 数组 |

---

## 版本沿革

- `v2.0.0`：WPM 第三人称刀皮方案（依赖 `api_weapon_player_model`）。
- `v2.01`：移除 WPM 依赖，改用 CS 引擎原生标准字段；收紧皮肤发放权限，仅认官方认证管理员。
- `v2.02`（本版）：在 v2.01 基础上修复上述 10 项 bug，并重新整合 DLC + IC 点完整发行版。

---

## 编译依赖

`amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`、`engine`

## 部署

- 仅替换 `HnsSkin.amxx` 即可启用皮肤本体。
- 如需 DLC / IC 点，请使用 Release `v2.02` 的完整包 `HNS_Skin_v2.02_Full.zip`。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。