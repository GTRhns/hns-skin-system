# HNS Skin System · 正式版 v1.0 (Official Release)

> Counter-Strike 1.6 / AMX Mod X · MySQL-powered custom skin system for the **GTR HNS** (Hide & Seek) server ecosystem.

![avatar](assets/avatar.jpg)

**HNS Skin System v1.0** is the fully rebuilt, open-source successor of the legacy `HnsSkin` plugin series (see the `versions/` archive). It is the **first official stable release** and completely rewrites the old codebase:

- ✅ **MySQL-backed** — shares one database connection with your HNS match library (`HnsMatchSql`), stored in separate `cpm_` tables
- ✅ **Unlimited skins** — add skins without any hard limit (bounded only by the model precache limit)
- ✅ **Rental + Permanent** — buying a skin grants a **30-day rental** (configurable); upgrade it to permanent with coins (default **2000**, configurable); **admins grant permanent** skins directly
- ✅ **TT / CT sectioned config** — skins are grouped by team in `skins.cfg`
- ✅ **Death sound per skin** — each skin can carry its own death sound (reusable across skins)
- ✅ **ICGB coin economy** — reuses your existing coin API (`hns_gc_get_player` / `hns_gc_set_player`)

---

## 🌍 Languages

| Language | File |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

---

## ✨ Feature Highlights

- **30-day rental by default** — every coin purchase writes `expire_at = now + rent_days`; expired skins are cleaned automatically and can be re-purchased
- **Upgrade to permanent** — `/skin` menu → “Upgrade to Permanent”, costs `upgrade_price` coins (default 2000)
- **Admin permanent grant** — `/cpm` menu grant = permanent (`expire_at = 0`), also upgrades an existing rental
- **Auto DB migration** — plugin adds the `expire_at` column to an existing `cpm_player_skins` table on startup
- **Menu status display** — `[永久]` / `[剩X天]` / `[已过期]` shown per skin
- **Configurable core values** — `[SETTINGS]` block in `skins.cfg`: `rent_days`, `upgrade_price`

## 🚀 Quick Start

1. Import [`sql/hns_skins.sql`](sql/hns_skins.sql) into your MySQL database (creates 3 tables). Existing DBs only need:
   `ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;`
2. Copy `addons/` into your server (merge with the existing `addons/` folder).
3. Make sure `CustomPlayerModelsApi.amxx` is loaded **before** `HnsMatchSkin.amxx` in `plugins.ini`.
4. Edit `addons/amxmodx/configs/mixsystem/skins.cfg` to add your skins.
5. Change map / restart. Done.

Full install guide: [`docs/安装说明.txt`](docs/安装说明.txt)

## 🗂️ Repository Layout

```
hns-skin-system/
├── addons/amxmodx/            # deployable plugin package (compiled .amxx + source + includes + configs)
├── sql/hns_skins.sql          # database schema (cpm_skins / cpm_player_skins / cpm_player_current)
├── docs/                      # installation documentation
├── assets/                    # author avatar
├── versions/                  # archived legacy releases (v1.0.0 ~ v3.0.2, match-skin-v5)
├── LICENSE                    # GPLv3
└── README.*.md                # multilingual documentation
```

## 🎮 Commands

| Command | Access | Description |
|---|---|---|
| `/skin` | everyone | choose / buy / upgrade the current team's skins |
| `/cpm` | ADMIN_RCON | admin menu: view pool / view player ownership / grant (permanent) / remove |

## 🛠️ Modifications & Key Functions (v1.0)

See the per-language README for the full technical breakdown. Key changes vs the legacy series:

| Function | Change |
|---|---|
| `DoBuy()` | purchase now writes a **rental** (`expire_at`), supports re-buy after expiry |
| `DoUpgrade()` | **new** — spend `upgrade_price` coins to make a rental permanent |
| `GiveSkinTo()` | admin grant = **permanent** (`expire_at=0`), upgrades existing rentals |
| `SkinExpire()` / `IsSkinValid()` / `DaysLeft()` | **new** — rental expiry helpers |
| `Db_InsertOwned()` | now stores `expire_at`, upsert via `ON DUPLICATE KEY UPDATE` |
| `Db_SetPermanent()` | **new** — sets `expire_at=0` |
| `ImportSkinsToDb()` | parses the `[SETTINGS]` block (`rent_days` / `upgrade_price`) |
| `CreateTablesSync()` | adds the `expire_at` column + auto ALTER for legacy DBs |
| `MenuSkin` / new upgrade menus | status display + “upgrade to permanent” flow |

## 📦 Legacy Releases

The `versions/` folder keeps all previous releases (HnsSkin v1.0.0 → v3.0.2, match-skin-v5, IC point menu) for history. This repository is now restarted as the **official v1.0**.

## 📄 License

GNU GPL v3 — see [LICENSE](LICENSE).
