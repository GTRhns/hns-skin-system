# Changelog

## v4.0.0 — 2026-11-12

Standalone rewrite of the skin system, replacing the old `HnsMatchSkin` plugin on `main`.

### Added
- English is now the default language. Players whose client language is not `cn` / `tw` / `en` / `ru` are switched to English 2 seconds after connecting; manual `/lang` choices are kept.
- Multilingual support: 简体中文 (`cn`), 繁體中文 (`tw`), English (`en`), Русский (`ru`) — 155 strings per language in `data/lang/hns_skin.txt`.
- Deathmatch team-switch follow: when a player is knifed and swapped to the other team without respawning, the matching team's skin and knife are applied within one second.
- Redesigned menus: `/skin` now separates character skins (TT / CT), knife models, grenade models (smoke / flash), GBIC points, smoke color, MySQL status and the admin panel.
- `HnsSponsorLocal.amxx` for the skin system's own GBIC points, decoupled from the match plugin's coin table.
- `precache_max` setting to avoid the CS 1.6 512-model limit on heavy HNS maps.
- Documentation for adding character skins, first-person / third-person weapon models (`v_` / `p_` / `w_`) and custom third-party WAV sounds (death sounds and knife sounds), including FastDL paths.

### Changed
- The skin system uses its own database (`skinsql` SQLite by default, MySQL optional) and its own config directory `configs/skinsql`; it no longer reads `mixsystem` or the match plugin's database.
- Plugin version bumped to `4.0.0`; compiled `HnsSkin.amxx` rebuilt from source.
- Repository `main` now contains the standalone v4.0.0 package. The previous `main` addons, SQL schema and install docs are archived under `versions/v3.1.0/`.

### Fixed
- Skins no longer stay on the old team's model after a deathmatch team swap.
- Skin/knife state is re-applied after map changes and late asynchronous ownership loads.

### Compatibility
- AMX Mod X 1.10 (ReAPI), modules `sqlite` and `nvault`.
- `CustomPlayerModelsApi.amxx` must load first; `crx_knife_models.amxx` (optional) must load before `HnsSkin.amxx`.
- Do not load `HnsMatchSkin.amxx` together with `HnsSkin.amxx`.
