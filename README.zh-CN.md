# HNS 皮肤系统 · v4.0.0 正式版

> Counter-Strike 1.6 / AMX Mod X · 为 **GTR HNS（捉迷藏）** 服务器制作的独立皮肤系统。

![作者头像](assets/avatar.jpg)

**HNS Skin System v4.0.0** 是 `HnsSkin` 系列的全新独立发行版，替换 `main` 分支上旧的 `HnsMatchSkin` 插件。皮肤系统使用自己的配置、数据库和点数，不再读写比赛插件的 `mixsystem`。

## v4.0.0 更新内容

- 🌍 **默认英语，内置四语言** — English / 简体中文 / 繁體中文 / Русский。
  客户端语言不是 `cn` / `tw` / `en` / `ru` 的玩家，进服 2 秒后自动切到英语。
  玩家用 `/lang` 手动选过语言的，保持玩家自己的选择。
- 🗂 **菜单重新整理** — 人物皮肤（TT / CT 分开）、刀皮、投掷物（烟雾 / 闪光）、GBIC 点数、烟雾颜色、MySQL 状态、管理设置全部分开，入口仍然是 `/skin`。
- 🔁 **死斗换边跟随** — 死斗被刀后当场换边、不重生时，插件会在 1 秒内发现新阵营，并自动套用该玩家在那一侧的皮肤和刀皮。
- 💾 **独立数据库与点数** — 自己的 SQLite / MySQL 库和 GBIC 点数，完全不碰比赛金币。
- 🛠 **开箱即用** — 已编译 `.amxx`、完整源码、include 和示例配置全部包含。

## 语言

| 语言 | 文档 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

插件语言文件：[`addons/amxmodx/data/lang/hns_skin.txt`](addons/amxmodx/data/lang/hns_skin.txt)，包含 `[cn]`、`[tw]`、`[en]`、`[ru]` 四段，每段 155 条。游戏内默认英语。

## 快速安装

1. 把 `addons/` 合并到服务器的 `cstrike/addons/` 目录。
2. 确认 `configs/plugins.ini` 的加载顺序：

   ```
   CustomPlayerModelsApi.amxx
   HnsSponsorLocal.amxx
   HnsSkin.amxx
   ```

   刀皮需要 `crx_knife_models.amxx`，必须排在 `HnsSkin.amxx` 前面。
3. 不要同时加载旧的 `HnsMatchSkin.amxx`，两个插件都会注册 `/skin`。
4. 在 `modules.ini` 打开 `sqlite`；点数和签到需要 `nvault`。
5. 换图或重启服务器。

完整安装说明：[`docs/安装说明.txt`](docs/安装说明.txt)。

## 功能

- **皮肤数量不限** — 只受模型预缓存上限限制
- **TT / CT 分开** — 每款皮肤只属于一个阵营，玩家只看到当前阵营的皮肤
- **租期 + 永久** — 金币购买默认 30 天租期（可配置），可花金币升级永久；管理员发放直接永久
- **每款独立死亡音效** — 一款可配多个音效，死亡时随机一条
- **刀皮 / 投掷物皮** — 刀皮走 `crxknives`，烟雾 / 闪光走 `nade_skins.cfg`
- **签到 + 在线奖励** — GBIC 经济完全在皮肤系统内
- **预缓存上限** — `precache_max` 防止重型 HNS 地图触发 CS 1.6 的 512 模型上限崩服
- **后台发放** — `cpm_skin_grant` 表可以直接给离线玩家发皮肤

## 目录结构

```
hns-skin-system/
├── addons/amxmodx/              # 可直接部署的插件包
│   ├── plugins/                 # 预编译 .amxx（3 个插件）
│   ├── scripting/               # 源码 + include/
│   ├── configs/                 # plugins.ini、KnifeModels.ini、skinsql/、custom_player_models.cfg
│   └── data/lang/hns_skin.txt   # cn / tw / en / ru 语言文件
├── docs/                        # 中文安装说明
├── assets/                      # 作者头像
├── versions/                    # 历史版本（v1.0.0 ~ v3.1.0）
├── CHANGELOG.md
├── LICENSE                      # GPLv3
└── README.*.md                  # 多语言文档
```

## 命令

| 命令 | 权限 | 说明 |
|---|---|---|
| `/skin` | 所有人 | 皮肤商店：人物 / 刀 / 投掷物 / 点数 / 烟雾颜色 |
| `/lang` | 所有人 | 切换语言（cn / tw / en / ru） |
| `/sign` | 所有人 | 每日签到（`/checkin`、`/qd`、`/签到` 同效） |
| `/cpm` | ADMIN_RCON | 管理菜单：皮肤池、拥有查询、发放、收回、清除 |
| `amx_giveskin <steamid> <皮肤名\|all\|all_t\|all_c\|all_knife\|all_nade>` | ADMIN_IMMUNITY | 给在线 / 离线玩家发皮肤 |
| `amx_takeskin <steamid> <皮肤名\|all\|all_knife\|all_nade>` | ADMIN_IMMUNITY | 收回皮肤 |
| `amx_clearskin <steamid>` | ADMIN_IMMUNITY | 清空玩家全部皮肤 |

## 配置

| 文件 | 用途 |
|---|---|
| `configs/skinsql/skins.cfg` | 皮肤池、`[SETTINGS]` 设置、`storage local/mysql` |
| `configs/skinsql/nade_skins.cfg` | 烟雾 / 闪光弹皮肤 |
| `configs/skinsql/knife_skins.cfg` | 刀皮商店价格 |
| `configs/skinsql/skinsql.cfg.example` | MySQL 连接模板 |
| `configs/KnifeModels.ini` | `crxknives` 的刀模型定义 |
| `configs/custom_player_models.cfg` | 人物模型引擎参数 |

默认数据库是本地 SQLite：`addons/amxmodx/data/sqlite3/skinsql.sq3`，表由插件自动创建。改用 MySQL 时把 `skinsql.cfg.example` 复制为 `skinsql.cfg` 填好账号，再把 `skins.cfg` 改成 `storage mysql`。

### 添加人物皮肤（第三人称身体模型）

1. 模型放到 `cstrike/models/player/<文件夹>/<文件夹>.mdl`，文件夹名必须和 `.mdl` 同名，贴图放同一文件夹。
2. 在 `skins.cfg` 的 `[T]` 或 `[CT]` 下加一行：

   ```
   [T]
   北极战士  models/player/arctic/arctic.mdl  0
   wav skin/arctic_die1.wav
   wav skin/arctic_die2.wav

   [CT]
   德国GSG9  models/player/gsg9/gsg9.mdl  500
   ```

   格式：`名字  模型路径  价格`。名字是全服唯一识别名，玩家买过之后不要改；`wav` 行属于它上面那一款，可写多行（或一行逗号分隔），死亡时随机播一条。
3. 换图生效，或 `/cpm` → MySQL 状态 → **重新同步皮肤目录**。

人物皮肤只改变**第三人称身体**（别人、观战、第三人称摄像看到的样子）。CS 1.6 的第一人称只能看到自己的手臂和武器，人物模型不会改变第一人称。

### 第一人称 / 第三人称武器模型

CS 1.6 的武器模型用三种前缀：

| 前缀 | 视角 | 说明 |
|---|---|---|
| `v_` | 第一人称 | 自己手里看到的模型 |
| `p_` | 第三人称 | 别人 / 观战看到的持枪模型 |
| `w_` | 世界模型 | 丢在地上 / 世界里的模型 |

**刀皮** — `configs/KnifeModels.ini`：

```
[爪子刀女手]
V_MODEL = models/v_knife4.mdl    ; 第一人称
P_MODEL = models/p_knife4.mdl    ; 第三人称
PRICE   = 300                    ; 0 = 免费
```

- 只写 `V_MODEL`：自己看到新刀，别人看到默认 `p_knife.mdl`。
- 两个都写：第一人称和第三人称都是新刀。
- 不写或文件不存在：回退 `v_knife.mdl` / `p_knife.mdl`。
- 段名要和 `knife_skins.cfg` 完全一致，价格覆盖才生效。

**投掷物** — `configs/skinsql/nade_skins.cfg`，一行一个：

```
my_smoke  nade/v_smoke_blue  500  smoke
my_flash  nade/v_flash_gold  300  flash
```

写 `v_` 路径即可，插件会自动找同目录的 `p_xxx.mdl`（第三人称）和 `w_xxx.mdl`（世界模型）并预缓存。只有 `v_` 时第一人称生效，其他视角保持默认。

### 声音配置（支持第三方自定义 WAV）

有两套声音可配：

1. **人物皮肤死亡音效** — `skins.cfg` 里的 `wav` 行（见上）。
2. **刀的音效** — `KnifeModels.ini` 对应刀段下的 `*_SOUND`：

   ```
   SELECT_SOUND  = knife/select.wav     ; 商店选中
   DEPLOY_SOUND  = knife/deploy.wav     ; 掏刀 / 切刀
   SLASH_SOUND   = knife/slash.wav      ; 轻砍
   STAB_SOUND    = knife/stab.wav       ; 重刀
   HIT_SOUND     = knife/hit.wav        ; 砍到人
   HITWALL_SOUND = knife/hitwall.wav    ; 砍到墙
   SELECT_MESSAGE = 选中提示（支持颜色代码，可写多行）
   ```

文件放置与格式：

- 声音放到 `cstrike/sound/<子目录>/<文件名>.wav`。
- 配置里写**相对 `sound/`** 的路径，不要写 `sound/` 前缀：
  文件 `cstrike/sound/skin/miku.wav` → 配置 `wav skin/miku.wav`。
- 用 PCM WAV（推荐 16-bit 单声道，11025 或 22050 Hz）。CS 1.6 的 `precache_sound` / `emit_sound` **不支持 mp3**，事件音效不要用 `.mp3`。
- 文件名用小写英文/数字/下划线，不要空格和中文。
- 模型和声音都在地图开始时预缓存。客户端也要有文件：上传到 FastDL（`FastDL/sound/...`、`FastDL/models/...`），或允许 `sv_allowdownload 1`。

完整中文图文步骤见 [`docs/安装说明.txt`](docs/安装说明.txt)。

## 历史版本

`versions/` 保留全部历史发行版：

- `v3.1.0` — 旧 `main` 分支的 `HnsMatchSkin` 插件、SQL 和安装文档（本次已归档）
- `v3.0.2`、`v3.0.0`、`v2.02`、`v2.01`、`v2.0.0`、`v1.1.0`、`v1.0.0`、`match-skin-v5`、`ic-v1.0.0`、`skin-1.0`

## 许可

GPLv3 — 见 [LICENSE](LICENSE)。
