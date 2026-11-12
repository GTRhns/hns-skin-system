# HNS 스킨 시스템 · v4.0.0

> Counter-Strike 1.6 / AMX Mod X · **GTR HNS (숨바꼭질)** 서버용 독립 스킨 시스템.

![작성자 아바타](assets/avatar.jpg)

**HNS Skin System v4.0.0** 은 `HnsSkin` 시리즈의 새로운 독립 릴리즈입니다. `main` 브랜치의 구형 `HnsMatchSkin` 플러그인을 대체하며, 경기 플러그인의 `mixsystem` 설정·데이터베이스·코인을 사용하지 않습니다.

## v4.0.0 변경 사항

- 🌍 **기본 영어, 4개 언어** — English, 简体中文, 繁體中文, Русский. 클라이언트 언어가 `cn` / `tw` / `en` / `ru` 가 아니면 접속 2초 후 영어로 전환됩니다. `/lang` 으로 직접 선택한 언어는 유지됩니다.
- 🗂 **메뉴 개편** — 캐릭터 스킨(TT / CT 분리), 나이프, 투척물(연막 / 섬광), GBIC 포인트, 연막 색상, MySQL 상태, 관리자 설정이 분리되었습니다. 진입점은 `/skin`.
- 🔁 **데스매치 팀 전환 추적** — 칼에 맞아 리스폰 없이 팀이 바뀌면 1초 안에 새 진영의 스킨과 나이프를 적용합니다.
- 💾 **독립 DB와 포인트** — 자체 SQLite / MySQL 및 GBIC 포인트 사용.

## 언어

| 언어 | 문서 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

플러그인 언어 파일: [`addons/amxmodx/data/lang/hns_skin.txt`](addons/amxmodx/data/lang/hns_skin.txt) — `[cn]`, `[tw]`, `[en]`, `[ru]` 각 155줄. 게임 내 기본 언어는 영어입니다.

## 빠른 설치

1. `addons/` 를 서버의 `cstrike/addons/` 에 병합합니다.
2. `configs/plugins.ini` 로드 순서:

   ```
   CustomPlayerModelsApi.amxx
   HnsSponsorLocal.amxx
   HnsSkin.amxx
   ```

   나이프 스킨은 `crx_knife_models.amxx` 가 필요하며 `HnsSkin.amxx` 보다 **먼저** 로드해야 합니다.
3. 구형 `HnsMatchSkin.amxx` 와 동시에 로드하지 마세요. 둘 다 `/skin` 을 등록합니다.
4. `modules.ini` 에서 `sqlite` 모듈을 켜고, 포인트·출석은 `nvault` 가 필요합니다.
5. 맵 변경 또는 서버 재시작.

자세한 설치 안내: [`docs/安装说明.txt`](docs/安装说明.txt) (중국어).

## 명령어

| 명령어 | 권한 | 설명 |
|---|---|---|
| `/skin` | 모든 플레이어 | 스킨 상점 |
| `/lang` | 모든 플레이어 | 언어 변경 (cn / tw / en / ru) |
| `/sign` | 모든 플레이어 | 일일 출석 |
| `/cpm` | ADMIN_RCON | 관리자 메뉴 |
| `amx_giveskin` / `amx_takeskin` / `amx_clearskin` | ADMIN_IMMUNITY | 지급 / 회수 / 초기화 |

## 이전 버전

`versions/` 에 모든 이전 릴리즈가 보관되어 있습니다. 이번 릴리즈에서 `v3.1.0`(구형 `HnsMatchSkin` 플러그인, SQL, 설치 문서)이 추가로 아카이브되었습니다.

## 라이선스

GPLv3 — [LICENSE](LICENSE).
