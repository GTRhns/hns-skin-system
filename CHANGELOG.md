# Changelog

## v4.0.0 — 2026-11-12

Standalone rewrite of the skin system, replacing the old `HnsMatchSkin` plugin on `main`.

### Added
- **English is now the default language.** Players whose client language is not `cn` / `tw` / `en` / `ru` are switched to English 2 seconds after connecting; manual `/lang` choices are kept. Players whose client language is `cn` / `tw` / `en` / `ru` keep their own language.
- **Multilingual support:** 简体中文 (`cn`), 繁體中文 (`tw`), English (`en`), Русский (`ru`) — 155 strings per language in `data/lang/hns_skin.txt`.
- **Deathmatch team-switch follow:** when a player is knifed and swapped to the other team without respawning, the matching team's skin and knife are applied within one second. Also re-applied after map changes and late asynchronous ownership loads.
- **Redesigned menus:** `/skin` now separates character skins (TT / CT), knife models, grenade models (smoke / flash), GBIC balance, buy points, smoke color, MySQL status and the admin panel. Skin / grenade / knife menus keep their current page when paging.
- **Local SQLite storage (default):** no MySQL needed, file at `data/sqlite3/skinsql.sq3`, tables created automatically, back up by copying the file.
- **MySQL storage (optional):** `skinsql/skinsql.cfg`, tables created automatically; multiple servers sharing the same database share purchases, current skins and smoke colors.
- **Own currency:** `HnsSponsorLocal.amxx` provides the skin system's own GBIC points, decoupled from the match plugin's coin table.
- **Rental / permanent economy:** 30-day rental by default (`rent_days`), upgrade to permanent (`upgrade_price`), admin grants are permanent.
- **Knife skins** via `crxknives` with a separate shop price override (`knife_skins.cfg`) and no free fallback for unpriced knives.
- **Grenade skins** for smoke and flash (`nade_skins.cfg`), first-person `v_`, third-person `p_` and world `w_` models auto-detected.
- **Per-skin death sounds:** multiple WAV entries per skin, one picked at random on death, replacing the stock death sound instead of overlapping it.
- **Knife sounds:** per-knife `SELECT_SOUND`, `DEPLOY_SOUND`, `SLASH_SOUND`, `STAB_SOUND`, `HIT_SOUND`, `HITWALL_SOUND`, `SELECT_MESSAGE`.
- **Daily check-in** (`/sign`, `/checkin`, `/qd`) and **playtime rewards** (`playtime_seconds`, `playtime_bonus`).
- **Offline grants:** `cpm_skin_grant` queue plus `amx_giveskin`, `amx_takeskin`, `amx_clearskin`; players do not need to be online.
- **`precache_max`** setting to avoid the CS 1.6 512-model limit on heavy HNS maps; skipped skins stay in the shop but are marked unavailable on that map.
- **Account identification:** legit players by SteamID; non-steam (Reunion) players by IP + name.
- **Documentation:** adding character skins, first-person / third-person weapon models (`v_` / `p_` / `w_`), custom third-party WAV sounds (death sounds and knife sounds), FastDL paths and both storage modes.

### Changed
- The skin system uses its own database (`skinsql`, local SQLite by default or MySQL) and its own config directory `configs/skinsql`; it no longer reads `mixsystem` or the match plugin's database.
- Plugin version bumped to `4.0.0`; compiled `HnsSkin.amxx` rebuilt from source.
- Repository `main` now contains the standalone v4.0.0 package. The previous `main` addons, SQL schema and install docs are archived under `versions/v3.1.0/`.

### Fixed
- Skins no longer stay on the old team's model after a deathmatch team swap.
- Skin/knife state is re-applied after map changes and late asynchronous ownership loads.

### Compatibility
- AMX Mod X 1.10 (ReAPI), modules `sqlite` and `nvault`.
- `CustomPlayerModelsApi.amxx` must load first; `crx_knife_models.amxx` (optional) must load before `HnsSkin.amxx`.
- Do not load `HnsMatchSkin.amxx` together with `HnsSkin.amxx`.
