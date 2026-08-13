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
- [融合版使用教程](#融合版使用教程)
- [IC 点系统（DLC）与对接教程](#ic-点系统dlc与对接教程)
- [这是什么](#这是什么)
- [版本历史归档](#版本历史归档)
- [项目结构](#项目结构)
- [工作原理：它是怎么触发的](#工作原理它是怎么触发的)
  - [皮肤系统 HnsSkin.sma](#皮肤系统-hnsskinsma)
  - [DLC 音效 HnsDlcSkin.sma](#dlc-音效-hnsdlcskinsma)
  - [DLC 饰品 HnsDlcAccessory.sma](#dlc-饰品-hnsdlcaccessorysma)
- [技术栈与语言](#技术栈与语言)
- [安装方法](#安装方法)
- [配置文件说明](#配置文件说明)
- [命令列表](#命令列表)
- [未来可扩展方向](#未来可扩展方向)
- [如何二次开发与维护](#如何二次开发与维护)
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
3. **僵尸服接入 + 模式自动切换** — 加“模式适配器”实现

详见 [《GUIDE.md》](GUIDE.md)。

---
## 融合版使用教程

**v3.0.0 起，皮肤系统与 IC 点系统已融合为单个插件 `HnsSkin.amxx`**：一个插件同时搞定皮肤选择 / 管理员发放 / IC 积分累计 / 积分兑换 / 对外接口，皮肤与积分共用一份存档，`/skin` 主菜单直接显示并兑换积分。

> 📖 从"第一步下载什么"到"比赛系统自动发分"，每一步都有讲解，零基础也能照做：
> 👉 [《融合版使用教程》](docs/融合版使用教程.md)

**游戏内快速上手：**

| 功能 | 方式 |
|------|------|
| 打开皮肤主菜单（含 IC 兑换） | 按 **Y** 输入 `/skin` |
| 打开 IC 菜单 | 按 **N 键** 或输入 `/ic` |
| 管理员给予 IC 点 | `/givetic <玩家名\|@ALL> <数量>`（需 admin） |
| 积分兑换皮肤 | 人物 500 分 / 刀 300 分（CVAR 可配置） |

---
## IC 点系统（DLC）与对接教程

IC 点系统 `HnsICPointMenu` 是皮肤系统的一个 **DLC 扩展**，也是**完全独立**的积分系统：

- **零依赖**：不依赖任何比赛系统 / PersistentDataStorage，仅用 AMXX 内置模块（`reapi` / `nvault`），可直接独立运行。
- **双插口对接**：对外暴露 `ic_add_points(id, 数量)` 与 `ic_get_points(id)` 两个 native 接口，供你的比赛系统自行对接发放积分。
- **发分时机由你定**：赢家 +10、输家 +5、参与就 +1……全看你的比赛规则，IC 点系统不替你决定。

> 📖 **想对接 IC 点系统？** 我们为**零基础玩家**写了完整教程，从"插插头"讲起，一步步带你接到任意比赛规则上：
> 👉 [《IC 点系统对接教程》](docs/IC点系统对接教程.md)

**游戏内用法（无需对接即可用）：**

| 功能 | 方式 |
|------|------|
| 玩家打开 IC 菜单 | 按 **N 键** 或聊天框输入 `/ic` |
| 管理员给予 IC 点 | `/givetic <玩家名\|@ALL> <数量>`（需 admin） |
| 积分兑换皮肤 | 人物 500 分 / 刀 300 分（CVAR 可配置） |

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

---

## 项目结构

```
hns-skin-system/
├── HnsSkin.sma              ← 核心插件（融合版 v3.0.0：皮肤 + IC 积分）
├── player_models.ini        ← 皮肤配置（T / CT / 刀 / USP 模型库）
├── LICENSE                  ← GPLv3 开源协议
├── assets/
│   ├── linna_avatar.png     ← 封面形象图
│   └── preview.png          ← 预览图
├── versions/                ← 历史版本源码归档（独立版 v1.0.0/v1.1.0/v2.0.0/v2.01 + 比赛版 v5.0.0）
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
    ├── HnsDlcSkin.sma       ← DLC：音效扩展（死亡音效 / 刀击音效）
    ├── HnsDlcAccessory.sma  ← DLC：饰品扩展（帽子 / 翅膀 / 面部）
    └── configs/
        ├── dlc_skin.ini     ← 音效配置
        └── dlc_accessory.ini← 饰品配置
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

1. **命令触发**：`register_clcmd` 拦截 `/skin`、`/skin_t`、`/skin_ct`、`/skin_knife`。
2. **重生触发**：用 ReGameDLL 的 `RegisterHookChain(RG_CBasePlayer_Spawn, ...)`，玩家每次重生自动重新套用已选皮肤，避免换图/死亡后丢失。
3. **切刀触发**：拦截 `CurWeapon` 消息 + `Ham_Item_Deploy`(post)，切到刀时自动重新应用刀皮肤，防止视角内模型丢失。
4. **数据持久化**：所有选择写进 `nvault`，重连、重启服务器都不丢。

### DLC 音效 HnsDlcSkin.sma

**触发链路：**

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

**触发链路：**

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

刀模型只需填 `v_knife.mdl`，插件会自动把 `p_knife.mdl` 设为第三人称模型，并通过 WPM follow 实体稳定渲染（即使玩家套了自定义人物模型也能正常显示）。

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

[back]
"天使翅膀" "models/accessory/angel_wings.mdl" "-8 0 20" "1.0"

[face]
"墨镜" "models/accessory/sunglasses.mdl" "0 0 32" "1.0"
```

格式：`"名称" "模型路径" "坐标偏移X Y Z" "缩放比例"`。模型放 `<cstrike>/models/` 目录。

---

## 命令列表

### 皮肤系统

| 命令 | 说明 | 权限 |
|------|------|------|
| `/skin` | 打开皮肤主菜单 | 所有人 |
| `/skin_t` | 直接打开 T 皮肤选择 | 所有人 |
| `/skin_ct` | 直接打开 CT 皮肤选择 | 所有人 |
| `/skin_knife` | 直接打开刀皮肤选择 | 所有人 |
| `/giveskin` | 打开皮肤发放菜单 | 管理员 |
| `/giveallskins` | 批量发放全部皮肤 | 管理员 |
| `/giveskinid` | 命令行发放皮肤 | 管理员 |

### DLC 音效

| 命令 | 说明 | 权限 |
|------|------|------|
| `/dlc_reload` | 重载音效配置 | ADMIN_RCON |

### DLC 饰品

| 命令 | 说明 | 权限 |
|------|------|------|
| `/acc` / `/accessory` | 打开饰品菜单 | 所有人 |
| `/acc_reload` | 重载饰品配置 | ADMIN_RCON |

---

## 未来可扩展方向

这套架构刻意做成了"配置驱动 + 事件驱动"，扩展点非常清晰：

1. **无限皮肤池**：往 `player_models.ini` 加模型行即可，菜单自动分页，无需改代码。

2. **更多 DLC 槽位**：`HnsDlcAccessory.sma` 目前有 `hat/back/face` 三个槽位，可扩展 `MAX_SLOTS` 增加宠物、光环、脚印等。

3. **音效精细分级**：目前死亡音效按"模型"匹配，可扩展为按"击杀方式/武器/连杀数"匹配，做出连杀音效、爆头音效。

4. **皮肤交易/合成**：基于已有的 nvault 拥有列表，可加 `/trade` 交易系统或皮肤合成系统。

5. **Web 后台管理**：可对接数据库（SQLite/MySQL）替代 nvault，配合 Web 面板做皮肤商城、积分兑换。

6. **与比赛系统联动**：虽然 HnsSkin 本身独立，但可通过 `hns_match_finished` 等 Forward 在比赛结束后给获胜方发放限定皮肤。

7. **第一人称特效**：基于 ReGameDLL 可加粒子、发光、特效枪皮等，让 DLC 生态更丰富。

---

## 如何二次开发与维护

**开发环境：**

1. 安装 AMX Mod X SDK（含 `amxxpc` 编译器与 `include/` 头文件）。
2. 把 `scripting/` 与本项目的源码文件放到一起，确保能 include 到 `reapi.inc`、`fakemeta.inc` 等。
3. 改完 `.sma` 后编译：`amxxpc 你的插件.sma`。
4. 在测试服务器 `amxx plugins` 确认加载无报错。

**维护约定：**

- 所有配置都走 `.ini`，不要硬编码模型/音效路径。
- 新增可复用函数用 `stock` 声明，方便其他插件调用。
- nvault 键名统一加前缀（如 `skinsys_`、`dlcacc_`），避免冲突。
- 改完记得更新 `dlc_*.ini` 的注释示例，保持文档与实现同步。

**遇到问题：**

- 插件没加载 → 看 `addons/amxmodx/logs/` 下的错误日志，确认模块是否齐全。
- 模型闪成原始 → 检查 `player_models.ini` 路径是否大小写一致、模型是否已 `precache`。
- DLC 无音效 → 确认 ReGameDLL 已装，且音效已 `precache_sound`。

---

## 版本历史归档

HnsSkin 历代版本源码已按版本独立归档在 [`versions/`](versions/)，每个版本目录内含该版完整源码与版本说明 `VERSION.md`（更新/更改/修复详情）：

**独立版 HnsSkin（仓库根目录 `HnsSkin.sma`）**

| 版本 | 日期 | 定位 | 归档目录 |
|------|------|------|---------|
| **v3.0.0**（当前推荐） | 2026-08-13 | 皮肤 × IC 积分融合版（一个插件搞定） | [versions/v3.0.0](versions/v3.0.0/) |
| v2.01 | 2026-08-12 | 纯标准字段方案，移除 WPM 依赖 | [versions/v2.01](versions/v2.01/) |
| v2.0.0 | 2026-08-10 | +WPM 第三人称刀皮（依赖 WPM） | [versions/v2.0.0](versions/v2.0.0/) |
| v1.1.0 | 2026-08-10 | +USP 皮肤、多项修复 | [versions/v1.1.0](versions/v1.1.0/) |
| v1.0.0 | 2026-08-06 | 初始稳定版 | [versions/v1.0.0](versions/v1.0.0/) |

**比赛版 HnsMatchSkin（服务器实际使用）**

| 版本 | 定位 | 归档目录 |
|------|------|---------|
| v5.0.0 | 玩家+管理员皮肤、M键菜单、发放、换队即时换肤、WPM | [versions/match-skin-v5](versions/match-skin-v5/) |

> 历史版本源码备份于此，便于查阅、对比与回滚。详见 [`versions/README.md`](versions/README.md)。

---

## 版本更新日志

### v3.0.0（2026-08-13）— 皮肤 × IC 积分融合版

**🆕 更新内容（关键）**

| 更新 | 说明 |
|------|------|
| 皮肤系统 × IC 点系统融合 | 将独立版 `HnsSkin` 与 `HnsICPointMenu` 合并为单个插件 `HnsSkin.amxx`，一个插件同时搞定皮肤 + IC 积分 |
| 统一主菜单 | `/skin` 主菜单新增「IC积分兑换」「查看积分」入口，实时显示当前积分 |
| 共用存档 | 皮肤与 IC 积分共用同一个 nvault 存档，零额外依赖 |
| 积分兑换永久解锁 | 用 IC 分兑换的皮肤直接解锁为玩家已拥有皮肤（永久），走皮肤系统统一的选择 / 应用 / 持久化流程 |
| 保留对外接口 | 仍暴露 `ic_add_points` / `ic_get_points` native 接口，比赛系统可自行对接发分 |

**🔧 融合细节**

| 项 | 说明 |
|------|------|
| 菜单 ID 隔离 | 皮肤菜单（8001~8009）与 IC 菜单（8101~8103）分区，互不冲突 |
| 共享 / 非共享模式 | `skinsys_shared` 控制 CT/T 是否共用人物皮肤，两种模式下主菜单与按键逻辑自适应 |
| 管理员命令 | `/givetic`、`/giveic`、`/addic` 直接给予 IC 点（仅认 users.ini 官方认证管理员） |

**⚠️ 升级提示**

- 替换 `HnsSkin.amxx` 即可，无需再单独安装 `HnsICPointMenu.amxx`。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。
- 若旧服同时装了独立版皮肤与 IC 点插件，请从 plugins.ini 移除旧插件，只保留融合版。

### v2.01（2026-08-12）— 纯标准字段方案，移除 WPM 依赖

**🆕 更新内容（关键）**

| 更新 | 说明 |
|------|------|
| 彻底移除 WPM 依赖 | 不再调用任何 WPM 原生函数（`api_wpn_player_model_*`），不再依赖 `addon_weapon_player_model.amxx` 与 `api_weapon_player_model.inc` |
| 改用 CS 引擎原生标准字段 | 刀/手枪皮肤直接写到武器实体上，全服务器兼容 |
| 第一人称刀皮 | 武器实体 `pev_viewmodel`（`v_knife.mdl`） |
| 第三人称刀皮 | 武器实体 `pev_weaponmodel`（`p_knife.mdl`），仅当 `p_` 模型存在时设置 |

**🔧 修复内容**

| 修复 | 说明 |
|------|------|
| 插件加载失败导致皮肤完全不显示 | 旧版调用 WPM 原生函数，若服务器未加载 WPM 插件，AMXX 加载时找不到原生函数使整个插件加载失败；本版彻底移除该依赖 |
| 换手/切回刀后皮肤变默认 | `Ham_Item_Deploy`(post) + `CurWeapon` 消息重新套用刀皮 |
| 切到手雷等武器出现左手、模型丢失 | 不再触碰玩家实体/武器扩展字段，手雷等武器渲染完全正常 |

**⚠️ 升级提示**

- 仅替换 `HnsSkin.amxx` 即可，无需再安装 `addon_weapon_player_model.amxx`。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。

### v2.0.0（2026-08-10）— 第三人称刀皮肤 WPM 增强

**🆕 新增内容**

| 新增 | 说明 |
|------|------|
| 第三人称刀皮肤 WPM 渲染 | 接入 [Weapon Player Model API](https://github.com/YoshiokaHaruki/AMXX-API-Weapon-Player-Model)，用 `MOVETYPE_FOLLOW` 独立实体跟随玩家骨骼渲染刀皮，彻底解决"玩家套自定义模型后第三人称刀皮失效"的老问题 |
| `hns_skin_wpm` 开关 | 新增 cvar（默认 `1` 开启），可设 `0` 关闭并回退到传统的 `pev_weaponmodel2` 渲染 |
| WPM 依赖文件 | 附带 `addon_weapon_player_model.amxx`、`api_weapon_player_model.inc`、`p_null.mdl`，开箱即用 |

**🔧 改动点**

- `set_player_knife_view()` 在原有第一/第三人称设置后，追加 `api_wpn_player_model_set()` 创建 follow 实体渲染刀皮
- `client_disconnected()` 追加 `api_wpn_player_model_remove()` 清理实体
- 新增 `addon_weapon_player_model.amxx` 为硬依赖，需与 `HnsSkin.amxx` 同时加载

**⚠️ 升级提示**

- 替换 `HnsSkin.amxx` 的同时，必须安装 `addon_weapon_player_model.amxx`（放在 `HnsSkin.amxx` 之前加载），否则插件无法启动。
- 已有玩家皮肤数据（nvault）不受影响，自动保留。

### v1.1.1（2026-08-10）— 修复换队后默认皮肤不跟随阵营

**🔧 修复内容（核心）**

| 修复 | 说明 |
|------|------|
| 换队后「默认皮肤」不跟随阵营 | **根因**：`rg_reset_user_model(id)` 默认 `update_index=false`，只重置模型标识字符串，**不刷新可见模型**。玩家未选择皮肤（默认皮肤）换队时，旧阵营模型残留，导致 T 穿上 CT 衣服、或警察刀匪变匪后皮肤不变。**修复**：改为 `rg_reset_user_model(id, true)`，换队时立即刷新可见模型到新阵营默认 |
| 刀切武器皮肤丢失 | 修正 `CurWeapon` 消息回调参数：`register_message` 回调签名是 `(msg_id, dest, in_entity)`，玩家 id 取第 3 个参数 `in_entity`，避免误用 msg_id 导致切刀后视角刀皮被还原 |

**⚠️ 升级提示**

- 直接替换 `HnsSkin.amxx` 即可。此项修复同时已同步至服务器实际使用的 `HnsMatchSkin.amxx`。

### v1.1.0（2026-08-10）— 修复多项 bug + 新增 USP 皮肤

**🆕 新增内容**

| 新增 | 说明 |
|------|------|
| USP 皮肤系统 | 新增完整的第一人称视角 USP 枪械皮肤支持，玩家可选择自定义 USP 模型 |
| `/skin_usp` 命令 | 直接打开 USP 皮肤选择菜单 |
| USP 皮肤回退机制 | 所选模型文件不存在时自动回退默认 USP，避免视角模型丢失/报错 |

**🔧 修复内容**

| 修复 | 说明 |
|------|------|
| 换队后皮肤不刷新 | 通过捕获 `TeamInfo` 事件，玩家换队时立即重新套用对应阵营皮肤，不再闪回默认模型 |
| 切武器视角模型丢失 | 新增 `Ham_Item_Deploy` 钩子，切到刀/USP 时自动重新应用已选皮肤 |
| 刀皮肤切换丢失 | 修正 `CurWeapon` 消息拦截逻辑，切刀时视角内模型保持正确 |
| 模型缺失兼容 | 皮肤文件不存在时安全回退默认模型，不再闪成原始模型或报错 |

**📁 配置更新**

- `player_models.ini` 新增 `[USP]` 分区，用于配置 USP 皮肤模型库。

**⚠️ 升级提示**

- 直接替换 `HnsSkin.amxx` 并覆盖 `player_models.ini` 即可，已有玩家皮肤数据（nvault）不受影响、自动保留。

### v1.0.0（初始版本）

- 独立皮肤系统首版发布：T / CT / 刀皮肤加载与发放、`nvault` 持久化、分页菜单。
- 附带 DLC 扩展：音效（`HnsDlcSkin.amxx`）与饰品（`HnsDlcAccessory.amxx`）。

---

## 开源协议

本项目基于 **GPLv3** 协议开源，自由使用、修改和分发。

---

**HnsSkin Skin System** — Built with passion for the CS 1.6 HNS community.
维护者：**LINNA**

---

<div align="center">

### <span style="color:red">⚠️ 严令禁止倒卖插件 ⚠️</span>

<span style="color:red">**本项目为原创独立开发作品，严禁任何形式的倒卖、转售或商业牟利行为！**</span>

<span style="color:red">源码已开源仅供学习交流与个人使用，未经授权不得将其打包、改头换面后用于收费出售、捆绑销售或二次分发获利。</span>

<span style="color:red">**一经发现，将直接追究相关法律责任，并停止后续更新与技术支持。**</span>

<span style="color:#ff8c00">如发现有人倒卖本插件，欢迎向维护者 **LINNA** 举报。</span>

</div>