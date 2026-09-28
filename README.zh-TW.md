# HNS 皮膚系統 · 正式版 v1.0

> Counter-Strike 1.6 / AMX Mod X · 基於 MySQL 的玩家自訂皮膚系統，誕生於 **GTR HNS（捉迷藏）** 伺服器生態。

![作者頭像](assets/avatar.jpg)

## 一、這是什麼

**HNS 皮膚系統 v1.0（正式版）** 是舊版 `HnsSkin` 插件系列的**全面重構開源版**，也是該系列**第一個官方正式穩定版本**。它把之前零散、依賴本機檔案的老皮膚系統徹底推倒重來，改寫為：

- ✅ **MySQL 連線** —— 使用自己獨立的 MySQL 資料庫（預設庫名 `skins`），不與其他插件共用，連線設定在 `configs/mixsystem/skinsql.cfg`
- ✅ **無限添加皮膚** —— 想加多少加多少，沒有硬性數量上限（只受伺服器模型預快取上限約束）
- ✅ **租期 + 永久機制** —— 金幣購買預設獲得 **30 天租期**（可設定）；花金幣可升級為永久（預設 **2000**，可設定）；**管理員可直接發放永久**
- ✅ **TT / CT 分區塊設定** —— 設定檔按陣營分區，T 款 / CT 款一目了然
- ✅ **每個皮膚可帶死亡音效** —— 音效可隨意複用
- ✅ **ICGB 金幣經濟** —— 複用你現有的金幣介面（`hns_gc_get_player` / `hns_gc_set_player`），不另起爐灶

---

## 🌍 語言切換

| 語言 | 檔案 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 簡體中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

---

## 二、誕生於哪一塊 / 前世今生

這個皮膚系統誕生於 **GTR HNS（Hide & Seek 捉迷藏）伺服器**的日常營運需求。HNS 玩法裡玩家對戰模型（skin）是個性化的核心體驗，因此最初為伺服器訂製了本機檔案版皮膚插件（見倉庫 `versions/` 歸檔：HnsSkin v1.0.0 → v3.0.2、match-skin-v5 等歷史版本）。

老版本存在幾個痛點：

1. 皮膚與玩家擁有資料依賴本機檔案/單一設定，無法跨服同步、無法在管理後台查詢；
2. 上架皮膚需要改原始碼或複雜設定，一般管理員學不會；
3. 沒有「租期 / 永久」的概念，要嘛永久要嘛沒有，缺少商業化營運空間。

**正式版 v1.0** 針對以上全部重寫：接 MySQL、設定化上架、引入「30 天租期 + 金幣升級永久 + 管理員發放永久」的三層機制，並支援無限添加皮膚。本倉庫已以此為**新的正式版起點**重新發布。

---

## 三、功能特性（詳細）

### 3.1 租期與永久機制
- 玩家用 ICGB 金幣購買皮膚 = 獲得 **`rent_days` 天租期**（預設 30 天，可設定）
- 租期到期後皮膚**自動失效**，玩家可**重新購買**（同價格再買一次刷新租期）
- 已購的租期皮膚可透過 `/skin` 選單 → **「升級為永久」**，花費 **`upgrade_price`** 金幣（預設 2000，可設定）
- **管理員發放 = 永久**：`/cpm` 管理選單發放的皮膚直接寫入 `expire_at = 0`；如果玩家已有該皮膚的租期，也會被直接升為永久
- 皮膚選單即時顯示狀態：`[永久]` / `[剩X天]` / `[已過期]`

### 3.2 MySQL 資料
- 使用自己獨立的 MySQL 資料庫（預設庫名 `skins`，讀 `mixsystem/skinsql.cfg`），不與其他插件共用
- 3 張表，前綴 `cpm_`：皮膚池 / 玩家擁有 / 玩家當前選用
- 支援 phpMyAdmin 直接查詢玩家擁有哪些皮膚、哪些是永久、哪些即將到期
- 插件啟動自動建表，老庫自動補 `expire_at` 欄，無需手動改庫

### 3.3 無限添加皮膚
- 皮膚上架 = 在 `skins.cfg` 對應陣營區塊下加兩行，**無限添加**
- 每款皮膚 = 名字 + 模型路徑 + 價格 +（可選）死亡音效
- 名字即識別 key，支援中文名；TT / CT 分區塊，按陣營自動歸類

### 3.4 陣營獨立
- 玩家當前是 T 就只顯示/使用/購買 T 款；是 C 就只顯示/使用/購買 C 款
- 沒買當前陣營的款時顯示預設模型，互不干擾

### 3.5 指令
| 指令 | 權限 | 說明 |
|---|---|---|
| `/skin` | 所有人 | 選擇 / 購買 / 升級永久 當前陣營皮膚 |
| `/cpm` | ADMIN_RCON | 管理選單：查看皮膚池 / 查看玩家擁有 / 發放（永久）/ 移除 |

---

## 四、快速開始（安裝部署）

### 4.1 資料庫
1. 在 MySQL 中執行 [`sql/hns_skins.sql`](sql/hns_skins.sql)（自動建立**獨立資料庫 `skins`** 和 3 張表）。
2. **老庫升級**：已建過 `cpm_player_skins` 的庫，只需執行：
   ```sql
   ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;
   ```
   （插件啟動時也會自動補這一欄，手動執行可保證資料庫先行一致）

### 4.2 插件部署
1. 把 `addons/` 整個目錄合併覆蓋到伺服器的 `addons/`。
2. 確認 `configs/plugins.ini` 中 `CustomPlayerModelsApi.amxx` 排在 `HnsMatchSkin.amxx` **之前**（顯示引擎必須先載入）。
3. 資料庫連線使用皮膚系統專屬的 `mixsystem/skinsql.cfg`（獨立庫，不與其他插件共用）。

### 4.3 設定皮膚
編輯 `addons/amxmodx/configs/mixsystem/skins.cfg`：

```
[SETTINGS]
rent_days  30       ; 租期天數, 0 = 直接永久
upgrade_price 2000  ; 升級永久價格 (ICGB金幣)

[TT]
; 名字   模型路徑              價格
李娜    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav          ; 可選: 上一款的死亡音效

[CT]
阿明    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav
```

改完**換圖或重啟**生效。

---

## 五、資料庫表結構

| 表 | 用途 | 關鍵欄位 |
|---|---|---|
| `cpm_skins` | 皮膚池（上架） | `model_key` 唯一名字、`model_path` 模型、`price` 價格、`team` T/C、`death_snd` 音效 |
| `cpm_player_skins` | 玩家擁有 | `authid` + `model_key` 聯合主鍵、`bought_at` 購買時間、**`expire_at` 到期時間（0=永久）** |
| `cpm_player_current` | 玩家當前選用 | `authid` + `team`，當前選用的皮膚 key |

常用查詢：
```sql
SELECT * FROM cpm_player_skins;                            -- 所有玩家擁有
SELECT * FROM cpm_player_skins WHERE expire_at=0;          -- 全部永久皮膚
SELECT * FROM cpm_player_skins WHERE expire_at>0;          -- 全部租期皮膚
SELECT * FROM cpm_player_skins WHERE authid='STEAM_0:1:123'; -- 指定玩家
```

---

## 六、技術實現：修改過 / 新增的函式（v1.0）

核心檔案：`addons/amxmodx/scripting/HnsMatchSkin.sma`

| 函式 | 類型 | 改動說明 |
|---|---|---|
| `DoBuy()` | 修改 | 購買改為寫入**租期** `expire_at = now + rent_days*86400`；支援過期後按原價**重新購買**；已永久/租期未過期時攔截提示 |
| `DoUpgrade()` | **新增** | 花費 `g_iUpgradePrice` 金幣把租期皮膚置為永久（記憶體 Trie + 資料庫 `expire_at=0` 雙寫） |
| `SkinExpire()` | **新增** | 回傳某皮膚的到期時間戳：0=永久，-1=未擁有 |
| `IsSkinValid()` | **新增** | 判斷「擁有 且 未過期」（租期與永久統一判斷） |
| `DaysLeft()` | **新增** | 計算剩餘天數（永久回傳 0） |
| `HasSkin()` | 保留 | 原擁有判斷，仍用於選單遍歷 |
| `GiveSkinTo()` | 修改 | 管理員發放 = **永久**（`expire_at=0`）；若玩家已有租期則自動升級為永久 |
| `RemoveSkinFrom()` | 修改 | 移除時同步清除到期時間（Trie） |
| `OnSkinChosen()` | 修改 | 有效皮膚才直接選用，否則進入購買/重購確認 |
| `MenuSkin` | 修改 | 新增「升級為永久」入口；皮膚項顯示 `[永久]/[剩X天]/[已過期]` |
| `MenuUpgrade()` / `MenuConfirmUpgrade()` | **新增** | 升級永久的選擇與確認選單 |
| `SkinHandler` / `UpgradeHandler` / `UpgradeConfirmHandler` | 修改/新增 | 對應選單回呼 |
| `Db_InsertOwned()` | 修改 | 寫入 `expire_at`；改用 `ON DUPLICATE KEY UPDATE` 支援重購/升級刷新 |
| `Db_SetPermanent()` | **新增** | `UPDATE ... SET expire_at=0` |
| `Db_LoadOwned()` | 修改 | 查詢帶上 `expire_at`；載入時過濾已過期記錄並順手清理資料庫 |
| `ImportSkinsToDb()` | 修改 | 解析 `[SETTINGS]` 區塊（`rent_days` / `upgrade_price`），TT/CT 分區塊匯入 |
| `CreateTablesSync()` | 修改 | `cpm_player_skins` 增加 `expire_at` 欄；對老庫自動執行 `ALTER TABLE` |
| `ApplyCurrentSkin()` / `fwd_PlayerPreThink` | 修改 | 套用皮膚前用 `IsSkinValid` 判斷，過期自動回退預設模型 |
| `client_disconnected` / `plugin_end` / `Db_LoadOwned` | 修改 | 玩家資料清理時同時銷毀到期時間 Trie |

---

## 七、擴充指南

### 7.1 加皮膚（最常用）
在 `skins.cfg` 的 `[TT]` 或 `[CT]` 區塊下複製兩行：
```
名字  模型路徑  價格
wav 音效路徑   (可選)
```
注意：名字全服唯一、一旦定下別改（否則玩家購買記錄遺失）；模型檔案必須真實存在。

### 7.2 改經濟數值
只改 `[SETTINGS]`：
```
rent_days 30        ; 想改成 7 天就填 7，想購買即永久就填 0
upgrade_price 2000  ; 升級永久的定價，隨便改
```

### 7.3 直接上資料庫上架
向 `cpm_skins` 插一行即可（等價於改設定），適合批次操作：
```sql
INSERT INTO cpm_skins (model_key, model_path, price, team, death_snd) VALUES ('名字','models/x/x.mdl',300,'T','misc/x.wav');
```

### 7.4 程式碼層擴充點
- 金幣介面：`hns_gc_get_player(id)` / `hns_gc_set_player(id, n)`（`hns_gc.inc`），想接別的貨幣系統改這兩處呼叫
- 顯示引擎：`CustomPlayerModelsApi`（`custom_player_models.inc`）負責模型預快取與客戶端顯示，換引擎只動這一層
- 權限控制：皮膚池 `pool_flags` 欄位可加權限要求（`IsAllowed()`）
- 新增陣營/玩法：在 `pool_e` 列舉與選單邏輯上擴充

---

## 八、常見問題 FAQ

**Q: 插件報找不到 `cpm_player_skins` 表？**
A: 先執行 `sql/hns_skins.sql`；老庫再執行上面的 ALTER。

**Q: 玩家買了但沒生效？**
A: 確認 `CustomPlayerModelsApi.amxx` 在 `plugins.ini` 裡排在 `HnsMatchSkin.amxx` 之前，且兩個 .amxx 都已放進 `plugins/`。

**Q: 換圖後新加的皮膚不出現？**
A: 皮膚是啟動/換圖時從 `skins.cfg` 匯入的，改完設定必須換圖或重啟。

**Q: 想改租期天數/升級價格？**
A: 改 `skins.cfg` 的 `[SETTINGS]`，然後換圖生效。

**Q: 老版本資料會遺失嗎？**
A: 老本機檔案版資料不遷移；新庫從零開始。`versions/` 裡保留了所有歷史版本供參考。

---

## 九、版本歷史

- **v1.0.0（正式版，本版）**：MySQL 化重寫、無限添加皮膚、租期/永久機制、TT/CT 分割槽設定、死亡音效、多語言文件
- `versions/` 歸檔：HnsSkin v1.0.0 / v1.1.0 / v2.0.0 / v2.01 / v2.02 / v3.0.0 / v3.0.2 / match-skin-v5 / IC 點選單（歷史留存，不再維護）

## 📄 許可證

GNU GPL v3 — 見 [LICENSE](LICENSE)。
