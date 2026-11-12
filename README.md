# HNS Skin System · v4.0.0 (Official Release)

> Counter-Strike 1.6 / AMX Mod X · standalone custom skin system for **GTR HNS** (Hide & Seek) servers.

![avatar](assets/avatar.jpg)

**HNS Skin System v4.0.0** is the new standalone release of the `HnsSkin` plugin series. It replaces the old `HnsMatchSkin` plugin on `main` and no longer shares the match plugin's `mixsystem` configs, database or coin table.

## What's new in v4.0.0

- 🌍 **English by default, 4 languages included** — English, 简体中文, 繁體中文, Русский.
  A player whose client language is not `cn` / `tw` / `en` / `ru` is switched to English 2 seconds after connecting.
  Players who pick a language manually with `/lang` keep their own choice.
- 🗂 **Redesigned menus** — character skins (TT / CT separated), knife models, grenade models (smoke / flash), GBIC points, smoke color, MySQL status and the admin panel are now separate entries. `/skin` stays the single entry point.
- 🔁 **Deathmatch team-switch follow** — in deathmatch, when a player is knifed and swapped to the other team without respawning, the plugin detects the new team within one second and applies that side's skin and knife automatically. No respawn required.
- 💾 **Own database and currency** — uses its own SQLite / MySQL storage and its own GBIC points; never reads the match plugin's `mixsystem` or coin table.
- 🛠 **Install-and-go package** — compiled `.amxx` files, full source, includes and example configs are all included.

## Languages

| Language | Documentation |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

The plugin language file is [`addons/amxmodx/data/lang/hns_skin.txt`](addons/amxmodx/data/lang/hns_skin.txt) with `[cn]`, `[tw]`, `[en]` and `[ru]` sections. The `README.*` files are documentation only; the in-game default is English.

## Quick Start

1. Merge `addons/` into your server's `cstrike/addons/` directory.
2. Make sure the load order in `configs/plugins.ini` is:

   ```
   CustomPlayerModelsApi.amxx
   HnsSponsorLocal.amxx
   HnsSkin.amxx
   ```

   `crx_knife_models.amxx` (optional, for knife skins) must be loaded **before** `HnsSkin.amxx`.
3. Do **not** load the old `HnsMatchSkin.amxx` at the same time — both register `/skin`.
4. Enable the `sqlite` module in `modules.ini`; points and daily check-in need `nvault`.
5. Change map or restart the server.

Chinese install guide: [`docs/安装说明.txt`](docs/安装说明.txt).

## Feature Highlights

- **Unlimited skins** — add as many as the model precache limit allows
- **TT / CT separated** — each skin belongs to one team; players only see and buy the skin of their current team
- **Rental + permanent** — coin purchase grants a 30-day rental (configurable); upgrade it to permanent with coins; admin grants are permanent
- **Death sound per skin** — each skin can carry one or more death sounds, randomly picked on death
- **Knife / grenade skins** — knife models via `crxknives`, smoke and flash models via `nade_skins.cfg`
- **Daily check-in and playtime rewards** — GBIC economy fully inside the skin system
- **Precache guard** — `precache_max` protects heavy HNS maps from the CS 1.6 512-model limit
- **Background grant** — `cpm_skin_grant` lets you grant skins to offline players directly from HeidiSQL / phpMyAdmin

## Repository layout

```
hns-skin-system/
├── addons/amxmodx/              # deployable package
│   ├── plugins/                 # compiled .amxx (3 plugins)
│   ├── scripting/               # source + include/
│   ├── configs/                 # plugins.ini, KnifeModels.ini, skinsql/, custom_player_models.cfg
│   └── data/lang/hns_skin.txt   # cn / tw / en / ru language file
├── docs/                        # installation guide (Chinese)
├── assets/                      # author avatar
├── versions/                    # legacy releases (v1.0.0 ~ v3.1.0)
├── CHANGELOG.md
├── LICENSE                      # GPLv3
└── README.*.md                  # multilingual documentation
```

## Commands

| Command | Access | Description |
|---|---|---|
| `/skin` | everyone | skin shop: character / knife / grenade / points / smoke color |
| `/lang` | everyone | switch language (cn / tw / en / ru) |
| `/sign` | everyone | daily check-in (`/checkin`, `/qd`, `/签到` also work) |
| `/cpm` | ADMIN_RCON | admin menu: pool, ownership, grant, remove, clear |
| `amx_giveskin <steamid> <skin\|all\|all_t\|all_c\|all_knife\|all_nade>` | ADMIN_IMMUNITY | grant skins to an online or offline player |
| `amx_takeskin <steamid> <skin\|all\|all_knife\|all_nade>` | ADMIN_IMMUNITY | remove skins |
| `amx_clearskin <steamid>` | ADMIN_IMMUNITY | clear all skins of a player |

## Configuration

| File | Purpose |
|---|---|
| `configs/skinsql/skins.cfg` | skin pool, `[SETTINGS]` block, `storage local/mysql` |
| `configs/skinsql/nade_skins.cfg` | smoke / flash grenade skins |
| `configs/skinsql/knife_skins.cfg` | knife shop prices |
| `configs/skinsql/skinsql.cfg.example` | MySQL connection template |
| `configs/KnifeModels.ini` | knife model definitions used by `crxknives` |
| `configs/custom_player_models.cfg` | player model engine cvars |

Default database is local SQLite at `addons/amxmodx/data/sqlite3/skinsql.sq3`; tables are created automatically. To use MySQL, copy `skinsql.cfg.example` to `skinsql.cfg`, fill in the credentials and set `storage mysql` in `skins.cfg`.

## Legacy releases

`versions/` keeps all previous releases for history:

- `v3.1.0` — the old `HnsMatchSkin` main-branch addons, SQL schema and install docs (archived in this release)
- `v3.0.2`, `v3.0.0`, `v2.02`, `v2.01`, `v2.0.0`, `v1.1.0`, `v1.0.0`, `match-skin-v5`, `ic-v1.0.0`, `skin-1.0`

## License

GPLv3 — see [LICENSE](LICENSE).
