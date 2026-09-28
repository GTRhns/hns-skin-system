# HNS 스킨 시스템 · 공식 릴리즈 v1.0

> Counter-Strike 1.6 / AMX Mod X · **GTR HNS (숨바꼭질)** 서버 생태계에서 탄생한 MySQL 기반 커스텀 스킨 시스템.

![작성자 아바타](assets/avatar.jpg)

## 1. 소개

**HNS 스킨 시스템 v1.0 (공식 릴리즈)** 은 기존 `HnsSkin` 플러그인 시리즈를 **전면 재구축한 오픈소스 버전**이자, 이 시리즈의 **첫 공식 안정 릴리즈**입니다. 로컬 파일에 의존하던 기존 시스템을 완전히 새로 썼습니다:

- ✅ **MySQL 연동** — 전용 독립 DB 사용(기본 DB명 `skins`), 다른 플러그인과 공유하지 않음; 연결 설정은 `configs/mixsystem/skinsql.cfg`
- ✅ **무제한 스킨 추가** — 개수 제한 없음(서버 모델 프리캐시 한도까지만)
- ✅ **임대 + 영구 메커니즘** — 구매 시 기본 **30일 임대**(설정 가능); 코인으로 **영구 업그레이드**(기본 **2000**, 설정 가능); **관리자 직접 영구 지급**
- ✅ **TT / CT 섹션 설정** — 진영별로 구분된 설정 파일
- ✅ **스킨별 죽음 사운드** — 스킨마다 고유 사운드(재사용 가능)
- ✅ **ICGB 코인 경제** — 기존 코인 API(`hns_gc_get_player` / `hns_gc_set_player`) 재사용

---

## 🌍 언어

| 언어 | 파일 |
|---|---|
| 🇬🇧 English | [README.md](README.md) |
| 🇨🇳 简体中文 | [README.zh-CN.md](README.zh-CN.md) |
| 🇹🇼 繁體中文 | [README.zh-TW.md](README.zh-TW.md) |
| 🇷🇺 Русский | [README.ru.md](README.ru.md) |
| 🇰🇷 한국어 | [README.ko.md](README.ko.md) |
| 🇯🇵 日本語 | [README.ja.md](README.ja.md) |

---

## 2. 탄생 배경

이 시스템은 **GTR HNS(숨바꼭질) 서버** 운영에서 탄생했습니다. HNS에서 플레이어의 모델(스킨)은 개성을 나타내는 핵심 요소라서, 처음에는 로컬 파일 기반 플러그인으로 제작되었습니다(`versions/` 아카이브: HnsSkin v1.0.0 → v3.0.2, match-skin-v5 등).

기존 버전의 문제점:

1. 스킨·구매 데이터가 로컬 파일에 의존 → 서버 간 동기화 불가, 관리자 패널에서 조회 불가
2. 스킨 등록에 소스 수정이나 복잡한 설정 필요
3. "임대/영구" 개념 부재 — 영구 아니면 없음

**공식 v1.0** 은 이를 모두 해결: MySQL 연동, 설정 파일 기반 등록, "30일 임대 + 코인 영구 업그레이드 + 관리자 영구 지급" 3단 메커니즘, 무제한 스킨 추가. 이 리포지토리는 이제 **새 공식 v1.0** 으로 재시작되었습니다.

---

## 3. 기능

### 3.1 임대와 영구
- ICGB 코인으로 구매 = **`rent_days` 일 임대**(기본 30일, 설정 가능)
- 만료 시 스킨 **자동 소멸**, **재구매 가능**(같은 가격, 임대 갱신)
- 임대 스킨은 `/skin` 메뉴 → **"영구 업그레이드"**로 전환, **`upgrade_price`** 코인 소모(기본 2000, 설정 가능)
- **관리자 지급 = 영구**: `/cpm` 메뉴로 지급 시 `expire_at = 0` 기록; 이미 임대 중이면 즉시 영구로 승격
- 메뉴에 상태 표시: `[영구]` / `[남은 X일]` / `[만료]`

### 3.2 MySQL 데이터
- 전용 독립 DB 사용(기본 DB명 `skins`, `mixsystem/skinsql.cfg` 참조), 다른 플러그인과 공유하지 않음
- 테이블 3개(`cpm_` 프리픽스): 스킨 풀 / 플레이어 보유 / 현재 선택
- phpMyAdmin에서 보유 현황, 영구 여부, 곧 만료될 스킨 조회 가능
- 플러그인이 테이블 자동 생성, 기존 DB에 `expire_at` 컬럼 자동 추가

### 3.3 무제한 스킨
- 등록 = `skins.cfg` 해당 진영 섹션에 두 줄, **무제한**
- 스킨 = 이름 + 모델 경로 + 가격 + (선택) 죽음 사운드
- 이름은 고유 키, 한글/중국어 지원; TT/CT 섹션 자동 분류

### 3.4 진영 분리
- T 진영이면 T 스킨만 보기/구매; C 진영이면 C 스킨만
- 미구매 시 기본 모델 표시

### 3.5 명령어
| 명령어 | 권한 | 설명 |
|---|---|---|
| `/skin` | 모두 | 현재 진영 스킨 선택 / 구매 / 영구 업그레이드 |
| `/cpm` | ADMIN_RCON | 관리 메뉴: 풀 보기 / 보유 보기 / 지급(영구) / 제거 |

---

## 4. 설치

### 4.1 데이터베이스
1. MySQL에서 [`sql/hns_skins.sql`](sql/hns_skins.sql) 실행(**전용 DB `skins`** + 테이블 3개 생성).
2. **기존 DB 업그레이드**(`cpm_player_skins`가 이미 있으면):
   ```sql
   ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;
   ```
   (플러그인이 시작 시 자동 추가하지만, 수동 실행이 안전)

### 4.2 플러그인 배포
1. `addons/` 폴더를 서버의 `addons/`에 병합.
2. `configs/plugins.ini`에서 `CustomPlayerModelsApi.amxx`가 `HnsMatchSkin.amxx` **앞**에 있어야 함.
3. DB 연결은 `mixsystem/skinsql.cfg` 사용(스킨 시스템 전용 독립 DB, 다른 플러그인과 공유하지 않음).

### 4.3 스킨 설정
`addons/amxmodx/configs/mixsystem/skins.cfg`:

```
[SETTINGS]
rent_days  30       ; 임대 일수, 0 = 바로 영구
upgrade_price 2000  ; 영구 업그레이드 가격 (ICGB 코인)

[TT]
; 이름    모델 경로              가격
LiNa    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav          ; 선택: 위 스킨의 죽음 사운드

[CT]
Amin    models/ddsct/ddsct.mdl  300
        wav misc/ddsct.wav
```

수정 후 **맵 변경 또는 재시작**.

---

## 5. DB 테이블

| 테이블 | 용도 | 주요 필드 |
|---|---|---|
| `cpm_skins` | 스킨 풀 | `model_key`(고유 이름), `model_path`, `price`, `team` T/C, `death_snd` |
| `cpm_player_skins` | 플레이어 보유 | `authid`+`model_key`(PK), `bought_at`, **`expire_at`(0=영구)** |
| `cpm_player_current` | 현재 선택 | `authid`+`team`, 선택된 스킨 |

조회 예시:
```sql
SELECT * FROM cpm_player_skins;                             -- 전체 보유
SELECT * FROM cpm_player_skins WHERE expire_at=0;           -- 모든 영구
SELECT * FROM cpm_player_skins WHERE expire_at>0;           -- 모든 임대
SELECT * FROM cpm_player_skins WHERE authid='STEAM_0:1:123'; -- 특정 플레이어
```

---

## 6. 수정/신규 함수 (v1.0)

핵심 파일: `addons/amxmodx/scripting/HnsMatchSkin.sma`

| 함수 | 유형 | 변경 내용 |
|---|---|---|
| `DoBuy()` | 수정 | 구매 시 **임대** 기록 `expire_at = now + rent_days*86400`; 만료 후 재구매 지원; 영구/유효 임대 중복 구매 차단 |
| `DoUpgrade()` | **신규** | `g_iUpgradePrice` 코인 소모 → 영구(메모리 Trie + DB `expire_at=0` 이중 기록) |
| `SkinExpire()` | **신규** | 만료 타임스탬프 반환: 0=영구, -1=미보유 |
| `IsSkinValid()` | **신규** | "보유 + 미만료" 판단(임대/영구 통합) |
| `DaysLeft()` | **신규** | 남은 일수(영구=0) |
| `HasSkin()` | 유지 | 기존 보유 판단, 메뉴 순회용 |
| `GiveSkinTo()` | 수정 | 관리자 지급 = **영구**(`expire_at=0`); 기존 임대도 자동 영구 승격 |
| `RemoveSkinFrom()` | 수정 | 제거 시 만료 시간(Trie)도 삭제 |
| `OnSkinChosen()` | 수정 | 유효 스킨이면 즉시 선택, 아니면 구매/재구매 확인 |
| `MenuSkin` | 수정 | "영구 업그레이드" 항목 추가; 상태 표시 `[영구]/[남은 X일]/[만료]` |
| `MenuUpgrade()` / `MenuConfirmUpgrade()` | **신규** | 업그레이드 선택/확인 메뉴 |
| `SkinHandler` / `UpgradeHandler` / `UpgradeConfirmHandler` | 수정/신규 | 메뉴 콜백 |
| `Db_InsertOwned()` | 수정 | `expire_at` 기록; `ON DUPLICATE KEY UPDATE`로 재구매/승격 갱신 |
| `Db_SetPermanent()` | **신규** | `UPDATE ... SET expire_at=0` |
| `Db_LoadOwned()` | 수정 | `expire_at` 조회; 만료 레코드 필터 + DB 정리 |
| `ImportSkinsToDb()` | 수정 | `[SETTINGS]` 블록(`rent_days`/`upgrade_price`) 파싱; TT/CT 섹션 임포트 |
| `CreateTablesSync()` | 수정 | `expire_at` 컬럼 추가; 기존 DB 자동 `ALTER TABLE` |
| `ApplyCurrentSkin()` / `fwd_PlayerPreThink` | 수정 | 적용 전 `IsSkinValid` 검사, 만료 시 기본 모델로 |
| `client_disconnected` / `plugin_end` / `Db_LoadOwned` | 수정 | 플레이어 퇴장/종료 시 Trie 정리 |

---

## 7. 확장 가이드

### 7.1 스킨 추가(가장 흔함)
`skins.cfg`의 `[TT]` 또는 `[CT]` 섹션에 두 줄:
```
이름  모델 경로  가격
wav  사운드 경로  (선택)
```
이름은 서버 전체에서 고유하고, 나중에 바꾸면 안 됨(구매 기록 소실). 모델 파일은 실제 존재해야 함.

### 7.2 경제 수치 변경
`[SETTINGS]`만 수정:
```
rent_days 30        ; 7이면 7일, 0이면 구매 즉시 영구
upgrade_price 2000  ; 영구 업그레이드 가격
```

### 7.3 DB 직접 등록
`cpm_skins`에 한 줄 삽입(설정 파일과 동일 효과, 대량 작업용):
```sql
INSERT INTO cpm_skins (model_key, model_path, price, team, death_snd) VALUES ('이름','models/x/x.mdl',300,'T','misc/x.wav');
```

### 7.4 코드 확장 포인트
- 코인 API: `hns_gc_get_player(id)` / `hns_gc_set_player(id, n)`(`hns_gc.inc`) — 다른 화폐 시스템으로 교체 시 이 두 곳만 수정
- 표시 엔진: `CustomPlayerModelsApi`(`custom_player_models.inc`) — 모델 프리캐시/클라이언트 표시 담당
- 권한: 스킨 풀 `pool_flags` 필드(`IsAllowed()`)
- 새 진영/모드: `pool_e` 열거와 메뉴 로직 확장

---

## 8. FAQ

**`cpm_player_skins` 테이블을 찾을 수 없나요?**
→ `sql/hns_skins.sql` 실행; 기존 DB면 위 ALTER 실행.

**구매했는데 스킨이 안 보이나요?**
→ `plugins.ini`에서 `CustomPlayerModelsApi.amxx`가 `HnsMatchSkin.amxx` 앞에 있는지 확인, 둘 다 `plugins/`에 있어야 함.

**맵 변경 후 추가한 스킨이 안 나오나요?**
→ 스킨은 시작/맵 변경 시 `skins.cfg`에서 가져옵니다. 설정 수정 후 맵 변경 또는 재시작 필수.

**임대 기간/가격 변경은?**
→ `skins.cfg`의 `[SETTINGS]` 수정 후 맵 변경.

**기존 데이터는 유지되나요?**
→ 로컬 파일 기반 데이터는 마이그레이션하지 않습니다. 새 DB는 초기화. 이전 버전은 `versions/`에 보존.

---

## 9. 버전 히스토리

- **v1.0.0(공식, 현재)** — MySQL 재작성, 무제한 스킨, 임대/영구 메커니즘, TT/CT 섹션, 죽음 사운드, 다국어 문서
- `versions/` 아카이브: HnsSkin v1.0.0 / v1.1.0 / v2.0.0 / v2.01 / v2.02 / v3.0.0 / v3.0.2 / match-skin-v5 / IC point menu(역사 보존, 미지원)

## 📄 라이선스

GNU GPL v3 — [LICENSE](LICENSE) 참조.
