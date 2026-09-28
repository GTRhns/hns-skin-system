# HNS 皮肤系统 · 正式版 v1.0

> Counter-Strike 1.6 / AMX Mod X · 基于 MySQL 的玩家自定义皮肤系统，诞生于 **GTR HNS（捉迷藏）** 服务器生态。

![作者头像](assets/avatar.jpg)

## 一、这是什么

**HNS 皮肤系统 v1.0（正式版）** 是旧版 `HnsSkin` 插件系列的**全面重构开源版**，也是该系列**第一个官方正式稳定版本**。它把之前零散、依赖本地文件的老皮肤系统彻底推倒重来，改写为：

- ✅ **MySQL 连接** —— 使用自己独立的 MySQL 数据库（默认库名 `skins`），不与其他插件共用，连接配置在 `configs/mixsystem/skinsql.cfg`
- ✅ **无限添加皮肤** —— 想加多少加多少，没有硬性数量上限（只受服务器模型预缓存上限约束）
- ✅ **租期 + 永久机制** —— 金币购买默认获得 **30 天租期**（可配置）；花金币可升级为永久（默认 **2000**，可配置）；**管理员可直接发放永久**
- ✅ **TT / CT 分区块配置** —— 配置文件按阵营分区，T 款 / CT 款一目了然
- ✅ **每个皮肤可带死亡音效** —— 音效可随意复用
- ✅ **ICGB 金币经济** —— 复用你现有的金币接口（`hns_gc_get_player` / `hns_gc_set_player`），不另起炉灶

---

## 🌍 语言切换

| 语言 | 文件 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

---

## 二、诞生于哪一块 / 前世今生

这个皮肤系统诞生于 **GTR HNS（Hide & Seek 捉迷藏）服务器**的日常运营需求。HNS 玩法里玩家对战模型（skin）是个性化的核心体验，因此最初为服务器定制了本地文件版皮肤插件（见仓库 `versions/` 归档：HnsSkin v1.0.0 → v3.0.2、match-skin-v5 等历史版本）。

老版本存在几个痛点：

1. 皮肤与玩家拥有数据依赖本地文件/单一配置，无法跨服同步、无法在管理后台查询；
2. 上架皮肤需要改源码或复杂配置，普通管理员学不会；
3. 没有"租期 / 永久"的概念，要么永久要么没有，缺少商业化运营空间。

**正式版 v1.0** 针对以上全部重写：接 MySQL、配置化上架、引入"30 天租期 + 金币升级永久 + 管理员发放永久"的三层机制，并支持无限添加皮肤。本仓库已以此为**新的正式版起点**重新发布。

---

## 三、功能特性（详细）

### 3.1 租期与永久机制
- 玩家用 ICGB 金币购买皮肤 = 获得 **`rent_days` 天租期**（默认 30 天，可配置）
- 租期到期后皮肤**自动失效**，玩家可**重新购买**（同价格再买一次刷新租期）
- 已购的租期皮肤可通过 `/skin` 菜单 → **"升级为永久"**，花费 **`upgrade_price`** 金币（默认 2000，可配置）
- **管理员发放 = 永久**：`/cpm` 管理菜单发放的皮肤直接写入 `expire_at = 0`；如果玩家已有该皮肤的租期，也会被直接升为永久
- 皮肤菜单实时显示状态：`[永久]` / `[剩X天]` / `[已过期]`

### 3.2 MySQL 数据
- 使用自己独立的 MySQL 数据库（默认库名 `skins`，读 `mixsystem/skinsql.cfg`），不与其他插件共用
- 3 张表，前缀 `cpm_`：皮肤池 / 玩家拥有 / 玩家当前选用
- 支持 phpMyAdmin 直接查询玩家拥有哪些皮肤、哪些是永久、哪些即将到期
- 插件启动自动建表，老库自动补 `expire_at` 列，无需手动改库

### 3.3 无限添加皮肤
- 皮肤上架 = 在 `skins.cfg` 对应阵营区块下加两行，**无限添加**
- 每款皮肤 = 名字 + 模型路径 + 价格 +（可选）死亡音效
- 名字即识别 key，支持中文名；TT / CT 分区块，按阵营自动归类

### 3.4 阵营独立
- 玩家当前是 T 就只显示/使用/购买 T 款；是 C 就只显示/使用/购买 C 款
- 没买当前阵营的款时显示默认模型，互不干扰

### 3.5 命令
| 命令 | 权限 | 说明 |
|---|---|---|
| `/skin` | 所有人 | 选择 / 购买 / 升级永久 当前阵营皮肤 |
| `/cpm` | ADMIN_RCON | 管理菜单：查看皮肤池 / 查看玩家拥有 / 发放（永久）/ 移除 |

---

## 四、快速开始（安装部署）

### 4.1 数据库
1. 在 MySQL 中执行 [`sql/hns_skins.sql`](sql/hns_skins.sql)（自动创建**独立数据库 `skins`** 和 3 张表）。
2. **老库升级**：已建过 `cpm_player_skins` 的库，只需执行：
   ```sql
   ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;
   ```
   （插件启动时也会自动补这一列，手动执行可保证数据库先行一致）

### 4.2 插件部署
1. 把 `addons/` 整个目录合并覆盖到服务器的 `addons/`。
2. 确认 `configs/plugins.ini` 中 `CustomPlayerModelsApi.amxx` 排在 `HnsMatchSkin.amxx` **之前**（显示引擎必须先加载）。
3. 数据库连接使用皮肤系统专属的 `mixsystem/skinsql.cfg`（独立库，不与其他插件共用）。

### 4.3 配置皮肤
编辑 `addons/amxmodx/configs/mixsystem/skins.cfg`：

```
[SETTINGS]
rent_days  30       ; 租期天数, 0 = 直接永久
upgrade_price 2000  ; 升级永久价格 (ICGB金币)

[TT]
; 名字   模型路径              价格
李娜    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav          ; 可选: 上一款的死亡音效

[CT]
阿明    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav
```

改完**换图或重启**生效。

---

## 五、数据库表结构

| 表 | 用途 | 关键字段 |
|---|---|---|
| `cpm_skins` | 皮肤池（上架） | `model_key` 唯一名字、`model_path` 模型、`price` 价格、`team` T/C、`death_snd` 音效 |
| `cpm_player_skins` | 玩家拥有 | `authid` + `model_key` 联合主键、`bought_at` 购买时间、**`expire_at` 到期时间（0=永久）** |
| `cpm_player_current` | 玩家当前选用 | `authid` + `team`，当前选用的皮肤 key |

常用查询：
```sql
SELECT * FROM cpm_player_skins;                            -- 所有玩家拥有
SELECT * FROM cpm_player_skins WHERE expire_at=0;          -- 全部永久皮肤
SELECT * FROM cpm_player_skins WHERE expire_at>0;          -- 全部租期皮肤
SELECT * FROM cpm_player_skins WHERE authid='STEAM_0:1:123'; -- 指定玩家
```

---

## 六、技术实现：修改过 / 新增的函数（v1.0）

核心文件：`addons/amxmodx/scripting/HnsMatchSkin.sma`

| 函数 | 类型 | 改动说明 |
|---|---|---|
| `DoBuy()` | 修改 | 购买改为写入**租期** `expire_at = now + rent_days*86400`；支持过期后按原价**重新购买**；已永久/租期未过期时拦截提示 |
| `DoUpgrade()` | **新增** | 花费 `g_iUpgradePrice` 金币把租期皮肤置为永久（内存 Trie + 数据库 `expire_at=0` 双写） |
| `SkinExpire()` | **新增** | 返回某皮肤的到期时间戳：0=永久，-1=未拥有 |
| `IsSkinValid()` | **新增** | 判断"拥有 且 未过期"（租期与永久统一判断） |
| `DaysLeft()` | **新增** | 计算剩余天数（永久返回 0） |
| `HasSkin()` | 保留 | 原拥有判断，仍用于菜单遍历 |
| `GiveSkinTo()` | 修改 | 管理员发放 = **永久**（`expire_at=0`）；若玩家已有租期则自动升级为永久 |
| `RemoveSkinFrom()` | 修改 | 移除时同步清除到期时间（Trie） |
| `OnSkinChosen()` | 修改 | 有效皮肤才直接选用，否则进入购买/重购确认 |
| `MenuSkin` | 修改 | 新增"升级为永久"入口；皮肤项显示 `[永久]/[剩X天]/[已过期]` |
| `MenuUpgrade()` / `MenuConfirmUpgrade()` | **新增** | 升级永久的选择与确认菜单 |
| `SkinHandler` / `UpgradeHandler` / `UpgradeConfirmHandler` | 修改/新增 | 对应菜单回调 |
| `Db_InsertOwned()` | 修改 | 写入 `expire_at`；改用 `ON DUPLICATE KEY UPDATE` 支持重购/升级刷新 |
| `Db_SetPermanent()` | **新增** | `UPDATE ... SET expire_at=0` |
| `Db_LoadOwned()` | 修改 | 查询带上 `expire_at`；加载时过滤已过期记录并顺手清理数据库 |
| `ImportSkinsToDb()` | 修改 | 解析 `[SETTINGS]` 区块（`rent_days` / `upgrade_price`），TT/CT 分区块导入 |
| `CreateTablesSync()` | 修改 | `cpm_player_skins` 增加 `expire_at` 列；对老库自动执行 `ALTER TABLE` |
| `ApplyCurrentSkin()` / `fwd_PlayerPreThink` | 修改 | 应用皮肤前用 `IsSkinValid` 判断，过期自动回退默认模型 |
| `client_disconnected` / `plugin_end` / `Db_LoadOwned` | 修改 | 玩家数据清理时同时销毁到期时间 Trie |

---

## 七、扩展指南

### 7.1 加皮肤（最常用）
在 `skins.cfg` 的 `[TT]` 或 `[CT]` 区块下复制两行：
```
名字  模型路径  价格
wav 音效路径   (可选)
```
注意：名字全服唯一、一旦定下别改（否则玩家购买记录丢失）；模型文件必须真实存在。

### 7.2 改经济数值
只改 `[SETTINGS]`：
```
rent_days 30        ; 想改成 7 天就填 7，想购买即永久就填 0
upgrade_price 2000  ; 升级永久的定价，随便改
```

### 7.3 直接上数据库上架
向 `cpm_skins` 插一行即可（等价于改配置），适合批量操作：
```sql
INSERT INTO cpm_skins (model_key, model_path, price, team, death_snd) VALUES ('名字','models/x/x.mdl',300,'T','misc/x.wav');
```

### 7.4 代码层扩展点
- 金币接口：`hns_gc_get_player(id)` / `hns_gc_set_player(id, n)`（`hns_gc.inc`），想接别的货币系统改这两处调用
- 显示引擎：`CustomPlayerModelsApi`（`custom_player_models.inc`）负责模型 precache 与客户端显示，换引擎只动这一层
- 权限控制：皮肤池 `pool_flags` 字段可加权限要求（`IsAllowed()`）
- 新增阵营/玩法：在 `pool_e` 枚举与菜单逻辑上扩展

---

## 八、常见问题 FAQ

**Q: 插件报找不到 `cpm_player_skins` 表？**
A: 先执行 `sql/hns_skins.sql`；老库再执行上面的 ALTER。

**Q: 玩家买了但没生效？**
A: 确认 `CustomPlayerModelsApi.amxx` 在 `plugins.ini` 里排在 `HnsMatchSkin.amxx` 之前，且两个 .amxx 都已放进 `plugins/`。

**Q: 换图后新加的皮肤不出现？**
A: 皮肤是启动/换图时从 `skins.cfg` 导入的，改完配置必须换图或重启。

**Q: 想改租期天数/升级价格？**
A: 改 `skins.cfg` 的 `[SETTINGS]`，然后换图生效。

**Q: 老版本数据会丢吗？**
A: 老本地文件版数据不迁移；新库从零开始。`versions/` 里保留了所有历史版本供参考。

---

## 九、版本历史

- **v1.0.0（正式版，本版）**：MySQL 化重写、无限添加皮肤、租期/永久机制、TT/CT 分区配置、死亡音效、多语言文档
- `versions/` 归档：HnsSkin v1.0.0 / v1.1.0 / v2.0.0 / v2.01 / v2.02 / v3.0.0 / v3.0.2 / match-skin-v5 / IC 点菜单（历史留存，不再维护）

## 📄 许可证

GNU GPL v3 — 见 [LICENSE](LICENSE)。
