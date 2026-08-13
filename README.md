<div align="center">

<img src="assets/linna_avatar.png" alt="Linna" width="300">

<br>

# HnsSkin+IC — CS 1.6 皮肤 × IC 积分融合版

[![AMX Mod X](https://img.shields.io/badge/AMX_Mod_X-1.10+-blue)]()
[![ReGameDLL](https://img.shields.io/badge/ReGameDLL-5.x-orange)]()
[![Version](https://img.shields.io/badge/Version-3.0.0-green)]()
[![DLC](https://img.shields.io/badge/DLC-IC_Point_%2B_Accessory-9cf)]()
[![License](https://img.shields.io/badge/License-GPLv3-success)]()

> **一个插件，同时搞定「皮肤系统」和「IC 积分系统」。**
> 融合了皮肤系统的多类型皮肤选择 / 管理员发放，与 IC 点系统的积分累计 / 兑换 / 对外接口，
> 取各自长处合二为一，即插即用、零额外依赖。
>
> **维护者 / 联系人：LINNA** · Art by Linna

</div>

---

## 目录

- [示例图](#示例图)
- [深入指南 GUIDE](#深入指南-guide)
- [这是什么](#这是什么)
- [版本历史与修复记录](#版本历史与修复记录)
- [项目结构](#项目结构)
- [工作原理：它是怎么触发的](#工作原理它是怎么触发的)
- [对外接口（Native）](#对外接口native)
- [技术栈与语言](#技术栈与语言)
- [安装方法](#安装方法)
- [配置文件说明](#配置文件说明)
- [命令列表](#命令列表)
- [未来可扩展方向](#未来可扩展方向)
- [开源协议](#开源协议)

---

## 示例图

以下是游戏内实际效果截图，展示不同皮肤模型在 CS 1.6 场景中的展示效果：

<div align="center">

<img src="assets/screenshots/skin_showcase_1.jpg" alt="皮肤展示 1" width="420">
<img src="assets/screenshots/skin_showcase_2.jpg" alt="皮肤展示 2" width="420">
<img src="assets/screenshots/skin_showcase_3.jpg" alt="皮肤展示 3" width="420">
<img src="assets/screenshots/skin_showcase_4.jpg" alt="皮肤展示 4" width="420">

</div>

---

## 深入指南 GUIDE

对于开发者和服主，这份文档解答三件事：

1. **代码怎么形成的** — 架构与触发原理
2. **适用/不适用哪些服** — 审辨判断标准
3. **僵尸服接入 + 模式自动切换** — 加"模式适配器"实现

详见 [《GUIDE.md》](GUIDE.md)。

---

## 这是什么

HnsSkin+IC 是一个**独立的皮肤加载 / 发放 + IC 积分系统**（v3.0.0 融合版）。核心插件 `HnsSkin.sma` 负责两件事：

1. **让玩家能用上自定义的 T / CT / 刀 / USP 皮肤**，并通过 `nvault` 永久记住每个玩家拥有哪些皮肤。
2. **IC 积分体系**：打比赛 / 活动获得积分，用积分解锁皮肤，对外提供 `ic_add_points` / `ic_get_points` 接口供比赛系统对接。

它被设计成**完全独立**的插件：

- 不 include 任何比赛系统头文件
- 不依赖比赛系统的 Forward / Native
- 关闭比赛系统它照样工作
- 放到任何 CS1.6 + AMX Mod X 服务器都能跑

在它之上，`dlc/` 目录下还有**可选扩展**，组成一个完整的"皮肤 + 音效 + 饰品"生态：

| 扩展 | 功能 | 是否必须 |
|------|------|----------|
| `HnsSkin.sma` | 皮肤 + IC 积分（融合版 v3.0.0） | 必须 |
| `HnsDlcSkin.sma` | 按皮肤模型替换死亡音效、刀击音效 | 可选 |
| `HnsDlcAccessory.sma` | 头部 / 背部 / 面部饰品（帽子、翅膀等） | 可选 |
| `HnsDlcKnife3P.sma` | 第三人称刀皮肤增强 | 可选 |

---

## 版本历史与修复记录

### v3.0.0（2026-08-13）— 皮肤 × IC 积分融合版（当前推荐）

将独立版 `HnsSkin`（皮肤系统）与 `HnsICPointMenu`（IC 点系统）**合二为一**，取各自长处：

| 来源 | 保留的长处 |
|------|-----------|
| 皮肤系统 | 多类型皮肤（T/CT/刀/USP）、共享皮肤模式、管理员发放/收回、选择持久化、纯标准字段方案 |
| IC 点系统 | IC 积分体系、积分兑换皮肤、对外 native 接口（`ic_add_points` / `ic_get_points`）、管理员直接给予 |

**整合点：**
- `/skin` 主菜单增加「IC积分兑换」「查看积分」入口，实时显示当前积分。
- 用 IC 分兑换的皮肤直接解锁为玩家已拥有皮肤（永久），走皮肤系统统一流程。
- 皮肤与 IC 积分共用同一个 nvault 存档，零额外依赖。

### v2.02（2026-08-13）— 皮肤系统修复版

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

### v2.01（2026-08-12）— 纯标准字段方案

| 修复 | 说明 |
|------|------|
| 插件加载失败导致皮肤完全不显示 | 旧版调用 WPM 原生函数，若服务器未加载 WPM 插件，AMXX 加载时找不到原生函数使整个插件加载失败；本版彻底移除该依赖 |
| 换手 / 切回刀后皮肤变默认 | `Ham_Item_Deploy`(post) + `CurWeapon` 消息重新套用刀皮 |
| 切到手雷等武器出现左手、模型丢失 | 不再触碰玩家实体/武器扩展字段，手雷等武器渲染完全正常 |

### v2.0.0（2026-08-10）— 第三人称刀皮肤 WPM 增强版

| 修复 | 说明 |
|------|------|
| 自定义人物模型下第三人称刀皮失效 | 通过 WPM follow 实体独立渲染，不再受玩家身体模型替换干扰 |
| 切刀后视角内模型丢失 | 复用 WPM 实体，保证切刀时第三人称刀皮稳定显示 |

### v1.1.0（2026-08-10）— 功能增强版（+USP 皮肤）

| 修复 | 说明 |
|------|------|
| 换队后皮肤不刷新 | 捕获 `TeamInfo` 事件，玩家换队时立即重新套用对应阵营皮肤 |
| 切武器视角模型丢失 | 新增 `Ham_Item_Deploy` 钩子，切到刀/USP 时自动重新应用已选皮肤 |
| 刀皮肤切换丢失 | 修正 `CurWeapon` 消息拦截逻辑，切刀时视角内模型保持正确 |
| 模型缺失兼容 | 皮肤文件不存在时安全回退默认模型，不再闪成原始模型或报错 |

### v1.0.0（2026-08-06）— 初始稳定版

首版发布：T/CT 阵营皮肤、刀皮肤、管理员发放、分页菜单、nvault 持久化、SteamID/IP 玩家鉴权。

---

## 项目结构

```
hns-skin-system/
├── HnsSkin.sma              ← 核心插件（融合版 v3.0.0：皮肤 + IC 积分）
├── player_models.ini        ← 皮肤配置（T / CT / 刀 / USP 模型库）
├── LICENSE                  ← GPLv3 开源协议
├── assets/
│   ├── linna_avatar.png     ← 封面形象图
│   ├── preview.png          ← 预览图
│   └── screenshots/         ← 游戏内效果截图
├── versions/                ← 历史版本源码归档（v1.0.0/v1.1.0/v2.0.0/v2.01/v2.02/v3.0.0 + 比赛版 v5.0.0 + IC 独立版）
├── scripting/
│   └── addon_weapon_player_model.sma ← WPM API 依赖插件源码（v2.01 起不再需要）
├── compiled/
│   └── HnsSkin.amxx            ← 融合版编译产物（v3.0.0）
├── include/
│   ├── ic_points.inc           ← IC 点对外接口头文件（供比赛系统对接）
│   └── api_weapon_player_model.inc   ← WPM API 头文件（v2.01 起不再需要）
├── models/
│   └── p_null.mdl            ← WPM 附件移动占位模型（v2.01 起不再需要）
└── dlc/
    ├── HnsSkin.sma           ← 融合版（皮肤 + IC 积分）
    ├── HnsICPointMenu.sma    ← IC 点系统（DLC）
    ├── HnsDlcSkin.sma        ← DLC：音效扩展（死亡音效 / 刀击音效）
    ├── HnsDlcAccessory.sma   ← DLC：饰品扩展（帽子 / 翅膀 / 面部）
    ├── HnsDlcKnife3P.sma     ← DLC：第三人称刀皮肤增强
    ├── ic_points.inc         ← IC 点接口头文件
    └── configs/
        ├── dlc_skin.ini      ← 音效配置
        └── dlc_accessory.ini ← 饰品配置
```

---

## 工作原理：它是怎么触发的

### 皮肤系统 HnsSkin.sma

**触发链路（选皮肤 → 应用模型）：**

```
玩家输入 /skin
   │
   ├─→ 解析命令 register_clcmd("say /skin", ...)
   │
   ├─→ 读取玩家鉴权信息（SteamID 或 IP，正版/盗版都支持）
   │
   ├─→ 从 nvault 读取该玩家已拥有的皮肤列表 & 当前选择
   │       键名前缀 skinsys_，文件：data/vault/skinsys_skin_vault.vault
   │
   ├─→ 弹出分页菜单（T / CT / 刀三个子菜单）
   │
   └─→ 玩家选定后，写入 nvault 并立即应用：
         - T/CT 皮肤 → 调用引擎 SetModel 换身体模型
         - 刀皮肤    → 武器实体 pev_viewmodel（自己看 v_knife.mdl）
                        + pev_weaponmodel（别人看 p_knife.mdl）
                        （CS 引擎原生标准字段，全服务器兼容，不依赖 WPM）
```

**关键触发点：**

1. **命令触发**：`register_clcmd` 拦截 `/skin`、`/skin_t`、`/skin_ct`、`/skin_knife`、`/skin_usp`。
2. **重生触发**：用 ReGameDLL 的 `RegisterHookChain(RG_CBasePlayer_Spawn, ...)`，玩家每次重生自动重新套用已选皮肤，避免换图/死亡后丢失。
3. **切刀触发**：拦截 `CurWeapon` 消息 + `Ham_Item_Deploy`(post)，切到刀时自动重新应用刀皮肤，防止视角内模型丢失。
4. **换队触发**：捕获 `TeamInfo` 事件，玩家换队时立即重新套用对应阵营皮肤。
5. **数据持久化**：所有选择写进 `nvault`，重连、重启服务器都不丢。

### IC 点系统（DLC）

**触发链路（获得积分 → 兑换皮肤）：**

```
比赛系统 / 管理员
   │
   ├─→ 调用 ic_add_points(id, 数量)  ← 对外接口，比赛系统对接
   │
   └─→ 玩家按 N 键 或输入 /ic
        └─→ 打开 IC 点菜单（查看积分 / 兑换皮肤）
             └─→ 积分够 → 解锁皮肤为已拥有（永久）
             └─→ 积分不够 → 提示"积分不足 需要 X 分（当前 Y 分）"
```

### DLC 音效 HnsDlcSkin.sma

```
玩家死亡 OnPlayerKilled
   └─→ 读取玩家当前身体模型路径（models/player/xxx/xxx.mdl）
        └─→ 在 dlc_skin.ini 的 [DeathSounds] 里查找匹配项
             └─→ 命中则 emit_sound 播放自定义死亡音效（同模型可配多个，随机播）

玩家挥刀/击中/重击
   └─→ 缓存当前刀模型 → 在 [KnifeSounds] 匹配
        └─→ Ham_PrimaryAttack = 挥砍音效
        └─→ Ham_SecondaryAttack = 重击音效
        └─→ Ham_TraceAttack = 击中音效
```

刀音效通过 `RegisterHam` 挂在 `weapon_knife` 上，实现"左键挥砍、右键重击、砍中人"三种独立音效。

### DLC 饰品 HnsDlcAccessory.sma

```
玩家输入 /acc 或 /accessory
   └─→ 弹出饰品菜单（hat 头部 / back 背部 / face 面部）
        └─→ 玩家选择 → 写入 nvault
             └─→ 玩家重生 OnPlayerSpawn
                  └─→ 创建 info_target 实体，SetModel 挂上饰品模型
                       └─→ 每 0.5 秒定时任务跟随玩家坐标/朝向刷新位置
                            （背部饰品用 angle_vector 计算背后偏移）
```

饰品用 `MOVETYPE_FOLLOW` 跟随玩家，`pev_aiment` 绑定到玩家实体，做到"挂在身上但不会穿透"。

---

## 对外接口（Native）

### IC 点接口（`include/ic_points.inc`）

| Native | 参数 | 用途 |
|--------|------|------|
| `ic_add_points` | id, 数量 | 给玩家增加 IC 积分（比赛系统发分用） |
| `ic_get_points` | id | 查询玩家当前 IC 积分 |

> **对接方式**：你的比赛系统 `#include <ic_points>` 后，在比赛结束回调里调用 `ic_add_points(id, 10)` 即可发分。发分时机完全由你的比赛规则决定（赢家 +10、输家 +5、参与就 +1……），IC 点系统不替你决定。

### 皮肤系统公开函数（供适配器调用）

| 函数 | 用途 |
|------|------|
| `set_user_model_from_skin(id)` | 重新应用玩家已选皮肤（僵尸服适配器恢复用） |

---

## 技术栈与语言

| 项 | 说明 |
|----|------|
| **语言** | Pawn（AMX Mod X 脚本语言，C 风格） |
| **运行环境** | Counter-Strike 1.6 + AMX Mod X 1.8.3+ |
| **依赖模块** | `amxmodx`、`fakemeta`、`amxmisc`、`reapi`、`nvault`、`hamsandwich`、`engine`（v2.01 起不再依赖 WPM） |
| **编译工具** | `amxxpc`（AMX Mod X 自带编译器） |
| **数据存储** | `nvault`（AMXX 内置持久化键值库） |

> Pawn 是 AMX Mod X 的官方脚本语言，语法类似 C，但用 `new` 声明变量、用 `stock` 声明可复用函数。所有 CS 插件（包括比赛系统）都用它写，编译产物是 `.amxx` 二进制插件。

---

## 安装方法

源码优先，编译后放入服务器：

```bash
# 1. 编译（把脚本放到 AMXX 的 scripting/ 目录）
amxxpc HnsSkin.sma
amxxpc dlc/HnsDlcSkin.sma
amxxpc dlc/HnsDlcAccessory.sma
```

```bash
# 2. 把生成的 .amxx 复制到 plugins 目录
cp *.amxx <cstrike>/addons/amxmodx/plugins/

# 3. 在 plugins.ini 里启用
echo "HnsSkin.amxx" >> <cstrike>/addons/amxmodx/configs/plugins.ini
echo "HnsDlcSkin.amxx" >> <cstrike>/addons/amxmodx/configs/plugins.ini
echo "HnsDlcAccessory.amxx" >> <cstrike>/addons/amxmodx/configs/plugins.ini
```

```bash
# 4. 复制配置文件
mkdir -p <cstrike>/addons/amxmodx/configs/mixsystem/
cp player_models.ini                <cstrike>/addons/amxmodx/configs/mixsystem/
cp dlc/configs/dlc_skin.ini         <cstrike>/addons/amxmodx/configs/mixsystem/
cp dlc/configs/dlc_accessory.ini    <cstrike>/addons/amxmodx/configs/mixsystem/
```

```bash
# 5. 重启服务器或换图生效
amxx plugins   # 确认插件都已加载
```

> **注意**：`HnsDlcSkin.sma` 和 `HnsDlcAccessory.sma` 需要 ReGameDLL。若服务器未装，可只部署 `HnsSkin.amxx`。
> **v2.01 起**：核心 `HnsSkin.amxx` 不再依赖 WPM 插件，直接部署即可，无需 `addon_weapon_player_model.amxx`。

---

## 配置文件说明

### `player_models.ini`（皮肤配置）

```ini
[T]
显示名称 models/player/文件夹/模型.mdl

[CT]
显示名称 models/player/文件夹/模型.mdl

[Knife]
显示名称 models/v_knife.mdl
```

刀模型只需填 `v_knife.mdl`，插件会自动把 `p_knife.mdl` 设为第三人称模型。

### `dlc_skin.ini`（音效配置）

```ini
[DeathSounds]
"models/player/arctic/arctic.mdl" "dlc/death_arctic.wav"

[KnifeSounds]
"models/v_knife.mdl" "dlc/knife_slash.wav" "dlc/knife_hit.wav" "dlc/knife_stab.wav"
```

音效文件放 `<cstrike>/sound/` 目录。同一模型可写多行死亡音效，死亡时随机播放一个。

### `dlc_accessory.ini`（饰品配置）

```ini
[hat]
"圣诞帽" "models/accessory/santa_hat.mdl" "0 0 36" "1.0"
```

---

## 命令列表

| 命令 | 功能 | 权限 |
|------|------|------|
| `/skin` `/skins` `/models` `/model` | 皮肤主菜单（含 IC 兑换） | 所有人 |
| `/skin_t` | 直达 T 土匪皮肤 | 所有人 |
| `/skin_ct` | 直达 CT 警察皮肤 | 所有人 |
| `/skin_knife` | 直达刀皮肤 | 所有人 |
| `/skin_usp` | 直达 USP 手枪皮肤 | 所有人 |
| `/ic` `/icpoint` 或 **N 键** | IC 点菜单 | 所有人 |
| `/giveskin` | 皮肤发放菜单 | 管理员 |
| `/giveallskins <玩家> <类型>` | 批量发放皮肤 | 管理员 |
| `/giveskinid <玩家> <类型> <皮肤名>` | 命令行发放皮肤 | 管理员 |
| `/take <玩家> <类型> <皮肤名>` | 收回皮肤 | 管理员 |
| `/givetic <玩家名\|@ALL> <数量>` | 给予 IC 积分 | 管理员 |

---

## 未来可扩展方向

1. **皮肤商城**：配合 IC 积分做完整的皮肤商城（限时 / 永久 / 折扣）。
2. **皮肤合成 / 抽奖**：用积分抽皮肤，增加留存。
3. **多服同步**：基于 nvault / MySQL 做多服务器皮肤同步。
4. **Web 管理面板**：在线查看 / 发放皮肤与积分。

---

## 开源协议

本项目基于 **GPLv3** 协议开源，自由使用、修改和分发。

---

**HnsSkin+IC — Skin & IC Point System** — Built with passion for the CS 1.6 HNS community.
维护者：**LINNA**

---

<div align="center">

### <span style="color:red">⚠️ 严令禁止倒卖插件 ⚠️</span>

<span style="color:red">**本项目为原创独立开发作品，严禁任何形式的倒卖、转售或商业牟利行为！**</span>

<span style="color:red">源码已开源仅供学习交流与个人使用，未经授权不得将其打包、改头换面后用于收费出售、捆绑销售或二次分发获利。</span>

<span style="color:red">**一经发现，将直接追究相关法律责任，并停止后续更新与技术支持。**</span>

<span style="color:#ff8c00">如发现有人倒卖本插件，欢迎向维护者 **LINNA** 举报。</span>

</div>
