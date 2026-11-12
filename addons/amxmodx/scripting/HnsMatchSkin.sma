/* ============================================================
   HNS Match Skin  -  玩家自定义皮肤系统
   配置目录: amxmodx/configs/skinsql  不读取比赛插件的 mixsystem
   货币: 皮肤商店自己的点数, 存在 nvault skin_gc, 不读比赛金币
   显示引擎: 依赖 CustomPlayerModelsApi.sma (模型 precache / 客户端显示)
   ------------------------------------------------------------
   模型 / 音效策略:
     - TT 款 (恐怖分子) 和 CT 款 (反恐精英) 是两条独立记录, 一行=一款
     - 每一款 = 一套模型 + 一个或多个死亡音效, 死亡时从该款音效里随机一条; 音效可复用
     - 玩家分别单独购买 TT 款 / CT 款
     - 玩家当前是 T 就只显示/使用/购买 TT 款; 当前是 C 就只显示/使用/购买 CT 款
     - 没买当前阵营的款时显示默认模型
   租期 / 永久机制:
     - 金币购买默认获得 30 天租期 (可配置), 到期自动失效, 可再次购买
     - 已购的限时皮肤可花"升级永久价格"(可配置, 默认 2000 金币)升级为永久
     - 管理员发放 = 直接永久 (expire_at=0)
   配置(在 skins.cfg 顶部 [SETTINGS] 区块):
     - rent_days        租期天数, 默认 30, 填 0 = 直接永久
     - upgrade_price    升级永久价格, 默认 2000
   玩家菜单: /skin
     1.人物皮肤 [总数红] -> CT皮肤 / TT皮肤
     2.刀皮模型 [数量红]
     3.投掷物模型 [数量红]
     (空行)
     4.GBIC点查询 [余额红]
     5.购买点数
     6.烟雾弹颜色 [当前颜色红]  (免费, MySQL 多服同步)
     (空行)
     7.MySQL链接 (黄, 需管理员 A/B)
     8.管理设置 (红, 需 A)
     每日签到改到个人设置; 一键清除只留管理菜单
   投掷物菜单: 先进分类页(烟雾弹/闪光弹), 再进对应列表
   管理菜单: /cpm 或主菜单第8项 (A权限)
   本地/盗版: Reunion 判定不是正版时, 按 IP 和名字一起存 (NAME:IP|名字)
     两个都必须相同才是同一个盗版账号。改名或换 IP 都是新档
     盗版模拟出来的 STEAM_0:x:x 不再当账号
     正版仍用 SteamID; 没有 Reunion 时才退回旧的 SteamID 认号
   后台按 SteamID 发放 (玩家可以不在线, 写入 MySQL, HeidiSQL 直接可见):
     - 管理菜单: 按SteamID发放 / 按SteamID收回 / 按SteamID一键清除
     - 控制台: amx_giveskin <steamid> <皮肤名|all|all_t|all_c|all_knife|all_nade>
               amx_takeskin <steamid> <皮肤名|all>
               amx_clearskin <steamid>
     - HeidiSQL 插入 cpm_skin_grant(steamid, skin_key) 后, 服务器约 8 秒写入拥有表
     - HeidiSQL 查看视图 cpm_heidi_player: steamid + 该玩家已获得的全部皮肤
   换图: plugin_precache 只读 skins.cfg 并预缓存模型;
         建表/导入 MySQL 放到 plugin_init 后台, 避免卡住 changelevel
   死亡音效: 拦截原版 player/die* / death* , 换成当前皮肤音效, 不再叠原声
   依赖:
     - CustomPlayerModelsApi.amxx  (须在 plugins.ini 中排在本插件之前)
     - storage local  本地 sqlite: data/sqlite3/skinsql.sq3
     - storage mysql  使用 skinsql/skinsql.cfg, 不使用比赛的 hnsmatch-sql.cfg
     - HnsSponsorLocal.amxx  皮肤商店自己的点数, 不跟比赛金币走
     - HnsLanguage.amxx 可选, 没有时用 data/lang/hns_skin.txt
   语言:
     - 支持 简体中文 / 繁體中文 / English / Русский
     - 默认英语: 客户端语言未识别(非 cn/tw/en/ru)或没手动选过语言的玩家, 进服 2 秒后自动切到英语
     - 玩家用 /lang 手动选择过语言的, 保持玩家自己的选择
     - crxknives 可选, 没有时刀皮商店为空
   ============================================================ */

#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <nvault>
#include <fakemeta>
#include <reapi>
#include <newmenus>
#include <string>
#include <hns_optional_sql>
#include <hns_gc>
#include <custom_player_models>
#include <hns_language>
#include <crxknives>

// ---- 表名 (与你的 hns 库同库, cpm_ 前缀分表) ----
#define SKINS_TABLE   "cpm_skins"
#define OWNS_TABLE    "cpm_player_skins"
#define CUR_TABLE     "cpm_player_current"
#define GRANT_TABLE   "cpm_skin_grant"
#define CHECKIN_TABLE "cpm_daily_checkin"
#define SMOKE_TABLE   "cpm_smoke_color"

native hns_smokenade_get_color(id);
native hns_smokenade_set_color(id, idx);
native hns_smokenade_count();
native hns_smokenade_name(idx, dest[], len);
native hns_smokenade_langkey(idx, dest[], len);

// ---- 数据库连接: 只读 skinsql/skinsql.cfg, 不读比赛库 ----
#define DB_CFG_FILE   "skinsql/skinsql.cfg"
#define DEFAULT_HOST  "127.0.0.1"
#define DEFAULT_USER  "root"
#define DEFAULT_PASS  "root"
#define DEFAULT_DB    "skinsql"

// ---- 死亡音效 ----
#define DEATH_SND_PATH 80
#define DEATH_SND_MAX  320

// ---- 皮肤数据源配置文件 (一行=一款, 启动自动导入 MySQL) ----
#define SKINS_CFG_FILE "skinsql/skins.cfg"

#define SKIN_KEY_MAX   32
#define SKIN_MODEL_MAX 64

// newmenus 默认每页 7 项, 用于从 item 反推所在页 (item / SKIN_PER_PAGE)
#define SKIN_PER_PAGE  7

// ---- 投掷物皮肤 (烟雾/闪光) ----
#define NADE_CFG_FILE  "skinsql/nade_skins.cfg"
#define NADE_KEY_MAX   32
#define NADE_KIND_SMOKE 0   // 烟雾弹
#define NADE_KIND_FLASH 1   // 闪光弹

// ---- 刀皮商店 ----
// 刀模型本体仍由 crxknives 引擎的 KnifeModels.ini 提供,
// 但商店显示的价格/免费规则改由这个 cfg 控制, 方便单独管理 (不影响引擎的刀定义)。
#define KNIFE_CFG_FILE "skinsql/knife_skins.cfg"
// 没写 PRICE 的刀不能当免费。0 才是免费，没标价按这个默认价卖。
#define KNIFE_DEFAULT_PRICE 300

#define ADMIN_FLAG ADMIN_BAN
#define TASK_REAPPLY_KNIFE 26000
#define TASK_AUTH_RETRY 27000
#define TASK_PLAYTIME 28000
#define TASK_APPLY_NADE 29000
#define TASK_MENU_SHOP 30000
#define TASK_GRANT_POLL 32000
#define TASK_SKIN_WATCH 31000
#define TASK_DEFAULT_LANG 33000
#define PLAYTIME_TICK 60.0

#define SHOP_MENU_SKIN 1
#define SHOP_MENU_NADE_CAT 2
#define SHOP_MENU_NADE_KIND 3
#define SHOP_MENU_KNIFE 4

// 阵营字符
#define TEAM_CHAR_T 'T'
#define TEAM_CHAR_C 'C'

// ---- 可配置项 (在 skins.cfg 的 [SETTINGS] 区块里改, 这里只是默认值) ----
new g_iRentDays = 30;       // 金币购买获得的租期天数, 0 = 直接永久
new g_iUpgradePrice = 2000; // 限时皮肤升级为永久的价格 (ICGB金币)
new g_iKnifeFree = 1;       // 刀皮前 N 把免费, 其余必须标价购买; 没写 PRICE 不再当成免费
new g_iNadeFree = 1;        // 烟雾/闪光弹皮肤前 N 个免费, 其余按 GBIC 购买
new g_iCheckinBonus = 10;   // 每日签到奖励 GBIC
new g_iPlaytimeBonus = 5;   // 在线满 1 小时奖励 GBIC
new g_iPlaytimeNeed = 3600; // 在线奖励所需秒数
new g_szBuyGoldText[160] = "请联系管理员购买 GBIC 点数";
new g_szBuyGoldUrl[128];

// CS1.6 引擎模型预缓存池 (MAX_MODELS) 只有 512 个, 且和地图自身的 *刷子模型共享。
// 重型 HNS 地图本身可能吃掉 290+ 个名额; 本插件若不限量预缓存全部皮肤模型,
// 极易触发 ED_ParseEdict: Model '*N' failed to precache because the item count is over the 512 limit 崩服。
// 这里的上限限制"本插件每张地图最多预缓存多少个皮肤模型"(刀皮/投掷物皮单独计, 数量很少)。
//   0  = 不限制 (旧行为, 危险)
//   >0 = 超出上限的皮肤仍然进商店目录, 但不预缓存、因此本图不可用(不会崩服)
//   默认 24: 重型 HNS 地图大约占用 290 个 *刷子模型名额, 留出余量给引擎/其它插件。
//   某张图崩服 -> 调小; 有富余 -> 调大, 一次 4~8 地试。
new g_iPrecacheMax = 0;
new g_iPrecacheUsed = 0;    // 本图已经成功预缓存了多少个皮肤模型

// 刀皮商店价格覆盖表: 刀名(NAME) -> 价格. 来自 knife_skins.cfg,
// 有记录时优先于 KnifeModels.ini 的 PRICE; 没有则回退到引擎 PRICE。
new Trie:g_tKnifePrice = Invalid_Trie;

static const g_szClcmds[][] = {
	"say /skin",
	"say_team /skin",
	"say /cpm",
	"say_team /cpm",
	"say /giveskin",
	"say_team /giveskin",
	"say /giveskinmenu",
	"say_team /giveskinmenu"
};

// 皮肤池记录 (一行 = 一个阵营款式)
enum _:pool_e {
	pool_key[SKIN_KEY_MAX],      // 唯一名字(识别/菜单/拥有都靠它, 如 hunan_t / hunan_c)
	pool_model[SKIN_MODEL_MAX],  // 模型路径 (相对 models/)
	pool_flags[16],              // 权限要求, 空=所有人
	pool_snd[DEATH_SND_MAX],     // 死亡音效列表, 逗号分隔 (相对 sound/, 空=不播; 死亡随机一条)
	pool_price,                  // 价格(ICGB金币) 0=免费
	pool_body,                   // 子模型
	pool_skin,                   // 皮肤序号
	pool_team,                   // 'T' 或 'C' (该款式属于哪个阵营)
	pool_precache                // 1 = 本图已成功预缓存模型; 0 = 因上限被跳过(本图不可用)
};

enum _:db_e { db_host[48], db_user[32], db_pass[32], db_db[32] };

enum _:qtype_e {
	QT_LOAD_OWNED = 1,
	QT_LOAD_CURRENT,
	QT_SAVE_CURRENT,
	QT_BUY_SKIN,
	QT_REMOVE_SKIN,
	QT_UPGRADE_SKIN,
	QT_CHECKIN_CLAIM,
	QT_SQL_PING,
	QT_SQL_COUNT
};

new g_eDb[db_e];
new Handle:g_hSqlTuple;

new Array:g_pPool;          // Array of pool_e
new Trie:g_pPoolIndex;      // key -> 池下标
new g_iPoolSize;

// 每个阵营各自的"当前选用款" key
new g_CurT[MAX_PLAYERS + 1][SKIN_KEY_MAX];   // 恐怖分子款
new g_CurC[MAX_PLAYERS + 1][SKIN_KEY_MAX];   // 反恐精英款
new g_iCurKnife[MAX_PLAYERS + 1];             // 当前刀皮编号, 0 = 默认 kf
new g_iKnifeRetry[MAX_PLAYERS + 1];           // 换图后覆盖 crxknives nVault 的重试次数
new g_iAuthRetry[MAX_PLAYERS + 1];            // 正版等待 SteamID 就绪后再读皮肤
new bool:g_bApplyingKnife[MAX_PLAYERS + 1];   // 正在强制套刀, 避免 knife_updated 递归重置
new Array:g_Owned[MAX_PLAYERS + 1];
new Trie:g_OwnedExpire[MAX_PLAYERS + 1];   // key -> 到期时间戳(UNIX秒), 0 = 永久
new g_szAuth[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH];
new Trie:g_tAuthByIp = Invalid_Trie;
new g_iLoadGen[MAX_PLAYERS + 1];
new bool:g_bOwnedLoaded[MAX_PLAYERS + 1];   // 该玩家的拥有列表是否已从MySQL加载完毕
new g_iLastTeam[MAX_PLAYERS + 1];
// 上一次真正应用到模型上的阵营+款, 用于每帧对比当前槽, 换图/复活/异步加载晚了都能补上
new g_szAppliedTeam[MAX_PLAYERS + 1];
new g_szAppliedKey[MAX_PLAYERS + 1][SKIN_KEY_MAX];

new bool:g_bPlayingDeathSnd; // emit_sound 替换死亡音效时防递归

new g_pendingGiveTeam[MAX_PLAYERS + 1]; // 0=全部  TEAM_CHAR_T / TEAM_CHAR_C
new bool:g_bSqlReady;
new bool:g_bLocalDb;
new bool:g_bHasReunion;
new g_szSqlStatus[96];
new g_iSqlLastErr;
new g_szSqlLastErr[128];
new g_iSqlOwnedCount;
new g_iSqlCurrentCount;
new g_iBrowseTeam[MAX_PLAYERS + 1]; // 玩家浏览的阵营 'T'/'C'
// 多级菜单传参暂存
new g_pendingTarget[MAX_PLAYERS + 1];
new g_pendingAdmin[MAX_PLAYERS + 1];
new g_pendingMode[MAX_PLAYERS + 1][8]; // "view" / "give" / "remove" / "sgbic"
new g_szPendingGbicSteam[MAX_PLAYERS + 1][40];
new g_legacyPendingAdmin[MAX_PLAYERS + 1]; // 兼容旧 callfunc 接口：按目标玩家隔离管理员状态

// 各菜单当前页 (选中/翻页后重建时停在同一页, 不再跳回第一页)
new g_iKnifePage[MAX_PLAYERS + 1];
new g_iBrowsePage[MAX_PLAYERS + 1];

// 每日签到 / 在线时长奖励 (nVault 跨图保存)
new g_iVaultReward = INVALID_HANDLE;
new g_iLastCheckin[MAX_PLAYERS + 1];
new bool:g_bCheckinPending[MAX_PLAYERS + 1];
new bool:g_bCheckinLegacyClaim[MAX_PLAYERS + 1];
new g_iPlayRemain[MAX_PLAYERS + 1];
new Float:g_flPlayStart[MAX_PLAYERS + 1];
new bool:g_bRewardLoaded[MAX_PLAYERS + 1];
new g_iNadePage[MAX_PLAYERS + 1];
// 投掷物皮肤: 当前停留的分类 (-1 = 分类选择页; 0 = 烟雾; 1 = 闪光)
new g_iNadeKindPage[MAX_PLAYERS + 1];
new g_iShopMenu[MAX_PLAYERS + 1];
new g_iShopPage[MAX_PLAYERS + 1];
new g_iShopKind[MAX_PLAYERS + 1];

// 后台发放队列一次最多消化这么多行, 放全局避免撑爆 pawn 栈
#define GRANT_BATCH 16
new g_iGrantId[GRANT_BATCH];
new g_szGrantSteam[GRANT_BATCH][64];
new g_szGrantKey[GRANT_BATCH][SKIN_KEY_MAX];
new g_szGrantAct[GRANT_BATCH][8];
new Float:g_flShopKeep[MAX_PLAYERS + 1];

// ---- 投掷物皮肤池 ----
enum _:nade_e {
	nade_key[NADE_KEY_MAX],      // 唯一名字
	nade_name[NADE_KEY_MAX],     // 显示名
	nade_model[SKIN_MODEL_MAX],  // 模型路径 (相对 models/, 不含 .mdl 也可)
	nade_kind,                   // NADE_KIND_SMOKE / NADE_KIND_FLASH
	nade_price                   // 价格(GBIC), 0 = 免费
};

new Array:g_pNade;              // Array of nade_e
new g_iNadeSize;

// 每个玩家当前选用的投掷物皮肤 key (空 = 默认模型)
new g_NadeSmoke[MAX_PLAYERS + 1][NADE_KEY_MAX];
new g_NadeFlash[MAX_PLAYERS + 1][NADE_KEY_MAX];

/* ============================================================
   纯工具函数
   ============================================================ */
bool:IsSkinAdmin(id) {
	// 管理员设置：仅 A (ADMIN_IMMUNITY)。
	return (get_user_flags(id) & ADMIN_IMMUNITY) != 0;
}

bool:IsVipBlockedFromSkin(id) {
	if (get_user_flags(id) & ADMIN_IMMUNITY)
		return false;
	new szFlag[8];
	get_cvar_string("hns_fullwatcher_flag", szFlag, charsmax(szFlag));
	if (!szFlag[0])
		copy(szFlag, charsmax(szFlag), "d");
	return (get_user_flags(id) & read_flags(szFlag)) != 0;
}

bool:IsSkinSqlAdmin(id) {
	// SQL 调试：A 或 B 任一即可。
	return (get_user_flags(id) & (ADMIN_IMMUNITY | ADMIN_RESERVATION)) != 0;
}

bool:CanGrantOnlineGbic(id) {
	// 在线发放：管理员 b 以上，即 A 或 B。
	return (get_user_flags(id) & (ADMIN_IMMUNITY | ADMIN_RESERVATION)) != 0;
}

bool:IsSkinOwner(id) {
	return (get_user_flags(id) & ADMIN_IMMUNITY) != 0;
}

bool:CanSkinTarget(admin, target) {
	return IsSkinOwner(admin) || admin == target;
}

bool:IsPendingAuth(const szAuth[]) {
	if (!szAuth[0])
		return true;
	return equal(szAuth, "STEAM_ID_PENDING")
		|| equal(szAuth, "VALVE_ID_PENDING")
		|| equal(szAuth, "STEAM_ID_LAN")
		|| equal(szAuth, "VALVE_ID_LAN")
		|| equal(szAuth, "BOT")
		|| equali(szAuth, "LAN:", 4);
}

bool:IsSteamAuth(const szAuth[]) {
	return !IsPendingAuth(szAuth);
}

// Reunion 在场时, 只有正版 CA_TYPE_STEAM 才按 SteamID 存皮肤。
// 盗版不使用模拟器伪造的 SteamID, 必须 IP 和名字同时一致。
bool:IsRealSteam(id) {
	if (!g_bHasReunion)
		return true;
	if (id < 1 || id > MaxClients || !is_user_connected(id))
		return false;
	return REU_GetAuthtype(id) == CA_TYPE_STEAM;
}

// CA_TYPE_NONE 表示 Reunion 还没判定完, 这时不能当成盗版名字。
bool:SkinAuthReady(id) {
	if (!g_bHasReunion)
		return true;
	if (id < 1 || id > MaxClients || !is_user_connected(id))
		return false;
	return REU_GetAuthtype(id) != CA_TYPE_NONE;
}

bool:IsUsableIp(const szIp[]) {
	if (!szIp[0] || equal(szIp, "0.0.0.0") || contain(szIp, ".") == -1)
		return false;
	return true;
}

bool:SkinSmokeNadeAvailable() {
	return bool:LibraryExists("hns_smokenade", LibType_Library);
}

SkinGetSmokeColorName(id, dest[], len);
MenuSmokeColor(id, page = 0);

// 盗版账号: NAME:IP|名字。缺 IP 时返回 false, 调用方继续等。
bool:BuildPirateAuth(id, dest[], len) {
	new szIp[22];
	get_user_ip(id, szIp, charsmax(szIp), 1);
	new iColon = contain(szIp, ":");
	if (iColon != -1)
		szIp[iColon] = EOS;
	if (!IsUsableIp(szIp))
		return false;

	new szName[MAX_NAME_LENGTH];
	get_user_name(id, szName, charsmax(szName));
	if (!szName[0])
		copy(szName, charsmax(szName), "unnamed");
	formatex(dest, len, "NAME:%s|%s", szIp, szName);
	return dest[0] != EOS;
}

bool:SkinIdentityPending(id) {
	if (!SkinAuthReady(id))
		return true;
	new szLive[MAX_AUTHID_LENGTH];
	get_user_authid(id, szLive, charsmax(szLive));
	if (IsRealSteam(id))
		return IsPendingAuth(szLive) && !equali(g_szAuth[id], "STEAM:", 6);
	if (equali(g_szAuth[id], "NAME:", 5))
		return false;
	new szKey[MAX_AUTHID_LENGTH];
	return !BuildPirateAuth(id, szKey, charsmax(szKey));
}

GetPlayerAuth(id, dest[], len) {
	if (!SkinAuthReady(id)) {
		if (equali(g_szAuth[id], "STEAM:", 6))
			copy(dest, len, g_szAuth[id]);
		else
			dest[0] = EOS;
		return;
	}

	new szAuth[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuth, charsmax(szAuth));

	// 正版使用 SteamID, 并加前缀避免与盗版名字冲突。
	if (IsRealSteam(id) && !IsPendingAuth(szAuth)) {
		formatex(dest, len, "STEAM:%s", szAuth);
		copy(g_szAuth[id], charsmax(g_szAuth[]), dest);
		return;
	}

	// 换图时常先拿到 PENDING, 不要用盗版键覆盖已经确认的正版 SteamID。
	if (equali(g_szAuth[id], "STEAM:", 6)) {
		copy(dest, len, g_szAuth[id]);
		return;
	}

	// 盗版: IP 和名字都写入账号。单引号由 EscapeSql 处理。
	if (!BuildPirateAuth(id, dest, len)) {
		if (equali(g_szAuth[id], "NAME:", 5))
			copy(dest, len, g_szAuth[id]);
		else
			dest[0] = EOS;
		return;
	}
	copy(g_szAuth[id], charsmax(g_szAuth[]), dest);
}

TodayYmd() {
	new szDay[12];
	get_time("%Y%m%d", szDay, charsmax(szDay));
	return str_to_num(szDay);
}

LoadRewardState(id) {
	if (g_bRewardLoaded[id])
		return;

	g_iLastCheckin[id] = 0;
	g_iPlayRemain[id] = g_iPlaytimeNeed;
	g_flPlayStart[id] = get_gametime();
	if (g_iVaultReward == INVALID_HANDLE)
		return;

	new szAuth[MAX_AUTHID_LENGTH], szKey[64], szVal[32];
	GetPlayerAuth(id, szAuth, charsmax(szAuth));
	if (!szAuth[0])
		return;

	formatex(szKey, charsmax(szKey), "chk_%s", szAuth);
	if (nvault_get(g_iVaultReward, szKey, szVal, charsmax(szVal)))
		g_iLastCheckin[id] = str_to_num(szVal);

	formatex(szKey, charsmax(szKey), "play_%s", szAuth);
	if (nvault_get(g_iVaultReward, szKey, szVal, charsmax(szVal))) {
		new iRemain = str_to_num(szVal);
		if (iRemain > 0)
			g_iPlayRemain[id] = iRemain;
	}
	g_bRewardLoaded[id] = true;
}

SaveRewardState(id) {
	if (g_iVaultReward == INVALID_HANDLE)
		return;

	new szAuth[MAX_AUTHID_LENGTH], szKey[64], szVal[32];
	GetPlayerAuth(id, szAuth, charsmax(szAuth));
	if (!szAuth[0])
		return;

	formatex(szKey, charsmax(szKey), "chk_%s", szAuth);
	num_to_str(g_iLastCheckin[id], szVal, charsmax(szVal));
	nvault_set(g_iVaultReward, szKey, szVal);

	formatex(szKey, charsmax(szKey), "play_%s", szAuth);
	num_to_str(GetPlayRemain(id), szVal, charsmax(szVal));
	nvault_set(g_iVaultReward, szKey, szVal);
}

HasCheckedInToday(id) {
	LoadRewardState(id);
	return g_iLastCheckin[id] == TodayYmd();
}

GetPlayRemain(id) {
	LoadRewardState(id);
	new iRemain = g_iPlayRemain[id] - floatround(get_gametime() - g_flPlayStart[id], floatround_floor);
	if (iRemain < 0)
		iRemain = 0;
	return iRemain;
}

FlushPlaytime(id) {
	LoadRewardState(id);
	new Float:flNow = get_gametime();
	new iElapsed = floatround(flNow - g_flPlayStart[id], floatround_floor);
	if (iElapsed < 0)
		iElapsed = 0;
	g_iPlayRemain[id] -= iElapsed;
	g_flPlayStart[id] = flNow;
}

GivePlaytimeRewards(id) {
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return;

	// 余额没读出来之前不要发奖, 否则会按 0 余额写回数据库
	if (!hns_gc_player_ready(id))
		return;

	FlushPlaytime(id);
	if (!g_bRewardLoaded[id])
		return;

	new iNeed = g_iPlaytimeNeed;
	if (iNeed < 60)
		iNeed = 3600;

	new bool:bGave = false;
	while (g_iPlayRemain[id] <= 0) {
		new iBal = hns_gc_add_player(id, g_iPlaytimeBonus);
		g_iPlayRemain[id] += iNeed;
		bGave = true;
		SkinChat(id, print_team_default, "SKIN_CHAT_PLAYTIME_OK", "在线满1小时, 获得 ^3%d^1 GBIC, 余额 ^3%d", g_iPlaytimeBonus, iBal);
	}
	if (bGave)
		SaveRewardState(id);
}

StartPlaytimeTrack(id) {
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return;
	LoadRewardState(id);
	g_flPlayStart[id] = get_gametime();
	remove_task(id + TASK_PLAYTIME);
	set_task(PLAYTIME_TICK, "TaskPlaytimeTick", id + TASK_PLAYTIME, _, _, "b");
}

StopPlaytimeTrack(id, bool:bSave) {
	remove_task(id + TASK_PLAYTIME);
	if (!bSave || !g_bRewardLoaded[id])
		return;
	GivePlaytimeRewards(id);
	SaveRewardState(id);
}

public TaskPlaytimeTick(taskid) {
	new id = taskid - TASK_PLAYTIME;
	if (!is_user_connected(id)) {
		remove_task(taskid);
		return;
	}
	GivePlaytimeRewards(id);
	SaveRewardState(id);
}

DoDailyCheckin(id) {
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return;
	LoadRewardState(id);
	if (!g_bSqlReady || g_hSqlTuple == Empty_Handle) {
		SkinChat(id, print_team_red, "SKIN_CHAT_CHECKIN_ERR", "皮肤库未连接, 今日签到未领取");
		return;
	}
	if (!hns_gc_available()) {
		SkinChat(id, print_team_red, "SKIN_CHAT_CHECKIN_ERR", "金币插件未加载, 今日签到未领取");
		return;
	}
	if (!hns_gc_player_ready(id)) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_WAIT", "GBIC 还在读取, 请稍后再试");
		return;
	}
	if (g_bCheckinPending[id]) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_WAIT", "签到正在处理中, 请稍后再试");
		return;
	}

	new szRawAuth[MAX_AUTHID_LENGTH], szAuth[MAX_AUTHID_LENGTH * 2], szDay[12];
	GetPlayerAuth(id, szRawAuth, charsmax(szRawAuth));
	if (!szRawAuth[0]) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_WAIT", "账号信息还未准备好, 请稍后再试");
		return;
	}
	EscapeSql(szRawAuth, szAuth, charsmax(szAuth));
	new iToday = TodayYmd();
	num_to_str(iToday, szDay, charsmax(szDay));

	g_bCheckinPending[id] = true;
	g_bCheckinLegacyClaim[id] = (g_iLastCheckin[id] == iToday);
	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_CHECKIN_CLAIM, id);
	cData[2] = iToday;
	new iNow = get_systime();
	new szQuery[320];
	if (g_bLocalDb)
		formatex(szQuery, charsmax(szQuery), "INSERT OR IGNORE INTO %s (authid, checkin_date, claimed_at) VALUES ('%s',%s,%d)", CHECKIN_TABLE, szAuth, szDay, iNow);
	else
		formatex(szQuery, charsmax(szQuery), "INSERT IGNORE INTO %s (authid, checkin_date, claimed_at) VALUES ('%s',%s,%d)", CHECKIN_TABLE, szAuth, szDay, iNow);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler", szQuery, cData, sizeof(cData));
}

public CmdCheckin(id) {
	DoDailyCheckin(id);
	return PLUGIN_HANDLED;
}

/* ---- HnsLanguage: /lang 简体/繁体/英语/俄语 ---- */
stock SkinLangUnescape(szText[], iLen) {
	replace_all(szText, iLen, "^^n", "^n");
	replace_all(szText, iLen, "^^1", "^1");
	replace_all(szText, iLen, "^^2", "^2");
	replace_all(szText, iLen, "^^3", "^3");
	replace_all(szText, iLen, "^^4", "^4");
}

stock SkinLang(id, const szKey[], szOut[], iLen, const szFallback[]) {
	szOut[0] = EOS;
	HnsLang_Get(id, szKey, szOut, iLen);
	if ((!szOut[0] || equal(szOut, szKey)) && any:GetLangTransKey(szKey) != -1)
		formatex(szOut, iLen, "%L", id, szKey);
	if (!szOut[0] || equal(szOut, szKey))
		copy(szOut, iLen, szFallback);
	SkinLangUnescape(szOut, iLen);
}
stock SkinLangF(id, const szKey[], const szFallback[], szOut[], iLen, any:...) {
	new szFmt[256];
	SkinLang(id, szKey, szFmt, charsmax(szFmt), szFallback);
	vformat(szOut, iLen, szFmt, 6);
}

stock SkinChat(id, team, const szKey[], const szFallback[], any:...) {
	if (!is_user_connected(id))
		return;
	new szPrefix[32], szFmt[191], szBody[191], szMsg[191];
	SkinLang(id, "SKIN_CHAT_PREFIX", szPrefix, charsmax(szPrefix), "^4[皮肤]^1");
	SkinLang(id, szKey, szFmt, charsmax(szFmt), szFallback);
	vformat(szBody, charsmax(szBody), szFmt, 5);
	formatex(szMsg, charsmax(szMsg), "%s %s", szPrefix, szBody);
	client_print_color(id, team, "%s", szMsg);
}

stock SkinTeamName(id, teamChar, dest[], len) {
	if (teamChar == TEAM_CHAR_T)
		SkinLang(id, "SKIN_TEAM_TT", dest, len, "TT");
	else if (teamChar == TEAM_CHAR_C)
		SkinLang(id, "SKIN_TEAM_CT", dest, len, "CT");
	else
		SkinLang(id, "SKIN_TEAM_ALL", dest, len, "全部");
}

stock SkinTeamShort(id, teamChar, dest[], len) {
	if (teamChar == TEAM_CHAR_T)
		SkinLang(id, "SKIN_TEAM_T", dest, len, "T");
	else if (teamChar == TEAM_CHAR_C)
		SkinLang(id, "SKIN_TEAM_CT", dest, len, "CT");
	else
		SkinLang(id, "SKIN_TEAM_ALL", dest, len, "全部");
}

stock SkinTeamLong(id, teamChar, dest[], len) {
	if (teamChar == TEAM_CHAR_T)
		SkinLang(id, "SKIN_TEAM_T_LONG", dest, len, " T(恐怖分子)");
	else
		SkinLang(id, "SKIN_TEAM_CT_LONG", dest, len, " CT(反恐精英)");
}

stock SkinSqlStatusText(id, dest[], len) {
	if (equal(g_szSqlStatus, "none"))
		SkinLang(id, "SKIN_SQL_NONE", dest, len, "未配置数据库");
	else if (equal(g_szSqlStatus, "fail"))
		SkinLang(id, "SKIN_SQL_FAIL", dest, len, "连接失败");
	else if (equal(g_szSqlStatus, "ok"))
		SkinLang(id, "SKIN_SQL_OK", dest, len, "已连接");
	else if (equal(g_szSqlStatus, "reconnect"))
		SkinLang(id, "SKIN_SQL_RECONNECT", dest, len, "正在重连");
	else if (equal(g_szSqlStatus, "query"))
		SkinLang(id, "SKIN_SQL_QUERY_FAIL", dest, len, "查询失败");
	else
		SkinLang(id, "SKIN_SQL_UNKNOWN", dest, len, "未知");
}

SkinMenuStyle(id, menu) {
	new szBack[32], szNext[32], szExit[32];
	SkinLang(id, "SKIN_MENU_BACK", szBack, charsmax(szBack), "上一页");
	SkinLang(id, "SKIN_MENU_NEXT", szNext, charsmax(szNext), "下一页");
	SkinLang(id, "SKIN_MENU_CLOSE", szExit, charsmax(szExit), "关闭");
	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
	menu_setprop(menu, MPROP_BACKNAME, szBack);
	menu_setprop(menu, MPROP_NEXTNAME, szNext);
	menu_setprop(menu, MPROP_EXITNAME, szExit);
	menu_setprop(menu, MPROP_NUMBER_COLOR, "\r");
	menu_setprop(menu, MPROP_NOCOLORS, 0);
}

FormatShopItem(id, dest[], len, const name[], bool:owned, price, bool:selected = false) {
	if (selected) {
		new szSel[32];
		SkinLang(id, "SKIN_TAG_SELECTED", szSel, charsmax(szSel), "  \r[已选择]");
		formatex(dest, len, "\w%s%s", name, szSel);
	} else if (owned)
		formatex(dest, len, "\w%s", name);
	else
		formatex(dest, len, "\d%s  [%d]", name, price);
}

SkinMenuReturn(id, menu) {
	new szBack[32];
	SkinLang(id, "SKIN_MENU_RETURN", szBack, charsmax(szBack), "返回");
	menu_setprop(menu, MPROP_EXITNAME, szBack);
}

SkinMenuForceExit(id, menu, const szExit[]) {
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_PERPAGE, 0);
	menu_setprop(menu, MPROP_EXIT, MEXIT_FORCE);
	menu_setprop(menu, MPROP_EXITNAME, szExit);
	while (menu_items(menu) < 9)
		menu_addblank2(menu);
}

MarkShopKeep(id) {
	g_flShopKeep[id] = get_gametime() + 0.40;
}

bool:KeepShopMenu(id) {
	return get_gametime() < g_flShopKeep[id];
}

bool:HasSkin(id, const key[]) {
	if (!g_Owned[id])
		return false;
	for (new i = 0; i < ArraySize(g_Owned[id]); i++) {
		new k[SKIN_KEY_MAX];
		ArrayGetString(g_Owned[id], i, k, charsmax(k));
		if (equal(k, key))
			return true;
	}
	return false;
}

// 返回某皮肤的到期时间戳: 0=永久,  >0=租期到期时刻,  -1=未拥有
SkinExpire(id, const key[]) {
	if (!g_OwnedExpire[id])
		return -1;
	new exp;
	if (!TrieGetCell(g_OwnedExpire[id], key, exp))
		return -1;
	return exp;
}

// 该皮肤当前是否仍然有效 (拥有 且 未过期)
bool:IsSkinValid(id, const key[]) {
	if (!HasSkin(id, key))
		return false;
	new exp = SkinExpire(id, key);
	return exp == 0 || exp > get_systime();
}

// 剩余天数 (永久返回 0)
DaysLeft(id, const key[]) {
	new exp = SkinExpire(id, key);
	if (exp <= 0)
		return 0;
	new d = (exp - get_systime()) / 86400;
	return d < 0 ? 0 : d;
}

PoolIndexOf(const key[]) {
	new idx;
	if (TrieGetCell(g_pPoolIndex, key, idx))
		return idx;
	return -1;
}

// 该池内款式本张地图是否已成功预缓存模型 (未预缓存的不能应用, 否则会拉不到模型)
bool:IsPoolPrecached(idx) {
	if (idx < 0 || idx >= g_iPoolSize)
		return false;
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);
	return bool:row[pool_precache];
}

// key 是否本图可用 (存在 且 已预缓存)
bool:IsSkinPrecached(const key[]) {
	new idx = PoolIndexOf(key);
	return idx != -1 && IsPoolPrecached(idx);
}

// 玩家 id 的当前阵营字符 'T' / 'C'
CharOfTeam(team) {
	if (team == TEAM_TERRORIST)
		return TEAM_CHAR_T;
	return TEAM_CHAR_C;
}

bool:IsAllowed(id, idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);
	if (!row[pool_flags][0])
		return true;
	return bool:(get_user_flags(id) & read_flags(row[pool_flags]));
}

KnifeOwnedKey(knife, dest[], len) {
	formatex(dest, len, "knife:%d", knife);
}

bool:IsKnifeOwned(id, knife) {
	// 前 N 把免费: 直接可用, 不需要购买也不需要数据库记录
	if (knife >= 0 && knife < g_iKnifeFree)
		return true;

	new name[MAX_NAME_LENGTH], price;
	KnifeInfo(knife, name, charsmax(name), price);
	// 只有明确标价 0 才免费。没写 PRICE 时 KnifeInfo 会给出默认价, 不能直接送。
	if (price <= 0)
		return true;
	new key[SKIN_KEY_MAX];
	KnifeOwnedKey(knife, key, charsmax(key));
	return IsSkinValid(id, key);
}

// 余额还在从 MySQL 读时, 读到的是 0。这时扣款会把真实余额写成 0。
bool:GoldReady(id) {
	if (hns_gc_player_ready(id))
		return true;
	SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_WAIT", "GBIC 还在读取, 请稍后再试");
	return false;
}

bool:IsKnifeShopItemValid(knife) {
	return knife >= 0 && knife < crxknives_get_knives_num();
}

/* ============================================================
   投掷物皮肤 (烟雾弹 / 闪光弹)
   ============================================================ */
NadeKindChar(kind) {
	return (kind == NADE_KIND_FLASH) ? 'F' : 'S';
}

NadeOwnedKey(const key[], dest[], len) {
	formatex(dest, len, "nade:%s", key);
}

// 玩家当前某类投掷物皮肤的槽 (烟雾='S' / 闪光='F')
NadeCurSlot(id, kind, dest[], len) {
	if (kind == NADE_KIND_FLASH)
		copy(dest, len, g_NadeFlash[id]);
	else
		copy(dest, len, g_NadeSmoke[id]);
}

SetNadeCurSlot(id, kind, const key[]) {
	if (kind == NADE_KIND_FLASH)
		copy(g_NadeFlash[id], charsmax(g_NadeFlash[]), key);
	else
		copy(g_NadeSmoke[id], charsmax(g_NadeSmoke[]), key);
}

// 前 N 个免费 (按配置出现顺序), 其余需要购买
bool:IsNadeFree(idx) {
	return idx >= 0 && idx < g_iNadeFree;
}

bool:IsNadeOwned(id, idx) {
	if (idx < 0 || idx >= g_iNadeSize)
		return false;
	if (IsNadeFree(idx))
		return true;

	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);
	if (row[nade_price] <= 0)
		return true;
	new key[SKIN_KEY_MAX];
	NadeOwnedKey(row[nade_key], key, charsmax(key));
	return IsSkinValid(id, key);
}

NadeFullPath(const model[], dest[], len) {
	if (equali(model, "models/", 7)) {
		copy(dest, len, model);
		return;
	}
	new iLen = strlen(model);
	if (iLen > 4 && equali(model[iLen - 4], ".mdl"))
		formatex(dest, len, "models/%s", model);
	else
		formatex(dest, len, "models/%s.mdl", model);
}

NadeFileName(const path[], dest[], len) {
	new i = strlen(path);
	while (i > 0 && path[i - 1] != '/' && path[i - 1] != 92)
		i--;
	copy(dest, len, path[i]);
}

bool:NadeResolvePath(const model[], dest[], len) {
	new szTry[PLATFORM_MAX_PATH], szFile[64];
	NadeFullPath(model, szTry, charsmax(szTry));
	if (file_exists(szTry)) {
		copy(dest, len, szTry);
		return true;
	}
	NadeFileName(szTry, szFile, charsmax(szFile));
	if (szFile[0]) {
		formatex(szTry, charsmax(szTry), "models/%s", szFile);
		if (file_exists(szTry)) {
			copy(dest, len, szTry);
			return true;
		}
	}
	NadeFullPath(model, dest, len);
	return false;
}

bool:NadeWorldPath(const view[], dest[], len) {
	copy(dest, len, view);
	if (contain(dest, "/v_") != -1)
		replace(dest, len, "/v_", "/w_");
	else if (contain(dest, "v_") != -1)
		replace(dest, len, "v_", "w_");
	else
		return false;
	return dest[0] && !equal(dest, view) && file_exists(dest);
}

bool:NadePlayerPath(const view[], dest[], len) {
	copy(dest, len, view);
	if (contain(dest, "/v_") != -1)
		replace(dest, len, "/v_", "/p_");
	else if (contain(dest, "v_") != -1)
		replace(dest, len, "v_", "p_");
	else
		return false;
	return dest[0] && !equal(dest, view) && file_exists(dest);
}

NadeKindOfWeapon(weapon) {
	if (is_nullent(weapon))
		return -1;
	new WeaponIdType:wid = WeaponIdType:get_member(weapon, m_iId);
	if (wid == WEAPON_SMOKEGRENADE)
		return NADE_KIND_SMOKE;
	if (wid == WEAPON_FLASHBANG)
		return NADE_KIND_FLASH;
	return -1;
}

ApplyNadeViewTo(id, weapon, const szView[]) {
	if (!is_user_connected(id) || !szView[0])
		return;
	set_entvar(id, var_viewmodel, szView);
	if (!is_nullent(weapon)) {
		set_entvar(weapon, var_viewmodel, szView);
		new szP[PLATFORM_MAX_PATH];
		if (NadePlayerPath(szView, szP, charsmax(szP)))
			set_entvar(weapon, var_weaponmodel, szP);
	}
}

bool:SkinMenuBusy(id) {
	if (!is_user_connected(id))
		return false;
	if (task_exists(id + TASK_MENU_SHOP))
		return true;
	new iOld, iNew;
	player_menu_info(id, iOld, iNew);
	return iNew != -1 || iOld > 0;
}

ApplyHeldNadeSkin(id) {
	if (!is_user_alive(id))
		return;
	if (SkinMenuBusy(id)) {
		remove_task(id + TASK_APPLY_NADE);
		set_task(0.20, "TaskApplyHeldNade", id + TASK_APPLY_NADE);
		return;
	}
	new weapon = get_member(id, m_pActiveItem);
	new kind = NadeKindOfWeapon(weapon);
	if (kind < 0)
		return;
	new szPath[PLATFORM_MAX_PATH];
	if (!GetNadeCurrentModel(id, kind, szPath, charsmax(szPath)))
		return;
	ApplyNadeViewTo(id, weapon, szPath);
}

public TaskApplyHeldNade(taskid) {
	ApplyHeldNadeSkin(taskid - TASK_APPLY_NADE);
}

ScheduleHeldNadeApply(id) {
	if (!is_user_connected(id))
		return;
	remove_task(id + TASK_APPLY_NADE);
	set_task(0.05, "TaskApplyHeldNade", id + TASK_APPLY_NADE);
}

public OnNadeDeployPre(const weapon) {
	new kind = NadeKindOfWeapon(weapon);
	if (kind < 0)
		return HC_CONTINUE;
	new id = get_member(weapon, m_pPlayer);
	if (id < 1 || id > MaxClients || !is_user_connected(id))
		return HC_CONTINUE;
	new szPath[PLATFORM_MAX_PATH];
	if (!GetNadeCurrentModel(id, kind, szPath, charsmax(szPath)))
		return HC_CONTINUE;
	SetHookChainArg(2, ATYPE_STRING, szPath);
	new szP[PLATFORM_MAX_PATH];
	if (NadePlayerPath(szPath, szP, charsmax(szP)))
		SetHookChainArg(3, ATYPE_STRING, szP);
	return HC_CONTINUE;
}

public OnNadeDeployPost(const weapon) {
	new kind = NadeKindOfWeapon(weapon);
	if (kind < 0)
		return HC_CONTINUE;
	new id = get_member(weapon, m_pPlayer);
	if (id < 1 || id > MaxClients)
		return HC_CONTINUE;
	ScheduleHeldNadeApply(id);
	return HC_CONTINUE;
}

OpenShopLater(id, which, page = 0, kind = -1) {
	if (!is_user_connected(id))
		return;
	g_iShopMenu[id] = which;
	g_iShopPage[id] = page;
	g_iShopKind[id] = kind;
	MarkShopKeep(id);
	remove_task(id + TASK_MENU_SHOP);
	set_task(0.05, "TaskOpenShop", id + TASK_MENU_SHOP);
}

public TaskOpenShop(taskid) {
	new id = taskid - TASK_MENU_SHOP;
	if (!is_user_connected(id))
		return;
	switch (g_iShopMenu[id]) {
		case SHOP_MENU_SKIN: MenuSkin(id, g_iShopPage[id]);
		case SHOP_MENU_NADE_CAT: MenuNades(id);
		case SHOP_MENU_NADE_KIND: MenuNadeKind(id, g_iShopKind[id], g_iShopPage[id]);
		case SHOP_MENU_KNIFE: MenuKnives(id, g_iShopPage[id]);
	}
}

// 读取 nade_skins.cfg 并预缓存模型: 名字 模型 价格 类型
LoadNadeCfg() {
	if (!g_pNade)
		g_pNade = ArrayCreate(nade_e);
	ArrayClear(g_pNade);
	g_iNadeSize = 0;

	new szCfg[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szCfg, charsmax(szCfg));
	format(szCfg, charsmax(szCfg), "%s/%s", szCfg, NADE_CFG_FILE);
	if (!file_exists(szCfg))
		return;

	new file = fopen(szCfg, "rt");
	if (!file)
		return;

	new szLine[256], szKey[NADE_KEY_MAX], szModel[SKIN_MODEL_MAX], szPrice[16], szKind[16];
	while (!feof(file)) {
		fgets(file, szLine, charsmax(szLine));
		trim(szLine);
		if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
			continue;

		szKey[0] = EOS;
		parse(szLine, szKey, charsmax(szKey), szModel, charsmax(szModel), szPrice, charsmax(szPrice), szKind, charsmax(szKind));
		trim(szKey); trim(szModel); trim(szPrice); trim(szKind);
		if (!szKey[0] || !szModel[0])
			continue;

		new row[nade_e];
		copy(row[nade_key], charsmax(row[nade_key]), szKey);
		copy(row[nade_name], charsmax(row[nade_name]), szKey);
		copy(row[nade_model], charsmax(row[nade_model]), szModel);
		row[nade_price] = str_to_num(szPrice);
		if (row[nade_price] < 0)
			row[nade_price] = 0;
		row[nade_kind] = equali(szKind, "flash") ? NADE_KIND_FLASH : NADE_KIND_SMOKE;

		new szPath[PLATFORM_MAX_PATH], szExtra[PLATFORM_MAX_PATH];
		NadeResolvePath(row[nade_model], szPath, charsmax(szPath));
		precache_model(szPath);
		if (NadeWorldPath(szPath, szExtra, charsmax(szExtra)))
			precache_model(szExtra);
		if (NadePlayerPath(szPath, szExtra, charsmax(szExtra)))
			precache_model(szExtra);

		ArrayPushArray(g_pNade, row, sizeof row);
		g_iNadeSize++;
	}
	fclose(file);
}

// 读取 knife_skins.cfg: 每行 "刀名 价格" (刀名要和 KnifeModels.ini 里的段名一致)
// 只覆盖"商店价格", 不影响 crxknives 引擎自己的刀定义/音效。
// 价格 0 = 免费; 前 g_iKnifeFree 把仍然无条件免费 (见 IsKnifeOwned)。
bool:IsBlankChar(ch) {
	return ch == ' ' || ch == 9;
}

LoadKnifeCfg() {
	if (g_tKnifePrice == Invalid_Trie)
		g_tKnifePrice = TrieCreate();
	else
		TrieClear(g_tKnifePrice);

	new szCfg[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szCfg, charsmax(szCfg));
	format(szCfg, charsmax(szCfg), "%s/%s", szCfg, KNIFE_CFG_FILE);
	if (!file_exists(szCfg))
		return;

	new file = fopen(szCfg, "rt");
	if (!file)
		return;

	new szLine[256], szName[MAX_NAME_LENGTH], szPrice[16];
	while (!feof(file)) {
		fgets(file, szLine, charsmax(szLine));
		trim(szLine);
		if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/' || szLine[0] == '[')
			continue;

		// 价格取最后一个空白分隔的字段, 前面整段当刀名 (允许刀名里带空格)
		new iLen = strlen(szLine);
		new iPos = iLen;
		while (iPos > 0 && IsBlankChar(szLine[iPos - 1]))
			iPos--;
		while (iPos > 0 && !IsBlankChar(szLine[iPos - 1]))
			iPos--;

		copy(szPrice, charsmax(szPrice), szLine[iPos]);
		copy(szName, charsmax(szName), szLine);
		szName[iPos] = EOS;
		trim(szName); trim(szPrice);
		StripQuotes(szName);
		StripQuotes(szPrice);
		if (!szName[0] || !szPrice[0])
			continue;

		new iPrice = str_to_num(szPrice);
		if (iPrice < 0)
			iPrice = 0;
		TrieSetCell(g_tKnifePrice, szName, iPrice);
	}
	fclose(file);
}

NadePoolIndex(const key[], kind = -1) {
	for (new i = 0; i < g_iNadeSize; i++) {
		new row[nade_e];
		ArrayGetArray(g_pNade, i, row, sizeof row);
		if (equali(row[nade_key], key) && (kind < 0 || row[nade_kind] == kind))
			return i;
	}
	return -1;
}

// 找到当前玩家某类投掷物应当使用的模型路径; 返回 false 表示用默认
bool:GetNadeCurrentModel(id, kind, dest[], len) {
	dest[0] = EOS;
	new key[NADE_KEY_MAX];
	NadeCurSlot(id, kind, key, charsmax(key));
	if (!key[0])
		return false;
	new idx = NadePoolIndex(key, kind);
	if (idx == -1)
		return false;
	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);
	NadeResolvePath(row[nade_model], dest, len);
	return dest[0] != EOS;
}

DoBuyNade(id, idx) {
	if (idx < 0 || idx >= g_iNadeSize)
		return;

	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);

	new key[SKIN_KEY_MAX];
	NadeOwnedKey(row[nade_key], key, charsmax(key));

	new exp = SkinExpire(id, key);
	if (exp == 0) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_PERM", "你已永久拥有该投掷物皮肤");
		return;
	}
	if (exp > 0 && exp > get_systime()) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_RENT", "你已拥有该投掷物皮肤(剩 ^3%d^1 天), 无需重复购买", DaysLeft(id, key));
		return;
	}
	if (g_hSqlTuple == Empty_Handle) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_BUY", "MySQL 未就绪, 暂不能购买");
		return;
	}
	if (!GoldReady(id))
		return;

	new price = row[nade_price];
	new iGold = hns_gc_get_player(id);
	if (iGold < price) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_NEED", "金币不足! 需要 %d, 你有 %d", price, iGold);
		return;
	}

	hns_gc_set_player(id, iGold - price);
	if (!g_Owned[id])
		g_Owned[id] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[id])
		g_OwnedExpire[id] = TrieCreate();
	if (!HasSkin(id, key))
		ArrayPushString(g_Owned[id], key);
	TrieSetCell(g_OwnedExpire[id], key, 0); // 投掷物皮肤永久拥有

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_InsertOwned(id, authid, key, 0, price);

	SelectNade(id, idx);
	SkinChat(id, print_team_blue, "SKIN_CHAT_BUY_PERM", "投掷物皮肤购买成功! 剩余金币 %d", iGold - price);
}

SelectNade(id, idx) {
	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);

	SetNadeCurSlot(id, row[nade_kind], row[nade_key]);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_SaveCurrent(id, authid, row[nade_key], NadeKindChar(row[nade_kind]));

	SkinChat(id, print_team_blue, "SKIN_CHAT_SELECTED", "你已选用投掷物皮肤: ^3%s", row[nade_key]);
}

MenuNades(id) {
	g_iNadeKindPage[id] = -1;
	// 分类选择页: 先进这里, 再选 烟雾弹 / 闪光弹
	new szTitle[160], szItem[160];
	SkinLangF(id, "SKIN_NADE_TITLE", "\y投掷物皮肤^n\w金币: \y%d  \w免费名额: \y%d",
		szTitle, charsmax(szTitle), hns_gc_get_player(id), g_iNadeFree);
	new menu = menu_create(szTitle, "NadeHandler");

	new szCat[96];
	SkinLangF(id, "SKIN_NADE_CAT_SMOKE", "烟雾弹皮肤  [%d款]", szCat, charsmax(szCat), CountNadesOfKind(NADE_KIND_SMOKE));
	formatex(szItem, charsmax(szItem), "\y%s", szCat);
	menu_additem(menu, szItem, "catS");
	SkinLangF(id, "SKIN_NADE_CAT_FLASH", "闪光弹皮肤  [%d款]", szCat, charsmax(szCat), CountNadesOfKind(NADE_KIND_FLASH));
	formatex(szItem, charsmax(szItem), "\y%s", szCat);
	menu_additem(menu, szItem, "catF");

	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

// 某一类投掷物皮肤的数量 (0=烟雾 1=闪光)
CountNadesOfKind(kind) {
	new n;
	for (new i = 0; i < g_iNadeSize; i++) {
		new row[nade_e];
		ArrayGetArray(g_pNade, i, row, sizeof row);
		if (row[nade_kind] == kind)
			n++;
	}
	return n;
}

// 单类投掷物皮肤列表 (只显示 kind 这一类), -1 = 全部分类
MenuNadeKind(id, kind, page = 0) {
	g_iNadeKindPage[id] = kind;
	g_iNadePage[id] = page;
	new szTitle[160], szItem[160], szInfo[12];
	new szKindName[16];
	SkinLang(id, kind == NADE_KIND_FLASH ? "SKIN_NADE_KIND_FLASH" : "SKIN_NADE_KIND_SMOKE",
		szKindName, charsmax(szKindName), kind == NADE_KIND_FLASH ? "闪光弹" : "烟雾弹");
	SkinLangF(id, "SKIN_NADE_KIND_TITLE", "\y%s皮肤^n\w金币: \y%d  \w免费名额: \y%d",
		szTitle, charsmax(szTitle), szKindName, hns_gc_get_player(id), g_iNadeFree);
	new menu = menu_create(szTitle, "NadeHandler");

	new added, curNade[SKIN_KEY_MAX];
	NadeCurSlot(id, kind, curNade, charsmax(curNade));
	for (new i = 0; i < g_iNadeSize; i++) {
		new row[nade_e];
		ArrayGetArray(g_pNade, i, row, sizeof row);
		if (row[nade_kind] != kind)
			continue;

		FormatShopItem(id, szItem, charsmax(szItem), row[nade_key], IsNadeOwned(id, i), row[nade_price], equal(curNade, row[nade_key]) != 0);
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szItem, szInfo);
		added++;
	}

	if (!added)
		menu_additem(menu, "\d(该分类暂无投掷物皮肤)", "none");

	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, page);
}

MenuConfirmNadeBuy(id, idx, kind = -1, page = 0) {
	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);

	g_iNadePage[id] = page;
	if (row[nade_price] == 0 || IsNadeFree(idx)) {
		DoBuyNade(id, idx);
		OpenShopLater(id, SHOP_MENU_NADE_KIND, page, kind >= 0 ? kind : row[nade_kind]);
		return;
	}

	new szTitle[160], szItem[96], szInfo[12], szRent[32];
	SkinLang(id, "SKIN_PERM", szRent, charsmax(szRent), "永久");
	SkinLangF(id, "SKIN_NADE_BUY_TITLE", "\y确认购买投掷物皮肤^n\w名称: %s^n\w价格: \y%d 金币  \w租期: %s",
		szTitle, charsmax(szTitle), row[nade_key], row[nade_price], szRent);
	new menu = menu_create(szTitle, "NadeConfirmHandler");
	num_to_str(idx, szInfo, charsmax(szInfo));
	SkinLangF(id, "SKIN_BUY_OK", "确认购买  \r-%d", szItem, charsmax(szItem), row[nade_price]);
	menu_additem(menu, szItem, szInfo);
	SkinLang(id, "SKIN_CANCEL", szItem, charsmax(szItem), "取消");
	menu_additem(menu, szItem, "cancel");
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0);
}

RefreshNadeKindNames(id, menu, kind) {
	new szItem[160], curNade[SKIN_KEY_MAX], szInfo[12], access, callback, name[2];
	NadeCurSlot(id, kind, curNade, charsmax(curNade));
	new count = menu_items(menu);
	for (new i = 0; i < count; i++) {
		menu_item_getinfo(menu, i, access, szInfo, charsmax(szInfo), name, charsmax(name), callback);
		if (!szInfo[0] || equal(szInfo, "none") || equal(szInfo, "catS") || equal(szInfo, "catF"))
			continue;
		new idx = str_to_num(szInfo);
		if (idx < 0 || idx >= g_iNadeSize)
			continue;
		new row[nade_e];
		ArrayGetArray(g_pNade, idx, row, sizeof row);
		FormatShopItem(id, szItem, charsmax(szItem), row[nade_key], IsNadeOwned(id, idx), row[nade_price], equal(curNade, row[nade_key]) != 0);
		menu_item_setname(menu, i, szItem);
	}
}

public NadeHandler(id, menu, item) {
	new kind = g_iNadeKindPage[id];
	new page = g_iNadePage[id];
	if (item == MENU_EXIT) {
		if (KeepShopMenu(id) && (kind == NADE_KIND_SMOKE || kind == NADE_KIND_FLASH)) {
			menu_display(id, menu, page);
			return PLUGIN_HANDLED;
		}
		menu_destroy(menu);
		if (kind == NADE_KIND_SMOKE || kind == NADE_KIND_FLASH)
			OpenShopLater(id, SHOP_MENU_NADE_CAT);
		else {
			OpenShopLater(id, SHOP_MENU_SKIN);
			ScheduleHeldNadeApply(id);
		}
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	page = item / SKIN_PER_PAGE;
	g_iNadePage[id] = page;

	if (equal(szInfo, "catS")) {
		menu_destroy(menu);
		OpenShopLater(id, SHOP_MENU_NADE_KIND, 0, NADE_KIND_SMOKE);
		return PLUGIN_HANDLED;
	}
	if (equal(szInfo, "catF")) {
		menu_destroy(menu);
		OpenShopLater(id, SHOP_MENU_NADE_KIND, 0, NADE_KIND_FLASH);
		return PLUGIN_HANDLED;
	}

	if (equal(szInfo, "none")) {
		MarkShopKeep(id);
		menu_display(id, menu, 0);
		return PLUGIN_HANDLED;
	}
	new idx = str_to_num(szInfo);
	if (idx >= 0 && idx < g_iNadeSize) {
		if (IsNadeOwned(id, idx)) {
			SelectNade(id, idx);
			MarkShopKeep(id);
			RefreshNadeKindNames(id, menu, kind);
			menu_display(id, menu, page);
		} else {
			menu_destroy(menu);
			MenuConfirmNadeBuy(id, idx, kind, page);
		}
	} else {
		MarkShopKeep(id);
		menu_display(id, menu, page);
	}
	return PLUGIN_HANDLED;
}

public NadeConfirmHandler(id, menu, item) {
	new kind = g_iNadeKindPage[id];
	if (item == MENU_EXIT) {
		if (KeepShopMenu(id)) {
			menu_display(id, menu, 0);
			return PLUGIN_HANDLED;
		}
		menu_destroy(menu);
		OpenShopLater(id, SHOP_MENU_NADE_KIND, g_iNadePage[id], kind);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (!equal(szInfo, "cancel"))
		DoBuyNade(id, str_to_num(szInfo));
	OpenShopLater(id, SHOP_MENU_NADE_KIND, g_iNadePage[id], kind);
	return PLUGIN_HANDLED;
}

public crxknives_attempt_change(id, knife) {
	if (!IsKnifeShopItemValid(knife))
		return PLUGIN_HANDLED;
	if (!IsKnifeOwned(id, knife)) {
		new name[MAX_NAME_LENGTH], price;
		KnifeInfo(knife, name, charsmax(name), price);
		SkinChat(id, print_team_red, "SKIN_CHAT_KNIFE_NEED", "刀皮 ^3%s^1 尚未购买", name);
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}

public crxknives_knife_updated(id, knife, bool:onconnect) {
	if (!is_user_connected(id) || g_bApplyingKnife[id])
		return;
	if (!g_bOwnedLoaded[id])
		return;

	new saved = g_iCurKnife[id];
	if (saved > 0 && IsKnifeShopItemValid(saved) && IsKnifeOwned(id, saved)) {
		if (knife != saved)
			ForceSelectKnife(id, saved);
		return;
	}

	if (!IsKnifeShopItemValid(knife) || !IsKnifeOwned(id, knife)) {
		if (knife != 0)
			ForceSelectKnife(id, 0);
	}
}

ResetKnifeToDefault(id) {
	if (!is_user_connected(id))
		return;

	g_iCurKnife[id] = 0;
	ForceSelectKnife(id, 0);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	if (authid[0])
		Db_SaveCurrent(id, authid, "", 'K');
}

MenuClearSkins(id) {
	if (!is_user_connected(id))
		return;

	new szTitle[96], szItem[64];
	SkinLang(id, "SKIN_CLEAR_TITLE", szTitle, charsmax(szTitle), "\y一键清除皮肤?");
	new menu = menu_create(szTitle, "ClearSkinHandler");
	SkinLang(id, "SKIN_CLEAR_OK", szItem, charsmax(szItem), "确认清除人物皮肤和刀皮");
	menu_additem(menu, szItem, "yes");
	SkinLang(id, "SKIN_CANCEL", szItem, charsmax(szItem), "取消");
	menu_additem(menu, szItem, "cancel");
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0);
}

public ClearSkinHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}

	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);

	if (equal(szInfo, "yes")) {
		new removed = ClearAllSkinsFrom(id);
		SkinChat(id, print_team_default, "SKIN_CHAT_SELF_CLEARED", "已清除自己的皮肤和刀皮 (%d款)", removed);
	}

	MenuSkin(id);
	return PLUGIN_HANDLED;
}

SelectKnife(id, knife) {
	if (!IsKnifeShopItemValid(knife) || !IsKnifeOwned(id, knife))
		return;

	g_iCurKnife[id] = knife;
	ForceSelectKnife(id, knife);

	new authid[MAX_AUTHID_LENGTH], szName[MAX_NAME_LENGTH], price;
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_SaveKnifeCurrent(id, authid, knife);
	KnifeInfo(knife, szName, charsmax(szName), price);
	SkinChat(id, print_team_blue, "SKIN_CHAT_KNIFE_SELECTED", "你已选用刀皮: ^3%s", szName);
	ScheduleKnifeReapply(id);
}

ForceSelectKnife(id, knife) {
	if (!is_user_connected(id))
		return;
	g_bApplyingKnife[id] = true;
	crxknives_select_knife(id, knife);
	g_bApplyingKnife[id] = false;
}

ScheduleKnifeReapply(id) {
	if (!is_user_connected(id))
		return;
	remove_task(id + TASK_REAPPLY_KNIFE);
	g_iKnifeRetry[id] = 0;
	set_task(1.0, "TaskReapplyKnife", id + TASK_REAPPLY_KNIFE);
}

public TaskReapplyKnife(taskid) {
	new id = taskid - TASK_REAPPLY_KNIFE;
	ReapplyKnife(id);
	if (!is_user_connected(id))
		return;
	g_iKnifeRetry[id]++;
	if (g_iKnifeRetry[id] < 5)
		set_task(1.2, "TaskReapplyKnife", taskid);
}

public OnPlayerSpawnPost(id) {
	if (is_user_alive(id)) {
		RefreshPlayerSkin(id);
		ReapplyKnife(id);
		ScheduleHeldNadeApply(id);
	}
}

ReapplyKnife(id) {
	if (!g_bOwnedLoaded[id] || !is_user_connected(id))
		return;

	new knife = g_iCurKnife[id];
	// 没选过、或选的是没买的刀: 拉回默认刀。crxknives 会自己套上上次的刀, 这里要清掉。
	if (knife <= 0 || !IsKnifeShopItemValid(knife) || !IsKnifeOwned(id, knife)) {
		g_iCurKnife[id] = 0;
		if (crxknives_get_user_knife(id) != 0)
			ForceSelectKnife(id, 0);
		return;
	}
	if (crxknives_get_user_knife(id) != knife)
		ForceSelectKnife(id, knife);
}

public BrowseHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuCharShop(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	new page = item / SKIN_PER_PAGE;
	menu_destroy(menu);
	if (!equal(szInfo, "none"))
		OnSkinChosen(id, str_to_num(szInfo), page);
	else
		MenuBrowseSkins(id, g_iBrowseTeam[id], page);
	return PLUGIN_HANDLED;
}

public GoldHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (equal(szInfo, "up"))
		MenuUpgrade(id);
	else
		MenuGold(id);
	return PLUGIN_HANDLED;
}

public SmokeColorHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	new page = item / SKIN_PER_PAGE;
	menu_destroy(menu);
	if (!SkinSmokeNadeAvailable()) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SMOKE_OFF", "Smoke color plugin is not loaded");
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new idx = str_to_num(szInfo);
	hns_smokenade_set_color(id, idx);
	new szName[32];
	SkinGetSmokeColorNameByIdx(id, idx, szName, charsmax(szName));
	SkinChat(id, print_team_blue, "SKIN_CHAT_SMOKE_SET", "Smoke color set to ^3%s^1, synced across servers", szName);
	MenuSmokeColor(id, page);
	return PLUGIN_HANDLED;
}

public SqlMenuHandler(id, menu, item) {
	if (!IsSkinSqlAdmin(id)) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (equal(szInfo, "ping"))
		SqlPing(id);
	else if (equal(szInfo, "count"))
		SqlCountMine(id);
	else if (equal(szInfo, "sync")) {
		DbSyncCatalog();
		new szStatus[64];
		SkinSqlStatusText(id, szStatus, charsmax(szStatus));
		SkinChat(id, print_team_default, "SKIN_CHAT_SQL_SYNCED", "已同步皮肤目录  状态: %s", szStatus);
		MenuSqlDebug(id);
	} else if (equal(szInfo, "reload"))
		SqlReload(id);
	else
		MenuSqlDebug(id);
	return PLUGIN_HANDLED;
}

public ConfirmHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuBrowseSkins(id, g_iBrowseTeam[id], g_iBrowsePage[id]);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (str_to_num(szInfo) >= 0 && !equal(szInfo, "cancel"))
		DoBuy(id, str_to_num(szInfo));
	MenuBrowseSkins(id, g_iBrowseTeam[id], g_iBrowsePage[id]);
	return PLUGIN_HANDLED;
}

public UpgradeHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuGold(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (!equal(szInfo, "none"))
		MenuConfirmUpgrade(id, str_to_num(szInfo));
	else
		MenuGold(id);
	return PLUGIN_HANDLED;
}

public UpgradeConfirmHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuUpgrade(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (str_to_num(szInfo) >= 0 && !equal(szInfo, "cancel"))
		DoUpgrade(id, str_to_num(szInfo));
	else
		MenuUpgrade(id);
	return PLUGIN_HANDLED;
}

public AdminHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	switch (str_to_num(szInfo)) {
		case 1: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			g_pendingGiveTeam[id] = 0;
			MenuPickPlayer("give", id);
		}
		case 2: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			g_pendingGiveTeam[id] = 0;
			MenuPickPlayer("all", id);
		}
		case 3: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有移除皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			MenuPickPlayer("remove", id);
		}
		case 4: MenuPoolList(id);
		case 5: MenuPickPlayer("view", id);
		case 6: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			MenuPickPlayer("knives", id);
		}
		case 7: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			MenuPickPlayer("nades", id);
		}
		case 8: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有移除皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			MenuPickPlayer("clear", id);
		}
		case 9: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			PromptSteamGrant(id, false);
		}
		case 10: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有移除皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			PromptSteamGrant(id, true);
		}
		case 11: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有移除皮肤权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			PromptSteamClear(id);
		}
		case 12: {
			if (!IsSkinOwner(id)) {
				SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放权限");
				MenuAdmin(id);
				return PLUGIN_HANDLED;
			}
			PromptGbicGrant(id);
		}
	}
	return PLUGIN_HANDLED;
}

public PoolListHandler(id, menu, item) {
	menu_destroy(menu);
	if (item == MENU_EXIT)
		MenuAdmin(id);
	return PLUGIN_HANDLED;
}

public PickPlayerHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (equal(szInfo, "none")) {
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	new target = str_to_num(szInfo);
	if (!is_user_connected(target)) {
		SkinChat(id, print_team_red, "SKIN_CHAT_TARGET_GONE", "目标玩家已离开");
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	if (!CanSkinTarget(id, target)) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "管理员只能操作自己的皮肤");
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	if (g_pendingMode[id][0] == 'v')
		MenuViewOwned(id, target);
	else if (g_pendingMode[id][0] == 'g')
		MenuGiveSkin(id, target);
	else if (g_pendingMode[id][0] == 'a') {
		new given = GiveAllSkinsTo(target, 0);
		SkinChat(id, print_team_default, "SKIN_CHAT_GIVE_ALL", "已向 %n 发放全部皮肤 (%d款)", target, given);
		MenuAdmin(id);
	} else if (g_pendingMode[id][0] == 'k') {
		new given = GiveAllKnivesTo(target);
		SkinChat(id, print_team_default, "SKIN_CHAT_GIVE_ALL_KNIFE", "已向 %n 发放全部刀皮 (%d款)", target, given);
		MenuAdmin(id);
	} else if (g_pendingMode[id][0] == 'n') {
		new given = GiveAllNadesTo(target);
		SkinChat(id, print_team_default, "SKIN_CHAT_GIVE_ALL_NADE", "已向 %n 发放全部投掷物皮肤 (%d款)", target, given);
		MenuAdmin(id);
	} else if (g_pendingMode[id][0] == 'c') {
		new removed = ClearAllSkinsFrom(target);
		SkinChat(id, print_team_default, "SKIN_CHAT_CLEARED", "已清除 %n 的全部皮肤 (%d款)", target, removed);
		MenuAdmin(id);
	} else
		MenuRemoveSkin(id, target);
	return PLUGIN_HANDLED;
}

GiveSkinTo(target, idx, bool:bSilent = false) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	if (!g_Owned[target])
		g_Owned[target] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[target])
		g_OwnedExpire[target] = TrieCreate();

	// 已拥有则直接升级为永久, 未拥有则新增
	if (!HasSkin(target, row[pool_key]))
		ArrayPushString(g_Owned[target], row[pool_key]);
	TrieSetCell(g_OwnedExpire[target], row[pool_key], 0);  // 管理员发放 = 永久

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(target, authid, charsmax(authid));
	Db_InsertOwned(target, authid, row[pool_key], 0);

	// 该阵营还没选用时, 发放即写入当前槽, 换图后才能从 cpm_player_current 还原
	new cur[SKIN_KEY_MAX];
	CurSlot(target, cur, charsmax(cur), row[pool_team]);
	if (!cur[0] || equal(cur, row[pool_key])) {
		if (row[pool_team] == TEAM_CHAR_T)
			copy(g_CurT[target], charsmax(g_CurT[]), row[pool_key]);
		else
			copy(g_CurC[target], charsmax(g_CurC[]), row[pool_key]);
		Db_SaveCurrent(target, authid, row[pool_key], row[pool_team]);
		if (is_user_connected(target) && CharOfTeam(get_member(target, m_iTeam)) == row[pool_team] && row[pool_precache])
			custom_player_models_set(target, row[pool_key]);
	}

	if (bSilent)
		return;

	if (g_pendingAdmin[target] && is_user_connected(g_pendingAdmin[target]))
		SkinChat(g_pendingAdmin[target], print_team_default, "SKIN_CHAT_GIVE_ADMIN", "已向 %n 发放永久皮肤 ^3%s", target, row[pool_key]);
	if (is_user_connected(target))
		SkinChat(target, print_team_default, "SKIN_CHAT_GIVE_PLAYER", "管理员为你发放了永久皮肤 ^3%s", row[pool_key]);
}

GiveAllSkinsTo(target, teamChar) {
	new given;
	for (new i = 0; i < g_iPoolSize; i++) {
		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		if (teamChar && row[pool_team] != teamChar)
			continue;
		GiveSkinTo(target, i, true);
		given++;
	}
	return given;
}

// 管理员给玩家发放单把刀皮 (永久)
GiveKnifeTo(target, knife) {
	if (!IsKnifeShopItemValid(knife))
		return;
	new key[SKIN_KEY_MAX];
	KnifeOwnedKey(knife, key, charsmax(key));
	if (HasSkin(target, key))
		return;

	if (!g_Owned[target])
		g_Owned[target] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[target])
		g_OwnedExpire[target] = TrieCreate();

	ArrayPushString(g_Owned[target], key);
	TrieSetCell(g_OwnedExpire[target], key, 0);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(target, authid, charsmax(authid));
	Db_InsertOwned(target, authid, key, 0);
}

// 管理员给玩家发放单个投掷物皮肤 (永久)
GiveNadeTo(target, idx) {
	if (idx < 0 || idx >= g_iNadeSize)
		return;
	new row[nade_e];
	ArrayGetArray(g_pNade, idx, row, sizeof row);
	new key[SKIN_KEY_MAX];
	NadeOwnedKey(row[nade_key], key, charsmax(key));
	if (HasSkin(target, key))
		return;

	if (!g_Owned[target])
		g_Owned[target] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[target])
		g_OwnedExpire[target] = TrieCreate();

	ArrayPushString(g_Owned[target], key);
	TrieSetCell(g_OwnedExpire[target], key, 0);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(target, authid, charsmax(authid));
	Db_InsertOwned(target, authid, key, 0);
}

// 管理员给玩家发放全部刀皮 (永久)
GiveAllKnivesTo(target) {
	new given, key[SKIN_KEY_MAX];
	for (new knife = 0; knife < crxknives_get_knives_num(); knife++) {
		KnifeOwnedKey(knife, key, charsmax(key));
		if (HasSkin(target, key))
			continue;

		if (!g_Owned[target])
			g_Owned[target] = ArrayCreate(SKIN_KEY_MAX);
		if (!g_OwnedExpire[target])
			g_OwnedExpire[target] = TrieCreate();

		ArrayPushString(g_Owned[target], key);
		TrieSetCell(g_OwnedExpire[target], key, 0);

		new authid[MAX_AUTHID_LENGTH];
		GetPlayerAuth(target, authid, charsmax(authid));
		Db_InsertOwned(target, authid, key, 0);
		given++;
	}
	return given;
}

// 管理员给玩家发放全部投掷物皮肤 (永久)
GiveAllNadesTo(target) {
	new given, key[SKIN_KEY_MAX];
	for (new i = 0; i < g_iNadeSize; i++) {
		new row[nade_e];
		ArrayGetArray(g_pNade, i, row, sizeof row);
		NadeOwnedKey(row[nade_key], key, charsmax(key));
		if (HasSkin(target, key))
			continue;

		if (!g_Owned[target])
			g_Owned[target] = ArrayCreate(SKIN_KEY_MAX);
		if (!g_OwnedExpire[target])
			g_OwnedExpire[target] = TrieCreate();

		ArrayPushString(g_Owned[target], key);
		TrieSetCell(g_OwnedExpire[target], key, 0);

		new authid[MAX_AUTHID_LENGTH];
		GetPlayerAuth(target, authid, charsmax(authid));
		Db_InsertOwned(target, authid, key, 0);
		given++;
	}
	return given;
}

ClearAllSkinsFrom(target) {
	if (!is_user_connected(target))
		return 0;
	new authid[MAX_AUTHID_LENGTH], note[96];
	GetPlayerAuth(target, authid, charsmax(authid));
	if (!authid[0])
		return 0;
	// 按账号把 MySQL 里的拥有和当前选用整表删掉, 不依赖内存里是否已经载入
	new n = ExecSteamClear(authid, 0, note, charsmax(note), false);
	return n < 0 ? 0 : n;
}

RemoveSkinFrom(target, const key[], bool:silent = false) {
	if (!g_Owned[target])
		return;

	new count = ArraySize(g_Owned[target]);
	for (new i = 0; i < count; i++) {
		new k[SKIN_KEY_MAX];
		ArrayGetString(g_Owned[target], i, k, charsmax(k));
		if (equal(k, key)) {
			ArrayDeleteItem(g_Owned[target], i);
			break;
		}
	}
	if (g_OwnedExpire[target])
		TrieDeleteKey(g_OwnedExpire[target], key);

	// 若移除的是当前阵营正在用的, 重置对应槽
	new idx = PoolIndexOf(key);
	if (idx != -1) {
		new row[pool_e];
		ArrayGetArray(g_pPool, idx, row, sizeof row);
		new teamChar = row[pool_team];
		new cur[SKIN_KEY_MAX];
		CurSlot(target, cur, charsmax(cur), teamChar);
		if (cur[0] && equal(cur, key)) {
			// 清掉该营地槽
			if (teamChar == TEAM_CHAR_T)
				g_CurT[target][0] = EOS;
			else
				g_CurC[target][0] = EOS;
			ApplyCurrentSkin(target);
		}
	}

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(target, authid, charsmax(authid));
	Db_RemoveOwned(target, authid, key);

	if (g_pendingAdmin[target] && is_user_connected(g_pendingAdmin[target]))
		SkinChat(g_pendingAdmin[target], print_team_default, "SKIN_CHAT_REMOVED", "已移除 %n 的皮肤 ^3%s", target, key);
}

/* ============================================================
   菜单构建 (非 public, 直接调用)
   ============================================================ */
CountTeamSkins(teamChar) {
	new n;
	for (new i = 0; i < g_iPoolSize; i++) {
		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		if (row[pool_team] == teamChar)
			n++;
	}
	return n;
}

CountKnifeSkins() {
	return crxknives_get_knives_num();
}

CountNadeSkins() {
	return g_iNadeSize;
}

MenuSkin(id, page = 0) {
	if (!is_user_connected(id))
		return;

	new iGold = hns_gc_get_player(id);
	new iCt = CountTeamSkins(TEAM_CHAR_C);
	new iTt = CountTeamSkins(TEAM_CHAR_T);
	new iChar = iCt + iTt;
	new iKnife = CountKnifeSkins();
	new iNade = CountNadeSkins();
	new szTitle[160], szItem[96], szColor[32];
	SkinGetSmokeColorName(id, szColor, charsmax(szColor));
	SkinLangF(id, "SKIN_MENU_TITLE", "\y皮肤商店^n\w金币: \y%d",
		szTitle, charsmax(szTitle), iGold);
	new menu = menu_create(szTitle, "SkinHandler");

	SkinLangF(id, "SKIN_MENU_CHAR", "人物皮肤  \r[%d]", szItem, charsmax(szItem), iChar);
	menu_additem(menu, szItem, "char");
	SkinLangF(id, "SKIN_MENU_KNIFE", "刀皮模型  \r[%d]", szItem, charsmax(szItem), iKnife);
	menu_additem(menu, szItem, "knife");
	SkinLangF(id, "SKIN_MENU_NADE", "投掷物模型  \r[%d]", szItem, charsmax(szItem), iNade);
	menu_additem(menu, szItem, "nade");
	menu_addblank(menu, 0);
	SkinLangF(id, "SKIN_MENU_GOLD", "GBIC点查询  \r[%d]", szItem, charsmax(szItem), iGold);
	menu_additem(menu, szItem, "gold");
	SkinLang(id, "SKIN_MENU_BUY", szItem, charsmax(szItem), "购买点数");
	SkinLangF(id, "SKIN_MENU_SMOKE", "Smoke color  \r[%s]", szItem, charsmax(szItem), szColor);
	menu_additem(menu, szItem, "smoke");
	menu_addblank(menu, 0);
	if (CanGrantOnlineGbic(id)) {
		SkinLang(id, "SKIN_MENU_GBIC_ONLINE", szItem, charsmax(szItem), "\r在线发放GBIC点");
		menu_additem(menu, szItem, "ogbic");
	}
	SkinLang(id, "SKIN_MENU_SQL", szItem, charsmax(szItem), "\yMySQL链接");
	menu_additem(menu, szItem, "sql");
	SkinLang(id, "SKIN_MENU_ADMIN", szItem, charsmax(szItem), "\r管理设置");
	menu_additem(menu, szItem, "admin");

	new szExit[32];
	SkinLang(id, "SKIN_MENU_CLOSE", szExit, charsmax(szExit), "关闭");
	SkinMenuForceExit(id, menu, szExit);
	menu_display(id, menu, 0);
}

MenuCharShop(id) {
	new szTitle[128], szItem[96];
	new iCt = CountTeamSkins(TEAM_CHAR_C);
	new iTt = CountTeamSkins(TEAM_CHAR_T);
	SkinLangF(id, "SKIN_CHAR_TITLE", "\y人物皮肤商店  \r[%d]",
		szTitle, charsmax(szTitle), iCt + iTt);
	new menu = menu_create(szTitle, "CharShopHandler");
	SkinLangF(id, "SKIN_MENU_CT", "CT皮肤  \r[%d]", szItem, charsmax(szItem), iCt);
	menu_additem(menu, szItem, "ct");
	SkinLangF(id, "SKIN_MENU_TT", "TT皮肤  \r[%d]", szItem, charsmax(szItem), iTt);
	menu_additem(menu, szItem, "tt");
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuBrowseSkins(id, teamChar, page = 0) {
	if (!is_user_connected(id))
		return;

	g_iBrowseTeam[id] = teamChar;
	g_iBrowsePage[id] = page;

	new szTeam[32], szNone[32], szTitle[160];
	SkinTeamName(id, teamChar, szTeam, charsmax(szTeam));
	SkinLang(id, "SKIN_NONE", szNone, charsmax(szNone), "无");
	new cur[SKIN_KEY_MAX];
	CurSlot(id, cur, charsmax(cur), teamChar);
	SkinLangF(id, "SKIN_BROWSE_TITLE", "\y%s皮肤^n\w金币: \y%d  \w当前: \y%s",
		szTitle, charsmax(szTitle), szTeam, hns_gc_get_player(id), cur[0] ? cur : szNone);
	new menu = menu_create(szTitle, "BrowseHandler");

	new szInfo[12], szTxt[160], added;
	for (new i = 0; i < g_iPoolSize; i++) {
		if (!IsAllowed(id, i))
			continue;

		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		if (row[pool_team] != teamChar)
			continue;

		FormatShopItem(id, szTxt, charsmax(szTxt), row[pool_key], IsSkinValid(id, row[pool_key]), row[pool_price], equal(cur, row[pool_key]) != 0);
		if (!row[pool_precache])
			format(szTxt, charsmax(szTxt), "%s  \r[当前不可用]", szTxt);

		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szTxt, szInfo);
		added++;
	}

	if (!added) {
		SkinLang(id, "SKIN_BROWSE_EMPTY", szTxt, charsmax(szTxt), "\d(当前阵营没有可用皮肤)");
		menu_additem(menu, szTxt, "none");
	}

	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, page);
}

MenuBuyGold(id) {
	new szTitle[64], szItem[160];
	SkinLang(id, "SKIN_BUY_GOLD_TITLE", szTitle, charsmax(szTitle), "\y购买点数");
	new menu = menu_create(szTitle, "BuyGoldHandler");
	if (g_szBuyGoldText[0])
		copy(szItem, charsmax(szItem), g_szBuyGoldText);
	else
		SkinLang(id, "SKIN_BUY_GOLD_TEXT", szItem, charsmax(szItem), "请联系管理员购买 GBIC 点数");
	menu_additem(menu, szItem, "info");
	if (g_szBuyGoldUrl[0]) {
		SkinLang(id, "SKIN_BUY_GOLD_OPEN", szItem, charsmax(szItem), "打开购买页面");
		menu_additem(menu, szItem, "open");
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuGold(id) {
	new iGold = hns_gc_get_player(id);
	new szTitle[192], szItem[96];
	new iRemain = GetPlayRemain(id);
	if (iRemain < 0)
		iRemain = 0;
	new iMin = iRemain / 60;
	new iSec = iRemain % 60;
	SkinLangF(id, "SKIN_GOLD_TITLE", "\yGBIC点查询^n ^n\w余额  \r[%d]^n\w租期  \y[%d天]^n\w升级永久  \y[%d]^n\w在线奖励  \y[%d分%d秒] \w后 +%d^n ",
		szTitle, charsmax(szTitle), iGold, g_iRentDays, g_iUpgradePrice, iMin, iSec, g_iPlaytimeBonus);
	new menu = menu_create(szTitle, "GoldHandler");
	SkinLangF(id, "SKIN_GOLD_UP", "升级已购皮肤为永久  \r[%d]", szItem, charsmax(szItem), g_iUpgradePrice);
	menu_additem(menu, szItem, "up");
	menu_addblank(menu, 0);
	SkinLang(id, "SKIN_GOLD_REFRESH", szItem, charsmax(szItem), "刷新余额");
	menu_additem(menu, szItem, "refresh");
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

SkinGetSmokeColorNameByIdx(id, idx, dest[], len) {
	new szKey[32], szFallback[24];
	if (idx < 0)
		idx = 0;
	if (!SkinSmokeNadeAvailable() || !hns_smokenade_langkey(idx, szKey, charsmax(szKey)) || !szKey[0])
		copy(szKey, charsmax(szKey), "SKIN_SMOKE_DEFAULT");
	if (!hns_smokenade_name(idx, szFallback, charsmax(szFallback)) || !szFallback[0])
		copy(szFallback, charsmax(szFallback), "Gray");
	SkinLang(id, szKey, dest, len, szFallback);
}

SkinGetSmokeColorName(id, dest[], len) {
	if (!SkinSmokeNadeAvailable()) {
		SkinLang(id, "SKIN_SMOKE_UNLOADED", dest, len, "N/A");
		return;
	}
	SkinGetSmokeColorNameByIdx(id, hns_smokenade_get_color(id), dest, len);
}

MenuSmokeColor(id, page = 0) {
	if (!is_user_connected(id))
		return;

	if (!SkinSmokeNadeAvailable()) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SMOKE_OFF", "Smoke color plugin is not loaded");
		MenuSkin(id);
		return;
	}

	new szCur[32], szTitle[160], szItem[96], szInfo[8], szSel[48];
	SkinGetSmokeColorName(id, szCur, charsmax(szCur));
	SkinLangF(id, "SKIN_SMOKE_TITLE", "\ySmoke color^n\wCurrent: \r[%s]^n\dFree, synced across servers",
		szTitle, charsmax(szTitle), szCur);
	new menu = menu_create(szTitle, "SmokeColorHandler");
	new iCur = hns_smokenade_get_color(id);
	new iCount = hns_smokenade_count();
	for (new i = 0; i < iCount; i++) {
		new szName[32];
		SkinGetSmokeColorNameByIdx(id, i, szName, charsmax(szName));
		if (i == iCur) {
			SkinLangF(id, "SKIN_SMOKE_SELECTED", "\y%s  \r[Selected]", szSel, charsmax(szSel), szName);
			copy(szItem, charsmax(szItem), szSel);
		} else
			formatex(szItem, charsmax(szItem), "\w%s", szName);
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szItem, szInfo);
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, page);
}

MenuSqlDebug(id) {
	if (!IsSkinSqlAdmin(id)) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有 SQL 调试权限");
		MenuSkin(id);
		return;
	}
	new szHost[64], szAuth[MAX_AUTHID_LENGTH], szStatus[64], szTitle[256], szItem[160];
	copy(szHost, charsmax(szHost), g_eDb[db_host]);
	GetPlayerAuth(id, szAuth, charsmax(szAuth));
	SkinSqlStatusText(id, szStatus, charsmax(szStatus));
	SkinLangF(id, "SKIN_SQL_TITLE", "\yMySQL连接与调试^n\w状态: %s%s^n\w主机: \y%s  \w库: \y%s^n\w你的账号: \y%s^n\w皮肤池: \y%d  \w拥有记录: \y%d  \w当前选用: \y%d",
		szTitle, charsmax(szTitle),
		g_bSqlReady ? "\y" : "\r", szStatus,
		szHost, g_eDb[db_db], szAuth,
		g_iPoolSize, g_iSqlOwnedCount, g_iSqlCurrentCount);
	new menu = menu_create(szTitle, "SqlMenuHandler");

	SkinLang(id, "SKIN_SQL_PING", szItem, charsmax(szItem), "测试连接");
	menu_additem(menu, szItem, "ping");
	SkinLang(id, "SKIN_SQL_COUNT", szItem, charsmax(szItem), "查询我的皮肤记录");
	menu_additem(menu, szItem, "count");
	SkinLang(id, "SKIN_SQL_SYNC", szItem, charsmax(szItem), "重新同步皮肤目录");
	menu_additem(menu, szItem, "sync");
	SkinLang(id, "SKIN_SQL_RELOAD", szItem, charsmax(szItem), "重新读取配置并重连");
	menu_additem(menu, szItem, "reload");
	if (g_szSqlLastErr[0]) {
		SkinLangF(id, "SKIN_SQL_ERR", "\r最近错误(%d): %s", szItem, charsmax(szItem), g_iSqlLastErr, g_szSqlLastErr);
		menu_additem(menu, szItem, "err");
	} else {
		SkinLang(id, "SKIN_SQL_ERR_NONE", szItem, charsmax(szItem), "\d最近错误: 无");
		menu_additem(menu, szItem, "err");
	}

	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

SqlPing(id) {
	if (g_hSqlTuple == Empty_Handle) {
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "none");
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_NONE", "未配置 MySQL");
		MenuSqlDebug(id);
		return;
	}
	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_SQL_PING, id);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler", "SELECT 1", cData, sizeof(cData));
	SkinChat(id, print_team_default, "SKIN_CHAT_SQL_PING", "正在测试 MySQL 连接...");
}

SqlCountMine(id) {
	if (g_hSqlTuple == Empty_Handle) {
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "none");
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_NONE", "未配置 MySQL");
		MenuSqlDebug(id);
		return;
	}
	new szAuth[MAX_AUTHID_LENGTH], szEsc[MAX_AUTHID_LENGTH * 2];
	GetPlayerAuth(id, szAuth, charsmax(szAuth));
	EscapeSql(szAuth, szEsc, charsmax(szEsc));
	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_SQL_COUNT, id);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler",
		fmt("SELECT (SELECT COUNT(*) FROM %s WHERE authid='%s'), (SELECT COUNT(*) FROM %s WHERE authid='%s')",
			OWNS_TABLE, szEsc, CUR_TABLE, szEsc),
		cData, sizeof(cData));
	SkinChat(id, print_team_default, "SKIN_CHAT_SQL_COUNTING", "正在查询记录  账号: ^3%s", szAuth);
}

SqlReload(id) {
	LoadDbCfg();
	SkinConnectDb();
	copy(g_szSqlStatus, charsmax(g_szSqlStatus), "reconnect");
	DbSyncCatalog();
	new szStatus[64];
	SkinSqlStatusText(id, szStatus, charsmax(szStatus));
	SkinChat(id, print_team_default, "SKIN_CHAT_SQL_RELOADED", "已重新读取配置并同步  状态: %s", szStatus);
	MenuSqlDebug(id);
}
MenuConfirmBuy(id, idx, page = 0) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	g_iBrowsePage[id] = page;
	if (row[pool_price] == 0) {
		DoBuy(id, idx);
		return;
	}

	new szRent[32], szTitle[160], szItem[96];
	if (g_iRentDays > 0)
		SkinLangF(id, "SKIN_DAYS", "%d天", szRent, charsmax(szRent), g_iRentDays);
	else
		SkinLang(id, "SKIN_PERM", szRent, charsmax(szRent), "永久");
	SkinLangF(id, "SKIN_BUY_TITLE", "\y确认购买^n\w皮肤: \y%s^n\w价格: \y%d 金币  \w租期: \y%s",
		szTitle, charsmax(szTitle), row[pool_key], row[pool_price], szRent);
	new menu = menu_create(szTitle, "ConfirmHandler");
	new szInfo[12];
	num_to_str(idx, szInfo, charsmax(szInfo));
	SkinLangF(id, "SKIN_BUY_OK", "确认购买  \r-%d", szItem, charsmax(szItem), row[pool_price]);
	menu_additem(menu, szItem, szInfo);
	SkinLang(id, "SKIN_CANCEL", szItem, charsmax(szItem), "取消");
	menu_additem(menu, szItem, "cancel");
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0);
}

MenuUpgrade(id) {
	new szTitle[128], szLeft[48];
	SkinLangF(id, "SKIN_UP_TITLE", "\y升级永久皮肤^n\w每款 \y%d 金币  \w余额: \y%d",
		szTitle, charsmax(szTitle), g_iUpgradePrice, hns_gc_get_player(id));
	new menu = menu_create(szTitle, "UpgradeHandler");
	new szInfo[12], szTxt[160], added;
	SkinLang(id, "SKIN_ITEM_LEFT", szLeft, charsmax(szLeft), "%s  \y[剩%d天]");
	for (new i = 0; i < g_iPoolSize; i++) {
		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		new exp = SkinExpire(id, row[pool_key]);
		if (exp <= 0 || exp <= get_systime())
			continue;
		format(szTxt, charsmax(szTxt), szLeft, row[pool_key], DaysLeft(id, row[pool_key]));
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szTxt, szInfo);
		added++;
	}
	if (!added) {
		SkinLang(id, "SKIN_UP_EMPTY", szTxt, charsmax(szTxt), "\d(没有正在租期中的皮肤)");
		menu_additem(menu, szTxt, "none");
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuConfirmUpgrade(id, idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);
	new szTitle[160], szItem[96];
	SkinLangF(id, "SKIN_UP_CONFIRM", "\y升级为永久?^n\w皮肤: \y%s^n\w花费: \y%d 金币",
		szTitle, charsmax(szTitle), row[pool_key], g_iUpgradePrice);
	new menu = menu_create(szTitle, "UpgradeConfirmHandler");
	new szInfo[12];
	num_to_str(idx, szInfo, charsmax(szInfo));
	SkinLangF(id, "SKIN_UP_OK", "确认升级  \r-%d", szItem, charsmax(szItem), g_iUpgradePrice);
	menu_additem(menu, szItem, szInfo);
	SkinLang(id, "SKIN_CANCEL", szItem, charsmax(szItem), "取消");
	menu_additem(menu, szItem, "cancel");
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0);
}

MenuAdmin(id) {
	if (!IsSkinAdmin(id)) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有管理权限");
		MenuSkin(id);
		return;
	}

	new szTitle[64], szItem[64];
	SkinLang(id, "SKIN_ADMIN_TITLE", szTitle, charsmax(szTitle), "\y管理员设置 \w· \r皮肤");
	new menu = menu_create(szTitle, "AdminHandler");
	// 发放与批量发放放在最前面, 其余管理功能保持可用。
	if (IsSkinOwner(id)) {
		SkinLang(id, "SKIN_ADMIN_GIVE", szItem, charsmax(szItem), "给玩家发放皮肤");
		menu_additem(menu, szItem, "1");
		SkinLang(id, "SKIN_ADMIN_GIVEALL", szItem, charsmax(szItem), "发放全部皮肤给玩家");
		menu_additem(menu, szItem, "2");
		SkinLang(id, "SKIN_ADMIN_REMOVE", szItem, charsmax(szItem), "移除玩家皮肤");
		menu_additem(menu, szItem, "3");
		SkinLang(id, "SKIN_ADMIN_CLEAR", szItem, charsmax(szItem), "一键清除在线玩家全部皮肤");
		menu_additem(menu, szItem, "8");
		SkinLang(id, "SKIN_ADMIN_POOL", szItem, charsmax(szItem), "查看皮肤池");
		menu_additem(menu, szItem, "4");
		SkinLang(id, "SKIN_ADMIN_OWNED", szItem, charsmax(szItem), "查看玩家已拥有皮肤");
		menu_additem(menu, szItem, "5");
		SkinLang(id, "SKIN_ADMIN_GIVEALL_KNIFE", szItem, charsmax(szItem), "发放全部刀皮给玩家");
		menu_additem(menu, szItem, "6");
		SkinLang(id, "SKIN_ADMIN_GIVEALL_NADE", szItem, charsmax(szItem), "发放全部投掷物皮肤给玩家");
		menu_additem(menu, szItem, "7");
		SkinLang(id, "SKIN_ADMIN_GIVE_STEAM", szItem, charsmax(szItem), "按SteamID发放(可离线)");
		menu_additem(menu, szItem, "9");
		SkinLang(id, "SKIN_ADMIN_TAKE_STEAM", szItem, charsmax(szItem), "按SteamID收回(可离线)");
		menu_additem(menu, szItem, "10");
		SkinLang(id, "SKIN_ADMIN_CLEAR_STEAM", szItem, charsmax(szItem), "按SteamID一键清除(可离线)");
		menu_additem(menu, szItem, "11");
		SkinLang(id, "SKIN_ADMIN_GIVE_GBIC", szItem, charsmax(szItem), "发放GBIC点");
		menu_additem(menu, szItem, "12");
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuPoolList(id) {
	if (g_iPoolSize == 0) {
		SkinChat(id, print_team_red, "SKIN_CHAT_POOL_EMPTY", "皮肤池为空");
		return;
	}

	new szTitle[64], szTeam[16];
	SkinLangF(id, "SKIN_POOL_TITLE", "\y皮肤池  \w共 \r%d \w款", szTitle, charsmax(szTitle), g_iPoolSize);
	new menu = menu_create(szTitle, "PoolListHandler");
	new szInfo[12], szTxt[160];
	for (new i = 0; i < g_iPoolSize; i++) {
		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		SkinTeamName(id, PoolTeamChar(i), szTeam, charsmax(szTeam));
		format(szTxt, charsmax(szTxt), "\y[%s]\w %s  \y[%d]", szTeam, row[pool_key], row[pool_price]);
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szTxt, szInfo);
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuPickPlayer(const mode[], id) {
	copy(g_pendingMode[id], 7, mode);
	g_pendingAdmin[id] = id;
	if (!IsSkinOwner(id)) {
		if (g_pendingMode[id][0] == 'v')
			MenuViewOwned(id, id);
		else if (g_pendingMode[id][0] == 'g')
			MenuGiveSkin(id, id);
		else if (g_pendingMode[id][0] == 'a')
			GiveAllSkinsTo(id, 0);
		else if (g_pendingMode[id][0] == 'k') {
			GiveAllKnivesTo(id);
			MenuAdmin(id);
		} else if (g_pendingMode[id][0] == 'n') {
			GiveAllNadesTo(id);
			MenuAdmin(id);
		} else
			MenuRemoveSkin(id, id);
		return;
	}

	new szTitle[64];
	if (g_pendingMode[id][0] == 'v')
		SkinLang(id, "SKIN_PICK_VIEW", szTitle, charsmax(szTitle), "\y选择玩家 \w· 查看拥有");
	else if (g_pendingMode[id][0] == 'g')
		SkinLang(id, "SKIN_PICK_GIVE", szTitle, charsmax(szTitle), "\y选择玩家 \w· 发放皮肤");
	else if (g_pendingMode[id][0] == 'a')
		SkinLang(id, "SKIN_PICK_ALL", szTitle, charsmax(szTitle), "\y选择玩家 \w· 发放全部");
	else if (g_pendingMode[id][0] == 'k')
		SkinLang(id, "SKIN_PICK_KNIVES", szTitle, charsmax(szTitle), "\y选择玩家 \w· 发放全部刀皮");
	else if (g_pendingMode[id][0] == 'n')
		SkinLang(id, "SKIN_PICK_NADES", szTitle, charsmax(szTitle), "\y选择玩家 \w· 发放全部投掷物皮肤");
	else if (g_pendingMode[id][0] == 'c')
		SkinLang(id, "SKIN_PICK_CLEAR", szTitle, charsmax(szTitle), "\y选择玩家 \w· 一键清除皮肤");
	else
		SkinLang(id, "SKIN_PICK_REMOVE", szTitle, charsmax(szTitle), "\y选择玩家 \w· 移除皮肤");

	new menu = menu_create(szTitle, "PickPlayerHandler");
	new szTxt[80], added;
	for (new i = 1; i <= MaxClients; i++) {
		if (!is_user_connected(i) || is_user_hltv(i))
			continue;
		new szName[32], szAuth[MAX_AUTHID_LENGTH];
		get_user_name(i, szName, charsmax(szName));
		GetPlayerAuth(i, szAuth, charsmax(szAuth));
		format(szTxt, charsmax(szTxt), "%s  \y[%s]", szName, szAuth);
		menu_additem(menu, szTxt, fmt("%d", i));
		added++;
	}
	if (!added) {
		SkinLang(id, "SKIN_PICK_EMPTY", szTxt, charsmax(szTxt), "\d(当前没有在线玩家)");
		menu_additem(menu, szTxt, "0", 0);
	}
	menu_display(id, menu);
}


public CmdGrantSteamInput(id) {
	if (!IsSkinAdmin(id))
		return PLUGIN_HANDLED;
	new szArg[96], szSteam[40], szSpec[40], note[96];
	read_args(szArg, charsmax(szArg));
	trim(szArg);
	remove_quotes(szArg);
	strtok(szArg, szSteam, charsmax(szSteam), szSpec, charsmax(szSpec), ' ');
	trim(szSpec);
	new ret;
	if (equal(g_pendingMode[id], "sclear"))
		ret = ExecSteamClear(szSteam, id, note, charsmax(note), true);
	else
		ret = ExecSteamGrant(szSteam, szSpec, equal(g_pendingMode[id], "stake"), id, note, charsmax(note));
	g_pendingMode[id][0] = 0;
	if (ret < 0)
		SkinChat(id, print_team_default, "SKIN_CHAT_GRANT_FAIL", "鍙戞斁澶辫触: %s", note);
	else if (equal(g_pendingMode[id], "x"))
		SkinChat(id, print_team_blue, "SKIN_CHAT_GRANT_OK", "%s", note);
	else
		SkinChat(id, print_team_blue, "SKIN_CHAT_GRANT_OK", "%s", note);
	return PLUGIN_HANDLED;
}

CmdAmxGrant(id, bool:bRemove) {
	if (!cmd_access(id, ADMIN_IMMUNITY, 0, 0))
		return PLUGIN_HANDLED;
	if (read_argc() < 3) {
		GrantTell(id, bRemove ? "用法: amx_takeskin <steamid> <皮肤名|all|all_t|all_c|all_knife|all_nade>" : "用法: amx_giveskin <steamid> <皮肤名|all|all_t|all_c|all_knife|all_nade>");
		return PLUGIN_HANDLED;
	}
	new szSteam[40], szSpec[40], note[96];
	read_argv(1, szSteam, charsmax(szSteam));
	read_argv(2, szSpec, charsmax(szSpec));
	new ret = ExecSteamGrant(szSteam, szSpec, bRemove, id, note, charsmax(note));
	if (ret < 0)
		GrantTell(id, note);
	else
		GrantTell(id, note);
	return PLUGIN_HANDLED;
}

public CmdAmxGiveSkin(id) {
	return CmdAmxGrant(id, false);
}

public CmdAmxTakeSkin(id) {
	return CmdAmxGrant(id, true);
}

PromptGbicGrant(id) {
	if (!IsSkinOwner(id))
		return;
	copy(g_pendingMode[id], charsmax(g_pendingMode[]), "sgbic");
	g_szPendingGbicSteam[id][0] = EOS;
	client_print(id, print_console, "输入 SteamID, 例如 STEAM_0:1:12345");
	client_cmd(id, "messagemode SkinGrantGbicSteam");
}

public CmdGrantGbicSteamInput(id) {
	if (!IsSkinOwner(id))
		return PLUGIN_HANDLED;
	if (!equal(g_pendingMode[id], "sgbic"))
		return PLUGIN_HANDLED;
	new szArg[40];
	read_args(szArg, charsmax(szArg));
	remove_quotes(szArg);
	trim(szArg);
	if (!IsSteamAuth(szArg) || containi(szArg, ":") == -1) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_AUTH", "SteamID 不正确");
		PromptGbicGrant(id);
		return PLUGIN_HANDLED;
	}
	copy(g_szPendingGbicSteam[id], charsmax(g_szPendingGbicSteam[]), szArg);
	client_print(id, print_console, "输入发放数量, 正数增加, 负数扣除, 不能为 0");
	client_cmd(id, "messagemode SkinGrantGbic");
	return PLUGIN_HANDLED;
}

public CmdGrantGbicInput(id) {
	if (!IsSkinOwner(id))
		return PLUGIN_HANDLED;
	if (!equal(g_pendingMode[id], "sgbic"))
		return PLUGIN_HANDLED;

	new szArg[16];
	read_args(szArg, charsmax(szArg));
	remove_quotes(szArg);
	trim(szArg);
	new iDelta = str_to_num(szArg);
	if (!iDelta) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_BAD", "数量不能为 0");
		client_cmd(id, "messagemode SkinGrantGbic");
		return PLUGIN_HANDLED;
	}

	new szAuth[32];
	copy(szAuth, charsmax(szAuth), g_szPendingGbicSteam[id]);
	g_pendingMode[id][0] = 0;
	g_szPendingGbicSteam[id][0] = 0;
	if (!szAuth[0] || !hns_gc_add_steamid(szAuth, iDelta)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_FAIL", "发放失败, 数据库未连接");
		return PLUGIN_HANDLED;
	}

	new szName[32];
	get_user_name(id, szName, charsmax(szName));
	log_amx("[HnsSkin] %s granted %d GBIC to %s", szName, iDelta, szAuth);
	SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_OK", "已给 %s 发放 %d GBIC", szAuth, iDelta);
	return PLUGIN_HANDLED;
}

#define GBIC_ONLINE_MAX 300000000

bool:GbicAmountDigits(const szArg[]) {
	if (!szArg[0])
		return false;
	for (new i = 0; szArg[i]; i++) {
		if (szArg[i] < '0' || szArg[i] > '9')
			return false;
	}
	return true;
}

MenuOnlineGbic(id) {
	if (!CanGrantOnlineGbic(id))
		return;

	new szTitle[64], szEmpty[64], szName[32], szItem[96];
	SkinLang(id, "SKIN_MENU_GBIC_ONLINE", szTitle, charsmax(szTitle), "\r在线发放GBIC点");
	new menu = menu_create(szTitle, "OnlineGbicHandler");
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);

	new iCount = 0;
	for (new i = 1; i <= MaxClients; i++) {
		if (!is_user_connected(i) || is_user_bot(i) || is_user_hltv(i))
			continue;
		get_user_name(i, szName, charsmax(szName));
		formatex(szItem, charsmax(szItem), "\w%s", szName);
		new szInfo[8];
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szItem, szInfo);
		iCount++;
	}
	if (!iCount) {
		SkinLang(id, "SKIN_MENU_GBIC_NONE", szEmpty, charsmax(szEmpty), "\d没有在线玩家");
		menu_additem(menu, szEmpty, "0", 0);
	}
	menu_display(id, menu);
}

public OnlineGbicHandler(id, menu, item) {
	if (!CanGrantOnlineGbic(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		if (is_user_connected(id))
			MenuSkin(id);
		return PLUGIN_HANDLED;
	}

	new szInfo[8], szName[32], iAccess, iCallback;
	menu_item_getinfo(menu, item, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
	menu_destroy(menu);

	new iTarget = str_to_num(szInfo);
	if (iTarget < 1 || iTarget > MaxClients || !is_user_connected(iTarget) || is_user_bot(iTarget) || is_user_hltv(iTarget)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_LEFT", "该玩家已离开");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	g_pendingTarget[id] = iTarget;
	copy(g_pendingMode[id], charsmax(g_pendingMode[]), "ogbic");
	get_user_name(iTarget, szName, charsmax(szName));
	client_print(id, print_console, "给 %s 发放 GBIC, 输入 1 到 %d", szName, GBIC_ONLINE_MAX);
	client_cmd(id, "messagemode SkinGrantOnlineGbic");
	return PLUGIN_HANDLED;
}

public CmdGrantOnlineGbic(id) {
	if (!CanGrantOnlineGbic(id))
		return PLUGIN_HANDLED;
	if (!equal(g_pendingMode[id], "ogbic"))
		return PLUGIN_HANDLED;

	new iTarget = g_pendingTarget[id];
	g_pendingMode[id][0] = 0;
	g_pendingTarget[id] = 0;

	new szArg[16];
	read_args(szArg, charsmax(szArg));
	remove_quotes(szArg);
	trim(szArg);
	if (!GbicAmountDigits(szArg)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_RANGE", "只能输入 1 到 %d 的整数", GBIC_ONLINE_MAX);
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	new iDelta = str_to_num(szArg);
	if (iDelta < 1 || iDelta > GBIC_ONLINE_MAX) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_RANGE", "只能输入 1 到 %d 的整数", GBIC_ONLINE_MAX);
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	if (!is_user_connected(iTarget) || is_user_bot(iTarget) || is_user_hltv(iTarget)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_LEFT", "该玩家已离开");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	new szAuth[32];
	get_user_authid(iTarget, szAuth, charsmax(szAuth));
	if (!IsSteamAuth(szAuth)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_AUTH", "该玩家 SteamID 还没就绪");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	new iCur = hns_gc_get_player(iTarget);
	if (iCur > cellmax - iDelta) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_FULL", "加上后会超过点数上限, 已取消");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	// 皮肤库和 GBIC 库是两套连接。在线玩家走和每小时奖励相同的入账。
	if (!LibraryExists("skin_gc_local", LibType_Library)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_FAIL", "发放失败, GBIC 数据库未连接");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}
	if (hns_gc_is_sql() && !hns_gc_player_ready(iTarget)) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GOLD_WAIT", "该玩家 GBIC 还在读取, 请稍后再发");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}
	new iAfter = hns_gc_add_player(iTarget, iDelta);
	if (iAfter != iCur + iDelta) {
		SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_FAIL", "发放失败, 余额没有写入");
		MenuOnlineGbic(id);
		return PLUGIN_HANDLED;
	}

	new szAdmin[32], szName[32];
	get_user_name(id, szAdmin, charsmax(szAdmin));
	get_user_name(iTarget, szName, charsmax(szName));
	log_amx("[HnsSkin] %s granted %d GBIC online to %s (%s)", szAdmin, iDelta, szName, szAuth);
	SkinChat(id, print_team_default, "SKIN_CHAT_GBIC_OK", "已给 %s 发放 %d GBIC", szName, iDelta);
	if (is_user_connected(iTarget) && iTarget != id)
		SkinChat(iTarget, print_team_default, "SKIN_CHAT_GBIC_GOT", "管理员给你发放了 %d GBIC", iDelta);
	MenuOnlineGbic(id);
	return PLUGIN_HANDLED;
}

PromptSteamGrant(id, bool:bRemove) {
	if (!IsSkinOwner(id))
		return;
	copy(g_pendingMode[id], charsmax(g_pendingMode[]), bRemove ? "stake" : "sgive");
	client_print(id, print_console, "输入: STEAM_0:1:12345 皮肤名  可用 all / all_t / all_c / all_knife / all_nade");
	client_cmd(id, "messagemode SkinGrantSteam");
}

PromptSteamClear(id) {
	if (!IsSkinOwner(id))
		return;
	copy(g_pendingMode[id], charsmax(g_pendingMode[]), "sclear");
	client_print(id, print_console, "输入要清除的 SteamID, 例如 STEAM_0:1:12345");
	client_cmd(id, "messagemode SkinGrantSteam");
}

RememberAuthByIp(id, const szAuth[]) {
	if (!g_tAuthByIp || !IsSteamAuth(szAuth))
		return;
	new szIp[32];
	get_user_ip(id, szIp, charsmax(szIp), 1);
	if (szIp[0])
		TrieSetString(g_tAuthByIp, szIp, szAuth);
}

LookupAuthByIp(id, dest[], len) {
	dest[0] = EOS;
	if (!g_tAuthByIp)
		return;
	new szIp[32];
	get_user_ip(id, szIp, charsmax(szIp), 1);
	if (szIp[0])
		TrieGetString(g_tAuthByIp, szIp, dest, len);
}

public fw_SetModel(ent, const model[]) {
	if (!pev_valid(ent))
		return FMRES_IGNORED;

	new szClass[32];
	pev(ent, pev_classname, szClass, charsmax(szClass));

	new kind;
	if (equali(szClass, "grenade")) {
		if (containi(model, "w_smokegrenade") != -1 || containi(model, "smokegrenade") != -1)
			kind = NADE_KIND_SMOKE;
		else if (containi(model, "w_flashbang") != -1 || containi(model, "flashbang") != -1)
			kind = NADE_KIND_FLASH;
		else
			return FMRES_IGNORED;
	} else {
		return FMRES_IGNORED;
	}

	new owner = pev(ent, pev_owner);
	if (owner < 1 || owner > MaxClients || !is_user_connected(owner))
		return FMRES_IGNORED;

	new szView[PLATFORM_MAX_PATH], szWorld[PLATFORM_MAX_PATH];
	if (!GetNadeCurrentModel(owner, kind, szView, charsmax(szView)))
		return FMRES_IGNORED;
	if (!NadeWorldPath(szView, szWorld, charsmax(szWorld)))
		return FMRES_IGNORED;

	engfunc(EngFunc_SetModel, ent, szWorld);
	return FMRES_SUPERCEDE;
}

ClearOwned(id) {
	if (g_Owned[id]) {
		ArrayDestroy(g_Owned[id]);
		g_Owned[id] = Empty_Handle;
	}
	if (g_OwnedExpire[id]) {
		TrieDestroy(g_OwnedExpire[id]);
		g_OwnedExpire[id] = Invalid_Trie;
	}
}

EscapeSql(const src[], dest[], len) {
	copy(dest, len, src);
	replace_all(dest, len, "\\", "\\\\");
	replace_all(dest, len, "'", "\\'");
}

bool:SameAuth(id, const authid[]) {
	return is_user_connected(id) && g_szAuth[id][0] && equal(g_szAuth[id], authid);
}

PackQueryData(cData[], type, id, extra = 0) {
	cData[0] = type;
	cData[1] = id;
	cData[2] = extra;
	cData[3] = g_iLoadGen[id];
	copy(cData[4], MAX_AUTHID_LENGTH - 1, g_szAuth[id]);
}

Db_LoadOwned(id, const authid[]) {
	ClearOwned(id);

	new szAuth[MAX_AUTHID_LENGTH * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_LOAD_OWNED, id);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler",
		fmt("SELECT model_key, expire_at FROM %s WHERE authid='%s'", OWNS_TABLE, szAuth),
		cData, sizeof(cData));
}

Db_LoadCurrent(id, const authid[]) {
	new szAuth[MAX_AUTHID_LENGTH * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_LOAD_CURRENT, id);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler",
		fmt("SELECT team, model_key FROM %s WHERE authid='%s'", CUR_TABLE, szAuth),
		cData, sizeof(cData));
}

Db_SaveCurrent(id, const authid[], const key[], teamChar) {
	new szTeam[2]; szTeam[0] = teamChar; szTeam[1] = EOS;
	new szAuth[MAX_AUTHID_LENGTH * 2], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(key, szKey, charsmax(szKey));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_SAVE_CURRENT, id);
	new iNow = get_systime();
	new szQuery[512];
	if (g_bLocalDb)
		formatex(szQuery, charsmax(szQuery), "INSERT OR REPLACE INTO %s (authid, team, model_key, updated) VALUES ('%s','%s','%s',%d)", CUR_TABLE, szAuth, szTeam, szKey, iNow);
	else
		formatex(szQuery, charsmax(szQuery), "INSERT INTO %s (authid, team, model_key, updated) VALUES ('%s','%s','%s',%d) ON DUPLICATE KEY UPDATE model_key='%s', updated=%d", CUR_TABLE, szAuth, szTeam, szKey, iNow, szKey, iNow);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler", szQuery, cData, sizeof(cData));
}
Db_SaveKnifeCurrent(id, const authid[], knife) {
	new key[SKIN_KEY_MAX];
	formatex(key, charsmax(key), "knife:%d", knife);
	Db_SaveCurrent(id, authid, key, 'K');
}

Db_InsertOwned(id, const authid[], const key[], expireAt, iPaid = 0) {
	new szAuth[MAX_AUTHID_LENGTH * 2], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(key, szKey, charsmax(szKey));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_BUY_SKIN, id, iPaid);
	new iNow = get_systime();
	new szQuery[512];
	if (g_bLocalDb)
		formatex(szQuery, charsmax(szQuery), "INSERT OR REPLACE INTO %s (authid, model_key, bought_at, expire_at) VALUES ('%s','%s',%d,%d)", OWNS_TABLE, szAuth, szKey, iNow, expireAt);
	else
		formatex(szQuery, charsmax(szQuery), "INSERT INTO %s (authid, model_key, bought_at, expire_at) VALUES ('%s','%s',%d,%d) ON DUPLICATE KEY UPDATE bought_at=%d, expire_at=%d", OWNS_TABLE, szAuth, szKey, iNow, expireAt, iNow, expireAt);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler", szQuery, cData, sizeof(cData));
}
Db_SetPermanent(id, const authid[], const key[], iPaid = 0) {
	new szAuth[MAX_AUTHID_LENGTH * 2], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(key, szKey, charsmax(szKey));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_UPGRADE_SKIN, id, iPaid);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler",
		fmt("UPDATE %s SET expire_at=0 WHERE authid='%s' AND model_key='%s'", OWNS_TABLE, szAuth, szKey),
		cData, sizeof(cData));
}

Db_RemoveOwned(id, const authid[], const key[]) {
	new szAuth[MAX_AUTHID_LENGTH * 2], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(key, szKey, charsmax(szKey));

	new cData[4 + MAX_AUTHID_LENGTH];
	PackQueryData(cData, QT_REMOVE_SKIN, id);
	SQL_ThreadQuery(g_hSqlTuple, "SqlHandler",
		fmt("DELETE FROM %s WHERE authid='%s' AND model_key='%s'", OWNS_TABLE, szAuth, szKey),
		cData, sizeof(cData));
}

SQL_ExecSync(Handle:conn, const szQuery[], any:...) {
	new szQ[2048];
	vformat(szQ, charsmax(szQ), szQuery, 3);
	new Handle:q = SQL_PrepareQuery(conn, "%s", szQ);
	if (q == Empty_Handle) {
		log_amx("[Skin] SQL 预处理失败: %s", szQ);
		return;
	}
	if (!SQL_Execute(q)) {
		new szErr[160];
		SQL_QueryError(q, szErr, charsmax(szErr));
		// 老库补列时列已存在, 不算故障
		if (containi(szErr, "Duplicate column") == -1)
			log_amx("[Skin] SQL 执行失败: %s | %s", szErr, szQ);
	}
	SQL_FreeHandle(q);
}

bool:LoadDbCfg() {
	copy(g_eDb[db_host], charsmax(g_eDb[db_host]), DEFAULT_HOST);
	copy(g_eDb[db_user], charsmax(g_eDb[db_user]), DEFAULT_USER);
	copy(g_eDb[db_pass], charsmax(g_eDb[db_pass]), DEFAULT_PASS);
	copy(g_eDb[db_db],   charsmax(g_eDb[db_db]),   DEFAULT_DB);

	new szCfg[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szCfg, charsmax(szCfg));
	format(szCfg, charsmax(szCfg), "%s/%s", szCfg, DB_CFG_FILE);

	if (!file_exists(szCfg))
		return true;

	new file = fopen(szCfg, "rt");
	if (!file)
		return true;

	new szLine[256], szKey[32], szVal[64];
	while (!feof(file)) {
		fgets(file, szLine, charsmax(szLine));
		if (!szLine[0] || szLine[0] == ';')
			continue;

		parse(szLine, szKey, charsmax(szKey), szVal, charsmax(szVal));
		trim(szKey); trim(szVal);

		// 去掉两端可能带的引号
		new iLen = strlen(szVal);
		if (iLen >= 2 && szVal[0] == '"' && szVal[iLen - 1] == '"') {
			szVal[iLen - 1] = EOS;
			for (new j = 0; szVal[j] && j < iLen; j++) szVal[j] = szVal[j + 1];
		}

		if (equali(szKey, "skin_host")) copy(g_eDb[db_host], charsmax(g_eDb[db_host]), szVal);
		else if (equali(szKey, "skin_user")) copy(g_eDb[db_user], charsmax(g_eDb[db_user]), szVal);
		else if (equali(szKey, "skin_pass")) copy(g_eDb[db_pass], charsmax(g_eDb[db_pass]), szVal);
		else if (equali(szKey, "skin_db"))   copy(g_eDb[db_db],   charsmax(g_eDb[db_db]),   szVal);
		else if (equali(szKey, "skin_storage"))
			g_bLocalDb = (equali(szVal, "local") || equali(szVal, "sqlite"));
	}
	fclose(file);

	return true;
}

ImportSkinsToDb(Handle:conn, const szCfg[]) {
	new file = fopen(szCfg, "rt");
	if (!file) {
		log_amx("[Skin] 皮肤配置文件不存在: %s", szCfg);
		return;
	}

	new szLine[512], szHead[32], szRestA[384];
	new szKey[SKIN_KEY_MAX], szModel[SKIN_MODEL_MAX];
	new sTeam[2], sPrice[16], sWav[DEATH_SND_MAX];
	new iImported, iSkipped;
	new bool:bPending;
	new bool:bSettings;

	while (!feof(file)) {
		fgets(file, szLine, charsmax(szLine));
		trim(szLine);
		if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
			continue;

		// 区块头: [TT]/[T] / [CT] / [SETTINGS]
		if (szLine[0] == '[') {
			if (bPending) {
				if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav))
					iImported++;
				else
					iSkipped++;
			}
			parse(szLine, szHead, charsmax(szHead), szRestA, charsmax(szRestA));
			TrimBracket(szHead);
			if (equali(szHead, "settings")) {
				bSettings = true;
			} else if (equali(szHead, "tt") || equali(szHead, "t")) {
				sTeam[0] = TEAM_CHAR_T;
				bSettings = false;
			} else if (equali(szHead, "ct")) {
				sTeam[0] = TEAM_CHAR_C;
				bSettings = false;
			} else {
				sTeam[0] = EOS;
				bSettings = false;
			}
			bPending = false;
			continue;
		}

		parse(szLine, szHead, charsmax(szHead), szRestA, charsmax(szRestA));
		trim(szHead);

		// [SETTINGS] 区块:  key value
		if (bSettings) {
			new szVal[16];
			copy(szVal, charsmax(szVal), szRestA);
			trim(szVal);
			StripQuotes(szVal);
			if (equali(szHead, "storage"))
				g_bLocalDb = (equali(szVal, "local") || equali(szVal, "sqlite"));
			else if (equali(szHead, "rent_days"))
				g_iRentDays = str_to_num(szVal);
			else if (equali(szHead, "upgrade_price"))
				g_iUpgradePrice = str_to_num(szVal);
			else if (equali(szHead, "knife_free"))
				g_iKnifeFree = str_to_num(szVal);
			else if (equali(szHead, "nade_free"))
				g_iNadeFree = str_to_num(szVal);
			else if (equali(szHead, "buy_gold_text") || equali(szHead, "buy_gold_url")) {
				new iPos = strlen(szHead);
				while (szLine[iPos] == ' ' || szLine[iPos] == '^t')
					iPos++;
				if (equali(szHead, "buy_gold_text"))
					copy(g_szBuyGoldText, charsmax(g_szBuyGoldText), szLine[iPos]);
				else
					copy(g_szBuyGoldUrl, charsmax(g_szBuyGoldUrl), szLine[iPos]);
				StripQuotes(g_szBuyGoldText);
				StripQuotes(g_szBuyGoldUrl);
			}
			else if (equali(szHead, "precache_max"))
				g_iPrecacheMax = str_to_num(szVal);
			else if (equali(szHead, "checkin_bonus"))
				g_iCheckinBonus = str_to_num(szVal);
			else if (equali(szHead, "playtime_bonus"))
				g_iPlaytimeBonus = str_to_num(szVal);
			else if (equali(szHead, "playtime_seconds")) {
				g_iPlaytimeNeed = str_to_num(szVal);
				if (g_iPlaytimeNeed < 60)
					g_iPlaytimeNeed = 3600;
			}
			continue;
		}

		// 裸区块头 tt / t / ct (单独一行, 不带方括号)
		if ((equali(szHead, "tt") || equali(szHead, "t") || equali(szHead, "ct")) && !szRestA[0]) {
			if (bPending) {
				if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav))
					iImported++;
				else
					iSkipped++;
			}
			if (equali(szHead, "tt") || equali(szHead, "t")) sTeam[0] = TEAM_CHAR_T;
			else sTeam[0] = TEAM_CHAR_C;
			bPending = false;
			continue;
		}

		// 音效行: 以 wav 开头, 属于上一款; 可写多行, 死亡时随机
		if (equali(szHead, "wav")) {
			new szOne[DEATH_SND_MAX];
			copy(szOne, charsmax(szOne), szRestA);
			trim(szOne);
			StripQuotes(szOne);
			AppendDeathSound(sWav, charsmax(sWav), szOne);
			continue;
		}

		// 新皮肤行: 先提交上一款
		if (bPending) {
			if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav))
				iImported++;
			else
				iSkipped++;
		}

		// 名字 模型 价格 (阵营来自当前区块)
		copy(szKey, charsmax(szKey), szHead);
		StripQuotes(szKey);
		parse(szLine, szHead, charsmax(szHead), szModel, charsmax(szModel), sPrice, charsmax(sPrice));
		trim(szModel); trim(sPrice);
		StripQuotes(szModel); StripQuotes(sPrice);
		if (!sPrice[0])
			ParseSkinFields(szRestA, szModel, charsmax(szModel), sPrice, charsmax(sPrice));

		if (!szKey[0] || (sTeam[0] != TEAM_CHAR_T && sTeam[0] != TEAM_CHAR_C) || !szModel[0]) {
			log_amx("[Skin] 跳过无效行: %s", szLine);
			bPending = false;
			iSkipped++;
			continue;
		}
		sWav[0] = EOS;
		bPending = true;
	}
	if (bPending) {
		if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav))
			iImported++;
		else
			iSkipped++;
	}

	fclose(file);
	log_amx("[Skin] 从 %s 导入/更新皮肤 %d 条, 跳过 %d 条", szCfg, iImported, iSkipped);
}

TrimBracket(sz[]) {
	new i;
	while (sz[i] == '[' || sz[i] == ' ')
		i++;
	new j = 0;
	while (sz[i] && sz[i] != ']' && sz[i] != ' ') {
		sz[j++] = sz[i++];
	}
	sz[j] = EOS;
}

ParseSkinFields(const src[], szModel[], iModelLen, sPrice[], iPriceLen) {
	new szWork[384];
	copy(szWork, charsmax(szWork), src);
	trim(szWork);

	sPrice[0] = EOS;
	szModel[0] = EOS;

	new iLen = strlen(szWork);
	new i = iLen - 1;
	while (i >= 0 && (szWork[i] == ' ' || szWork[i] == 9))
		i--;
	new iEnd = i;
	while (i >= 0 && szWork[i] >= '0' && szWork[i] <= '9')
		i--;

	if (iEnd > i && i >= 0 && (szWork[i] == ' ' || szWork[i] == 9)) {
		copy(sPrice, iPriceLen, szWork[i + 1]);
		szWork[i] = EOS;
		trim(szWork);
	}

	copy(szModel, iModelLen, szWork);
	trim(szModel);
	StripQuotes(szModel);
	StripQuotes(sPrice);
	if (!sPrice[0])
		copy(sPrice, iPriceLen, "0");
}

AppendDeathSound(dest[], iLen, const szOne[]) {
	if (!szOne[0])
		return;

	new szWork[DEATH_SND_MAX];
	copy(szWork, charsmax(szWork), szOne);
	trim(szWork);

	while (szWork[0]) {
		new szPart[DEATH_SND_PATH], szRest[DEATH_SND_MAX];
		strtok2(szWork, szPart, charsmax(szPart), szRest, charsmax(szRest), ',', 1);
		trim(szPart);
		StripQuotes(szPart);
		if (szPart[0] && !DeathSoundInList(dest, szPart)) {
			if (!dest[0]) {
				copy(dest, iLen, szPart);
			} else if (strlen(dest) + 1 + strlen(szPart) <= iLen) {
				format(dest, iLen, "%s,%s", dest, szPart);
			} else {
				log_amx("[Skin] 死亡音效列表过长, 跳过: %s", szPart);
			}
		}
		copy(szWork, charsmax(szWork), szRest);
		trim(szWork);
	}
}

bool:DeathSoundInList(const list[], const szOne[]) {
	if (!list[0] || !szOne[0])
		return false;

	new szWork[DEATH_SND_MAX];
	copy(szWork, charsmax(szWork), list);
	while (szWork[0]) {
		new szPart[DEATH_SND_PATH], szRest[DEATH_SND_MAX];
		strtok2(szWork, szPart, charsmax(szPart), szRest, charsmax(szRest), ',', 1);
		trim(szPart);
		if (equal(szPart, szOne))
			return true;
		copy(szWork, charsmax(szWork), szRest);
		trim(szWork);
	}
	return false;
}

PrecacheDeathSounds(const list[]) {
	new szWork[DEATH_SND_MAX];
	copy(szWork, charsmax(szWork), list);
	while (szWork[0]) {
		new szPart[DEATH_SND_PATH], szRest[DEATH_SND_MAX];
		strtok2(szWork, szPart, charsmax(szPart), szRest, charsmax(szRest), ',', 1);
		trim(szPart);
		if (szPart[0])
			precache_sound(szPart);
		copy(szWork, charsmax(szWork), szRest);
		trim(szWork);
	}
}

PickDeathSound(const list[], dest[], iLen) {
	dest[0] = EOS;
	if (!list[0])
		return;

	new szParts[8][DEATH_SND_PATH];
	new iCount;
	new szWork[DEATH_SND_MAX];
	copy(szWork, charsmax(szWork), list);
	while (szWork[0] && iCount < sizeof szParts) {
		new szRest[DEATH_SND_MAX];
		strtok2(szWork, szParts[iCount], charsmax(szParts[]), szRest, charsmax(szRest), ',', 1);
		trim(szParts[iCount]);
		if (szParts[iCount][0])
			iCount++;
		copy(szWork, charsmax(szWork), szRest);
		trim(szWork);
	}
	if (!iCount)
		return;
	copy(dest, iLen, szParts[random_num(0, iCount - 1)]);
}

bool:CommitSkinRow(Handle:conn, const szKey[], const sTeam[], const szModel[], const sPrice[], const sWav[], bool:bPrecache = true) {
	new iPrice = str_to_num(sPrice);
	if (conn != Empty_Handle) {
		new szEscKey[SKIN_KEY_MAX * 2], szEscModel[SKIN_MODEL_MAX * 2], szEscWav[DEATH_SND_MAX * 2];
		EscapeSql(szKey, szEscKey, charsmax(szEscKey));
		EscapeSql(szModel, szEscModel, charsmax(szEscModel));
		EscapeSql(sWav, szEscWav, charsmax(szEscWav));
		new iNow = get_systime();
		if (g_bLocalDb)
			SQL_ExecSync(conn, "INSERT OR REPLACE INTO %s (model_key, team, model, body, skin, price, flags, death_sound, active, created, updated) VALUES ('%s','%s','%s',0,0,%d,'','%s',1,%d,%d)", SKINS_TABLE, szEscKey, sTeam, szEscModel, iPrice, szEscWav, iNow, iNow);
		else
			SQL_ExecSync(conn, "INSERT INTO %s (model_key, team, model, body, skin, price, flags, death_sound, created, updated) VALUES ('%s','%s','%s',0,0,%d,'','%s', %d, %d) ON DUPLICATE KEY UPDATE team=VALUES(team), model=VALUES(model), price=VALUES(price), death_sound=VALUES(death_sound), active=1, updated=%d", SKINS_TABLE, szEscKey, sTeam, szEscModel, iPrice, szEscWav, iNow, iNow, iNow);
	}

	if (!bPrecache)
		return true;

	new row[pool_e];
	copy(row[pool_key], charsmax(row[pool_key]), szKey);
	copy(row[pool_model], charsmax(row[pool_model]), szModel);
	copy(row[pool_snd], charsmax(row[pool_snd]), sWav);
	row[pool_price] = iPrice;
	row[pool_team] = sTeam[0];
	return AddSkinToPool(row);
}

StripQuotes(sz[]) {
	new iLen = strlen(sz);
	if (iLen >= 2 && sz[0] == '"' && sz[iLen - 1] == '"') {
		sz[iLen - 1] = EOS;
		for (new j = 0; sz[j] && j < iLen; j++) sz[j] = sz[j + 1];
	}
}

CreateTablesSync(Handle:conn) {
	if (g_bLocalDb) {
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (id INTEGER PRIMARY KEY AUTOINCREMENT, model_key VARCHAR(32) NOT NULL UNIQUE, team CHAR(1) NOT NULL DEFAULT '', model VARCHAR(64) NOT NULL, body INT NOT NULL DEFAULT 0, skin INT NOT NULL DEFAULT 0, price INT NOT NULL DEFAULT 0, flags VARCHAR(16) NOT NULL DEFAULT '', death_sound VARCHAR(320) NOT NULL DEFAULT '', active INT NOT NULL DEFAULT 1, created INT NOT NULL DEFAULT 0, updated INT NOT NULL DEFAULT 0)", SKINS_TABLE);
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) NOT NULL, model_key VARCHAR(32) NOT NULL, bought_at INT NOT NULL DEFAULT 0, expire_at INT NOT NULL DEFAULT 0, steamid VARCHAR(64) NOT NULL DEFAULT '', PRIMARY KEY (authid, model_key))", OWNS_TABLE);
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) NOT NULL, team CHAR(1) NOT NULL DEFAULT '', model_key VARCHAR(32) NOT NULL DEFAULT '', updated INT NOT NULL DEFAULT 0, PRIMARY KEY (authid, team))", CUR_TABLE);
	} else {
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, model_key VARCHAR(32) NOT NULL, team CHAR(1) NOT NULL DEFAULT '', model VARCHAR(64) NOT NULL, body TINYINT NOT NULL DEFAULT 0, skin TINYINT NOT NULL DEFAULT 0, price INT NOT NULL DEFAULT 0, flags VARCHAR(16) NOT NULL DEFAULT '', death_sound VARCHAR(320) NOT NULL DEFAULT '', active TINYINT NOT NULL DEFAULT 1, created INT NOT NULL DEFAULT 0, updated INT NOT NULL DEFAULT 0, UNIQUE KEY uk_key (model_key))", SKINS_TABLE);
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) NOT NULL, model_key VARCHAR(32) NOT NULL, bought_at INT NOT NULL DEFAULT 0, expire_at INT NOT NULL DEFAULT 0, PRIMARY KEY (authid, model_key), KEY idx_authid (authid))", OWNS_TABLE);
		SQL_ExecSync(conn, "ALTER TABLE %s ADD COLUMN expire_at INT NOT NULL DEFAULT 0", OWNS_TABLE);
		SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) NOT NULL, team CHAR(1) NOT NULL DEFAULT '', model_key VARCHAR(32) NOT NULL DEFAULT '', updated INT NOT NULL DEFAULT 0, PRIMARY KEY (authid, team))", CUR_TABLE);
	}
	SQL_ExecSync(conn, "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) NOT NULL, checkin_date INT NOT NULL, claimed_at INT NOT NULL DEFAULT 0, PRIMARY KEY (authid, checkin_date))", CHECKIN_TABLE);
}

stock SkinConnectDb() {
	if (g_hSqlTuple != Empty_Handle) {
		SQL_FreeHandle(g_hSqlTuple);
		g_hSqlTuple = Empty_Handle;
	}

	new driver[16];
	if (g_bLocalDb)
		copy(driver, charsmax(driver), "sqlite");
	else
		copy(driver, charsmax(driver), "mysql");
	if (!SQL_SetAffinity(driver)) {
		log_amx("[Skin] 缺少 %s 模块, 皮肤库未连接", driver);
		g_bSqlReady = false;
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "fail");
		formatex(g_szSqlLastErr, charsmax(g_szSqlLastErr), "missing %s", driver);
		return;
	}

	if (g_bLocalDb) {
		copy(g_eDb[db_host], charsmax(g_eDb[db_host]), "sqlite");
		g_eDb[db_user][0] = EOS;
		g_eDb[db_pass][0] = EOS;
		copy(g_eDb[db_db], charsmax(g_eDb[db_db]), "skinsql");
		g_hSqlTuple = SQL_MakeDbTuple("localhost", "", "", "skinsql");
		log_amx("[Skin] 使用本地数据库 data/sqlite3/skinsql.sq3");
	} else {
		g_hSqlTuple = SQL_MakeDbTuple(g_eDb[db_host], g_eDb[db_user], g_eDb[db_pass], g_eDb[db_db]);
		SQL_SetCharset(g_hSqlTuple, "utf8");
		log_amx("[Skin] 使用 MySQL %s / %s", g_eDb[db_host], g_eDb[db_db]);
	}
}
bool:AddSkinToPool(row[pool_e]) {
	if (!row[pool_key][0] || !row[pool_model][0])
		return false;
	if (PoolIndexOf(row[pool_key]) != -1)
		return true;

	if (row[pool_snd][0])
		PrecacheDeathSounds(row[pool_snd]);

	// 预缓存上限: 超过则跳过模型预缓存(本图不可用), 仍然保留皮肤目录/商店, 避免撞 512 模型池崩服
	if (g_iPrecacheMax > 0 && g_iPrecacheUsed >= g_iPrecacheMax) {
		row[pool_precache] = 0;
		ArrayPushArray(g_pPool, row, sizeof row);
		TrieSetCell(g_pPoolIndex, row[pool_key], g_iPoolSize);
		g_iPoolSize++;
		return true;
	}

	if (!custom_player_models_register(row[pool_key], row[pool_model],
		row[pool_body], row[pool_skin],
		row[pool_model], row[pool_body], row[pool_skin])) {
		log_amx("[Skin] 预缓存失败(模型文件缺失?): %s -> %s", row[pool_key], row[pool_model]);
		return false;
	}

	row[pool_precache] = 1;
	g_iPrecacheUsed++;
	ArrayPushArray(g_pPool, row, sizeof row);
	TrieSetCell(g_pPoolIndex, row[pool_key], g_iPoolSize);
	g_iPoolSize++;
	return true;
}

LoadPoolSync(Handle:conn) {
	new Handle:q = SQL_PrepareQuery(conn,
		"SELECT model_key, team, model, body, skin, price, flags, death_sound FROM %s WHERE active=1", SKINS_TABLE);
	if (q == Empty_Handle)
		return;

	if (!SQL_Execute(q)) {
		new szErr[160];
		SQL_QueryError(q, szErr, charsmax(szErr));
		log_amx("[Skin] 读取皮肤池失败: %s", szErr);
		SQL_FreeHandle(q);
		return;
	}

	// 0 model_key, 1 team, 2 model, 3 body, 4 skin, 5 price, 6 flags, 7 death_sound
	if (SQL_MoreResults(q) && SQL_NumColumns(q) >= 8) {
		while (SQL_MoreResults(q)) {
			new row[pool_e];
			new szTeam[2];
			SQL_ReadResult(q, 0, row[pool_key],  charsmax(row[pool_key]));
			SQL_ReadResult(q, 1, szTeam, charsmax(szTeam));
			row[pool_team] = szTeam[0];
			SQL_ReadResult(q, 2, row[pool_model], charsmax(row[pool_model]));
			row[pool_body] = SQL_ReadResult(q, 3);
			row[pool_skin] = SQL_ReadResult(q, 4);
			row[pool_price] = SQL_ReadResult(q, 5);
			SQL_ReadResult(q, 6, row[pool_flags], charsmax(row[pool_flags]));
			SQL_ReadResult(q, 7, row[pool_snd],   charsmax(row[pool_snd]));
			AddSkinToPool(row);
			SQL_NextRow(q);
		}
	}

	SQL_FreeHandle(q);
	log_amx("[Skin] 皮肤池加载完成, 共 %d 个皮肤", g_iPoolSize);
}

LoadSkinsCfgDirect() {
	new szCfg[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szCfg, charsmax(szCfg));
	format(szCfg, charsmax(szCfg), "%s/%s", szCfg, SKINS_CFG_FILE);
	ImportSkinsToDb(Empty_Handle, szCfg);
	log_amx("[Skin] 已从配置文件直接加载皮肤池, 共 %d 个皮肤 (已预缓存模型 %d 个, 上限 precache_max=%d)",
		g_iPoolSize, g_iPrecacheUsed, g_iPrecacheMax);
}

DbPrecachePool() {
	LoadSkinsCfgDirect();
}

DbSyncCatalog(bool:bImportCfg = true) {
	if (g_hSqlTuple == Empty_Handle) {
		g_bSqlReady = false;
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "none");
		return;
	}

	new szErr[160], iErr;
	new Handle:conn = SQL_Connect(g_hSqlTuple, iErr, szErr, charsmax(szErr));
	if (conn == Empty_Handle) {
		g_bSqlReady = false;
		g_iSqlLastErr = iErr;
		copy(g_szSqlLastErr, charsmax(g_szSqlLastErr), szErr);
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "fail");
		log_amx("[Skin] 后台同步皮肤目录失败(%d): %s", iErr, szErr);
		return;
	}

	CreateTablesSync(conn);

	// 换图只建表, 不把 skins.cfg 全量 upsert; 改配置后用管理菜单「同步」
	if (bImportCfg) {
		new szCfg[PLATFORM_MAX_PATH];
		get_localinfo("amxx_configsdir", szCfg, charsmax(szCfg));
		format(szCfg, charsmax(szCfg), "%s/%s", szCfg, SKINS_CFG_FILE);
		ImportSkinsCatalogOnly(conn, szCfg);
	}

	g_bSqlReady = true;
	g_iSqlLastErr = 0;
	g_szSqlLastErr[0] = EOS;
	copy(g_szSqlStatus, charsmax(g_szSqlStatus), "ok");
	SQL_FreeHandle(conn);
}

ImportSkinsCatalogOnly(Handle:conn, const szCfg[]) {
	new file = fopen(szCfg, "rt");
	if (!file)
		return;

	new szLine[512], szHead[32], szRestA[384];
	new szKey[SKIN_KEY_MAX], szModel[SKIN_MODEL_MAX];
	new sTeam[2], sPrice[16], sWav[DEATH_SND_MAX];
	new iImported, iSkipped;
	new bool:bPending;
	new bool:bSettings;

	while (!feof(file)) {
		fgets(file, szLine, charsmax(szLine));
		trim(szLine);
		if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
			continue;

		if (szLine[0] == '[') {
			if (bPending) {
				if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav, false))
					iImported++;
				else
					iSkipped++;
			}
			parse(szLine, szHead, charsmax(szHead), szRestA, charsmax(szRestA));
			TrimBracket(szHead);
			if (equali(szHead, "settings")) {
				bSettings = true;
			} else if (equali(szHead, "tt") || equali(szHead, "t")) {
				sTeam[0] = TEAM_CHAR_T;
				bSettings = false;
			} else if (equali(szHead, "ct")) {
				sTeam[0] = TEAM_CHAR_C;
				bSettings = false;
			} else {
				sTeam[0] = EOS;
				bSettings = false;
			}
			bPending = false;
			continue;
		}

		parse(szLine, szHead, charsmax(szHead), szRestA, charsmax(szRestA));
		trim(szHead);

		if (bSettings) {
			continue;
		}

		if ((equali(szHead, "tt") || equali(szHead, "t") || equali(szHead, "ct")) && !szRestA[0]) {
			if (bPending) {
				if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav, false))
					iImported++;
				else
					iSkipped++;
			}
			if (equali(szHead, "tt") || equali(szHead, "t")) sTeam[0] = TEAM_CHAR_T;
			else sTeam[0] = TEAM_CHAR_C;
			bPending = false;
			continue;
		}

		if (equali(szHead, "wav")) {
			new szOne[DEATH_SND_MAX];
			copy(szOne, charsmax(szOne), szRestA);
			trim(szOne);
			StripQuotes(szOne);
			AppendDeathSound(sWav, charsmax(sWav), szOne);
			continue;
		}

		if (bPending) {
			if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav, false))
				iImported++;
			else
				iSkipped++;
		}

		copy(szKey, charsmax(szKey), szHead);
		StripQuotes(szKey);
		parse(szLine, szHead, charsmax(szHead), szModel, charsmax(szModel), sPrice, charsmax(sPrice));
		trim(szModel); trim(sPrice);
		StripQuotes(szModel); StripQuotes(sPrice);
		if (!sPrice[0])
			ParseSkinFields(szRestA, szModel, charsmax(szModel), sPrice, charsmax(sPrice));

		if (!szKey[0] || (sTeam[0] != TEAM_CHAR_T && sTeam[0] != TEAM_CHAR_C) || !szModel[0]) {
			bPending = false;
			iSkipped++;
			continue;
		}
		sWav[0] = EOS;
		bPending = true;
	}
	if (bPending) {
		if (CommitSkinRow(conn, szKey, sTeam, szModel, sPrice, sWav, false))
			iImported++;
		else
			iSkipped++;
	}

	fclose(file);
	log_amx("[Skin] 后台同步皮肤目录 %d 条, 跳过 %d 条", iImported, iSkipped);
}

CurSlot(id, dest[], len, teamChar) {
	if (teamChar == TEAM_CHAR_T)
		copy(dest, len, g_CurT[id]);
	else
		copy(dest, len, g_CurC[id]);
}

ApplyCurrentSkin(id) {
	new teamChar = CharOfTeam(get_member(id, m_iTeam));
	new key[SKIN_KEY_MAX];
	CurSlot(id, key, charsmax(key), teamChar);

	if (key[0] && PoolIndexOf(key) != -1 && IsSkinValid(id, key) && IsSkinPrecached(key)) {
		custom_player_models_set(id, key);
		SkinChat(id, print_team_default, "SKIN_CHAT_APPLIED", "已应用皮肤: ^3%s", key);
		MarkAppliedSkin(id, teamChar, key);
	} else {
		custom_player_models_reset(id);
		MarkAppliedSkin(id, teamChar, "");
	}
}

MarkAppliedSkin(id, teamChar, const key[]) {
	g_szAppliedTeam[id] = teamChar;
	copy(g_szAppliedKey[id], charsmax(g_szAppliedKey[]), key);
}

SelectSkin(id, idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	new teamChar = CharOfTeam(get_member(id, m_iTeam));
	// 只允许应用当前阵营的皮肤；购买另一阵营只保存所有权，不立即换模型
	// 本图因预缓存上限被跳过的款式不能应用 (模型没进池会拉不到)
	if (row[pool_team] == teamChar && row[pool_precache])
		custom_player_models_set(id, row[pool_key]);
	// 写入对应阵营槽
	if (row[pool_team] == TEAM_CHAR_T)
		copy(g_CurT[id], charsmax(g_CurT[]), row[pool_key]);
	else
		copy(g_CurC[id], charsmax(g_CurC[]), row[pool_key]);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_SaveCurrent(id, authid, row[pool_key], row[pool_team]);

	new szTeam[48];
	SkinTeamLong(id, row[pool_team], szTeam, charsmax(szTeam));
	SkinChat(id, print_team_blue, "SKIN_CHAT_SELECTED", "你已选用%s阵营皮肤: ^3%s", szTeam, row[pool_key]);
}

DoBuy(id, idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	// 本图未预缓存(超过 precache_max)的不能购买, 换图后再买
	if (!row[pool_precache]) {
		SkinChat(id, print_team_default, "SKIN_CHAT_MAP_NA", "皮肤 ^3%s^1 本图未加载(模型预缓存上限), 换图后再试", row[pool_key]);
		return;
	}

	// 已永久拥有: 不能再买
	new exp = SkinExpire(id, row[pool_key]);
	if (exp == 0) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_PERM", "你已永久拥有该皮肤");
		return;
	}
	// 租期还有效: 无需重复购买
	if (exp > 0 && exp > get_systime()) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_RENT", "你已拥有该皮肤(剩 ^3%d^1 天), 无需重复购买", DaysLeft(id, row[pool_key]));
		return;
	}

	if (g_hSqlTuple == Empty_Handle) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_BUY", "MySQL 未就绪, 暂不能购买");
		return;
	}

	new iGold = hns_gc_get_player(id);
	if (iGold < row[pool_price]) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_NEED", "金币不足! 需要 %d, 你有 %d", row[pool_price], iGold);
		return;
	}

	hns_gc_set_player(id, iGold - row[pool_price]);

	if (!g_Owned[id])
		g_Owned[id] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[id])
		g_OwnedExpire[id] = TrieCreate();
	if (!HasSkin(id, row[pool_key]))
		ArrayPushString(g_Owned[id], row[pool_key]);

	// 到期时间戳: 0 = 永久
	new iExpire = (g_iRentDays > 0) ? get_systime() + g_iRentDays * 86400 : 0;
	TrieSetCell(g_OwnedExpire[id], row[pool_key], iExpire);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_InsertOwned(id, authid, row[pool_key], iExpire, row[pool_price]);

	SelectSkin(id, idx);
	if (row[pool_team] != CharOfTeam(get_member(id, m_iTeam)))
		SkinChat(id, print_team_default, "SKIN_CHAT_SELECTED_OTHER_TEAM", "皮肤 ^3%s^1 已保存, 切换阵营后生效", row[pool_key]);
	if (iExpire == 0)
		SkinChat(id, print_team_blue, "SKIN_CHAT_BUY_PERM", "购买成功(永久)! 剩余金币 %d", iGold - row[pool_price]);
	else
		SkinChat(id, print_team_blue, "SKIN_CHAT_BUY_RENT", "购买成功! 租期 %d 天, 剩余金币 %d", g_iRentDays, iGold - row[pool_price]);
}

KnifeInfo(knife, name[], nameLen, &price) {
	name[0] = EOS;
	price = 0;
	crxknives_get_attribute_str(knife, "NAME", name, nameLen, false);
	if (!name[0])
		formatex(name, nameLen, "Knife %d", knife);
	crxknives_get_attribute_int(knife, "PRICE", price, false);
	if (price < 0)
		price = 0;

	// knife_skins.cfg 里有该刀(按名字)就覆盖商店价格, 方便单独管理
	if (g_tKnifePrice != Invalid_Trie && name[0]) {
		new iOverride;
		if (TrieGetCell(g_tKnifePrice, name, iOverride))
			price = iOverride;
	}
}

DoBuyKnife(id, knife) {
	if (!IsKnifeShopItemValid(knife))
		return;

	new key[SKIN_KEY_MAX], name[MAX_NAME_LENGTH], price;
	KnifeOwnedKey(knife, key, charsmax(key));
	KnifeInfo(knife, name, charsmax(name), price);

	new exp = SkinExpire(id, key);
	if (exp == 0) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_PERM", "你已永久拥有该刀皮");
		return;
	}
	if (exp > 0 && exp > get_systime()) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_OWNED_RENT", "你已拥有该刀皮(剩 ^3%d^1 天), 无需重复购买", DaysLeft(id, key));
		return;
	}
	if (g_hSqlTuple == Empty_Handle) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_BUY", "MySQL 未就绪, 暂不能购买");
		return;
	}

	new iGold = hns_gc_get_player(id);
	if (iGold < price) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_NEED", "金币不足! 需要 %d, 你有 %d", price, iGold);
		return;
	}

	hns_gc_set_player(id, iGold - price);
	if (!g_Owned[id])
		g_Owned[id] = ArrayCreate(SKIN_KEY_MAX);
	if (!g_OwnedExpire[id])
		g_OwnedExpire[id] = TrieCreate();
	if (!HasSkin(id, key))
		ArrayPushString(g_Owned[id], key);

	new iExpire = (g_iRentDays > 0) ? get_systime() + g_iRentDays * 86400 : 0;
	TrieSetCell(g_OwnedExpire[id], key, iExpire);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_InsertOwned(id, authid, key, iExpire, price);
	SelectKnife(id, knife);

	if (iExpire == 0)
		SkinChat(id, print_team_blue, "SKIN_CHAT_BUY_PERM", "刀皮购买成功(永久)! 剩余金币 %d", iGold - price);
	else
		SkinChat(id, print_team_blue, "SKIN_CHAT_BUY_RENT", "刀皮购买成功! 租期 %d 天, 剩余金币 %d", g_iRentDays, iGold - price);
}

MenuKnives(id, page = 0) {
	new szTitle[160], szItem[160], szName[MAX_NAME_LENGTH], szInfo[12], curKnife;
	curKnife = crxknives_get_user_knife(id);
	SkinLangF(id, "SKIN_KNIFE_TITLE", "\y刀皮商店^n\w金币: \y%d  \w当前: \y%d  \w免费名额: \y%d",
		szTitle, charsmax(szTitle), hns_gc_get_player(id), curKnife, g_iKnifeFree);
	new menu = menu_create(szTitle, "KnifeHandler");

	new selectedKnife = g_iCurKnife[id] ? g_iCurKnife[id] : curKnife;
	for (new knife = 0; knife < crxknives_get_knives_num(); knife++) {
		new price;
		KnifeInfo(knife, szName, charsmax(szName), price);
		FormatShopItem(id, szItem, charsmax(szItem), szName, (knife < g_iKnifeFree || IsKnifeOwned(id, knife)), price, knife == selectedKnife);
		num_to_str(knife, szInfo, charsmax(szInfo));
		menu_additem(menu, szItem, szInfo);
	}

	if (!crxknives_get_knives_num())
		menu_additem(menu, "\d(暂无刀皮)", "none");

	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, page);
}

MenuConfirmKnifeBuy(id, knife, page = 0) {
	new name[MAX_NAME_LENGTH], price, szTitle[160], szItem[96], szInfo[12];
	KnifeInfo(knife, name, charsmax(name), price);
	g_iKnifePage[id] = page;
	if (price == 0 || knife < g_iKnifeFree) {
		DoBuyKnife(id, knife);
		OpenShopLater(id, SHOP_MENU_KNIFE, page);
		return;
	}
	new szRent[32];
	if (g_iRentDays > 0)
		SkinLangF(id, "SKIN_DAYS", "%d天", szRent, charsmax(szRent), g_iRentDays);
	else
		SkinLang(id, "SKIN_PERM", szRent, charsmax(szRent), "永久");
	SkinLangF(id, "SKIN_KNIFE_BUY_TITLE", "\y确认购买刀皮^n\w名称: %s^n\w价格: \y%d 金币  \w租期: %s",
		szTitle, charsmax(szTitle), name, price, szRent);
	new menu = menu_create(szTitle, "KnifeConfirmHandler");
	num_to_str(knife, szInfo, charsmax(szInfo));
	SkinLangF(id, "SKIN_BUY_OK", "确认购买  \r-%d", szItem, charsmax(szItem), price);
	menu_additem(menu, szItem, szInfo);
	SkinLang(id, "SKIN_CANCEL", szItem, charsmax(szItem), "取消");
	menu_additem(menu, szItem, "cancel");
	SkinMenuStyle(id, menu);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0);
}

DoUpgrade(id, idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	new exp = SkinExpire(id, row[pool_key]);
	if (exp == 0) {
		SkinChat(id, print_team_blue, "SKIN_CHAT_ALREADY_PERM", "该皮肤已经是永久了");
		return;
	}
	if (exp < 0 || (exp > 0 && exp <= get_systime())) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NEED_OWN", "你还没有有效的 %s, 先购买后再升级", row[pool_key]);
		return;
	}

	if (g_hSqlTuple == Empty_Handle) {
		SkinChat(id, print_team_red, "SKIN_CHAT_SQL_UP", "MySQL 未就绪, 暂不能升级");
		return;
	}

	new iGold = hns_gc_get_player(id);
	if (iGold < g_iUpgradePrice) {
		SkinChat(id, print_team_red, "SKIN_CHAT_GOLD_UP", "金币不足! 升级永久需要 %d, 你有 %d", g_iUpgradePrice, iGold);
		return;
	}

	hns_gc_set_player(id, iGold - g_iUpgradePrice);

	TrieSetCell(g_OwnedExpire[id], row[pool_key], 0);

	new authid[MAX_AUTHID_LENGTH];
	GetPlayerAuth(id, authid, charsmax(authid));
	Db_SetPermanent(id, authid, row[pool_key], g_iUpgradePrice);

	MenuGold(id);
	SkinChat(id, print_team_blue, "SKIN_CHAT_UP_OK", "升级永久成功! 皮肤 ^3%s^1 现在永久有效, 剩余金币 %d", row[pool_key], iGold - g_iUpgradePrice);
}

OnSkinChosen(id, idx, page = 0) {
	if (idx < 0 || idx >= g_iPoolSize)
		return;

	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);

	// 本图因预缓存上限未加载该模型, 不能购买/应用 (换一张地图即可用)
	if (!row[pool_precache]) {
		SkinChat(id, print_team_default, "SKIN_CHAT_MAP_NA", "皮肤 ^3%s^1 本图未加载(模型预缓存上限), 换图后再试", row[pool_key]);
		MenuBrowseSkins(id, g_iBrowseTeam[id], page);
		return;
	}

	if (IsSkinValid(id, row[pool_key])) {
		SelectSkin(id, idx);
		MenuBrowseSkins(id, g_iBrowseTeam[id], page);
	} else
		MenuConfirmBuy(id, idx, page);
}

MenuViewOwned(id, target) {
	g_pendingTarget[id] = target;
	new szName[33]; get_user_name(target, szName, charsmax(szName));
	new teamChar = CharOfTeam(get_member(target, m_iTeam));
	new szTeam[16], szTitle[96], szTxt[128], szSel[32], szPerm[24], szExp[24], szLeft[32];
	SkinTeamShort(id, teamChar, szTeam, charsmax(szTeam));
	SkinLangF(id, "SKIN_VIEW_TITLE", " %s 拥有的皮肤 (当前%s)", szTitle, charsmax(szTitle), szName, szTeam);
	new menu = menu_create(szTitle, "ViewOwnedHandler");
	SkinLang(id, "SKIN_TAG_SELECTED", szSel, charsmax(szSel), "  \r[已选择]");
	SkinLang(id, "SKIN_TAG_PERM", szPerm, charsmax(szPerm), "  [永久]");
	SkinLang(id, "SKIN_TAG_EXPIRED", szExp, charsmax(szExp), "  [已过期]");
	SkinLang(id, "SKIN_TAG_LEFT", szLeft, charsmax(szLeft), "  [剩%d天]");
	if (g_Owned[target] && ArraySize(g_Owned[target]) > 0) {
		for (new i = 0; i < ArraySize(g_Owned[target]); i++) {
			new key[SKIN_KEY_MAX];
			ArrayGetString(g_Owned[target], i, key, charsmax(key));
			new idx = PoolIndexOf(key);
			new exp = SkinExpire(target, key);
			new szStat[24], szTeam[16];
			if (exp == 0)
				copy(szStat, charsmax(szStat), szPerm);
			else if (exp > get_systime())
				format(szStat, charsmax(szStat), szLeft, DaysLeft(target, key));
			else
				copy(szStat, charsmax(szStat), szExp);
			if (idx != -1)
				SkinTeamName(id, PoolTeamChar(idx), szTeam, charsmax(szTeam));
			else
				copy(szTeam, charsmax(szTeam), "?");
			format(szTxt, charsmax(szTxt), "\y[%s]\w %s%s%s",
				szTeam, key, szStat,
				cur_match(target, key, teamChar) ? szSel : "");
			menu_additem(menu, szTxt);
		}
	} else {
		SkinLang(id, "SKIN_VIEW_EMPTY", szTxt, charsmax(szTxt), "\d(该玩家没有皮肤)");
		menu_additem(menu, szTxt);
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

bool:cur_match(target, const key[], teamChar) {
	new cur[SKIN_KEY_MAX];
	CurSlot(target, cur, charsmax(cur), teamChar);
	return cur[0] && equal(cur, key);
}

MenuGiveSkin(id, target) {
	g_pendingTarget[id] = target;
	g_pendingAdmin[id] = id;
	new szName[33]; get_user_name(target, szName, charsmax(szName));
	new szTeam[16], szTitle[96];
	SkinTeamShort(id, g_pendingGiveTeam[id], szTeam, charsmax(szTeam));
	SkinLangF(id, "SKIN_GIVE_TITLE", "\y发放皮肤 \w· %s^n\w范围: \y%s", szTitle, charsmax(szTitle), szName, szTeam);
	new menu = menu_create(szTitle, "GiveSkinHandler");
	new szInfo[12], szTxt[160], added;

	// 1. 阵营角色皮肤 (info = 纯索引数字)
	for (new i = 0; i < g_iPoolSize; i++) {
		new row[pool_e];
		ArrayGetArray(g_pPool, i, row, sizeof row);
		if (g_pendingGiveTeam[id] && row[pool_team] != g_pendingGiveTeam[id])
			continue;
		format(szTxt, charsmax(szTxt), "\w%s", row[pool_key]);
		num_to_str(i, szInfo, charsmax(szInfo));
		menu_additem(menu, szTxt, szInfo);
		added++;
	}

	// 2. 刀皮模型 (info 前缀 "k", 永不受阵营/范围限制)
	for (new knife = 0; knife < crxknives_get_knives_num(); knife++) {
		new kname[MAX_NAME_LENGTH], kprice;
		KnifeInfo(knife, kname, charsmax(kname), kprice);
		SkinLangF(id, "SKIN_GIVE_TAG_KNIFE", "\w[刀] %s", szTxt, charsmax(szTxt), kname);
		formatex(szInfo, charsmax(szInfo), "k%d", knife);
		menu_additem(menu, szTxt, szInfo);
		added++;
	}

	// 3. 投掷物皮肤 (info 前缀 "n")
	for (new i = 0; i < g_iNadeSize; i++) {
		new row[nade_e];
		ArrayGetArray(g_pNade, i, row, sizeof row);
		SkinLangF(id, "SKIN_GIVE_TAG_NADE", "\w[投掷物] %s", szTxt, charsmax(szTxt), row[nade_key]);
		formatex(szInfo, charsmax(szInfo), "n%d", i);
		menu_additem(menu, szTxt, szInfo);
		added++;
	}

	if (!added) {
		SkinLang(id, "SKIN_GIVE_EMPTY", szTxt, charsmax(szTxt), "\d(没有可发放的皮肤)");
		menu_additem(menu, szTxt, "none");
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

MenuRemoveSkin(id, target) {
	g_pendingTarget[id] = target;
	g_pendingAdmin[id] = id;
	new szName[33]; get_user_name(target, szName, charsmax(szName));
	new szTitle[96], szTxt[128], szTeam[16];
	SkinLangF(id, "SKIN_REMOVE_TITLE", " 移除 %s 的皮肤", szTitle, charsmax(szTitle), szName);
	new menu = menu_create(szTitle, "RemoveSkinHandler");
	if (g_Owned[target] && ArraySize(g_Owned[target]) > 0) {
		for (new i = 0; i < ArraySize(g_Owned[target]); i++) {
			new key[SKIN_KEY_MAX];
			ArrayGetString(g_Owned[target], i, key, charsmax(key));
			new idx = PoolIndexOf(key);
			if (idx != -1)
				SkinTeamShort(id, PoolTeamChar(idx), szTeam, charsmax(szTeam));
			else
				copy(szTeam, charsmax(szTeam), "?");
			format(szTxt, charsmax(szTxt), "[%s] %s", szTeam, key);
			menu_additem(menu, szTxt, key);
		}
	} else {
		SkinLang(id, "SKIN_VIEW_EMPTY", szTxt, charsmax(szTxt), "\d(该玩家没有皮肤)");
		menu_additem(menu, szTxt);
	}
	SkinMenuStyle(id, menu);
	SkinMenuReturn(id, menu);
	menu_display(id, menu, 0);
}

PoolTeamChar(idx) {
	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);
	return row[pool_team];
}

public plugin_natives() {
	register_native("hns_skin_open", "native_hns_skin_open");
	hns_register_optional_sql();
	set_native_filter("SkinNativeFilter");
}

public native_hns_skin_open(plugin, params) {
	#pragma unused plugin
	new id = get_param(1);
	if (is_user_connected(id))
		MenuSkin(id);
	return 1;
}

public SkinNativeFilter(const szName[], iIndex, iTrap) {
	if (equal(szName, "REU_GetAuthtype") || equal(szName, "has_reunion")) {
		g_bHasReunion = false;
		return PLUGIN_HANDLED;
	}
	if (contain(szName, "crxknives_") == 0)
		return PLUGIN_HANDLED;
	return PLUGIN_CONTINUE;
}
public plugin_precache() {
	g_pPool = ArrayCreate(pool_e);
	g_pPoolIndex = TrieCreate();
	g_pNade = ArrayCreate(nade_e);

	// 换图只读 skins.cfg / nade_skins.cfg / knife_skins.cfg 并预缓存模型, 不连 MySQL, 避免卡住 changelevel
	DbPrecachePool();
	LoadNadeCfg();
	LoadKnifeCfg();
}

public plugin_init() {
	register_plugin("HNS Match Skin", "4.0.0", "OpenHNS");
	register_library("hns_match_skin");
	register_dictionary("hns_skin.txt");
	g_bHasReunion = has_reunion();

	// crx 在 plugin_cfg 里缓存 km_select_message, 必须在它之前关掉英文选刀提示
	MuteCrxKnifeSelectMessage();

	for (new i = 0; i < sizeof(g_szClcmds); i++)
		register_clcmd(g_szClcmds[i], "Cl_Cmd");
	register_clcmd("say /sign", "CmdCheckin");
	register_clcmd("say_team /sign", "CmdCheckin");
	register_clcmd("say /qd", "CmdCheckin");
	register_clcmd("say_team /qd", "CmdCheckin");
	register_clcmd("SkinGrantSteam", "CmdGrantSteamInput");
	register_clcmd("SkinGrantGbicSteam", "CmdGrantGbicSteamInput");
	register_clcmd("SkinGrantGbic", "CmdGrantGbicInput");
	register_clcmd("SkinGrantOnlineGbic", "CmdGrantOnlineGbic");
	register_concmd("amx_giveskin", "CmdAmxGiveSkin", ADMIN_IMMUNITY, "<steamid> <skin|all|all_t|all_c|all_knife|all_nade>");
	register_concmd("amx_takeskin", "CmdAmxTakeSkin", ADMIN_IMMUNITY, "<steamid> <skin|all|all_t|all_c|all_knife|all_nade>");
	register_concmd("amx_clearskin", "CmdAmxClearSkin", ADMIN_IMMUNITY, "<steamid>");
	set_task(8.0, "TaskGrantPoll", TASK_GRANT_POLL, _, _, "b");
	register_clcmd("say /checkin", "CmdCheckin");
	register_clcmd("say_team /checkin", "CmdCheckin");
	register_clcmd("say /签到", "CmdCheckin");
	register_clcmd("say_team /签到", "CmdCheckin");

	LoadDbCfg();
	g_tAuthByIp = TrieCreate();
	SkinConnectDb();

	// 建表/导入目录放到后台, 不卡住 changelevel
	set_task(0.1, "TaskSyncCatalog");

	// 死斗刀人是当场换边、不重生。每秒看一次队伍，换边后套上该玩家自己的那一边皮肤
	set_task(1.0, "TaskWatchSkins", TASK_SKIN_WATCH, _, _, "b");

	// 拦截原版死亡音效, 换成皮肤音效 (否则会叠在一起)
	register_forward(FM_EmitSound, "fwdEmitSoundDeath", 0);

	// 投掷物皮肤: 换掉出厂的烟雾/闪光模型
	register_forward(FM_SetModel, "fw_SetModel", 0);
	RegisterHookChain(RG_CBasePlayerWeapon_DefaultDeploy, "OnNadeDeployPre", false);
	RegisterHookChain(RG_CBasePlayerWeapon_DefaultDeploy, "OnNadeDeployPost", true);
	RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawnPost", true);
	if (g_iVaultReward == INVALID_HANDLE)
		g_iVaultReward = nvault_open("skin_reward");
}

public TaskSyncCatalog() {
	DbSyncCatalog(false);
}

public plugin_cfg() {
	MuteCrxKnifeSelectMessage();
	if (g_iVaultReward == INVALID_HANDLE)
		g_iVaultReward = nvault_open("skin_reward");
}

MuteCrxKnifeSelectMessage() {
	set_cvar_num("km_select_message", 0);
	new pCvar = get_cvar_pointer("km_select_message");
	if (pCvar)
		set_pcvar_num(pCvar, 0);
}

public plugin_end() {
	if (g_pPool) { ArrayDestroy(g_pPool); g_pPool = Empty_Handle; }
	if (g_pPoolIndex) { TrieDestroy(g_pPoolIndex); g_pPoolIndex = Invalid_Trie; }
	if (g_tAuthByIp) { TrieDestroy(g_tAuthByIp); g_tAuthByIp = Invalid_Trie; }
	if (g_pNade) { ArrayDestroy(g_pNade); g_pNade = Empty_Handle; }
	if (g_iVaultReward != INVALID_HANDLE) {
		nvault_close(g_iVaultReward);
		g_iVaultReward = INVALID_HANDLE;
	}
	for (new i = 1; i <= MaxClients; i++) {
		if (g_Owned[i])
			ArrayDestroy(g_Owned[i]);
		if (g_OwnedExpire[i])
			TrieDestroy(g_OwnedExpire[i]);
	}
	if (g_hSqlTuple) {
		SQL_FreeHandle(g_hSqlTuple);
		g_hSqlTuple = Empty_Handle;
	}
}

bool:IsDefaultDeathSound(const sample[]) {
	if (!sample[0])
		return false;
	if (equali(sample, "player/die1.wav")
		|| equali(sample, "player/die2.wav")
		|| equali(sample, "player/die3.wav")
		|| equali(sample, "player/death6.wav")
		|| equali(sample, "player/pl_die1.wav"))
		return true;
	if (containi(sample, "player/die") == 0)
		return true;
	if (containi(sample, "player/death") == 0)
		return true;
	return false;
}

bool:GetSkinDeathSound(id, dest[], iLen) {
	dest[0] = EOS;
	if (id < 1 || id > MaxClients || !is_user_connected(id))
		return false;

	new teamChar = CharOfTeam(get_member(id, m_iTeam));
	new key[SKIN_KEY_MAX];
	CurSlot(id, key, charsmax(key), teamChar);
	if (!key[0])
		return false;

	new idx = PoolIndexOf(key);
	if (idx == -1)
		return false;

	new row[pool_e];
	ArrayGetArray(g_pPool, idx, row, sizeof row);
	PickDeathSound(row[pool_snd], dest, iLen);
	return dest[0] != EOS;
}

public fwdEmitSoundDeath(id, iChannel, szSample[], Float:volume, Float:attenuation, fFlags, pitch) {
	if (g_bPlayingDeathSnd)
		return FMRES_IGNORED;
	if (id < 1 || id > MaxClients)
		return FMRES_IGNORED;
	if (!IsDefaultDeathSound(szSample))
		return FMRES_IGNORED;

	new szSnd[DEATH_SND_PATH];
	if (!GetSkinDeathSound(id, szSnd, charsmax(szSnd)))
		return FMRES_IGNORED;

	g_bPlayingDeathSnd = true;
	emit_sound(id, iChannel, szSnd, volume, attenuation, fFlags, pitch);
	g_bPlayingDeathSnd = false;
	return FMRES_SUPERCEDE;
}

RefreshPlayerSkin(id) {
	if (!is_user_connected(id))
		return;

	new team = get_member(id, m_iTeam);
	if (team != TEAM_TERRORIST && team != TEAM_CT) {
		if (g_szAppliedKey[id][0])
			custom_player_models_reset(id);
		g_iLastTeam[id] = 0;
		g_szAppliedTeam[id] = 0;
		g_szAppliedKey[id][0] = EOS;
		return;
	}

	new t = CharOfTeam(team);
	new key[SKIN_KEY_MAX];
	CurSlot(id, key, charsmax(key), t);

	new bool:bWantCustom = (key[0] && PoolIndexOf(key) != -1 && IsSkinValid(id, key) && IsSkinPrecached(key));
	if (!bWantCustom)
		key[0] = EOS;

	if (g_iLastTeam[id] == t && g_szAppliedTeam[id] == t && equal(g_szAppliedKey[id], key))
		return;

	g_iLastTeam[id] = t;
	if (bWantCustom)
		custom_player_models_set(id, key);
	else
		custom_player_models_reset(id);
	MarkAppliedSkin(id, t, key);
}

public TaskWatchSkins() {
	new players[MAX_PLAYERS], num;
	get_players(players, num, "ch");
	for (new i = 0; i < num; i++) {
		new id = players[i];
		if (!g_bOwnedLoaded[id])
			continue;
		new team = get_member(id, m_iTeam);
		if (team != TEAM_TERRORIST && team != TEAM_CT)
			continue;
		if (g_iLastTeam[id] == CharOfTeam(team) && g_szAppliedKey[id][0])
			continue;
		RefreshPlayerSkin(id);
	}
}

public client_authorized(id) {
	if (!g_hSqlTuple || is_user_bot(id) || is_user_hltv(id))
		return;
	TryLoadOwned(id);
}

public client_putinserver(id) {
	// 进服/换图: 清掉上一次的"已应用"记录, 保证稍后按DB里的当前槽重新贴模型
	g_iLastTeam[id] = 0;
	g_szAppliedTeam[id] = 0;
	g_szAppliedKey[id][0] = EOS;
	StartPlaytimeTrack(id);

	// 默认英语: 等语言核心插件(1秒识别)跑完再判断, 没识别出 cn/tw/en/ru 的玩家切英语
	remove_task(id + TASK_DEFAULT_LANG);
	set_task(2.0, "TaskDefaultLang", id + TASK_DEFAULT_LANG);

	if (!g_hSqlTuple || is_user_bot(id) || is_user_hltv(id))
		return;
	TryLoadOwned(id);
}

// 默认英语: 只在玩家还没被识别/手动选择过语言时生效, 不覆盖玩家自己的选择
public TaskDefaultLang(taskid) {
	new id = taskid - TASK_DEFAULT_LANG;
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return;

	// 语言核心已经识别成非简体(繁中/英语/俄语)时不动
	if (HnsLang_GetPlayer(id) != HNS_LANG_ZH)
		return;

	new szLang[16];
	get_user_info(id, "lang", szLang, charsmax(szLang));
	strtolower(szLang);

	// 客户端明确是中文的保持中文; 英语/俄语核心已处理; 其余(含空/未知)默认切英语
	if (equal(szLang, "cn") || equal(szLang, "zh") || containi(szLang, "schinese") != -1
		|| equal(szLang, "tw") || equal(szLang, "zh_tw") || containi(szLang, "tchinese") != -1
		|| equal(szLang, "en") || equal(szLang, "ru"))
		return;

	HnsLang_Set(id, HNS_LANG_EN);
}

TryLoadOwned(id) {
	if (!is_user_connected(id) || !g_hSqlTuple || is_user_bot(id) || is_user_hltv(id))
		return;

	new szLive[MAX_AUTHID_LENGTH], szCached[MAX_AUTHID_LENGTH];
	get_user_authid(id, szLive, charsmax(szLive));
	LookupAuthByIp(id, szCached, charsmax(szCached));
	// 盗版不等 SteamID, 直接按 IP 读. 正版还是 PENDING 时继续等
	if (IsRealSteam(id) && IsPendingAuth(szLive) && !IsSteamAuth(g_szAuth[id]) && !IsSteamAuth(szCached) && g_iAuthRetry[id] < 15) {
		ScheduleAuthRetry(id);
		return;
	}

	new szOld[MAX_AUTHID_LENGTH], szAuth[MAX_AUTHID_LENGTH];
	copy(szOld, charsmax(szOld), g_szAuth[id]);
	GetPlayerAuth(id, szAuth, charsmax(szAuth));
	if (!szAuth[0]) {
		ScheduleAuthRetry(id);
		return;
	}

	// SteamID 没变且已经读过库: 只重新贴模型, 不要 ClearOwned
	if (equal(szOld, szAuth) && g_Owned[id] && g_bOwnedLoaded[id]) {
		RefreshPlayerSkin(id);
		ScheduleKnifeReapply(id);
		return;
	}

	remove_task(id + TASK_AUTH_RETRY);
	g_iAuthRetry[id] = 0;
	g_bOwnedLoaded[id] = false;
	g_iLoadGen[id]++;
	copy(g_szAuth[id], charsmax(g_szAuth[]), szAuth);
	Db_LoadOwned(id, szAuth);
}

ScheduleAuthRetry(id) {
	if (!is_user_connected(id))
		return;
	remove_task(id + TASK_AUTH_RETRY);
	if (g_iAuthRetry[id] >= 15)
		return;
	set_task(0.5, "TaskAuthRetry", id + TASK_AUTH_RETRY);
}

public TaskAuthRetry(taskid) {
	new id = taskid - TASK_AUTH_RETRY;
	if (!is_user_connected(id))
		return;

	new szLive[MAX_AUTHID_LENGTH];
	get_user_authid(id, szLive, charsmax(szLive));
	if (IsRealSteam(id) && IsSteamAuth(szLive)) {
		g_iAuthRetry[id] = 0;
		TryLoadOwned(id);
		return;
	}
	if (!IsRealSteam(id)) {
		g_iAuthRetry[id] = 0;
		TryLoadOwned(id);
		return;
	}

	g_iAuthRetry[id]++;
	if (g_iAuthRetry[id] < 15) {
		set_task(0.5, "TaskAuthRetry", taskid);
		return;
	}

	// 一直拿不到 SteamID 才退回 LAN:IP, 避免换图瞬间用空账号把皮肤冲掉
	TryLoadOwned(id);
}

public client_disconnected(id) {
	g_pendingGiveTeam[id] = 0;
	g_pendingTarget[id] = 0;
	g_pendingAdmin[id] = 0;
	g_pendingMode[id][0] = 0;
	g_iBrowseTeam[id] = 0;
	g_legacyPendingAdmin[id] = 0;
	g_iLoadGen[id]++;
	StopPlaytimeTrack(id, true);
	RememberAuthByIp(id, g_szAuth[id]);
	g_szAuth[id][0] = EOS;
	ClearOwned(id);
	g_bOwnedLoaded[id] = false;
	g_iLastTeam[id] = 0;
	g_szAppliedTeam[id] = 0;
	g_szAppliedKey[id][0] = EOS;
	g_CurT[id][0] = EOS;
	g_CurC[id][0] = EOS;
	g_iCurKnife[id] = 0;
	g_NadeSmoke[id][0] = EOS;
	g_NadeFlash[id][0] = EOS;
	g_iKnifePage[id] = 0;
	g_iKnifeRetry[id] = 0;
	g_iAuthRetry[id] = 0;
	g_bApplyingKnife[id] = false;
	g_flShopKeep[id] = 0.0;
	remove_task(id + TASK_REAPPLY_KNIFE);
	remove_task(id + TASK_AUTH_RETRY);
	g_iBrowsePage[id] = 0;
	g_iNadePage[id] = 0;
	g_iNadeKindPage[id] = -1;
	g_iShopMenu[id] = 0;
	g_iShopPage[id] = 0;
	g_iShopKind[id] = -1;
	remove_task(id + TASK_APPLY_NADE);
	remove_task(id + TASK_MENU_SHOP);
	g_iLastCheckin[id] = 0;
	g_iPlayRemain[id] = 0;
	g_flPlayStart[id] = 0.0;
	g_bRewardLoaded[id] = false;
}

RefundGold(id, iPaid) {
	if (iPaid <= 0 || !is_user_connected(id))
		return;
	hns_gc_set_player(id, hns_gc_get_player(id) + iPaid);
	SkinChat(id, print_team_red, "SKIN_CHAT_REFUND", "数据库写入失败, 已退回 ^3%d^1 金币", iPaid);
}

public SqlHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queueTime) {
	new id = data[1];
	new iPaid = data[2];
	new iGen = data[3];
	new szAuth[MAX_AUTHID_LENGTH];
	copy(szAuth, charsmax(szAuth), data[4]);

	if (failstate != TQUERY_SUCCESS) {
		log_amx("[Skin] SQL错误(%d): %s", errnum, error);
		g_bSqlReady = false;
		g_iSqlLastErr = errnum;
		copy(g_szSqlLastErr, charsmax(g_szSqlLastErr), error);
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "query");
		if ((data[0] == QT_BUY_SKIN || data[0] == QT_UPGRADE_SKIN) && SameAuth(id, szAuth) && iGen == g_iLoadGen[id])
			RefundGold(id, iPaid);
		if ((data[0] == QT_SQL_PING || data[0] == QT_SQL_COUNT) && is_user_connected(id)) {
			SkinChat(id, print_team_red, "SKIN_CHAT_SQL_ERR", "MySQL失败(%d): %s", errnum, error);
			MenuSqlDebug(id);
		}
		return PLUGIN_HANDLED;
	}

	if (data[0] == QT_SQL_PING) {
		g_bSqlReady = true;
		g_iSqlLastErr = 0;
		g_szSqlLastErr[0] = EOS;
		copy(g_szSqlStatus, charsmax(g_szSqlStatus), "ok");
		if (is_user_connected(id)) {
			SkinChat(id, print_team_blue, "SKIN_CHAT_SQL_OK", "MySQL 连接正常");
			MenuSqlDebug(id);
		}
		return PLUGIN_HANDLED;
	}

	if (data[0] == QT_SQL_COUNT) {
		g_bSqlReady = true;
		g_iSqlOwnedCount = SQL_ReadResult(query, 0);
		g_iSqlCurrentCount = SQL_ReadResult(query, 1);
		if (is_user_connected(id)) {
			SkinChat(id, print_team_blue, "SKIN_CHAT_SQL_COUNTED", "拥有 %d 条, 当前选用 %d 条", g_iSqlOwnedCount, g_iSqlCurrentCount);
			MenuSqlDebug(id);
		}
		return PLUGIN_HANDLED;
	}

	if (!SameAuth(id, szAuth) || iGen != g_iLoadGen[id])
		return PLUGIN_HANDLED;

	switch (data[0]) {
		case QT_LOAD_OWNED: {
			ClearOwned(id);
			g_Owned[id] = ArrayCreate(SKIN_KEY_MAX);
			g_OwnedExpire[id] = TrieCreate();
			new now = get_systime();
			while (SQL_MoreResults(query)) {
				new key[SKIN_KEY_MAX];
				SQL_ReadResult(query, 0, key, charsmax(key));
				new exp = SQL_ReadResult(query, 1);
				// 已过期的租期记录: 不算拥有, 顺手清掉库里的
				if (exp != 0 && exp <= now) {
					Db_RemoveOwned(id, szAuth, key);
					SQL_NextRow(query);
					continue;
				}
				ArrayPushString(g_Owned[id], key);
				TrieSetCell(g_OwnedExpire[id], key, exp);
				SQL_NextRow(query);
			}
			g_bOwnedLoaded[id] = true;
			Db_LoadCurrent(id, szAuth);
		}
		case QT_LOAD_CURRENT: {
			g_CurT[id][0] = EOS;
			g_CurC[id][0] = EOS;
			g_NadeSmoke[id][0] = EOS;
			g_NadeFlash[id][0] = EOS;
			g_iCurKnife[id] = 0;
			// 线程查询 FieldNameToNum 常返回 -1, 按 SELECT team, model_key 列序读
			if (SQL_NumColumns(query) >= 2) {
				while (SQL_MoreResults(query)) {
					new szTeam[2];
					SQL_ReadResult(query, 0, szTeam, charsmax(szTeam));
					if (szTeam[0] == TEAM_CHAR_T)
						SQL_ReadResult(query, 1, g_CurT[id], charsmax(g_CurT[]));
					else if (szTeam[0] == TEAM_CHAR_C)
						SQL_ReadResult(query, 1, g_CurC[id], charsmax(g_CurC[]));
					else if (szTeam[0] == 'S')
						SQL_ReadResult(query, 1, g_NadeSmoke[id], charsmax(g_NadeSmoke[]));
					else if (szTeam[0] == 'F')
						SQL_ReadResult(query, 1, g_NadeFlash[id], charsmax(g_NadeFlash[]));
					else if (szTeam[0] == 'K') {
						new szKnifeKey[SKIN_KEY_MAX];
						SQL_ReadResult(query, 1, szKnifeKey, charsmax(szKnifeKey));
						if (szKnifeKey[0] && containi(szKnifeKey, "knife:") == 0)
							g_iCurKnife[id] = str_to_num(szKnifeKey[6]);
					}
					SQL_NextRow(query);
				}
			}
			RefreshPlayerSkin(id);
			ReapplyKnife(id);
			ScheduleKnifeReapply(id);
			ScheduleHeldNadeApply(id);
		}
	}

	return PLUGIN_HANDLED;
}

public Cl_Cmd(id) {
	new szArg[64];
	read_argv(0, szArg, charsmax(szArg));

	if (containi(szArg, "/cpm") != -1 || containi(szArg, "/giveskin") != -1) {
		if (IsSkinAdmin(id))
			MenuAdmin(id);
		else
			SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有管理权限");
	} else {
		MenuSkin(id);
	}
	return PLUGIN_HANDLED;
}

public SkinHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);

	if (equal(szInfo, "char"))
		MenuCharShop(id);
	else if (equal(szInfo, "knife"))
		MenuKnives(id);
	else if (equal(szInfo, "nade"))
		MenuNades(id);
	else if (equal(szInfo, "smoke"))
		MenuSmokeColor(id);
	else if (equal(szInfo, "ogbic")) {
		if (CanGrantOnlineGbic(id))
			MenuOnlineGbic(id);
		else {
			SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放权限");
			MenuSkin(id);
		}
	}
	else if (equal(szInfo, "gold"))
		MenuGold(id);
	else if (equal(szInfo, "checkin")) {
		DoDailyCheckin(id);
		MenuSkin(id);
	}
	else if (equal(szInfo, "buy"))
		MenuBuyGold(id);
	else if (equal(szInfo, "clear"))
		MenuClearSkins(id);
	else if (equal(szInfo, "sql")) {
		if (IsSkinSqlAdmin(id))
			MenuSqlDebug(id);
		else {
			SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有 SQL 调试权限");
			MenuSkin(id);
		}
	} else if (equal(szInfo, "admin")) {
		if (IsSkinAdmin(id))
			MenuAdmin(id);
		else {
			SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有管理权限");
			MenuSkin(id);
		}
	} else
		MenuSkin(id);
	return PLUGIN_HANDLED;
}

public CharShopHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (equal(szInfo, "ct"))
		MenuBrowseSkins(id, TEAM_CHAR_C);
	else if (equal(szInfo, "tt"))
		MenuBrowseSkins(id, TEAM_CHAR_T);
	else
		MenuCharShop(id);
	return PLUGIN_HANDLED;
}

public BuyGoldHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuSkin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (equal(szInfo, "open") && g_szBuyGoldUrl[0])
		show_motd(id, g_szBuyGoldUrl, "GBIC");
	else if (g_szBuyGoldText[0])
		SkinChat(id, print_team_default, "SKIN_CHAT_BUY_GOLD", "%s", g_szBuyGoldText);
	else
		SkinChat(id, print_team_default, "SKIN_CHAT_BUY_GOLD", "请联系管理员购买 GBIC 点数");
	MenuBuyGold(id);
	return PLUGIN_HANDLED;
}

RefreshKnifeNames(id, menu) {
	new szItem[160], szName[MAX_NAME_LENGTH], szInfo[12], access, callback, name[2], price;
	new selectedKnife = g_iCurKnife[id] ? g_iCurKnife[id] : crxknives_get_user_knife(id);
	new count = menu_items(menu);
	for (new i = 0; i < count; i++) {
		menu_item_getinfo(menu, i, access, szInfo, charsmax(szInfo), name, charsmax(name), callback);
		if (!szInfo[0] || equal(szInfo, "none"))
			continue;
		new knife = str_to_num(szInfo);
		if (!IsKnifeShopItemValid(knife))
			continue;
		KnifeInfo(knife, szName, charsmax(szName), price);
		FormatShopItem(id, szItem, charsmax(szItem), szName, (knife < g_iKnifeFree || IsKnifeOwned(id, knife)), price, knife == selectedKnife);
		menu_item_setname(menu, i, szItem);
	}
}

public KnifeHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		if (KeepShopMenu(id)) {
			menu_display(id, menu, g_iKnifePage[id]);
			return PLUGIN_HANDLED;
		}
		menu_destroy(menu);
		OpenShopLater(id, SHOP_MENU_SKIN);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	new page = item / SKIN_PER_PAGE;
	g_iKnifePage[id] = page;
	if (!equal(szInfo, "none")) {
		new knife = str_to_num(szInfo);
		if (IsKnifeOwned(id, knife)) {
			SelectKnife(id, knife);
			MarkShopKeep(id);
			RefreshKnifeNames(id, menu);
			menu_display(id, menu, page);
		} else {
			menu_destroy(menu);
			MenuConfirmKnifeBuy(id, knife, page);
		}
	} else {
		MarkShopKeep(id);
		menu_display(id, menu, 0);
	}
	return PLUGIN_HANDLED;
}

public KnifeConfirmHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		OpenShopLater(id, SHOP_MENU_KNIFE, g_iKnifePage[id]);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (!equal(szInfo, "cancel"))
		DoBuyKnife(id, str_to_num(szInfo));
	OpenShopLater(id, SHOP_MENU_KNIFE, g_iKnifePage[id]);
	return PLUGIN_HANDLED;
}

public ViewOwnedHandler(id, menu, item) {
	menu_destroy(menu);
	MenuAdmin(id);
	return PLUGIN_HANDLED;
}

public GiveSkinHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[12], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (!CanSkinTarget(id, g_pendingTarget[id])) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "管理员只能操作自己的皮肤");
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	if (!equal(szInfo, "none") && is_user_connected(g_pendingTarget[id])) {
		// info 形如 "<idx>"(角色皮肤) / "k<idx>"(刀皮) / "n<idx>"(投掷物皮肤)
		if (szInfo[0] == 'k')
			GiveKnifeTo(g_pendingTarget[id], str_to_num(szInfo[1]));
		else if (szInfo[0] == 'n')
			GiveNadeTo(g_pendingTarget[id], str_to_num(szInfo[1]));
		else
			GiveSkinTo(g_pendingTarget[id], str_to_num(szInfo));
	}
	MenuAdmin(id);
	return PLUGIN_HANDLED;
}

public RemoveSkinHandler(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	new szInfo[SKIN_KEY_MAX], access, callback;
	menu_item_getinfo(menu, item, access, szInfo, charsmax(szInfo), _, _, callback);
	menu_destroy(menu);
	if (!CanSkinTarget(id, g_pendingTarget[id])) {
		SkinChat(id, print_team_red, "SKIN_CHAT_NO_ADMIN", "管理员只能操作自己的皮肤");
		MenuAdmin(id);
		return PLUGIN_HANDLED;
	}
	RemoveSkinFrom(g_pendingTarget[id], szInfo);
	MenuAdmin(id);
	return PLUGIN_HANDLED;
}

public hns_give_skin_menu_public(admin, target, type) {
	g_legacyPendingAdmin[target] = admin;
	if (!is_user_connected(admin) || !IsSkinOwner(admin)) {
		if (is_user_connected(admin))
			SkinChat(admin, print_team_red, "SKIN_CHAT_NO_ADMIN", "你没有发放皮肤权限");
		return PLUGIN_HANDLED;
	}
	if (!is_user_connected(target)) {
		SkinChat(admin, print_team_red, "SKIN_CHAT_TARGET_GONE", "目标玩家已离开");
		return PLUGIN_HANDLED;
	}
	if (!CanSkinTarget(admin, target)) {
		SkinChat(admin, print_team_red, "SKIN_CHAT_NO_ADMIN", "管理员只能操作自己的皮肤");
		return PLUGIN_HANDLED;
	}
	if (type == 3) {
		new given = GiveAllKnivesTo(target);
		SkinChat(admin, print_team_default, "SKIN_CHAT_GIVE_ALL_KNIFE", "已向 %n 发放全部刀皮 (%d款)", target, given);
		return PLUGIN_HANDLED;
	}
	if (type == 4) {
		new given = GiveAllNadesTo(target);
		SkinChat(admin, print_team_default, "SKIN_CHAT_GIVE_ALL_NADE", "已向 %n 发放全部投掷物皮肤 (%d款)", target, given);
		return PLUGIN_HANDLED;
	}
	g_pendingGiveTeam[admin] = (type == 1) ? TEAM_CHAR_T : TEAM_CHAR_C;
	MenuGiveSkin(admin, target);
	return PLUGIN_HANDLED;
}

public hns_give_all_skins_public(target, type) {
	if (!is_user_connected(target))
		return PLUGIN_HANDLED;
	if (!g_legacyPendingAdmin[target] || !is_user_connected(g_legacyPendingAdmin[target]) || !CanSkinTarget(g_legacyPendingAdmin[target], target))
		return PLUGIN_HANDLED;
	if (type == 3) {
		new given = GiveAllKnivesTo(target);
		if (g_legacyPendingAdmin[target] && is_user_connected(g_legacyPendingAdmin[target]))
			SkinChat(g_legacyPendingAdmin[target], print_team_default, "SKIN_CHAT_GIVE_ALL_KNIFE", "已向 %n 发放全部刀皮 (%d款)", target, given);
		return PLUGIN_HANDLED;
	}
	if (type == 4) {
		new given = GiveAllNadesTo(target);
		if (g_legacyPendingAdmin[target] && is_user_connected(g_legacyPendingAdmin[target]))
			SkinChat(g_legacyPendingAdmin[target], print_team_default, "SKIN_CHAT_GIVE_ALL_NADE", "已向 %n 发放全部投掷物皮肤 (%d款)", target, given);
		return PLUGIN_HANDLED;
	}
	new teamChar = (type == 1) ? TEAM_CHAR_T : TEAM_CHAR_C;
	new given = GiveAllSkinsTo(target, teamChar);
	if (g_legacyPendingAdmin[target] && is_user_connected(g_legacyPendingAdmin[target])) {
		new szTeam[16];
		SkinTeamShort(g_legacyPendingAdmin[target], teamChar, szTeam, charsmax(szTeam));
		SkinChat(g_legacyPendingAdmin[target], print_team_default, "SKIN_CHAT_GIVE_ALL_TEAM", "已向 %n 发放全部%s皮肤 (%d款)", target, szTeam, given);
	}
	return PLUGIN_HANDLED;
}

public hns_clear_skins_public(target) {
	if (!is_user_connected(target))
		return PLUGIN_HANDLED;
	new removed = ClearAllSkinsFrom(target);
	if (g_legacyPendingAdmin[target] && is_user_connected(g_legacyPendingAdmin[target]))
		SkinChat(g_legacyPendingAdmin[target], print_team_default, "SKIN_CHAT_CLEARED", "已清除 %n 的全部皮肤 (%d款)", target, removed);
	return PLUGIN_HANDLED;
}

new bool:g_bGrantSchema;

Handle:OpenSkinConn() {
	if (g_hSqlTuple == Empty_Handle)
		return Empty_Handle;
	new iErr, szErr[128];
	new Handle:conn = SQL_Connect(g_hSqlTuple, iErr, szErr, charsmax(szErr));
	if (conn == Empty_Handle)
		log_amx("[HnsSkin] SQL connect failed: %s", szErr);
	return conn;
}

EnsureGrantSchema(Handle:conn) {
	if (g_bGrantSchema || conn == Empty_Handle)
		return;
	new szCreate[512];
	if (g_bLocalDb)
		formatex(szCreate, charsmax(szCreate), "CREATE TABLE IF NOT EXISTS %s (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid VARCHAR(64) NOT NULL, skin_key VARCHAR(32) NOT NULL, action VARCHAR(8) NOT NULL DEFAULT 'give', status INT NOT NULL DEFAULT 0, note VARCHAR(128) NOT NULL DEFAULT '', created INT NOT NULL DEFAULT 0, done_at INT NOT NULL DEFAULT 0)", GRANT_TABLE);
	else
		formatex(szCreate, charsmax(szCreate), "CREATE TABLE IF NOT EXISTS %s (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, steamid VARCHAR(64) NOT NULL, skin_key VARCHAR(32) NOT NULL, action VARCHAR(8) NOT NULL DEFAULT 'give', status TINYINT NOT NULL DEFAULT 0, note VARCHAR(128) NOT NULL DEFAULT '', created INT NOT NULL DEFAULT 0, done_at INT NOT NULL DEFAULT 0, KEY idx_status (status, id)) ENGINE=InnoDB DEFAULT CHARSET=utf8", GRANT_TABLE);
	SQL_ExecSync(conn, "%s", szCreate);
	new szAlter[160];
	formatex(szAlter, charsmax(szAlter), "ALTER TABLE %s ADD COLUMN steamid VARCHAR(64) NOT NULL DEFAULT ''", OWNS_TABLE);
	SQL_ExecSync(conn, "%s", szAlter);
	g_bGrantSchema = true;
}

bool:NormalizeGrantSteam(const raw[], authid[], authLen, steamid[], steamLen) {
	new sz[64];
	copy(sz, charsmax(sz), raw);
	trim(sz);
	remove_quotes(sz);
	if (!sz[0] || IsPendingAuth(sz))
		return false;
	if (equali(sz, "STEAM:", 6)) {
		copy(steamid, steamLen, sz[6]);
		trim(steamid);
		if (!steamid[0])
			return false;
		copy(authid, authLen, sz);
		return true;
	}
	if (equali(sz, "NAME:", 5)) {
		copy(authid, authLen, sz);
		copy(steamid, steamLen, sz);
		return true;
	}
	if (equali(sz, "STEAM_", 6) || equali(sz, "VALVE_", 6)) {
		formatex(authid, authLen, "STEAM:%s", sz);
		copy(steamid, steamLen, sz);
		return true;
	}
	return false;
}

FindPlayerByAuth(const authid[]) {
	if (!authid[0])
		return 0;
	for (new i = 1; i <= MaxClients; i++) {
		if (!is_user_connected(i) || is_user_hltv(i))
			continue;
		new szAuth[MAX_AUTHID_LENGTH];
		GetPlayerAuth(i, szAuth, charsmax(szAuth));
		if (szAuth[0] && equal(szAuth, authid))
			return i;
	}
	return 0;
}

GiveKeyMemory(id, const key[]) {
	if (!is_user_connected(id) || !key[0])
		return;
	if (equal(key, "knife:", 6)) {
		GiveKnifeTo(id, str_to_num(key[6]));
		return;
	}
	if (equal(key, "nade:", 5)) {
		for (new i = 0; i < g_iNadeSize; i++) {
			new row[nade_e];
			ArrayGetArray(g_pNade, i, row, sizeof row);
			if (equal(row[nade_key], key[5])) {
				GiveNadeTo(id, i);
				return;
			}
		}
		return;
	}
	new idx = PoolIndexOf(key);
	if (idx != -1)
		GiveSkinTo(id, idx, true);
}

TakeKeyMemory(id, const key[]) {
	if (is_user_connected(id) && key[0])
		RemoveSkinFrom(id, key, true);
}

ClearPlayerMemory(id) {
	if (!is_user_connected(id))
		return;
	if (g_Owned[id])
		ArrayClear(g_Owned[id]);
	if (g_OwnedExpire[id])
		TrieClear(g_OwnedExpire[id]);
	g_CurT[id][0] = EOS;
	g_CurC[id][0] = EOS;
	g_NadeSmoke[id][0] = EOS;
	g_NadeFlash[id][0] = EOS;
	g_iCurKnife[id] = 0;
	crxknives_select_knife(id, 0);
	ApplyCurrentSkin(id);
}

SqlInsertOwned(Handle:conn, const authid[], const steamid[], const key[]) {
	new szAuth[MAX_AUTHID_LENGTH * 2], szSteam[96], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(steamid, szSteam, charsmax(szSteam));
	EscapeSql(key, szKey, charsmax(szKey));
	new iNow = get_systime();
	if (g_bLocalDb)
		SQL_ExecSync(conn, "INSERT OR REPLACE INTO %s (authid, model_key, bought_at, expire_at, steamid) VALUES ('%s','%s',%d,0,'%s')", OWNS_TABLE, szAuth, szKey, iNow, szSteam);
	else
		SQL_ExecSync(conn, "INSERT INTO %s (authid, model_key, bought_at, expire_at, steamid) VALUES ('%s','%s',%d,0,'%s') ON DUPLICATE KEY UPDATE expire_at=0, steamid='%s'", OWNS_TABLE, szAuth, szKey, iNow, szSteam, szSteam);
}
SqlDeleteOwned(Handle:conn, const authid[], const key[]) {
	new szAuth[MAX_AUTHID_LENGTH * 2], szKey[SKIN_KEY_MAX * 2];
	EscapeSql(authid, szAuth, charsmax(szAuth));
	EscapeSql(key, szKey, charsmax(szKey));
	SQL_ExecSync(conn, "DELETE FROM %s WHERE authid='%s' AND model_key='%s'", OWNS_TABLE, szAuth, szKey);
	SQL_ExecSync(conn, "DELETE FROM %s WHERE authid='%s' AND model_key='%s'", CUR_TABLE, szAuth, szKey);
}

new g_szGrantKeys[256][SKIN_KEY_MAX];

CollectGrantKeys(const spec[]) {
	new n, maxKeys = sizeof g_szGrantKeys;
	if (!spec[0])
		return 0;
	if (equali(spec, "all") || equali(spec, "*")) {
		for (new i = 0; i < g_iPoolSize && n < maxKeys; i++) {
			new row[pool_e];
			ArrayGetArray(g_pPool, i, row, sizeof row);
			if (row[pool_key][0])
				copy(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), row[pool_key]);
		}
		for (new knife = 0; knife < crxknives_get_knives_num() && n < maxKeys; knife++)
			formatex(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), "knife:%d", knife);
		for (new i = 0; i < g_iNadeSize && n < maxKeys; i++) {
			new row[nade_e];
			ArrayGetArray(g_pNade, i, row, sizeof row);
			if (row[nade_key][0])
				formatex(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), "nade:%s", row[nade_key]);
		}
		return n;
	}
	if (equali(spec, "all_t") || equali(spec, "all_c")) {
		new team = equali(spec, "all_t") ? TEAM_CHAR_T : TEAM_CHAR_C;
		for (new i = 0; i < g_iPoolSize && n < maxKeys; i++) {
			new row[pool_e];
			ArrayGetArray(g_pPool, i, row, sizeof row);
			if (row[pool_team] == team && row[pool_key][0])
				copy(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), row[pool_key]);
		}
		return n;
	}
	if (equali(spec, "all_knife")) {
		for (new knife = 0; knife < crxknives_get_knives_num() && n < maxKeys; knife++)
			formatex(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), "knife:%d", knife);
		return n;
	}
	if (equali(spec, "all_nade")) {
		for (new i = 0; i < g_iNadeSize && n < maxKeys; i++) {
			new row[nade_e];
			ArrayGetArray(g_pNade, i, row, sizeof row);
			if (row[nade_key][0])
				formatex(g_szGrantKeys[n++], charsmax(g_szGrantKeys[]), "nade:%s", row[nade_key]);
		}
		return n;
	}
	copy(g_szGrantKeys[0], charsmax(g_szGrantKeys[]), spec);
	return 1;
}

ApplyGrantSpec(Handle:conn, const rawSteam[], const spec[], const action[], note[], noteLen) {
	new szAuth[MAX_AUTHID_LENGTH], szSteam[64];
	if (!NormalizeGrantSteam(rawSteam, szAuth, charsmax(szAuth), szSteam, charsmax(szSteam))) {
		copy(note, noteLen, "SteamID 不正确");
		return -1;
	}
	new target = FindPlayerByAuth(szAuth);
	new bool:bTake = equali(action, "take");
	if (equali(action, "clear") || equali(spec, "*")) {
		new szEsc[MAX_AUTHID_LENGTH * 2];
		EscapeSql(szAuth, szEsc, charsmax(szEsc));
		new n;
		new Handle:q = SQL_PrepareQuery(conn, "SELECT COUNT(*) FROM %s WHERE authid='%s'", OWNS_TABLE, szEsc);
		if (q != Empty_Handle && SQL_Execute(q) && SQL_MoreResults(q))
			n = SQL_ReadResult(q, 0);
		if (q != Empty_Handle)
			SQL_FreeHandle(q);
		SQL_ExecSync(conn, "DELETE FROM %s WHERE authid='%s'", OWNS_TABLE, szEsc);
		SQL_ExecSync(conn, "DELETE FROM %s WHERE authid='%s'", CUR_TABLE, szEsc);
		if (target)
			ClearPlayerMemory(target);
		formatex(note, noteLen, "已清除 %s 的皮肤 (%d款)", szSteam, n);
		return n;
	}
	new n = CollectGrantKeys(spec);
	if (n <= 0) {
		copy(note, noteLen, "没有匹配的皮肤");
		return -1;
	}
	for (new i = 0; i < n; i++) {
		if (bTake) {
			SqlDeleteOwned(conn, szAuth, g_szGrantKeys[i]);
			if (target)
				TakeKeyMemory(target, g_szGrantKeys[i]);
		} else {
			SqlInsertOwned(conn, szAuth, szSteam, g_szGrantKeys[i]);
			if (target)
				GiveKeyMemory(target, g_szGrantKeys[i]);
		}
	}
	formatex(note, noteLen, "%s %s %s (%d款)", bTake ? "已收回" : "已发放", szSteam, spec, n);
	return n;
}

LogGrantRow(Handle:conn, const steamid[], const spec[], const action[], status, const note[]) {
	new szSteam[96], szSpec[SKIN_KEY_MAX * 2], szNote[160];
	EscapeSql(steamid, szSteam, charsmax(szSteam));
	EscapeSql(spec, szSpec, charsmax(szSpec));
	EscapeSql(note, szNote, charsmax(szNote));
	new szInsert[512];
	new iNow = get_systime();
	formatex(szInsert, charsmax(szInsert), "INSERT INTO %s (steamid, skin_key, action, status, note, created, done_at) VALUES ('%s','%s','%s',%d,'%s',%d,%d)", GRANT_TABLE, szSteam, szSpec, action, status, szNote, iNow, iNow);
	SQL_ExecSync(conn, "%s", szInsert);
}

ExecSteamGrant(const rawSteam[], const spec[], bool:bRemove, admin, note[], noteLen) {
	new Handle:conn = OpenSkinConn();
	if (conn == Empty_Handle) {
		copy(note, noteLen, "数据库未连接");
		return -1;
	}
	EnsureGrantSchema(conn);
	new ret = ApplyGrantSpec(conn, rawSteam, spec, bRemove ? "take" : "give", note, noteLen);
	new szAuth[MAX_AUTHID_LENGTH], szSteam[64];
	if (NormalizeGrantSteam(rawSteam, szAuth, charsmax(szAuth), szSteam, charsmax(szSteam)))
		LogGrantRow(conn, szSteam, spec, bRemove ? "take" : "give", ret < 0 ? 2 : 1, note);
	SQL_FreeHandle(conn);
	if (admin)
		log_amx("[HnsSkin] grant %s %s %s -> %s", bRemove ? "take" : "give", rawSteam, spec, note);
	return ret;
}

ExecSteamClear(const rawSteam[], admin, note[], noteLen, bool:bLog) {
	new Handle:conn = OpenSkinConn();
	if (conn == Empty_Handle) {
		copy(note, noteLen, "数据库未连接");
		return -1;
	}
	EnsureGrantSchema(conn);
	new ret = ApplyGrantSpec(conn, rawSteam, "*", "clear", note, noteLen);
	new szAuth[MAX_AUTHID_LENGTH], szSteam[64];
	if (bLog && NormalizeGrantSteam(rawSteam, szAuth, charsmax(szAuth), szSteam, charsmax(szSteam)))
		LogGrantRow(conn, szSteam, "*", "clear", ret < 0 ? 2 : 1, note);
	SQL_FreeHandle(conn);
	if (admin)
		log_amx("[HnsSkin] clear %s -> %s", rawSteam, note);
	return ret;
}

public CmdAmxClearSkin(id) {
	if (!cmd_access(id, ADMIN_IMMUNITY, 0, 0))
		return PLUGIN_HANDLED;
	if (read_argc() < 2) {
		GrantTell(id, "用法: amx_clearskin <steamid>");
		return PLUGIN_HANDLED;
	}
	new szSteam[40], note[96];
	read_argv(1, szSteam, charsmax(szSteam));
	ExecSteamClear(szSteam, id, note, charsmax(note), true);
	GrantTell(id, note);
	return PLUGIN_HANDLED;
}

GrantTell(id, const msg[]) {
	if (id && is_user_connected(id))
		client_print(id, print_console, "%s", msg);
	else
		server_print("[HnsSkin] %s", msg);
}

public TaskGrantPoll() {
	new Handle:conn = OpenSkinConn();
	if (conn == Empty_Handle)
		return;
	EnsureGrantSchema(conn);
	new Handle:q = SQL_PrepareQuery(conn, "SELECT id, steamid, skin_key, action FROM %s WHERE status=0 ORDER BY id LIMIT 12", GRANT_TABLE);
	new iIds[12], szSteam[12][64], szKey[12][36], szAct[12][12], n;
	if (q != Empty_Handle && SQL_Execute(q)) {
		while (SQL_MoreResults(q) && n < 12) {
			iIds[n] = SQL_ReadResult(q, 0);
			SQL_ReadResult(q, 1, szSteam[n], charsmax(szSteam[]));
			SQL_ReadResult(q, 2, szKey[n], charsmax(szKey[]));
			SQL_ReadResult(q, 3, szAct[n], charsmax(szAct[]));
			n++;
			SQL_NextRow(q);
		}
	}
	if (q != Empty_Handle)
		SQL_FreeHandle(q);
	for (new i = 0; i < n; i++) {
		new note[96];
		new ret = ApplyGrantSpec(conn, szSteam[i], szKey[i], szAct[i][0] ? szAct[i] : "give", note, charsmax(note));
		new szNote[160];
		EscapeSql(note, szNote, charsmax(szNote));
		SQL_ExecSync(conn, "UPDATE %s SET status=%d, note='%s', done_at=%d WHERE id=%d", GRANT_TABLE, ret < 0 ? 2 : 1, szNote, get_systime(), iIds[i]);
	}
	SQL_FreeHandle(conn);
}