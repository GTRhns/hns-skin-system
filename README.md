# HnsSkin — CS 1.6 独立皮肤系统

> 一款完全独立的 Counter-Strike 1.6 AMX Mod X 皮肤插件。
> 不依赖任何比赛系统，即插即用。

---

## 功能特点

- **独立运行** — 无需 HNS 比赛系统或其他第三方插件，开箱即用
- **三种皮肤类型** — T 阵营、CT 阵营、刀皮肤，各有独立的皮肤库

- **第一人称+第三人称** — 刀皮肤同时设置 `pev_viewmodel`（自己看）和 `pev_weaponmodel`（别人看）
- **武器切换自动应用** — 切换到刀时自动重新应用皮肤，不会丢失
- **分页菜单** — 皮肤数量再多也能通过翻页选择，带边界检查防止溢出
- **数据持久化** — 通过 nvault 存储玩家拥有的皮肤和选择，重连不丢失
- **皮肤发放系统** — 管理员可通过菜单或命令向玩家发放皮肤
- **批量发放** — 支持一键发放全部皮肤

## 命令列表

| 命令 | 说明 | 权限 |
|------|------|------|
| `/skin` | 打开皮肤主菜单 | 所有人 |
| `/skin_t` | 直接打开 T 皮肤选择 | 所有人 |
| `/skin_ct` | 直接打开 CT 皮肤选择 | 所有人 |
| `/skin_knife` | 直接打开刀皮肤选择 | 所有人 |
| `/giveskin` | 打开皮肤发放菜单 | 管理员(LEVEL_A) |
| `/giveallskins` | 批量发放全部皮肤 | 管理员(LEVEL_A) |
| `/giveskinid` | 命令行发放皮肤 | 管理员(LEVEL_A) |

## 依赖模块

服务器必须安装以下 AMX Mod X 模块：

| 模块 | 用途 |
|------|------|
| **amxmodx** | 核心 API |
| **fakemeta** | 引擎接口（设置刀模型） |
| **amxmisc** | 工具函数 |
| **reapi** | ReGameDLL API（重生 Hook、设置模型） |
| **nvault** | 数据持久化存储 |

## 安装方法

### 1. 安装插件

```bash
# 将插件放入 plugins 目录
cp compiled/HnsSkin.amxx <cstrike>/addons/amxmodx/plugins/

# 编辑 plugins.ini 添加一行
echo "HnsSkin.amxx" >> <cstrike>/addons/amxmodx/configs/plugins.ini
```

### 2. 安装配置文件

```bash
# 创建配置目录
mkdir -p <cstrike>/addons/amxmodx/configs/mixsystem/

# 复制配置文件
cp configs/player_models.ini <cstrike>/addons/amxmodx/configs/mixsystem/
```

### 3. 重启服务器或换图生效

```
amxx plugins  # 确认 HnsSkin.amxx 已加载
```

## 配置文件说明

### `configs/mixsystem/player_models.ini`

普通玩家皮肤配置，格式：

```ini
[T]
显示名称 models/player/文件夹/模型.mdl

[CT]
显示名称 models/player/文件夹/模型.mdl

[Knife]
显示名称 models/v_knife.mdl
```

刀模型只需填写 `v_knife.mdl` 路径，插件会自动将 `p_knife.mdl` 设为第三人称模型。

## 皮肤发放

### 菜单方式

```
/giveskin → 选择目标玩家 → 选择发放类型 → 选择具体皮肤
```

### 命令方式

```
/giveallskins <玩家名> <T/CT/Knife/all>
/giveskinid <玩家名> <T/CT/Knife> <皮肤名>
```

## 数据存储

所有皮肤数据存储在 nvault 中，键名前缀为 `skinsys_`，文件位于：

```
<cstrike>/addons/amxmodx/data/vault/skinsys_skin_vault.vault
```

## 开发者

### 编译源码

```bash
# 需要 amxxpc 编译器和相关 include 文件
amxxpc HnsSkin.sma -ocompiled/HnsSkin.amxx
```

### 兼容性

- 测试环境：AMX Mod X 1.10, Counter-Strike 1.6
- 支持正版（SteamID）和盗版（IP）玩家
- 皮肤数据在正版和盗版之间不互通

## 开源协议

本项目基于 GPLv3 协议开源，自由使用、修改和分发。