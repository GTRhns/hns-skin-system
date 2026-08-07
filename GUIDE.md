# HnsSkin 皮肤系统 — 深入指南

> 本文档面向开发者与服主，解答三件事：
> 1. **这套代码是怎么形成的**（架构与触发原理）
> 2. **皮肤系统适用于哪些服、不适用于哪些服**
> 3. **僵尸服如何接入皮肤并实现模式自动切换**

---

## 一、代码是怎么形成的

### 1.1 它从哪来

HnsSkin 最初是 HNS 比赛系统里 `HnsMatchSkin.sma` 的一部分（负责比赛内给玩家换模型）。为了让皮肤系统**脱离比赛系统独立使用**，我们做了三层重构：

1. **去依赖**：删掉所有 `#include <hns_match>`、比赛 Forward、比赛全局变量。
2. **抽配置**：把皮肤列表抽到 `player_models.ini`，用段落 `[T]/[CT]/[Knife]` 区分三类皮肤。
3. **加持久化**：用 `nvault` 保存"玩家拥有哪些皮肤 + 当前选择"，重连不丢。

重构后它变成一个**自包含插件**：只依赖 AMXX 基础模块（`fakemeta`、`nvault`、`reapi`），不碰任何比赛系统。

### 1.2 核心数据流

```
player_models.ini
   │  编译时读取（plugin_precache）
   ▼
内存数组 g_aTModels / g_aCTModels / g_aKnifeModels   ← 皮肤模型路径
   + g_aTModelNames / ...                            ← 皮肤显示名
   │
   ▼
游戏内玩家操作
   /skin → cmdSkinMain() → showSkinSelectMenu() → 分页菜单
   │                                            │
   │                                            ▼ 选中
   │                                    nvault 写入“拥有+当前选择”
   │                                            │
   ▼                                            ▼
玩家重生 OnPlayerSpawn（HookChain） ──→ 自动套用已选皮肤
   │
   ▼
刀皮肤额外：CurWeapon 消息 → 切刀时重设 pev_viewmodel2 / pev_weaponmodel2
```

### 1.3 关键触发点（Event 钩子）

| 事件 | 作用 | 实现 |
|------|------|------|
| `plugin_precache` | 编译时读配置、预缓存模型 | `fopen` 解析 ini + `precache_model` |
| `cmdSkinMain` | `/skin` 命令 | `register_clcmd("say /skin", ...)` |
| `OnPlayerSpawn` | 重生自动应用皮肤 | `RegisterHookChain(RG_CBasePlayer_Spawn, ...)` |
| `CurWeapon` | 切刀防丢模型 | `register_message(get_user_msgid("CurWeapon"), ...)` |
| 菜单回调 | 分页/选择 | `register_menucmd(register_menuid(...), 1023, ...)` |

### 1.4 为什么这样设计

- **配置驱动**：加皮肤只改 ini，不改代码，菜单自动分页。
- **数据驱动**：`nvault` 键值存储，天然支持断线重连。
- **事件驱动**：不与任何模式耦合，比赛/公共/僵尸服都能用。

---

## 二、皮肤系统适用于哪些服，不适用于哪些服

### 2.1 适用（推荐使用）

| 类型 | 说明 |
|------|------|
| **娱乐/公共服** | 玩家自由换皮，最主流的用法 |
| **HNS 捉迷藏服** | 躲藏者换隐藏皮肤，符合玩法 |
| **俱乐部/皮肤商城服** | 配合积分系统做皮肤兑换 |
| **二次元/动漫皮肤服** | 社区服常见，人气高 |

### 2.2 不适用 / 需谨慎

| 类型 | 原因 |
|------|------|
| **纯竞技（比赛/排位）** | 皮肤会造成视觉不公平（模型大小、颜色暴露），大部分比赛服**禁用**自定义皮肤 |
| **有反作弊强校验的服** | 客户端模型替换可能触发误判 / 模型校验失败 |
| **要求模型统一的服务** | 如某些比赛插件会强制 `mp_models` 统一，冲突 |
| **低配客户端服** | 每个玩家加载不同模型，低配机可能卡顿、下载慢 |

> 判断标准一句话：**如果服务器要求"所有玩家看到的模型一致"，就不适用；如果允许个性化，就适用。**

---

## 三、如何维护

### 3.1 日常维护

- 加皮肤：编辑 `player_models.ini`，加一行 `显示名 models/player/xxx/xxx.mdl`，重启或换图生效。
- 改欢迎语/帮助：`showSkinHelp()` 里的 `client_print_color`。
- 清空玩家数据：删 `data/vault/skinsys_skin_vault.vault`（会清掉所有人皮肤）。

### 3.2 调试排错

- 插件没加载 → 看 `logs/` 错误日志，确认 `reapi`/`nvault` 模块开启。
- 模型闪回原始 → 检查 ini 路径**大小写**是否与模型文件一致，模型是否已 precache。
- 菜单打不开 → 确认 `register_menucmd` 的 key 掩码与 `show_menu` 一致。

### 3.3 升级注意

改 `.sma` 后重新 `amxxpc 编译`，覆盖 `.amxx` 即可；`nvault` 数据不受版本影响。

---

## 四、僵尸服接入 + 模式自动切换（进阶）

场景：一个服同时有**普通模式**（玩家可选皮肤）和**僵尸模式**（僵尸要用专属皮肤，人类用人类皮肤），需要**自动切换**。

### 4.1 思路

皮肤系统本身只负责"读配置 + 套模型"。要适配僵尸服，我们**不侵入核心插件**，而是加一个"模式适配器"插件，监听模式事件，强制覆盖模型：

```
模式事件（僵尸/人类切换）
   │
   ▼
适配器插件 Adapter.sma
   1. 玩家变僵尸 → 强制套用僵尸模型（覆盖玩家自带皮肤）
   2. 玩家是人类 → 恢复玩家从 /skin 选的皮肤
   3. 模式结束 → 恢复默认
```

### 4.2 自动切换的三条路径

**路径 A：监听僵尸插件的 Forward**

大多数僵尸插件（如 Zombie Plague）会提供 Forward，例如：

```pawn
// 假设僵尸插件有: zp_user_infected_post(id, infector)
public zp_user_infected_post(const id, const infector) {
    // 强制换僵尸模型
    set_pev(id, pev_weaponmodel2, "models/player/zombie/zombie.mdl");
}
public zp_user_humanized_post(const id) {
    // 恢复玩家自定义皮肤（调用 HnsSkin 的公开函数/重现选择）
    set_user_model_from_skin(id);
}
```

**路径 B：监听玩家出生 Hook**

如果僵尸插件没有 Forward，退化方案：在 `OnPlayerSpawn` 里判断玩家当前是不是僵尸（查 `pev_health`/自定义变量），再决定模型。

**路径 C：插件间通信（Native/Forward）**

在 HnsSkin 里暴露一个公开函数/Forward：

```pawn
// HnsSkin.sma 内新增
forward hns_skin_on_model_change(id, newModel[]);
public set_user_model_from_skin(const id) { /* 应用已选皮肤 */ }
// 并在 include 里声明，供适配器调用
```

适配器专注"模式判断"，HnsSkin 专注"皮肤应用"，职责分离。

### 4.3 完整示例：僵尸服适配器骨架

```pawn
#include <amxmodx>
#include <fakemeta>
#include <reapi>

// 僵尸模型路径（放 cstrike/models/player/zombie/）
#define ZOMBIE_MODEL "models/player/zombie/zombie.mdl"

public plugin_init() {
    // 假设僵尸插件提供这两个 Forward
    register_forward_chain("zp_user_infected_post", "onZombie");
    register_forward_chain("zp_user_humanized_post", "onHuman");
}

public onZombie(const id) {
    // 强制僵尸模型
    set_pev(id, pev_weaponmodel2, ZOMBIE_MODEL);
}

public onHuman(const id) {
    // 恢复玩家自定义皮肤（调用 HnsSkin 提供的方法）
    callfunc("set_user_model_from_skin", id);
}
```

> 要点：**判断逻辑放适配器，模型应用放核心**。这样皮肤系统保持纯净，僵尸逻辑随时可拆。

---

## 五、总结

- HnsSkin = 配置驱动 + 事件驱动 + 数据持久化的独立皮肤插件。
- 它来自比赛系统皮肤模块的三层重构（去依赖/抽配置/加持久化）。
- 适用于娱乐/公开/皮肤服，不适用于强制统一模型的竞技服。
- 僵尸服接入 = 加一个"模式适配器"，监听模式事件，强切/恢复模型，不侵入核心。

维护者：**LINNA**