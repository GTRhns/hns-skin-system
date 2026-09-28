# HNS スキンシステム · 正式版 v1.0

> Counter-Strike 1.6 / AMX Mod X · **GTR HNS（かくれんぼ）** サーバー群で生まれた MySQL 対応カスタムスキンシステム。

![作者アバター](assets/avatar.jpg)

## 1. これは何か

**HNS スキンシステム v1.0（正式版）** は、旧 `HnsSkin` プラグインシリーズを**全面リビルドしたオープンソース版**であり、このシリーズの**初の公式安定版**です。ローカルファイルに依存していた旧システムを完全に書き直しました:

- ✅ **MySQL 対応** — 専用の独立 DB を使用（既定 DB 名 `skins`）、他のプラグインとは共有しない; 接続設定は `configs/mixsystem/skinsql.cfg`
- ✅ **スキン無制限追加** — 数に上限なし（サーバーのモデルプリキャッシュ上限まで）
- ✅ **レンタル＋永続** — 購入で基本 **30日レンタル**（設定可）; コインで**永続化アップグレード**（既定 **2000**、設定可）; **管理者は直接永続付与**
- ✅ **TT / CT セクション設定** — 陣営ごとに分かれた設定ファイル
- ✅ **スキンごとのデスサウンド** — 各スキンに専用サウンド（使い回し可）
- ✅ **ICGB コイン経済** — 既存コイン API（`hns_gc_get_player` / `hns_gc_set_player`）を再利用

---

## 🌍 言語

| 言語 | ファイル |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

---

## 2. 誕生の背景

このシステムは **GTR HNS（Hide & Seek かくれんぼ）サーバー**の運営ニーズから生まれました。HNS ではプレイヤーのモデル（スキン）が個性の中核となるため、当初はローカルファイル版プラグインとして作られました（`versions/` アーカイブ: HnsSkin v1.0.0 → v3.0.2、match-skin-v5 など）。

旧バージョンの問題点:

1. スキン・購入データがローカルファイル依存 → サーバー間で同期不可、管理画面で照会不可
2. スキン追加にソース改修や複雑な設定が必要
3. 「レンタル／永続」の概念なし — 永続か、さもなくば無しか

**正式版 v1.0** はこれらを全て解決: MySQL 化、設定ファイルでの追加、「30日レンタル＋コインでの永続化＋管理者による永続付与」の 3 段メカニズム、無制限スキン追加。本リポジトリは**新しい正式 v1.0** として再スタートしました。

---

## 3. 機能

### 3.1 レンタルと永続
- ICGB コインでの購入 = **`rent_days` 日レンタル**（既定 30日、設定可）
- 期限切れでスキンは**自動的に無効化**、**再購入可能**（同価格でレンタル更新）
- レンタルスキンは `/skin` メニュー → **「永続化」**で **`upgrade_price`** コイン消費（既定 2000、設定可）
- **管理者付与 = 永続**: `/cpm` メニューで付与すると `expire_at = 0` に; 既にレンタル中なら即永続へ昇格
- メニューに状態表示: `[永久]` / `[残りX日]` / `[期限切れ]`

### 3.2 MySQL データ
- 専用の独立 DB を使用（既定 DB 名 `skins`、`mixsystem/skinsql.cfg` を参照）、他のプラグインとは共有しない
- テーブル 3 つ（`cpm_` プレフィックス）: スキンプール / プレイヤー所有 / 現在選択
- phpMyAdmin で所有状況、永続かどうか、まもなく期限切れのスキンを照会可能
- プラグインが自動でテーブル作成、既存 DB には `expire_at` カラムを自動追加

### 3.3 無制限スキン
- 追加 = `skins.cfg` の該当陣営セクションに 2 行、**無制限**
- スキン = 名前 + モデルパス + 価格 +（任意）デスサウンド
- 名前は固有キー、日本語・中国語対応; TT/CT セクションで自動分類

### 3.4 陣営分離
- T 陣営なら T スキンのみ表示/購入; C 陣営なら C スキンのみ
- 未購入ならデフォルトモデル表示

### 3.5 コマンド
| コマンド | 権限 | 説明 |
|---|---|---|
| `/skin` | 全員 | 現在の陣営スキンの選択 / 購入 / 永続化 |
| `/cpm` | ADMIN_RCON | 管理メニュー: プール閲覧 / 所有閲覧 / 付与（永続）/ 削除 |

---

## 4. インストール

### 4.1 データベース
1. MySQL で [`sql/hns_skins.sql`](sql/hns_skins.sql) を実行（**専用 DB `skins`** とテーブル 3 つを作成）。
2. **既存 DB のアップグレード**（`cpm_player_skins` が既にある場合）:
   ```sql
   ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;
   ```
   （プラグイン起動時に自動追加されますが、手動実行の方が確実）

### 4.2 プラグイン配布
1. `addons/` フォルダをサーバーの `addons/` にマージ。
2. `configs/plugins.ini` で `CustomPlayerModelsApi.amxx` が `HnsMatchSkin.amxx` の**前**にあること。
3. DB 接続は `mixsystem/skinsql.cfg` を使用（スキンシステム専用の独立 DB、他のプラグインとは共有しない）。

### 4.3 スキン設定
`addons/amxmodx/configs/mixsystem/skins.cfg`:

```
[SETTINGS]
rent_days  30       ; レンタル日数, 0 = 即永続
upgrade_price 2000  ; 永続化の価格 (ICGBコイン)

[TT]
; 名前    モデルパス             価格
LiNa    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav          ; 任意: 上記スキンのデスサウンド

[CT]
Amin    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav
```

変更後は**マップ変更または再起動**。

---

## 5. DB テーブル

| テーブル | 用途 | 主要カラム |
|---|---|---|
| `cpm_skins` | スキンプール | `model_key`（固有名）, `model_path`, `price`, `team` T/C, `death_snd` |
| `cpm_player_skins` | プレイヤー所有 | `authid`+`model_key`（複合PK）, `bought_at`, **`expire_at`（0=永続）** |
| `cpm_player_current` | 現在の選択 | `authid` + `team`、選択中のスキン |

照会例:
```sql
SELECT * FROM cpm_player_skins;                              -- 全所有
SELECT * FROM cpm_player_skins WHERE expire_at=0;            -- 全永続
SELECT * FROM cpm_player_skins WHERE expire_at>0;            -- 全レンタル
SELECT * FROM cpm_player_skins WHERE authid='STEAM_0:1:123'; -- 特定プレイヤー
```

---

## 6. 変更・新規関数（v1.0）

コアファイル: `addons/amxmodx/scripting/HnsMatchSkin.sma`

| 関数 | 種類 | 変更内容 |
|---|---|---|
| `DoBuy()` | 変更 | 購入で**レンタル**記録 `expire_at = now + rent_days*86400`; 期限切れ後の再購入対応; 永続/有効レンタルの二重購入を阻止 |
| `DoUpgrade()` | **新規** | `g_iUpgradePrice` コイン消費 → 永続化（メモリ Trie + DB `expire_at=0` の二重書き込み） |
| `SkinExpire()` | **新規** | 期限タイムスタンプ返却: 0=永続, -1=未所有 |
| `IsSkinValid()` | **新規** | 「所有＋未期限切れ」判定（レンタル/永続を統合） |
| `DaysLeft()` | **新規** | 残り日数（永続=0） |
| `HasSkin()` | 維持 | 従来の所有判定、メニュー走査用 |
| `GiveSkinTo()` | 変更 | 管理者付与 = **永続**（`expire_at=0`）; 既存レンタルも自動昇格 |
| `RemoveSkinFrom()` | 変更 | 削除時に期限情報（Trie）も削除 |
| `OnSkinChosen()` | 変更 | 有効スキンなら即選択、それ以外は購入/再購入確認 |
| `MenuSkin` | 変更 | 「永続化」項目を追加; 状態表示 `[永久]/[残りX日]/[期限切れ]` |
| `MenuUpgrade()` / `MenuConfirmUpgrade()` | **新規** | 永続化の選択・確認メニュー |
| `SkinHandler` / `UpgradeHandler` / `UpgradeConfirmHandler` | 変更/新規 | メニューコールバック |
| `Db_InsertOwned()` | 変更 | `expire_at` を記録; `ON DUPLICATE KEY UPDATE` で再購入/昇格を更新 |
| `Db_SetPermanent()` | **新規** | `UPDATE ... SET expire_at=0` |
| `Db_LoadOwned()` | 変更 | `expire_at` を取得; 期限切れレコードを除外し DB も整理 |
| `ImportSkinsToDb()` | 変更 | `[SETTINGS]` ブロック（`rent_days`/`upgrade_price`）解析; TT/CT セクション取り込み |
| `CreateTablesSync()` | 変更 | `expire_at` カラム追加; 既存 DB に自動 `ALTER TABLE` |
| `ApplyCurrentSkin()` / `fwd_PlayerPreThink` | 変更 | 適用前に `IsSkinValid` 判定、期限切れはデフォルトモデルへ |
| `client_disconnected` / `plugin_end` / `Db_LoadOwned` | 変更 | 退出・終了時の Trie 後始末 |

---

## 7. 拡張ガイド

### 7.1 スキン追加（最も一般的）
`skins.cfg` の `[TT]` または `[CT]` セクションに 2 行:
```
名前  モデルパス  価格
wav サウンドパス  (任意)
```
名前はサーバー全体で一意、後から変えると購入履歴が失われる。モデルファイルは実在必須。

### 7.2 経済数値の変更
`[SETTINGS]` のみ変更:
```
rent_days 30        ; 7 にすれば 7日, 0 にすれば購入即永続
upgrade_price 2000  ; 永続化の価格
```

### 7.3 DB 直接登録
`cpm_skins` に 1 行挿入（設定ファイルと同等、大量登録に便利）:
```sql
INSERT INTO cpm_skins (model_key, model_path, price, team, death_snd) VALUES ('名前','models/x/x.mdl',300,'T','misc/x.wav');
```

### 7.4 コード拡張ポイント
- コイン API: `hns_gc_get_player(id)` / `hns_gc_set_player(id, n)`（`hns_gc.inc`）— 別の通貨に差し替えるならこの 2 箇所
- 表示エンジン: `CustomPlayerModelsApi`（`custom_player_models.inc`）— モデルプリキャッシュとクライアント表示担当
- 権限: スキンプールの `pool_flags` フィールド（`IsAllowed()`）
- 新陣営・新モード: `pool_e` 列挙とメニューロジックを拡張

---

## 8. FAQ

**`cpm_player_skins` テーブルが見つからない?**
→ `sql/hns_skins.sql` を実行。既存 DB なら上記 ALTER を実行。

**購入したのにスキンが見えない?**
→ `plugins.ini` で `CustomPlayerModelsApi.amxx` が `HnsMatchSkin.amxx` の前にあるか確認。両方 `plugins/` に置くこと。

**マップ変更後に追加スキンが出ない?**
→ スキンは起動/マップ変更時に `skins.cfg` から取り込まれます。設定変更後はマップ変更または再起動必須。

**レンタル期間・価格の変更は?**
→ `skins.cfg` の `[SETTINGS]` を変更後、マップ変更。

**旧データは残りますか?**
→ ローカルファイル版のデータは移行しません。新 DB はゼロから。旧バージョンは `versions/` に保存済み。

---

## 9. バージョン履歴

- **v1.0.0（正式、現行）** — MySQL 化、無制限スキン、レンタル/永続メカニズム、TT/CT セクション、デスサウンド、多言語ドキュメント
- `versions/` アーカイブ: HnsSkin v1.0.0 / v1.1.0 / v2.0.0 / v2.01 / v2.02 / v3.0.0 / v3.0.2 / match-skin-v5 / IC point menu（歴史保存、未サポート）

## 📄 ライセンス

GNU GPL v3 — [LICENSE](LICENSE) 参照。
