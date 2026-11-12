# HNS 皮膚系統 · v4.0.0 正式版

> Counter-Strike 1.6 / AMX Mod X · 為 **GTR HNS（捉迷藏）** 伺服器製作的獨立皮膚系統。

![作者頭像](assets/avatar.jpg)

**HNS Skin System v4.0.0** 是 `HnsSkin` 系列的全新獨立發行版，取代 `main` 分支上舊的 `HnsMatchSkin` 插件。皮膚系統使用自己的設定、資料庫和點數，不再讀寫比賽插件的 `mixsystem`。

## v4.0.0 更新

- 🌍 **預設英語，內建四語言** — English / 简体中文 / 繁體中文 / Русский。客戶端語言不是 `cn` / `tw` / `en` / `ru` 的玩家，進服 2 秒後自動切換成英語；用 `/lang` 手動選過語言的玩家保持自己的選擇。
- 🗂 **選單重新整理** — 人物皮膚（TT / CT 分開）、刀皮、投擲物（煙霧 / 閃光）、GBIC 點數、煙霧顏色、MySQL 狀態、管理設定全部分開，入口仍是 `/skin`。
- 🔁 **死鬥換邊跟隨** — 死鬥被刀後當場換邊、不重生時，插件會在 1 秒內偵測新陣營並自動套用該側的皮膚與刀皮。
- 💾 **獨立資料庫與點數** — 自己的 SQLite / MySQL 與 GBIC 點數，不碰比賽金幣。

## 語言

| 語言 | 文件 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

外掛語言檔：[`addons/amxmodx/data/lang/hns_skin.txt`](addons/amxmodx/data/lang/hns_skin.txt)，含 `[cn]`、`[tw]`、`[en]`、`[ru]` 四段，每段 155 條。遊戲內預設英語。

## 快速安裝

1. 把 `addons/` 合併到伺服器的 `cstrike/addons/`。
2. `configs/plugins.ini` 載入順序：

   ```
   CustomPlayerModelsApi.amxx
   HnsSponsorLocal.amxx
   HnsSkin.amxx
   ```

   刀皮需要 `crx_knife_models.amxx`，必須排在 `HnsSkin.amxx` 前面。
3. 不要同時載入舊的 `HnsMatchSkin.amxx`，兩者都會註冊 `/skin`。
4. 在 `modules.ini` 開啟 `sqlite`；點數與簽到需要 `nvault`。
5. 換圖或重啟伺服器。

完整說明：[`docs/安装说明.txt`](docs/安装说明.txt)。

## 模型與聲音配置

- **人物皮膚（第三人稱）**：模型放 `cstrike/models/player/<資料夾>/<資料夾>.mdl`，在 `configs/skinsql/skins.cfg` 的 `[T]` / `[CT]` 下加一行 `名字 模型路徑 價格`。CS 1.6 第一人稱看不到人物皮膚，只影響別人 / 觀戰 / 第三人稱視角。
- **刀皮（第一 / 第三人稱）**：`configs/KnifeModels.ini` 裡 `V_MODEL` = 第一人稱（自己手裡），`P_MODEL` = 第三人稱（別人看到）；只寫 `V_MODEL` 時別人看到預設刀。
- **投擲物**：`configs/skinsql/nade_skins.cfg` 寫 `v_` 模型，插件會自動找同目錄的 `p_` / `w_` 模型。
- **聲音（支援第三方 WAV）**：檔案放 `cstrike/sound/<子目錄>/<檔名>.wav`，設定寫相對 `sound/` 的路徑（例如 `wav skin/die.wav`）。用 PCM WAV，不要用 mp3。人物死亡音效寫在 `skins.cfg` 的 `wav` 行，刀音效寫在 `KnifeModels.ini` 的 `SELECT_SOUND` / `DEPLOY_SOUND` / `SLASH_SOUND` / `STAB_SOUND` / `HIT_SOUND` / `HITWALL_SOUND`。
- 模型與聲音都要上 FastDL（`FastDL/models/...`、`FastDL/sound/...`），否則客戶端會缺模型或沒聲音。

## 指令

| 指令 | 權限 | 說明 |
|---|---|---|
| `/skin` | 所有人 | 皮膚商店 |
| `/lang` | 所有人 | 切換語言（cn / tw / en / ru） |
| `/sign` | 所有人 | 每日簽到 |
| `/cpm` | ADMIN_RCON | 管理選單 |
| `amx_giveskin` / `amx_takeskin` / `amx_clearskin` | ADMIN_IMMUNITY | 後台發放 / 收回 / 清除 |

## 歷史版本

`versions/` 保留全部歷史發行版，包含本次歸檔的 `v3.1.0`（舊 `HnsMatchSkin` 插件、SQL 與安裝文件）。

## 許可

GPLv3 — 見 [LICENSE](LICENSE)。
