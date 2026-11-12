# HNS スキンシステム · v4.0.0

> Counter-Strike 1.6 / AMX Mod X · **GTR HNS（かくれんぼ）** サーバー向けの独立スキンシステム。

![作者アバター](assets/avatar.jpg)

**HNS Skin System v4.0.0** は `HnsSkin` シリーズの新しい独立リリースです。`main` ブランチの旧 `HnsMatchSkin` プラグインを置き換え、試合プラグインの `mixsystem` 設定・データベース・コインを使用しません。

## v4.0.0 の変更点

- 🌍 **デフォルト英語・4 言語対応** — English / 简体中文 / 繁體中文 / Русский。クライアント言語が `cn` / `tw` / `en` / `ru` 以外の場合、接続 2 秒後に英語へ切り替わります。`/lang` で手動選択した言語は維持されます。
- 🗂 **メニュー刷新** — キャラクタースキン（TT / CT 分離）、ナイフ、投擲物（スモーク / フラッシュ）、GBIC ポイント、スモーク色、MySQL 状態、管理設定を分離。入口は `/skin`。
- 🔁 **デスマッチの陣営変更追従** — ナイフで倒されてリスポーンなしで陣営が変わっても、1 秒以内にその陣営のスキンとナイフを適用します。
- 💾 **独立 DB とポイント** — 独自の SQLite / MySQL と GBIC ポイントを使用。

## 言語

| 言語 | ドキュメント |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

プラグイン言語ファイル: [`addons/amxmodx/data/lang/hns_skin.txt`](addons/amxmodx/data/lang/hns_skin.txt) — `[cn]`, `[tw]`, `[en]`, `[ru]` 各 155 行。ゲーム内のデフォルトは英語です。

## クイックインストール

1. `addons/` をサーバーの `cstrike/addons/` にマージします。
2. `configs/plugins.ini` の読み込み順:

   ```
   CustomPlayerModelsApi.amxx
   HnsSponsorLocal.amxx
   HnsSkin.amxx
   ```

   ナイフスキンには `crx_knife_models.amxx` が必要で、`HnsSkin.amxx` より**先**に読み込んでください。
3. 旧 `HnsMatchSkin.amxx` と同時に読み込まないでください。どちらも `/skin` を登録します。
4. `modules.ini` で `sqlite` を有効化。ポイントとチェックインには `nvault` が必要です。
5. マップ変更またはサーバー再起動。

詳しい手順: [`docs/安装说明.txt`](docs/安装说明.txt)（中国語）。

## コマンド

| コマンド | 権限 | 説明 |
|---|---|---|
| `/skin` | 全員 | スキンショップ |
| `/lang` | 全員 | 言語切替（cn / tw / en / ru） |
| `/sign` | 全員 | デイリーチェックイン |
| `/cpm` | ADMIN_RCON | 管理メニュー |
| `amx_giveskin` / `amx_takeskin` / `amx_clearskin` | ADMIN_IMMUNITY | 付与 / 削除 / クリア |

## 過去のリリース

`versions/` にすべての過去リリースを保存しています。今回 `v3.1.0`（旧 `HnsMatchSkin` プラグイン、SQL、インストール資料）を追加アーカイブしました。

## ライセンス

GPLv3 — [LICENSE](LICENSE).
