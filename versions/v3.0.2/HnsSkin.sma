/*
 * HnsSkin+IC v3.0.0
 * 皮肤系统 × IC 积分系统 融合版
 *
 * 功能:
 *   - 多类型皮肤: 人物(T/CT)、刀、USP、烟雾弹、闪光弹
 *   - 共享皮肤模式 (CT/T 共用人物皮肤)
 *   - 管理员发放/收回皮肤
 *   - IC 积分兑换与发放, 提供 ic_add_points/ic_get_points 接口
 *   - 存档: nvault 本地, 可选 MySQL 云端
 *
 * 命令:
 *   玩家: /skin /skin_t /skin_ct /skin_knife /skin_usp /ic
 *   管理员: /givetic /giveallskins /giveskin /giveskinid /take
 *
 * 依赖: amxmodx / fakemeta / amxmisc / reapi / hamsandwich / nvault
 */

#include <amxmodx>
#include <fakemeta>
#include <amxmisc>
#include <reapi>
#include <nvault>
#include <hamsandwich>
#include <engine>

// 云端存档(MySQL/sqlx)，默认关闭。未配置 mysql 模块时自动回退本地 nvault。
// 开启云端同步: 取消注释下行，并安装 AMXX sqlx/mysql 模块、配置 configs/mysql.ini 后重新编译。
//   #define SKINSYS_ENABLE_MYSQL
#if defined SKINSYS_ENABLE_MYSQL
    #tryinclude <sqlx>
    #if defined _sqlx_included
        #define SKINSYS_SQLX 1
    #else
        #define SKINSYS_SQLX 0
    #endif
#else
    #define SKINSYS_SQLX 0
#endif

#if SKINSYS_SQLX == 1
    new Handle:g_hSqlTuple = Empty_Handle;   // sqlx 连接元组 (Empty_Handle = 未启用)
#else
    new g_hSqlTuple = 0;                     // 未启用 sqlx 时的占位
#endif
new bool:g_bSqlConnected = false;            // 是否已成功连接云端
static const SQL_TABLE[] = "skinsys_skins";

// 前向声明
stock bool:has_skin(const id, const iType, const iSkinIndex);
stock give_skin(const id, const iType, const iSkinIndex);
stock apply_model(const id);
stock parse_skin_json(const id, const szData[]);
stock ensure_default_skins(const id);

//  插件信息
#define PLUGIN_NAME "HnsSkin+IC Skin System"
#define PLUGIN_VERSION "3.0.2"
#define PLUGIN_AUTHOR "OpenSkin"

//  常量定义
#define MAX_AUTHID_LENGTH    64
#define MAX_MODEL_NAME      128
#define MAX_SKIN_NAME       64
#define MAX_OWNED_SKINS     64

// 皮肤类型编号 (与菜单/存档一致)
#define SKIN_TYPE_PERSON   0   // 人物
#define SKIN_TYPE_KNIFE    2   // 小刀
#define SKIN_TYPE_USP      3   // USP
#define SKIN_TYPE_SMOKE    4   // 烟雾弹
#define SKIN_TYPE_FLASH    5   // 闪光弹
#define MAX_MENU_PAGE       7
#define Invalid_Array       -1
#define EOS                 0

// 权限等级(保留)
#define PERM_NONE           0
#define PERM_VIP            1
#define PERM_ADMIN          2
#define PERM_OWNER          3

// 皮肤系统菜单ID
#define MENU_PLAYER_MAIN    8001
#define MENU_JOIN_TEAM      8002
#define MENU_SKIN_MAIN       8003
#define MENU_SKIN_SELECT     8004
#define MENU_GIVE_PLAYER     8007
#define MENU_GIVE_TYPE       8008
#define MENU_GIVE_SKIN       8009

// IC 点系统菜单ID(避开皮肤菜单ID)
#define MENU_IC_MAIN         8101
#define MENU_IC_REDEEM       8102
#define MENU_IC_SKINLIST     8103

// 官方认证管理员(users.ini)
#define MAX_OFFICIAL_ADMINS     64
#define MAX_AUTH_LEN            48
#define MAX_FLAG_LEN            32

//  全局变量 - 官方管理员判定
new g_szOfficialAuth[MAX_OFFICIAL_ADMINS][MAX_AUTH_LEN];
new g_iOfficialAccess[MAX_OFFICIAL_ADMINS];
new g_iOfficialAdminCount;
new bool:g_bOfficialLoaded;

//  全局变量 - 皮肤模型数组
new Array:g_aTModels;          // T模型路径
new Array:g_aTModelNames;      // T模型显示名称
new Array:g_aCTModels;         // CT模型路径
new Array:g_aCTModelNames;     // CT模型显示名称
new Array:g_aKnifeModels;      // 刀模型路径(第一人称)
new Array:g_aKnifeModelNames;  // 刀模型显示名称
new Array:g_aKnifeThirdModels; // 刀手动指定的第三人称模型路径(可为空)
new Array:g_aUSPModels;        // USP模型路径
new Array:g_aUSPModelNames;    // USP模型显示名称
new Array:g_aSmokeModels;      // 烟雾弹模型路径
new Array:g_aSmokeModelNames;  // 烟雾弹模型显示名称
new Array:g_aFlashModels;      // 闪光弹模型路径
new Array:g_aFlashModelNames;  // 闪光弹模型显示名称

// 玩家已拥有的皮肤索引数组
new g_iOwnedT[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedTCount[MAX_PLAYERS + 1];
new g_iOwnedCT[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedCTCount[MAX_PLAYERS + 1];
new g_iOwnedKnife[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedKnifeCount[MAX_PLAYERS + 1];
new g_iOwnedUSP[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedUSPCount[MAX_PLAYERS + 1];
new g_iOwnedSmoke[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedSmokeCount[MAX_PLAYERS + 1];
new g_iOwnedFlash[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedFlashCount[MAX_PLAYERS + 1];

// 玩家当前选择的皮肤索引
new g_iSelectedT[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedCT[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedKnife[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedUSP[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedSmoke[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedFlash[MAX_PLAYERS + 1] = {-1, ...};

// 共享皮肤模式(KZ): CT/T 共用同一套角色皮肤 (默认开启)
new g_pShared;

// 皮肤选择菜单临时变量
new g_iSkinSelectType[MAX_PLAYERS + 1];   // 0=T, 1=CT, 2=Knife, 3=USP
new g_iSkinSelectPage[MAX_PLAYERS + 1];

// 一次性换肤提示音开关: 玩家主动切换刀皮肤时置 true, 播一次后清零
new bool:g_bKnifeSndOn[MAX_PLAYERS + 1];

// 全局变量 - 皮肤发放
new g_iGiveTarget[MAX_PLAYERS + 1];
new g_iGiveType[MAX_PLAYERS + 1];
new g_iGivePage[MAX_PLAYERS + 1];

// 云端全量查看: 记录发起查看的管理员与当前展示页
new g_iCloudViewer;
new g_iCloudViewPage;

//  全局变量 - IC 点系统
new g_iICPoints[MAX_PLAYERS + 1];
new bool:g_bICLoaded[MAX_PLAYERS + 1];
new g_iICTargetType[MAX_PLAYERS + 1];   // 兑换时选择的皮肤类型 0=T 1=CT 2=Knife
new g_iICSkinPage[MAX_PLAYERS + 1];

new pcvar_person_pts, pcvar_knife_pts;

// 音效相关 (换肤/切刀提示音, 可在 amxx.cfg 用 skinsys_sound 设为 0 关闭)
new pcvar_sound;
#define SND_SKIN_APPLY   "weapons/knife_deploy1.wav"  // 换肤/出刀提示(CS自带, 无需额外文件)
#define SND_SKIN_PURCHASE "items/gunpickup2.wav"        // 积分兑换成功音(CS自带)
#define SND_MENU_CLICK   "buttons/button3.wav"          // 菜单选择音(CS自带)

//  全局变量 - 玩家标识
new g_szPlayerAuth[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH];
new g_szPlayerIP[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH];
new g_szPlayerName[MAX_PLAYERS + 1][32];

// nvault 句柄
new g_iVault = INVALID_HANDLE;

// 玩家自选语言 (空=简体中文, 其余: "zh-TW"/"en"/"ru")
new g_szSkinLang[MAX_PLAYERS + 1][8];
// 多语言字典 (从 lang/HnsSkin.txt 解析, 让手动切换语言生效; 不依赖 AMXX 运行时语言缓存)
static Trie:g_tLangZh = Invalid_Trie;
static Trie:g_tLangTw = Invalid_Trie;
static Trie:g_tLangEn = Invalid_Trie;
static Trie:g_tLangRu = Invalid_Trie;

//  Native 接口: 供外部系统 (如比赛系统) 对接发放/查询 IC 点
//  用法(在外部插件中):
//    #include <ic_points>
//    ic_add_points(id, 10);   // 给玩家 +10 IC 点
//    new pts = ic_get_points(id); // 查询玩家当前 IC 点
public plugin_natives() {
    register_library("HnsICPointSystem");
    register_native("ic_add_points", "native_ic_add_points");
    register_native("ic_get_points", "native_ic_get_points");
}
public native_ic_add_points(plugin_id, num_params) {
    new id = get_param(1);
    new iAmount = get_param(2);
    if (!is_user_connected(id) || iAmount <= 0) return 0;
    add_ic_points(id, iAmount);
    return 1;
}
public native_ic_get_points(plugin_id, num_params) {
    new id = get_param(1);
    if (!is_user_connected(id)) return 0;
    if (!g_bICLoaded[id]) load_player_ic(id);
    return g_iICPoints[id];
}

//  plugin_precache - 加载模型配置并预缓存
public plugin_precache() {
    load_player_models();
    precache_all_models();

    // 预缓存皮肤系统音效 (均为 CS 自带, 不存在也不影响运行)
    precache_sound(SND_SKIN_APPLY);
    precache_sound(SND_SKIN_PURCHASE);
    precache_sound(SND_MENU_CLICK);
}

//  plugin_init - 注册命令、菜单、事件
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // 注册CVAR：标记高级皮肤系统已激活
    register_cvar("skinsys_advanced", "1");

    // CVAR：共享皮肤模式 (默认开启: CT/T 共用一套人物皮肤，用于KZ服)
    g_pShared = register_cvar("skinsys_shared", "1");

    // IC 点兑换价格 (CVAR 可配置)
    pcvar_person_pts = register_cvar("ic_skin_person", "500", FCVAR_SERVER);
    pcvar_knife_pts  = register_cvar("ic_skin_knife",  "300", FCVAR_SERVER);
    pcvar_sound = register_cvar("skinsys_sound", "1");

    // 武器切换消息 — 刀/USP皮肤每次切换时重新应用
    register_message(get_user_msgid("CurWeapon"), "FM_CurWeapon");
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "Knife_Deploy_Post", true);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "USP_Deploy_Post", true);
    RegisterHam(Ham_Item_Deploy, "weapon_smokegrenade", "Smoke_Deploy_Post", true);
    RegisterHam(Ham_Item_Deploy, "weapon_flashbang", "Flash_Deploy_Post", true);
    RegisterHam(Ham_Item_Deploy, "weapon_hegrenade", "HE_Deploy_Post", true);

    // 打开 nvault 数据库 (皮肤 + IC 分共用)
    g_iVault = nvault_open("skinsys_skin_vault");

    // 注册多语言字典
    register_dictionary("HnsSkin.txt");
    // 解析语言字典到内存 (手动切换语言用)
    load_lang_entries();

    // 加载 users.ini 官方管理员认证库
    load_official_admins();

    // === 皮肤系统命令 ===
    register_clcmd("say /skin", "cmdSkinMain");
    register_clcmd("say /models", "cmdSkinMain");
    register_clcmd("say /skins", "cmdSkinMain");
    register_clcmd("say /model", "cmdSkinMain");
    register_clcmd("say_team /skin", "cmdSkinMain");
    register_clcmd("say_team /models", "cmdSkinMain");
    register_clcmd("say_team /skins", "cmdSkinMain");
    register_clcmd("say_team /model", "cmdSkinMain");

    register_clcmd("say /skin_t", "cmdSkinSelectT");
    register_clcmd("say /skin_ct", "cmdSkinSelectCT");
    register_clcmd("say /skin_knife", "cmdSkinSelectKnife");
    register_clcmd("say /skin_usp", "cmdSkinSelectUSP");
    register_clcmd("say /skin_smoke", "cmdSkinSelectSmoke");
    register_clcmd("say /skin_flash", "cmdSkinSelectFlash");

    register_clcmd("say /skinmenu", "cmdMenu");

    register_srvcmd("skinsys_giveallskins_menu", "srvCmdGiveAllSkins");
    register_srvcmd("skinsys_giveskin_menu", "srvCmdGiveSkinMenu");

    register_clcmd("say /giveallskins", "cmdGiveAllSkins");
    register_clcmd("say /giveskin", "cmdGiveSkinMenuStart");
    register_clcmd("say /giveskinmenu", "cmdGiveSkinMenuStart");
    register_clcmd("say /giveskinid", "cmdGiveSkinCmd");
    register_clcmd("say /giveoffline", "cmdGiveOffline");
    register_clcmd("say /giveofflineid", "cmdGiveOffline");
    register_clcmd("say /take", "cmdTakeSkin");
    register_clcmd("say /exportskins", "cmdExportSkins");

    // === IC 点系统命令 ===
    register_clcmd("nightvision", "cmdICMenu");
    register_clcmd("say /ic", "cmdICMenu");
    register_clcmd("say_team /ic", "cmdICMenu");
    register_clcmd("say /icpoint", "cmdICMenu");
    register_clcmd("say_team /icpoint", "cmdICMenu");

    // 管理员直接给予 IC 点
    register_clcmd("say /givetic", "cmdGiveIC");
    register_clcmd("say /giveic", "cmdGiveIC");
    register_clcmd("say /addic", "cmdGiveIC");
    register_clcmd("say_team /givetic", "cmdGiveIC");
    register_clcmd("say_team /giveic", "cmdGiveIC");
    register_clcmd("say_team /addic", "cmdGiveIC");

    // === 皮肤菜单注册 ===
    register_menucmd(register_menuid("HnsSkinMainMenu"), 1023, "handleSkinMainMenu");
    register_menucmd(register_menuid("HnsSkinLangMenu"), 1023, "handleLangMenu");
    register_menucmd(register_menuid("HnsSkinSkinSelect"), 1023, "handleSkinSelectMenu");
    register_menucmd(register_menuid("HnsSkinGiveSelectPlayer"), 1023, "handleGiveSelectPlayer");
    register_menucmd(register_menuid("HnsSkinGiveSelectType"), 1023, "handleGiveSelectType");
    register_menucmd(register_menuid("HnsSkinGiveSelectSkin"), 1023, "handleGiveSelectSkin");
    register_menucmd(register_menuid("HnsSkinGiveSelectSkinList"), 1023, "handleGiveSelectSkinList");
    register_menucmd(register_menuid("HnsMySQLTerminal"), 1023, "handleMySQLTerminalMenu");

    // === IC 点菜单注册 ===
    register_menucmd(register_menuid("HnsICMain"), (1<<0)|(1<<1)|(1<<9), "icMainHandler");
    register_menucmd(register_menuid("HnsICRedeem"), (1<<0)|(1<<1)|(1<<2)|(1<<9), "icRedeemHandler");
    register_menucmd(register_menuid("HnsICSkinList"), 511|(1<<8)|(1<<9), "icSkinListHandler");

    // === 事件注册 ===
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);
    register_event("TeamInfo", "OnTeamInfoChange", "a");

    // 确保 mixsystem 配置目录存在
    new szDir[256];
    get_localinfo("amxx_configsdir", szDir, charsmax(szDir));
    format(szDir, charsmax(szDir), "%s/mixsystem", szDir);
    if (!dir_exists(szDir)) {
        mkdir(szDir);
    }

    // 初始化云端(MySQL)后端 (自动检测, 失败则回退本地)
    sql_backend_init();

    log_amx("[SkinSystem] 融合版插件加载完成 (v%s)", PLUGIN_VERSION);
}

// 从 data/lang/HnsSkin.txt 解析各语言字典(简体/繁体/英语/俄语) 到内存
stock load_lang_entries() {
    g_tLangZh = TrieCreate();
    g_tLangTw = TrieCreate();
    g_tLangEn = TrieCreate();
    g_tLangRu = TrieCreate();

    new szPath[256];
    get_localinfo("amxx_datadir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/lang/HnsSkin.txt", szPath);
    if (!file_exists(szPath)) {
        log_amx("[SkinSystem] 警告: 语言文件缺失(将按英文 key 显示): %s", szPath);
        return;
    }
    new f = fopen(szPath, "rt");
    if (!f) return;

    new szLine[256], szKey[64], szVal[192], szSec[12];
    new Trie:tCur = g_tLangZh;
    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        if (szLine[0] == EOS || szLine[0] == ';' || szLine[0] == '/') continue;
        if (szLine[0] == '[') {
            new iClose = contain(szLine, "]");
            if (iClose > 1) {
                copy(szSec, charsmax(szSec), szLine[1]);
                szSec[iClose - 1] = EOS;
                trim(szSec);
                if (equal(szSec, "zh")) tCur = g_tLangZh;
                else if (equal(szSec, "zh-TW")) tCur = g_tLangTw;
                else if (equal(szSec, "en")) tCur = g_tLangEn;
                else if (equal(szSec, "ru")) tCur = g_tLangRu;
                else tCur = g_tLangZh;
            }
            continue;
        }
        new iEq = contain(szLine, "=");
        if (iEq <= 0) continue;
        copy(szKey, charsmax(szKey), szLine);
        szKey[iEq] = EOS;
        trim(szKey);
        trim(szLine[iEq + 1]);
        copy(szVal, charsmax(szVal), szLine[iEq + 1]);
        if (tCur != Invalid_Trie && szKey[0] != EOS) {
            TrieSetString(tCur, szKey, szVal);
        }
    }
    fclose(f);
}

// 取玩家当前所选语言的字典 (默认简体)
stock Trie:get_lang_trie(const id) {
    if (id > 0) {
        if (equal(g_szSkinLang[id], "zh-TW")) return g_tLangTw;
        if (equal(g_szSkinLang[id], "en")) return g_tLangEn;
        if (equal(g_szSkinLang[id], "ru")) return g_tLangRu;
    }
    return g_tLangZh;
}

// 从语言文件取文案 (优先玩家自选语言, 缺则回退简体->英语->key 本身)
stock tr_key(const id, const szKey[], szOut[], iLen) {
    if (iLen <= 1) { szOut[0] = EOS; return; }
    new Trie:t = get_lang_trie(id);
    if (t != Invalid_Trie && TrieGetString(t, szKey, szOut, iLen)) return;
    if (g_tLangZh != Invalid_Trie && t != g_tLangZh && TrieGetString(g_tLangZh, szKey, szOut, iLen)) return;
    if (g_tLangEn != Invalid_Trie && TrieGetString(g_tLangEn, szKey, szOut, iLen)) return;
    copy(szOut, iLen, szKey);
}

// 当前语言是否匹配某代码 (空=简体)
stock bool:lang_active(const id, const szLang[]) {
    if (szLang[0] == EOS) return g_szSkinLang[id][0] == EOS;
    return equal(g_szSkinLang[id], szLang);
}

// 保存并应用玩家语言
stock set_player_lang(const id, const szLang[]) {
    if (!is_user_connected(id)) return;
    copy(g_szSkinLang[id], charsmax(g_szSkinLang[]), szLang);
    // 同步 AMXX 语言信息(控制台/聊天消息尽量跟随)
    set_user_info(id, "_lang", szLang[0] ? szLang : "zh");
    if (g_iVault != INVALID_HANDLE) {
        new szKey[128], szIdent[MAX_AUTHID_LENGTH];
        get_player_identifier(id, szIdent, charsmax(szIdent));
        format(szKey, charsmax(szKey), "skinsys_skin_lang_%s", szIdent);
        nvault_set(g_iVault, szKey, szLang);
    }
}

// 登录时加载已保存的语言
stock load_player_lang(const id) {
    if (g_iVault == INVALID_HANDLE) return;
    new szKey[128], szIdent[MAX_AUTHID_LENGTH];
    get_player_identifier(id, szIdent, charsmax(szIdent));
    format(szKey, charsmax(szKey), "skinsys_skin_lang_%s", szIdent);
    new szStored[8];
    if (nvault_get(g_iVault, szKey, szStored, charsmax(szStored))) {
        if (equal(szStored, "zh-TW") || equal(szStored, "en") || equal(szStored, "ru")) {
            copy(g_szSkinLang[id], charsmax(g_szSkinLang[]), szStored);
            set_user_info(id, "_lang", szStored);
        }
    }
}

//  语言设置菜单 (含帮助说明)
public showLangMenu(const id) {
    if (!is_user_connected(id)) return;

    new szTitle[32], szExit[16], szHelpT[32], szL1[64], szL2[64], szL3[64];
    tr_key(id, "LANG_TITLE", szTitle, charsmax(szTitle));
    tr_key(id, "MENU_EXIT", szExit, charsmax(szExit));
    tr_key(id, "HELP_TITLE", szHelpT, charsmax(szHelpT));
    tr_key(id, "HELP_L1", szL1, charsmax(szL1));
    tr_key(id, "HELP_L2", szL2, charsmax(szL2));
    tr_key(id, "HELP_L3", szL3, charsmax(szL3));

    new szMarkZh[4], szMarkTw[4], szMarkEn[4], szMarkRu[4];
    szMarkZh[0] = EOS; if (lang_active(id, "")) copy(szMarkZh, charsmax(szMarkZh), " ✓");
    szMarkTw[0] = EOS; if (lang_active(id, "zh-TW")) copy(szMarkTw, charsmax(szMarkTw), " ✓");
    szMarkEn[0] = EOS; if (lang_active(id, "en")) copy(szMarkEn, charsmax(szMarkEn), " ✓");
    szMarkRu[0] = EOS; if (lang_active(id, "ru")) copy(szMarkRu, charsmax(szMarkRu), " ✓");

    new szMenu[512], iLen;
    iLen = formatex(szMenu, charsmax(szMenu), "\y◤ %s ◥^n^n", szTitle);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g1. \w简体中文%s^n", szMarkZh);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g2. \w繁體中文%s^n", szMarkTw);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g3. \wEnglish%s^n", szMarkEn);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g4. \wРусский%s^n^n", szMarkRu);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y──────── \w%s \y────────^n", szHelpT);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w  %s^n", szL1);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w  %s^n", szL2);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w  %s^n", szL3);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y─────── \r0\y. \w%s^n", szExit);

    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinLangMenu");
}

public handleLangMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (key == 9) { cmdSkinMain(id); return PLUGIN_HANDLED; }  // 0 = 返回

    if (key == 0) set_player_lang(id, "");
    else if (key == 1) set_player_lang(id, "zh-TW");
    else if (key == 2) set_player_lang(id, "en");
    else if (key == 3) set_player_lang(id, "ru");

    new szMsg[48];
    tr_key(id, "SKINSYS_CHANGED", szMsg, charsmax(szMsg));
    client_print_color(id, print_team_default, "^4[HnsSkin] ^1%s", szMsg);
    showLangMenu(id);
    return PLUGIN_HANDLED;
}

//  统一主菜单 - /skin (含 IC 积分兑换入口)
public cmdSkinMain(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_CONTINUE;
    }
    if (!g_bICLoaded[id]) load_player_ic(id);

    new szTitle[64], szPerson[32], szTPerson[32], szCTPerson[32], szKnife[32], szSmoke[32], szFlash[32], szUSP[32];
    new szGive[64], szMySql[64], szIC[64], szLangSet[32], szExit[16];
    tr_key(id, "MENU_TITLE", szTitle, charsmax(szTitle));
    tr_key(id, "MENU_PERSON", szPerson, charsmax(szPerson));
    tr_key(id, "MENU_T_PERSON", szTPerson, charsmax(szTPerson));
    tr_key(id, "MENU_CT_PERSON", szCTPerson, charsmax(szCTPerson));
    tr_key(id, "MENU_KNIFE", szKnife, charsmax(szKnife));
    tr_key(id, "MENU_SMOKE", szSmoke, charsmax(szSmoke));
    tr_key(id, "MENU_FLASH", szFlash, charsmax(szFlash));
    tr_key(id, "MENU_USP", szUSP, charsmax(szUSP));
    tr_key(id, "MENU_GIVE", szGive, charsmax(szGive));
    tr_key(id, "MENU_MYSQL", szMySql, charsmax(szMySql));
    tr_key(id, "MENU_IC", szIC, charsmax(szIC));
    tr_key(id, "MENU_LANGUAGE", szLangSet, charsmax(szLangSet));
    tr_key(id, "MENU_EXIT", szExit, charsmax(szExit));

    new szMenu[512];
    new iLen = formatex(szMenu, charsmax(szMenu), "\y◤━━━━━━ %s ━━━━━━◥^n^n", szTitle);

    // 皮肤总量 - 动态统计当前已加载皮肤数 (1-5 的 [N] 为黄字皮肤总数)
    if (is_shared_mode()) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g1. \w%s    [\y%d\y]^n", szPerson, ArraySize(g_aTModels));
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g1. \w%s    [\y%d\y]^n", szTPerson, ArraySize(g_aTModels));
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g2. \w%s   [\y%d\y]^n", szCTPerson, ArraySize(g_aCTModels));
    }
    new iKnifeKey = is_shared_mode() ? 2 : 3;
    new iSmokeKey = is_shared_mode() ? 3 : 4;
    new iFlashKey = is_shared_mode() ? 4 : 5;
    new iUSPKey = is_shared_mode() ? 5 : 6;
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s    [\y%d\y]^n", iKnifeKey, szKnife, ArraySize(g_aKnifeModels));
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s  [\y%d\y]^n", iSmokeKey, szSmoke, ArraySize(g_aSmokeModels));
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s  [\y%d\y]^n", iFlashKey, szFlash, ArraySize(g_aFlashModels));
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s     [\y%d\y]^n^n^n", iUSPKey, szUSP, ArraySize(g_aUSPModels));

    // 管理区: 语言设置(第6项, 黄色, 含帮助) -> 发放管理 -> MySQL终端
    new iLangKey = is_shared_mode() ? 6 : 7;
    new iGiveKey  = iLangKey + 1;
    new iMySqlKey = iGiveKey + 1;
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \r✦ \w%s^n", iLangKey, szLangSet);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \w%s^n", iGiveKey, szGive);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s^n^n", iMySqlKey, szMySql);

    // IC 积分入口 (共享模式菜单空间足够, 显示; 非共享已在语言页含帮助, 避免菜单溢出)
    if (is_shared_mode()) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y──────── \w%s \y────────^n", szIC);
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \w%s \d(当前 \y%d\r分)^n", szIC, g_iICPoints[id]);
    }
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w%s^n", szExit);

    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinMainMenu");
    return PLUGIN_HANDLED;
}

public handleSkinMainMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    // 共享模式键位: 1人物0..5USP4 6语言5 7发放6 8MySQL7 9IC8 0退出9
    // 非共享模式键位: 1T0..6USP5 7语言6 8发放7 9MySQL8 0退出9
    new bShared = is_shared_mode();

    // 人物
    if (key == 0) {
        g_iSkinSelectType[id] = 0; // T (共享时即共用人物)
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // CT (仅非共享模式)
    if (!bShared && key == 1) {
        g_iSkinSelectType[id] = 1;
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // 小刀
    if (key == (bShared ? 1 : 2)) {
        g_iSkinSelectType[id] = 2;
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // 烟雾弹
    if (key == (bShared ? 2 : 3)) {
        g_iSkinSelectType[id] = 4;
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // 闪光弹
    if (key == (bShared ? 3 : 4)) {
        g_iSkinSelectType[id] = 5;
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // USP
    if (key == (bShared ? 4 : 5)) {
        g_iSkinSelectType[id] = 3;
        g_iSkinSelectPage[id] = 0;
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }

    // 语言设置 (黄色, 含帮助)
    if (key == (bShared ? 5 : 6)) {
        showLangMenu(id);
        return PLUGIN_HANDLED;
    }

    // 发放管理 (黄色)
    if (key == (bShared ? 6 : 7)) {
        cmdGiveSkinMenuStart(id);
        return PLUGIN_HANDLED;
    }

    // MySQL终端管理 (红色) - 自动检测
    if (key == (bShared ? 7 : 8)) {
        showMySQLTerminalMenu(id);
        return PLUGIN_HANDLED;
    }

    // IC 积分 (共享模式菜单第9项)
    if (bShared && key == 8) {
        showRedeemMenu(id);
        return PLUGIN_HANDLED;
    }

    // 0 退出 -> key9 无处理器自动关闭
    return PLUGIN_HANDLED;
}

//  MySQL 终端管理 - 自动检测: 有 MySQL 配置则用云端, 否则本地 nvault
new g_iMySqlState[MAX_PLAYERS + 1];   // 0=未知 1=MySQL 2=本地
stock mysql_backend_available() {
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mysql.ini", szPath);
    // 存在且含主机地址即视为启用 MySQL; 否则回退本地
    if (file_exists(szPath)) {
        new f = fopen(szPath, "rt");
        if (f) {
            new szLine[128];
            new bool:bHasHost = false;
            while (!feof(f)) {
                fgets(f, szLine, charsmax(szLine));
                trim(szLine);
                if (szLine[0] == EOS || szLine[0] == ';') continue;
                if (containi(szLine, "host") >= 0 || containi(szLine, "=") >= 0) {
                    bHasHost = true;
                    break;
                }
            }
            fclose(f);
            return bHasHost;
        }
    }
    return false;
}

// 云端(MySQL / sqlx) 后端实现
#if SKINSYS_SQLX == 1
stock sql_read_config(szHost[], iHLen, szUser[], iULen, szPass[], iPLen, szDb[], iDLen) {
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mysql.ini", szPath);
    if (!file_exists(szPath)) return;

    new f = fopen(szPath, "rt");
    if (!f) return;

    new szLine[256], szKey[32], szVal[192];
    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        if (szLine[0] == EOS || szLine[0] == ';' || szLine[0] == '/' || szLine[0] == '#') continue;

        new iEq = containi(szLine, "=");
        if (iEq <= 0) continue;

        copy(szKey, charsmax(szKey), szLine);
        szKey[iEq] = 0;
        trim(szKey);

        copy(szVal, charsmax(szVal), szLine[iEq + 1]);
        trim(szVal);
        new szQ[2] = {34, 0};  // 双引号
        replace_all(szVal, charsmax(szVal), szQ, "");

        if (containi(szKey, "host") >= 0) copy(szHost, iHLen, szVal);
        else if (containi(szKey, "user") >= 0) copy(szUser, iULen, szVal);
        else if (containi(szKey, "pass") >= 0) copy(szPass, iPLen, szVal);
        else if (containi(szKey, "db") >= 0) copy(szDb, iDLen, szVal);
    }
    fclose(f);
}
#endif

// 通用皮肤名: 类型+索引 -> 显示名 (0=T 1=CT 2=刀 3=USP 4=烟雾 5=闪光), 支持多语言
stock get_skin_display_name(const iType, const iIndex, szOut[], iLen, const id = 0) {
    if (iType == 0) ArrayGetString(g_aTModelNames, iIndex, szOut, iLen);
    else if (iType == 1) ArrayGetString(g_aCTModelNames, iIndex, szOut, iLen);
    else if (iType == 2) ArrayGetString(g_aKnifeModelNames, iIndex, szOut, iLen);
    else if (iType == 3) ArrayGetString(g_aUSPModelNames, iIndex, szOut, iLen);
    else if (iType == 4) ArrayGetString(g_aSmokeModelNames, iIndex, szOut, iLen);
    else if (iType == 5) ArrayGetString(g_aFlashModelNames, iIndex, szOut, iLen);

    // 中文名 -> 语言 key, 有则按语言翻译
    new szKey[32];
    if (map_skin_name_to_key(szOut, szKey, charsmax(szKey))) {
        tr_key(id, szKey, szOut, iLen);
    }
}

// 把配置里的中文皮肤名映射到语言文件 key; 匹配不到返回 false 原样显示
stock bool:map_skin_name_to_key(const szCn[], szKey[], iLen) {
    new i;
    static const names[12][MAX_SKIN_NAME] = {
        "北极战士", "中东游击", "精英部队", "凤凰战士",
        "德国GSG9", "法国GIGN", "英国SAS", "美国城市特警",
        "默认刀", "默认USP", "默认烟雾弹", "默认闪光弹"
    };
    static const keys[12][] = {
        "SKIN_ARCTIC", "SKIN_GUERILLA", "SKIN_LEET", "SKIN_TERROR",
        "SKIN_GSG9", "SKIN_GIGN", "SKIN_SAS", "SKIN_URBAN",
        "SKIN_DEF_KNIFE", "SKIN_DEF_USP", "SKIN_DEF_SMOKE", "SKIN_DEF_FLASH"
    };
    for (i = 0; i < 12; i++) {
        if (equal(szCn, names[i])) {
            copy(szKey, iLen, keys[i]);
            return true;
        }
    }
    return false;
}

// 取某玩家某类型第 i 个拥有的皮肤索引
stock get_owned_index(const id, const iType, const i) {
    if (iType == 0) return g_iOwnedT[id][i];
    else if (iType == 1) return g_iOwnedCT[id][i];
    else if (iType == 2) return g_iOwnedKnife[id][i];
    else if (iType == 3) return g_iOwnedUSP[id][i];
    else if (iType == 4) return g_iOwnedSmoke[id][i];
    else if (iType == 5) return g_iOwnedFlash[id][i];
    return -1;
}

// 追加某类型拥有的皮肤名列表到输出行
stock append_owned_names_line(const id, const iType, szLine[], iLen, &iCur) {
    new iCount;
    if (iType == 0) iCount = g_iOwnedTCount[id];
    else if (iType == 1) iCount = g_iOwnedCTCount[id];
    else if (iType == 2) iCount = g_iOwnedKnifeCount[id];
    else if (iType == 3) iCount = g_iOwnedUSPCount[id];
    else if (iType == 4) iCount = g_iOwnedSmokeCount[id];
    else if (iType == 5) iCount = g_iOwnedFlashCount[id];
    new szNone[16];
    tr_key(0, "EXPORT_NONE", szNone, charsmax(szNone));
    if (iCount <= 0) {
        iCur += format(szLine[iCur], iLen - iCur, "%s", szNone);
        return;
    }
    new szName[MAX_SKIN_NAME];
    for (new i = 0; i < iCount; i++) {
        new idx = get_owned_index(id, iType, i);
        get_skin_display_name(iType, idx, szName, charsmax(szName), 0);
        if (i > 0) iCur += format(szLine[iCur], iLen - iCur, ", ");
        if (szName[0] == EOS) iCur += format(szLine[iCur], iLen - iCur, "#%d", idx);
        else iCur += format(szLine[iCur], iLen - iCur, "%s", szName);
    }
}

// 本地可读导出: 生成 mixsystem/skin_players.txt, 识别 IP/昵称/SteamID, 标 [steam版]/[盗版], 多语言
stock export_skin_records() {
    new szFull[256];
    get_localinfo("amxx_configsdir", szFull, charsmax(szFull));
    new szFile[512];
    format(szFile, charsmax(szFile), "%s/mixsystem/skin_players.txt", szFull);

    new f = fopen(szFile, "wt");
    if (!f) {
        log_amx("[SkinSystem] 无法生成可读皮肤存档: %s", szFile);
        return 0;
    }

    new szHeader[64], szPirate[16], szSteam[16], szSid[16], szIpTag[8], szOwned[32], szNone[16], szTotal[48], szTime[64];
    tr_key(0, "EXPORT_HEADER", szHeader, charsmax(szHeader));
    tr_key(0, "EXPORT_PIRATE", szPirate, charsmax(szPirate));
    tr_key(0, "EXPORT_STEAM", szSteam, charsmax(szSteam));
    tr_key(0, "EXPORT_STEAMID", szSid, charsmax(szSid));
    tr_key(0, "EXPORT_IP", szIpTag, charsmax(szIpTag));
    tr_key(0, "EXPORT_OWNED", szOwned, charsmax(szOwned));
    tr_key(0, "EXPORT_NONE", szNone, charsmax(szNone));
    tr_key(0, "EXPORT_TOTAL", szTotal, charsmax(szTotal));
    get_time("%Y-%m-%d %H:%M:%S", szTime, charsmax(szTime));

#if SKINSYS_SQLX == 1
    // 云端全量同步到本地导出文件 (后台线程, 每个在线玩家的云端记录并入)
    sql_export_merge_all();
#endif

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ch");
    new iCount = 0;

    fprintf(f, "%s^n", szHeader);
    fprintf(f, "%s^n", szTime);

    for (new p = 0; p < iNum; p++) {
        new pid = iPlayers[p];
        new szName[32]; get_user_name(pid, szName, charsmax(szName));
        new szIP[MAX_AUTHID_LENGTH]; get_user_ip(pid, szIP, charsmax(szIP), 1);
        new szAuth[MAX_AUTHID_LENGTH]; get_user_authid(pid, szAuth, charsmax(szAuth));

        // 盗版判定: authid 为经典盗版占位即视为非 Steam 版
        new bool:bPirate = false;
        if (contain(szAuth, "ID_LAN") != -1 || equali(szAuth, "STEAM_ID_LAN") || equali(szAuth, "VALVE_ID_LAN") || szAuth[0] == EOS || equal(szAuth, "4294967295")) {
            bPirate = true;
        }

        fprintf(f, "^n====================================================^n");
        if (bPirate) {
            fprintf(f, "[%s]  %s^n", szPirate, szName);
        } else {
            fprintf(f, "[%s]  %s^n", szSteam, szName);
            fprintf(f, "  %s: %s^n", szSid, szAuth);
        }
        fprintf(f, "  %s:      %s^n", szIpTag, szIP);
        fprintf(f, "  %s:^n", szOwned);

        new szLine[1024];
        println_to_file_cat(f, pid, 0, szLine, szNone);
        println_to_file_cat(f, pid, 1, szLine, szNone);
        println_to_file_cat(f, pid, 2, szLine, szNone);
        println_to_file_cat(f, pid, 3, szLine, szNone);
        println_to_file_cat(f, pid, 4, szLine, szNone);
        println_to_file_cat(f, pid, 5, szLine, szNone);

        iCount++;
    }

    fprintf(f, "^n==== ");
    fprintf(f, szTotal, iCount);
    fprintf(f, " ====^n");
    fclose(f);
    return iCount;
}

// 输出单个类型持有行到文件
stock println_to_file_cat(const f, const pid, const iType, szLine[], const szNone[]) {
    new szTypeName[24];
    if (iType == 0) tr_key(0, "TYPE_T", szTypeName, charsmax(szTypeName));
    else if (iType == 1) tr_key(0, "TYPE_CT", szTypeName, charsmax(szTypeName));
    else if (iType == 2) tr_key(0, "TYPE_KNIFE", szTypeName, charsmax(szTypeName));
    else if (iType == 3) tr_key(0, "TYPE_USP", szTypeName, charsmax(szTypeName));
    else if (iType == 4) tr_key(0, "TYPE_SMOKE", szTypeName, charsmax(szTypeName));
    else if (iType == 5) tr_key(0, "TYPE_FLASH", szTypeName, charsmax(szTypeName));

    new iCur = 0;
    new szTag[24];
    formatex(szTag, charsmax(szTag), "    %s : ", szTypeName);
    iCur += format(szLine[iCur], charsmax(szLine) - iCur, "%s", szTag);
    append_owned_names_line(pid, iType, szLine, charsmax(szLine), iCur);
    fprintf(f, "%s^n", szLine);
}

public cmdExportSkins(const id, const level, const cid) {
    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] Only admins can export");
        return PLUGIN_HANDLED;
    }
    new iCount = export_skin_records();
    client_print(id, print_chat, "[SkinSystem] Skin list exported to skin_players.txt, %d online players", iCount);
    return PLUGIN_HANDLED;
}

// 序列化玩家拥有皮肤 -> JSON (与 nvault 共用结构)
stock build_skin_json(const id, szData[], iLen) {
    new i = 0;
    i += format(szData[i], iLen - i, "{^"t^":[");
    for (new x = 0; x < g_iOwnedTCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedT[id][x]);
    }
    i += format(szData[i], iLen - i, "],^"ct^":[");
    for (new x = 0; x < g_iOwnedCTCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedCT[id][x]);
    }
    i += format(szData[i], iLen - i, "],^"knife^":[");
    for (new x = 0; x < g_iOwnedKnifeCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedKnife[id][x]);
    }
    i += format(szData[i], iLen - i, "],^"usp^":[");
    for (new x = 0; x < g_iOwnedUSPCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedUSP[id][x]);
    }
    i += format(szData[i], iLen - i, "],^"smoke^":[");
    for (new x = 0; x < g_iOwnedSmokeCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedSmoke[id][x]);
    }
    i += format(szData[i], iLen - i, "],^"flash^":[");
    for (new x = 0; x < g_iOwnedFlashCount[id]; x++) {
        if (x > 0) i += format(szData[i], iLen - i, ",");
        i += format(szData[i], iLen - i, "%d", g_iOwnedFlash[id][x]);
    }
    i += format(szData[i], iLen - i, "]}");
    return i;
}

#if SKINSYS_SQLX == 1
// 线程回调: 忽略结果 (sqlx 说明: query 无需手动释放)
public sql_ignore_result(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    // 无操作
}

// 线程回调: 探测连接
public SqlProbeResult(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if (!failstate) {
        if (!g_bSqlConnected) log_amx("[SkinSystem] 云端存档连接成功");
        g_bSqlConnected = true;
    } else {
        if (g_bSqlConnected) log_amx("[SkinSystem] 云端存档连接失败: %s", error);
        g_bSqlConnected = false;
    }
}

stock sql_write_skins(const id) {
    if (!g_bSqlConnected || g_hSqlTuple == Empty_Handle || !is_user_connected(id)) return;

    new szData[1280];
    build_skin_json(id, szData, charsmax(szData));

    new szId[64];
    get_player_identifier(id, szId, charsmax(szId));
    if (szId[0] == EOS) return;

    replace_all(szId, charsmax(szId), "'", "''");
    replace_all(szData, charsmax(szData), "'", "''");

    new szQ[2048];
    format(szQ, charsmax(szQ), "REPLACE INTO %s (authid, skin_json) VALUES ('%s', '%s')", SQL_TABLE, szId, szData);
    SQL_ThreadQuery(g_hSqlTuple, "sql_ignore_result", szQ);
}

stock sql_load_skins(const id) {
    if (!g_bSqlConnected || g_hSqlTuple == Empty_Handle || !is_user_connected(id)) return;

    new szId[64];
    get_player_identifier(id, szId, charsmax(szId));
    if (szId[0] == EOS) return;

    replace_all(szId, charsmax(szId), "'", "''");

    new szQ[512];
    format(szQ, charsmax(szQ), "SELECT skin_json FROM %s WHERE authid = '%s' LIMIT 1", SQL_TABLE, szId);

    new aData[2];
    aData[0] = id;
    SQL_ThreadQuery(g_hSqlTuple, "SqlLoadResult", szQ, aData, sizeof aData);
}

public SqlLoadResult(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if (failstate || !data[0]) {
        return;
    }
    new id = data[0];
    if (!is_user_connected(id)) {
        return;
    }

    if (SQL_NumResults(query) > 0) {
        new szJson[1280];
        SQL_ReadResult(query, 0, szJson, charsmax(szJson));
        parse_skin_json(id, szJson);
        ensure_default_skins(id);
        if (is_user_alive(id)) apply_model(id);
        client_print(id, print_chat, "[SkinSystem] 已从云端同步皮肤数据");
    }
}

#if SKINSYS_SQLX == 1
// 导出前合并云端: 为每个在线玩家拉取云端记录覆盖内存, 使导出包含云端数据
stock sql_export_merge_all() {
    if (!g_bSqlConnected || g_hSqlTuple == Empty_Handle) return;
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");
    for (new i = 0; i < iNum; i++) {
        new pid = iPlayers[i];
        if (!is_user_connected(pid)) continue;
        new szId[64];
        get_player_identifier(pid, szId, charsmax(szId));
        if (szId[0] == EOS) continue;
        new szQ[512], szEsc[64];
        copy(szEsc, charsmax(szEsc), szId);
        replace_all(szEsc, charsmax(szEsc), "'", "''");
        format(szQ, charsmax(szQ), "SELECT skin_json FROM %s WHERE authid = '%s' LIMIT 1", SQL_TABLE, szEsc);
        new aData[2];
        aData[0] = pid;
        SQL_ThreadQuery(g_hSqlTuple, "SqlLoadResult", szQ, aData, sizeof aData);
    }
}
#endif

// 云端全量查看: 查询整张皮肤表, 按管理员分页显示 (无需玩家在线)
stock sql_load_all_skins(const admin, const iPage) {
    if (!g_bSqlConnected || g_hSqlTuple == Empty_Handle) {
        client_print(admin, print_chat, "[SkinSystem] 云端未连接, 无法查看");
        return;
    }
    g_iCloudViewer = admin;
    g_iCloudViewPage = iPage;
    new szQ[256];
    formatex(szQ, charsmax(szQ), "SELECT authid, skin_json FROM %s ORDER BY authid", SQL_TABLE);
    SQL_ThreadQuery(g_hSqlTuple, "SqlLoadAllResult", szQ);
}

public SqlLoadAllResult(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new admin = g_iCloudViewer;
    g_iCloudViewer = 0;
    if (!is_user_connected(admin)) {
        return;
    }
    if (failstate) {
        client_print(admin, print_chat, "[SkinSystem] 云端全量查询失败: %s", error);
        return;
    }

    new iRows = SQL_NumResults(query);
    if (iRows <= 0) {
        client_print(admin, print_chat, "[SkinSystem] 云端暂无皮肤记录");
        return;
    }

    // 整理: authid + 各类型拥有数 (从 skin_json 解析)
    new const iPageSize = 10;
    new iStart = g_iCloudViewPage * iPageSize;
    if (iStart >= iRows) iStart = iRows - iRows % iPageSize; // 越界时回到最后一页起点
    new iEnd = iStart + iPageSize;
    if (iEnd > iRows) iEnd = iRows;

    new szAuth[64], szJson[1280];
    new aCount[6];
    client_print(admin, print_chat, "[SkinSystem] ---- 云端皮肤全量 (第%d/%d页, 共%d条) ----", g_iCloudViewPage + 1, (iRows + iPageSize - 1) / iPageSize, iRows);
    new szSection[256];
    new szKeyName[8];
    new aTmp[MAX_OWNED_SKINS];
    new keys[6][8] = { {"t"}, {"ct"}, {"knife"}, {"usp"}, {"smoke"}, {"flash"} };
    for (new r = iStart; r < iEnd; r++) {
        SQL_ReadResult(query, 0, szAuth, charsmax(szAuth));
        SQL_ReadResult(query, 1, szJson, charsmax(szJson));
        for (new x = 0; x < 6; x++) {
            aCount[x] = 0;
            copy(szKeyName, charsmax(szKeyName), keys[x]);
            if (extract_json_array(szJson, szKeyName, szSection, charsmax(szSection))) {
                new iTc = 0;
                parse_skin_array(szSection, aTmp, iTc);
                aCount[x] = iTc;
            }
        }
        client_print(admin, print_chat, "%s: 人%d 刀%d 烟%d 闪%d USP%d",
            szAuth, aCount[0], aCount[2], aCount[4], aCount[5], aCount[3]);
    }
    client_print(admin, print_chat, "[SkinSystem] ---- 输入 '/skin' 打开发放管理进行离线发放 ----");
}
#endif

#if SKINSYS_SQLX == 1
stock sql_backend_init() {
    if (!mysql_backend_available()) {
        log_amx("[SkinSystem] 未找到 mysql.ini, 云端存档关闭, 使用本地 nvault");
        return;
    }

    new szHost[128], szUser[64], szPass[128], szDb[64];
    sql_read_config(szHost, charsmax(szHost), szUser, charsmax(szUser), szPass, charsmax(szPass), szDb, charsmax(szDb));
    if (szHost[0] == EOS) {
        log_amx("[SkinSystem] mysql.ini 未解析出 host, 云端存档关闭");
        return;
    }

    g_hSqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb);

    new szQ[256];
    format(szQ, charsmax(szQ), "CREATE TABLE IF NOT EXISTS %s (authid VARCHAR(64) PRIMARY KEY, skin_json TEXT)", SQL_TABLE);
    SQL_ThreadQuery(g_hSqlTuple, "sql_ignore_result", szQ);

    SQL_ThreadQuery(g_hSqlTuple, "SqlProbeResult", "SELECT 1");

    log_amx("[SkinSystem] 云端存档已尝试启用 (host=%s db=%s)", szHost, szDb);
}
#else
stock sql_backend_init() {
    log_amx("[SkinSystem] 未检测到 sqlx 模块, 云端存档已禁用, 使用本地 nvault(=skin_data.txt)");
}

stock sql_write_skins(const id) {
    // 无 sqlx: 云写入为空操作
}
stock sql_load_skins(const id) {
    // 无 sqlx: 云读取为空操作
}
#endif

public showMySQLTerminalMenu(const id) {
    // 管理员权限检查
    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证管理员才能使用 MySQL 终端");
        return PLUGIN_HANDLED;
    }
    new bool:bMySql = bool:mysql_backend_available();
    g_iMySqlState[id] = bMySql ? 1 : 2;

    new szMenu[256], iLen;
    iLen = formatex(szMenu, charsmax(szMenu), "\y◤━━ MySQL 终端管理 ━━◥^n^n");

#if SKINSYS_SQLX == 1
    if (bMySql && g_bSqlConnected) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g当前后端: \yMySQL 云端存档 \d(已连接)^n^n");
    } else if (bMySql) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r当前后端: \dMySQL 已配置但未连接 (检查连接)^n^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d当前后端: 本地 nvault (未配置 mysql.ini)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d如需云端: 配置 mysql.ini, 重新编译加 SKINSYS_ENABLE_MYSQL^n^n");
    }
#else
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d当前后端: 本地 nvault (未开启云端)^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d如需云端: 配置 mysql.ini, 重新编译加 SKINSYS_ENABLE_MYSQL^n^n");
#endif
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \w在线发放皮肤^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \w离线发放 \d(按SteamID, 无需玩家在线)^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \w查看全量皮肤记录^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回^n");

    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsMySQLTerminal");
    return PLUGIN_HANDLED;
}

public handleMySQLTerminalMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (key == 9) { // 0 返回
        cmdSkinMain(id);
        return PLUGIN_HANDLED;
    }
    if (key == 0) { // 1 在线发放皮肤
        cmdGiveSkinMenuStart(id);
        return PLUGIN_HANDLED;
    }
    if (key == 1) { // 2 离线发放 (按SteamID)
        client_print(id, print_chat, "[SkinSystem] 离线发放用法(控制台):  say /giveoffline <SteamID> <类型> <皮肤序号>");
        client_print(id, print_chat, "[SkinSystem] 类型: 0近似T 1CT 2刀 3USP 4烟雾 5闪光; 序号从0起, 如 '/giveoffline STEAM_0:1:123 2 0'");
        return PLUGIN_HANDLED;
    }
    if (key == 2) { // 3 查看全量皮肤记录
        showCloudFullView(id);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_HANDLED;
}

// 全量查看: 云端连接则查全表, 否则显示在线玩家统计
public showCloudFullView(const id) {
#if SKINSYS_SQLX == 1
    if (g_bSqlConnected && g_hSqlTuple != Empty_Handle) {
        sql_load_all_skins(id, 0);
        return;
    }
#endif
    // 本地回退
    showGiveTabDataMenu(id);
}

// 离线发放命令: /giveoffline <SteamID> <类型> <皮肤序号>
public cmdGiveOffline(const id, const level, const cid) {
    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证管理员才能离线发放");
        return PLUGIN_HANDLED;
    }
    new szId[128], szType[16], szIndex[16];
    read_argv(1, szId, charsmax(szId));
    read_argv(2, szType, charsmax(szType));
    read_argv(3, szIndex, charsmax(szIndex));
    if (szId[0] == EOS || szType[0] == EOS || szIndex[0] == EOS) {
        client_print(id, print_chat, "[SkinSystem] 用法: /giveoffline <SteamID> <类型> <皮肤序号>");
        return PLUGIN_HANDLED;
    }
    new iType = str_to_num(szType);
    new iIndex = str_to_num(szIndex);
    new iRet = grant_skin_offline(szId, iType, iIndex);
    if (iRet != -1) {
        // 若该 SteamID 的玩家恰好在线, 即时刷新其内存与外观
        sync_online_skin_by_identifier(szId);
    }
    if (iRet == 1) {
        client_print(id, print_chat, "[SkinSystem] 已离线发放 %s 类型%d 皮肤序号%d", szId, iType, iIndex);
    } else if (iRet == 0) {
        client_print(id, print_chat, "[SkinSystem] %s 已拥有该皮肤, 无需重复发放", szId);
    } else {
        client_print(id, print_chat, "[SkinSystem] 发放失败: 类型或皮肤序号越界", szId);
    }
    return PLUGIN_HANDLED;
}

public showGiveTabDataMenu(const id) {
    if (!is_user_connected(id)) return;

    client_print(id, print_chat, "[SkinSystem] —— 在线玩家皮肤统计 ——");
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");
    for (new p = 0; p < iNum; p++) {
        new pid = iPlayers[p];
        new szName[32];
        get_user_name(pid, szName, charsmax(szName));
#if SKINSYS_SQLX == 1
        new szBackend[24];
        copy(szBackend, charsmax(szBackend), g_bSqlConnected ? "云端" : "本地");
        client_print(id, print_chat, " %s: 人%d/刀%d/烟%d/闪%d/USP%d [%s]", szName,
            count_owned_skins(pid, 0), count_owned_skins(pid, 2),
            count_owned_skins(pid, 4), count_owned_skins(pid, 5), count_owned_skins(pid, 3), szBackend);
#else
        client_print(id, print_chat, " %s: 人%d/刀%d/烟%d/闪%d/USP%d [本地]", szName,
            count_owned_skins(pid, 0), count_owned_skins(pid, 2),
            count_owned_skins(pid, 4), count_owned_skins(pid, 5), count_owned_skins(pid, 3));
#endif
    }
    return;
}

//  皮肤系统帮助说明
public showSkinHelp(const id) {
    if (!is_user_connected(id)) return;

    client_print_color(id, print_team_default, "^4[HnsSkin] ^1皮肤系统使用帮助:");
    client_print_color(id, print_team_default, "^1  /^3skin ^1- 打开皮肤主菜单");
    client_print_color(id, print_team_default, "^1  /^3skin_t ^1- 直接选 T 皮肤");
    client_print_color(id, print_team_default, "^1  /^3skin_ct ^1- 直接选 CT 皮肤");
    client_print_color(id, print_team_default, "^1  /^3skin_knife ^1- 直接选刀皮肤");
    client_print_color(id, print_team_default, "^1  /^3skin_usp ^1- 直接选USP皮肤");
    client_print_color(id, print_team_default, "^4[HnsSkin] ^1  /^3ic ^1- 查看IC积分 / /^3skin^1 里可兑换皮肤");
    client_print_color(id, print_team_default, "^4[HnsSkin] ^1更多命令见仓库 README 或 /skinmenu");
}

//  IC 点查看菜单
public showICPointsInfo(const id) {
    if (!is_user_connected(id)) return;
    if (!g_bICLoaded[id]) load_player_ic(id);

    client_print_color(id, print_team_default, "^4[IC点] ^1你当前拥有 ^3%d^1 IC 积分", g_iICPoints[id]);
    client_print_color(id, print_team_default, "^4[IC点] ^1在 /^3skin^1 菜单选择「IC积分兑换」即可用积分解锁皮肤");
    client_print_color(id, print_team_default, "^4[IC点] ^1也能按 ^3N^1 键 或输入 /^3ic^1 打开 IC 菜单");
}

//  IC 点主菜单 (N 键 / /ic)
public cmdICMenu(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!g_bICLoaded[id]) load_player_ic(id);
    showMainMenu(id);
    return PLUGIN_HANDLED;
}
public icMainHandler(id, key) {
    if (key == 9) return PLUGIN_HANDLED;
    if (key == 0) showRedeemMenu(id);
    else if (key == 1) showICPointsInfo(id);
    return PLUGIN_HANDLED;
}
public showMainMenu(id) {
    new szMenu[512], iLen;
    iLen = formatex(szMenu, charsmax(szMenu), "\r* * * IC 点 系 统 * * *^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y  ★ 当前积分: \w%d^n", g_iICPoints[id]);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \w积分兑换皮肤 \y▶^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \w查看积分说明 \y▶^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w关闭 \y✕");
    show_menu(id, (1<<0)|(1<<1)|(1<<9), szMenu, -1, "HnsICMain");
}

//  管理员直接给予 IC 点
//  用法: /givetic <玩家名|@ALL> <数量>
//  权限: users.ini 官方认证管理员 (is_user_admin)
public cmdGiveIC(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!is_user_admin(id)) {
        client_print_color(id, print_team_default, "^4[IC点] ^3只有管理员才能直接给予IC点");
        return PLUGIN_HANDLED;
    }
    new szArg1[33], szArg2[16];
    read_argv(1, szArg1, charsmax(szArg1));
    read_argv(2, szArg2, charsmax(szArg2));
    if (szArg1[0] == 0 || szArg2[0] == 0) {
        client_print_color(id, print_team_default, "^4[IC点] ^3用法: /givetic <玩家名|@ALL> <数量>");
        return PLUGIN_HANDLED;
    }
    new iAmount = str_to_num(szArg2);
    if (iAmount <= 0) {
        client_print_color(id, print_team_default, "^4[IC点] ^3数量必须大于0");
        return PLUGIN_HANDLED;
    }
    // 批量给予所有在线玩家
    if (equali(szArg1, "@ALL") || equali(szArg1, "@all") || equali(szArg1, "*") || equali(szArg1, "ALL")) {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "ch");
        for (new i = 0; i < iNum; i++) if (is_user_connected(iPlayers[i])) add_ic_points(iPlayers[i], iAmount);
        client_print_color(0, print_team_default, "^4[IC点] ^1管理员 %n ^3给予在线所有玩家 ^4+%d^1 IC点", id, iAmount);
        return PLUGIN_HANDLED;
    }
    // 单个玩家: 支持部分名字匹配
    new target = find_player("bl", szArg1);
    if (!is_user_connected(target)) {
        client_print_color(id, print_team_default, "^4[IC点] ^3找不到玩家 ^4%s", szArg1);
        return PLUGIN_HANDLED;
    }
    add_ic_points(target, iAmount);
    client_print_color(0, print_team_default, "^4[IC点] ^1管理员 %n ^3给予 %n ^4+%d^1 IC点", id, target, iAmount);
    return PLUGIN_HANDLED;
}

//  IC 积分兑换: 选择皮肤类型
public icRedeemHandler(id, key) {
    if (key == 9) { showMainMenu(id); return PLUGIN_HANDLED; }
    if (key == 0) g_iICTargetType[id] = 0;
    else if (key == 1) g_iICTargetType[id] = 1;
    else if (key == 2) g_iICTargetType[id] = 2;
    g_iICSkinPage[id] = 0;
    showRedeemSkinList(id);
    return PLUGIN_HANDLED;
}
public showRedeemMenu(id) {
    if (!is_user_connected(id)) return;
    if (!g_bICLoaded[id]) load_player_ic(id);

    new szMenu[256], iLen;
    iLen = formatex(szMenu, charsmax(szMenu), "\r* * * IC 积 分 兑 换 * * *^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y  ★ 当前积分: \w%d^n", g_iICPoints[id]);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \w人物皮肤  \y(T) ▶^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \w人物皮肤  \y(CT) ▶^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \w刀皮肤     \y(高价) ▶^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回 \y◀");
    show_menu(id, (1<<0)|(1<<1)|(1<<2)|(1<<9), szMenu, -1, "HnsICRedeem");
}

// 获取某玩家在某类型下是否已拥有 (融合版: 直接走皮肤系统所有权)
public icSkinListHandler(id, key) {
    if (key == 9) { showRedeemMenu(id); return PLUGIN_HANDLED; }
    if (key == 8) { g_iICSkinPage[id]++; showRedeemSkinList(id); return PLUGIN_HANDLED; }

    new iType = g_iICTargetType[id];
    new iTotal = ic_type_model_count(iType);
    new idx = g_iICSkinPage[id] * 8 + key;
    if (idx >= iTotal) { showRedeemSkinList(id); return PLUGIN_HANDLED; }

    if (has_skin(id, iType, idx)) {
        client_print_color(id, print_team_default, "^4[IC点] ^3已拥有该皮肤");
        showRedeemSkinList(id);
        return PLUGIN_HANDLED;
    }

    new cost = (iType == 2) ? get_pcvar_num(pcvar_knife_pts) : get_pcvar_num(pcvar_person_pts);
    if (g_iICPoints[id] < cost) {
        client_print_color(id, print_team_default, "^4[IC点] ^3积分不足 需要\w%d^3(当前\w%d^3)", cost, g_iICPoints[id]);
        showRedeemSkinList(id);
        return PLUGIN_HANDLED;
    }

    // 兑换: 扣积分并解锁皮肤(成为永久已拥有皮肤)
    g_iICPoints[id] -= cost;
    save_player_ic(id);
    give_skin(id, iType, idx);
    save_player_skins(id);

    new szName[MAX_SKIN_NAME];
    ic_type_name(iType, idx, szName, charsmax(szName));
    client_print_color(id, print_team_default, "^4[IC点] ^1兑换成功! 已解锁皮肤 ^4%s^1 (扣除\w%d^1分)", szName, cost);
    play_skin_purchase_sfx(id);   // 兑换成功提示音
    if (is_user_alive(id)) apply_model(id);
    showRedeemSkinList(id);
    return PLUGIN_HANDLED;
}

public showRedeemSkinList(id) {
    if (!is_user_connected(id)) return;
    new iType = g_iICTargetType[id];
    new iTotal = ic_type_model_count(iType);
    if (iTotal <= 0) {
        client_print_color(id, print_team_default, "^4[IC点] ^3皮肤列表为空");
        showRedeemMenu(id);
        return;
    }

    new ip = g_iICSkinPage[id], per = 8, st = ip * per, en = st + per;
    if (en > iTotal) en = iTotal;

    new szMenu[512], iLen, szName[MAX_SKIN_NAME], k = 0;
    new szTypeName[16];
    if (iType == 0) copy(szTypeName, charsmax(szTypeName), "T阵营");
    else if (iType == 1) copy(szTypeName, charsmax(szTypeName), "CT阵营");
    else copy(szTypeName, charsmax(szTypeName), "刀");

    iLen = formatex(szMenu, charsmax(szMenu), "\r* * * 皮 肤 列 表 * * *^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y  └ %s 第 %d/%d 页^n^n", szTypeName, ip + 1, (iTotal + per - 1) / per);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n");

    for (new i = st; i < en; i++) {
        ic_type_name(iType, i, szName, charsmax(szName));
        if (has_skin(id, iType, i))
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s \y✓已拥有^n", ++k, szName);
        else {
            new cost = (iType == 2) ? get_pcvar_num(pcvar_knife_pts) : get_pcvar_num(pcvar_person_pts);
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s \y(%d分)^n", ++k, szName, cost);
        }
    }

    if (en < iTotal) iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w----------------------------^n");
    if (en < iTotal) iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \w下一页 \y▶^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回 \y◀");

    new keys = 0;
    for (new i = 0; i < en - st; i++) keys |= (1 << i);
    if (en < iTotal) keys |= (1 << 8);
    keys |= (1 << 9);
    show_menu(id, keys, szMenu, -1, "HnsICSkinList");
}

//  IC 辅助: 按类型取模型总数 / 名称
stock ic_type_model_count(const iType) {
    if (iType == 0) return ArraySize(g_aTModels);
    else if (iType == 1) return ArraySize(g_aCTModels);
    else return ArraySize(g_aKnifeModels);
}
stock ic_type_name(const iType, const iIndex, szOut[], iLen) {
    if (iType == 0) ArrayGetString(g_aTModelNames, iIndex, szOut, iLen);
    else if (iType == 1) ArrayGetString(g_aCTModelNames, iIndex, szOut, iLen);
    else ArrayGetString(g_aKnifeModelNames, iIndex, szOut, iLen);
}

//  IC 积分持久化 (nvault)
stock get_ic_identifier(const id, szBuffer[], iLen) {
    if (g_szPlayerAuth[id][0] == 0) get_user_authid(id, g_szPlayerAuth[id], MAX_AUTHID_LENGTH - 1);
    copy(szBuffer, iLen, g_szPlayerAuth[id]);
}
stock load_player_ic(const id) {
    if (!is_user_connected(id)) return;
    new szId[MAX_AUTHID_LENGTH], szKey[160];
    get_ic_identifier(id, szId, charsmax(szId));
    if (szId[0] == 0) return;
    copy(szKey, charsmax(szKey), "skinsys_icpts_");
    add(szKey, charsmax(szKey), szId);
    g_iICPoints[id] = nvault_get(g_iVault, szKey);
    g_bICLoaded[id] = true;
}
stock save_player_ic(const id) {
    new szId[MAX_AUTHID_LENGTH], szKey[160];
    get_ic_identifier(id, szId, charsmax(szId));
    if (szId[0] == 0) return;
    copy(szKey, charsmax(szKey), "skinsys_icpts_");
    add(szKey, charsmax(szKey), szId);
    new szPts[16];
    formatex(szPts, charsmax(szPts), "%d", g_iICPoints[id]);
    nvault_set(g_iVault, szKey, szPts);
}
stock add_ic_points(id, iAmount) {
    if (!is_user_connected(id) || iAmount <= 0) return;
    if (!g_bICLoaded[id]) load_player_ic(id);
    g_iICPoints[id] += iAmount;
    save_player_ic(id);
    client_print_color(id, print_team_default, "^4[IC点] ^1获得\w+%d^1分 (当前\w%d^1)", iAmount, g_iICPoints[id]);
}

//  plugin_end - 清理
public plugin_end() {
    // 换图/关服时自动生成皮肤清单 (本地可读, 多语言)
    export_skin_records();

    if (g_iVault != INVALID_HANDLE) {
        nvault_close(g_iVault);
    }
    if (g_tLangZh != Invalid_Trie) TrieDestroy(g_tLangZh);
    if (g_tLangTw != Invalid_Trie) TrieDestroy(g_tLangTw);
    if (g_tLangEn != Invalid_Trie) TrieDestroy(g_tLangEn);
    if (g_tLangRu != Invalid_Trie) TrieDestroy(g_tLangRu);
    cleanup_arrays();
}

//  刀 / USP 模型应用 (标准字段方案)
stock play_skin_sound(const id, const szSnd[], const Float:fVol = 0.6, const Float:fPitch = 1.0) {
    if (!is_user_connected(id) || !get_pcvar_num(pcvar_sound)) {
        return;
    }
    // 用 CHAN_AUTO / ATTN_NORM 播放, 音量可调; pitch 乘 100 转整数
    new iPitch = floatround(fPitch * 100.0, floatround_round);
    emit_sound(id, CHAN_AUTO, szSnd, fVol, ATTN_NORM, 0, iPitch);
}

// 换肤/应用皮肤时播放 (切成手部视角, 用于第三人称般的效果提示)
stock play_skin_apply_sfx(const id) {
    play_skin_sound(id, SND_SKIN_APPLY, 0.5, 1.0);
}

// 积分兑换成功音
stock play_skin_purchase_sfx(const id) {
    play_skin_sound(id, SND_SKIN_PURCHASE, 0.7, 1.0);
}

// 菜单选择音
stock play_menu_click_sfx(const id) {
    play_skin_sound(id, SND_MENU_CLICK, 0.5, 1.0);
}

stock set_player_knife_view(const id, const szPath[]) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }
    new iEnt = find_ent_by_owner(-1, "weapon_knife", id);
    if (!iEnt) {
        return;
    }
    set_pev(iEnt, pev_viewmodel, szPath);
    // 第三人称持刀模型: 仅使用配置中手动指定的 p_ 模型; 未指定时复用第一人称模型
    new szMan[MAX_MODEL_NAME];
    szMan[0] = EOS;
    if (g_iSelectedKnife[id] >= 0 && g_iSelectedKnife[id] < ArraySize(g_aKnifeThirdModels)) {
        ArrayGetString(g_aKnifeThirdModels, g_iSelectedKnife[id], szMan, charsmax(szMan));
    }
    if (szMan[0] != EOS && file_exists(szMan)) {
        set_pev(iEnt, pev_weaponmodel, szMan);
    } else {
        set_pev(iEnt, pev_weaponmodel, szPath);
    }
    // 出刀/换肤提示音 (切到默认刀皮肤时也播放)
    if (g_bKnifeSndOn[id]) {
        play_skin_apply_sfx(id);
        g_bKnifeSndOn[id] = false;
    }
}
stock get_knife_thirdperson_path(const szPath[], output[], const iLen) {
    // 输入形如 models/v_xxx.mdl, 将其推导为 models/p_xxx.mdl (第三人称持刀模型)
    copy(output, iLen, szPath);
    new iPos = contain(output, "v_");
    if (iPos >= 0) {
        output[iPos] = 'p';
        return 1;
    }
    return 0;
}
public Knife_Deploy_Post(const iWeapon) {
    new id = get_member(iWeapon, m_pPlayer);
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    set_task(0.05, "task_apply_knife", id);
}
public task_apply_knife(const id) {
    if (!is_user_connected(id) || !is_user_alive(id) || get_user_weapon(id) != CSW_KNIFE) {
        return;
    }
    if (g_iSelectedKnife[id] >= 0) {
        new iSize = ArraySize(g_aKnifeModels);
        if (g_iSelectedKnife[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aKnifeModels, g_iSelectedKnife[id], szPath, charsmax(szPath));
            set_player_knife_view(id, szPath);
        }
    }
    // 每次拔出/切到刀时播放切刀音效(仅当音效开关开启, 且有自定义刀皮肤)
    if (g_bKnifeSndOn[id] || (g_iSelectedKnife[id] >= 0 && g_iSelectedKnife[id] < ArraySize(g_aKnifeModels))) {
        play_skin_apply_sfx(id);
    }
    g_bKnifeSndOn[id] = false;
}
stock set_player_usp_view(const id, const szPath[]) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }
    new iEnt = find_ent_by_owner(-1, "weapon_usp", id);
    if (!iEnt) {
        return;
    }
    if (!file_exists(szPath)) {
        set_pev(iEnt, pev_viewmodel, "models/v_usp.mdl");
        return;
    }
    set_pev(iEnt, pev_viewmodel, szPath);
}
public USP_Deploy_Post(iItem) {
    new id = get_member(iItem, m_pPlayer);
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    if (g_iSelectedUSP[id] >= 0) {
        new iSize = ArraySize(g_aUSPModels);
        if (g_iSelectedUSP[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aUSPModels, g_iSelectedUSP[id], szPath, charsmax(szPath));
            set_player_usp_view(id, szPath);
        }
    }
}

stock set_player_smoke_view(const id, const szPath[]) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }
    new szPathP[MAX_MODEL_NAME];
    new bool:bHasThird = bool:get_knife_thirdperson_path(szPath, szPathP, charsmax(szPathP));
    new iEnt = find_ent_by_owner(-1, "weapon_smokegrenade", id);
    if (!iEnt) {
        return;
    }
    set_pev(iEnt, pev_viewmodel, szPath);
    // 第三人称抛掷模型: 有 p_ 则用, 缺失回退默认 p_smokegrenade
    if (bHasThird) {
        if (file_exists(szPathP)) {
            set_pev(iEnt, pev_weaponmodel, szPathP);
        } else {
            set_pev(iEnt, pev_weaponmodel, "models/p_smokegrenade.mdl");
        }
    }
}

public Smoke_Deploy_Post(const iWeapon) {
    new id = get_member(iWeapon, m_pPlayer);
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    set_task(0.05, "task_apply_smoke", id);
}
public task_apply_smoke(const id) {
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    if (g_iSelectedSmoke[id] >= 0) {
        new iSize = ArraySize(g_aSmokeModels);
        if (g_iSelectedSmoke[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aSmokeModels, g_iSelectedSmoke[id], szPath, charsmax(szPath));
            set_player_smoke_view(id, szPath);
        }
    }
}

stock set_player_flash_view(const id, const szPath[]) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }
    new szPathP[MAX_MODEL_NAME];
    new bool:bHasThird = bool:get_knife_thirdperson_path(szPath, szPathP, charsmax(szPathP));
    new iEnt = find_ent_by_owner(-1, "weapon_flashbang", id);
    if (!iEnt) {
        return;
    }
    set_pev(iEnt, pev_viewmodel, szPath);
    if (bHasThird) {
        if (file_exists(szPathP)) {
            set_pev(iEnt, pev_weaponmodel, szPathP);
        } else {
            set_pev(iEnt, pev_weaponmodel, "models/p_flashbang.mdl");
        }
    }
}

public Flash_Deploy_Post(const iWeapon) {
    new id = get_member(iWeapon, m_pPlayer);
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    set_task(0.05, "task_apply_flash", id);
}
public task_apply_flash(const id) {
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    if (g_iSelectedFlash[id] >= 0) {
        new iSize = ArraySize(g_aFlashModels);
        if (g_iSelectedFlash[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aFlashModels, g_iSelectedFlash[id], szPath, charsmax(szPath));
            set_player_flash_view(id, szPath);
        }
    }
}

public HE_Deploy_Post(const iWeapon) {
    // 暂无高爆弹皮肤类型, 保留钩子便于后续扩展; 不做任何事
    return;
}
public FM_CurWeapon(const iMsgId, const iMsgDest, const iEntity) {
    new id = iEntity;
    if (!is_user_alive(id) || !is_user_connected(id))
        return FMRES_IGNORED;
    new iWeapon = get_msg_arg_int(2);
    if (iWeapon == CSW_KNIFE) {
        if (g_iSelectedKnife[id] >= 0) {
            new iSize = ArraySize(g_aKnifeModels);
            if (g_iSelectedKnife[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                ArrayGetString(g_aKnifeModels, g_iSelectedKnife[id], szPath, charsmax(szPath));
                set_player_knife_view(id, szPath);
            }
        }
    }
    else if (iWeapon == CSW_USP) {
        if (g_iSelectedUSP[id] >= 0) {
            new iSize = ArraySize(g_aUSPModels);
            if (g_iSelectedUSP[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                ArrayGetString(g_aUSPModels, g_iSelectedUSP[id], szPath, charsmax(szPath));
                set_player_usp_view(id, szPath);
            }
        }
    }
    else if (iWeapon == CSW_SMOKEGRENADE) {
        if (g_iSelectedSmoke[id] >= 0) {
            new iSize = ArraySize(g_aSmokeModels);
            if (g_iSelectedSmoke[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                ArrayGetString(g_aSmokeModels, g_iSelectedSmoke[id], szPath, charsmax(szPath));
                set_player_smoke_view(id, szPath);
            }
        }
    }
    else if (iWeapon == CSW_FLASHBANG) {
        if (g_iSelectedFlash[id] >= 0) {
            new iSize = ArraySize(g_aFlashModels);
            if (g_iSelectedFlash[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                ArrayGetString(g_aFlashModels, g_iSelectedFlash[id], szPath, charsmax(szPath));
                set_player_flash_view(id, szPath);
            }
        }
    }
    return FMRES_IGNORED;
}

//  client_putinserver - 初始化+加载存档
public client_putinserver(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        g_iSelectedT[id] = 0;
        g_iSelectedCT[id] = 0;
        g_iSelectedKnife[id] = 0;
        g_iSelectedUSP[id] = 0;
        g_iSelectedSmoke[id] = 0;
        g_iSelectedFlash[id] = 0;
        g_iOwnedTCount[id] = 0;
        g_iOwnedCTCount[id] = 0;
        g_iOwnedKnifeCount[id] = 0;
        g_iOwnedUSPCount[id] = 0;
        g_iOwnedSmokeCount[id] = 0;
        g_iOwnedFlashCount[id] = 0;
        g_iSkinSelectType[id] = 0;
        g_iSkinSelectPage[id] = 0;
        g_iGiveTarget[id] = 0;
        g_iGiveType[id] = 0;
        g_iGivePage[id] = 0;
        g_iICPoints[id] = 0;
        g_bICLoaded[id] = false;
        g_szPlayerAuth[id][0] = EOS;
        g_szPlayerIP[id][0] = EOS;
        g_szPlayerName[id][0] = EOS;
        g_szSkinLang[id][0] = EOS;
        return;
    }

    reset_player_data(id);

    get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]));
    get_user_ip(id, g_szPlayerIP[id], charsmax(g_szPlayerIP[]), 1);
    get_user_name(id, g_szPlayerName[id], charsmax(g_szPlayerName[]));

    load_player_skins(id);
    load_player_ic(id);
}

//  client_disconnected - 保存存档
public client_disconnected(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }
    save_player_skins(id);
    save_player_ic(id);
    g_bICLoaded[id] = false;
}

//  client_authorized - Steam验证后重新加载
public client_authorized(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }
    new szAuth[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuth, charsmax(szAuth));
    if (!equal(szAuth, "STEAM_ID_LAN") && !equal(szAuth, "VALVE_ID_LAN")) {
        copy(g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]), szAuth);
        load_player_skins(id);
        load_player_ic(id);
        load_player_lang(id);
    }
}

//  重置玩家数据
stock reset_player_data(id) {
    g_iOwnedTCount[id] = 0;
    g_iOwnedCTCount[id] = 0;
    g_iOwnedKnifeCount[id] = 0;
    g_iOwnedUSPCount[id] = 0;
    g_iSelectedT[id] = -1;
    g_iSelectedCT[id] = -1;
    g_iSelectedKnife[id] = -1;
    g_iSelectedUSP[id] = -1;
    g_iSelectedSmoke[id] = -1;
    g_iSelectedFlash[id] = -1;
    g_iOwnedSmokeCount[id] = 0;
    g_iOwnedFlashCount[id] = 0;
    g_iSkinSelectType[id] = 0;
    g_iSkinSelectPage[id] = 0;
    g_iGiveTarget[id] = 0;
    g_iGiveType[id] = 0;
    g_iGivePage[id] = 0;
    g_iICPoints[id] = 0;
    g_bICLoaded[id] = false;
    g_iICTargetType[id] = 0;
    g_iICSkinPage[id] = 0;
    g_bKnifeSndOn[id] = false;
    g_szPlayerAuth[id][0] = EOS;
    g_szPlayerIP[id][0] = EOS;
    g_szPlayerName[id][0] = EOS;
}

//  === 配置加载 ===
stock load_player_models() {
    g_aTModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aTModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aCTModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aCTModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aKnifeModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aKnifeModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aKnifeThirdModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aUSPModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aUSPModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aSmokeModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aSmokeModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aFlashModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aFlashModelNames = ArrayCreate(MAX_SKIN_NAME, 1);

    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/player_models.ini", szPath);
    if (!file_exists(szPath)) {
        get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
        format(szPath, charsmax(szPath), "%s/mixsystem/player_models.ini", szPath);
    }

    new f = fopen(szPath, "rt");
    if (!f) {
        log_amx("[SkinSystem] 皮肤配置文件不存在: %s, 使用内置默认模型", szPath);
        load_default_player_models();
        return;
    }

    new szLine[512];
    new bool:bInT = false, bool:bInCT = false, bool:bInKnife = false, bool:bInUSP = false, bool:bInSmoke = false, bool:bInFlash = false;

    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (szLine[0] == ';' || szLine[0] == '/' && szLine[1] == '/' || szLine[0] == EOS) {
            continue;
        }

        if (szLine[0] == '[') {
            new len = strlen(szLine);
            if (szLine[len - 1] == ']') {
                szLine[--len] = EOS;
            }
            if (szLine[0] == '[') {
                copy(szLine, charsmax(szLine), szLine[1]);
            }
            if (equali(szLine, "T") || equali(szLine, "Terrorist") || equali(szLine, "TT")) {
                bInT = true; bInCT = false; bInKnife = false; bInUSP = false; bInSmoke = false; bInFlash = false;
            } else if (equali(szLine, "CT") || equali(szLine, "Counter-Terrorist") || equali(szLine, "CounterTerrorist")) {
                bInCT = true; bInT = false; bInKnife = false; bInUSP = false; bInSmoke = false; bInFlash = false;
            } else if (equali(szLine, "Knife") || equali(szLine, "Knives")) {
                bInKnife = true; bInT = false; bInCT = false; bInUSP = false; bInSmoke = false; bInFlash = false;
            } else if (equali(szLine, "USP") || equali(szLine, "Usp") || equali(szLine, "usp")) {
                bInUSP = true; bInT = false; bInCT = false; bInKnife = false; bInSmoke = false; bInFlash = false;
            } else if (equali(szLine, "Smoke") || equali(szLine, "smoke")) {
                bInSmoke = true; bInT = false; bInCT = false; bInKnife = false; bInUSP = false; bInFlash = false;
            } else if (equali(szLine, "Flash") || equali(szLine, "flash")) {
                bInFlash = true; bInT = false; bInCT = false; bInKnife = false; bInUSP = false; bInSmoke = false;
            } else {
                bInT = false; bInCT = false; bInKnife = false; bInUSP = false; bInSmoke = false; bInFlash = false;
            }
            continue;
        }

        new szName[MAX_SKIN_NAME];
        new szModelPath[MAX_MODEL_NAME];
        new iSpacePos = contain(szLine, " ");
        if (iSpacePos <= 0) {
            continue;
        }
        copy(szName, iSpacePos + 1, szLine);
        copy(szModelPath, charsmax(szModelPath), szLine[iSpacePos + 1]);
        trim(szName);
        trim(szModelPath);
        if (szName[0] == EOS || szModelPath[0] == EOS) {
            continue;
        }

        if (bInT) { ArrayPushString(g_aTModels, szModelPath); ArrayPushString(g_aTModelNames, szName); }
        else if (bInCT) { ArrayPushString(g_aCTModels, szModelPath); ArrayPushString(g_aCTModelNames, szName); }
        else if (bInKnife) {
            // 刀皮肤行支持可选第三字段: 名称 v_模型 [手动指定的第三人称p_模型]
            static szThird[MAX_MODEL_NAME];
            szThird[0] = EOS;
            new iThirdSpace = contain(szModelPath, " ");
            if (iThirdSpace > 0) {
                // szModelPath 形如 "v_x.mdl p_x.mdl", 拆出第二模型并保留第一
                static szFirst[MAX_MODEL_NAME];
                copy(szFirst, charsmax(szFirst), szModelPath);
                szFirst[iThirdSpace] = EOS;
                copy(szThird, charsmax(szThird), szModelPath[iThirdSpace + 1]);
                trim(szFirst); trim(szThird);
                copy(szModelPath, charsmax(szModelPath), szFirst);
            }
            ArrayPushString(g_aKnifeModels, szModelPath);
            ArrayPushString(g_aKnifeModelNames, szName);
            ArrayPushString(g_aKnifeThirdModels, szThird);
        }
        else if (bInUSP) { ArrayPushString(g_aUSPModels, szModelPath); ArrayPushString(g_aUSPModelNames, szName); }
        else if (bInSmoke) { ArrayPushString(g_aSmokeModels, szModelPath); ArrayPushString(g_aSmokeModelNames, szName); }
        else if (bInFlash) { ArrayPushString(g_aFlashModels, szModelPath); ArrayPushString(g_aFlashModelNames, szName); }
    }
    fclose(f);

    log_amx("[SkinSystem] 皮肤: T=%d, CT=%d, Knife=%d, USP=%d, Smoke=%d, Flash=%d",
        ArraySize(g_aTModels), ArraySize(g_aCTModels), ArraySize(g_aKnifeModels), ArraySize(g_aUSPModels),
        ArraySize(g_aSmokeModels), ArraySize(g_aFlashModels));
}

// 内置默认模型（配置文件不存在时使用）
stock load_default_player_models() {
    ArrayPushString(g_aTModels, "models/player/arctic/arctic.mdl");
    ArrayPushString(g_aTModelNames, "默认T");
    ArrayPushString(g_aTModels, "models/player/guerilla/guerilla.mdl");
    ArrayPushString(g_aTModelNames, "中东游击");
    ArrayPushString(g_aTModels, "models/player/leet/leet.mdl");
    ArrayPushString(g_aTModelNames, "精英部队");
    ArrayPushString(g_aTModels, "models/player/terror/terror.mdl");
    ArrayPushString(g_aTModelNames, "凤凰战士");

    ArrayPushString(g_aCTModels, "models/player/gsg9/gsg9.mdl");
    ArrayPushString(g_aCTModelNames, "默认CT");
    ArrayPushString(g_aCTModels, "models/player/gsg9/gsg9.mdl");
    ArrayPushString(g_aCTModelNames, "德国GSG9");
    ArrayPushString(g_aCTModels, "models/player/gign/gign.mdl");
    ArrayPushString(g_aCTModelNames, "法国GIGN");
    ArrayPushString(g_aCTModels, "models/player/sas/sas.mdl");
    ArrayPushString(g_aCTModelNames, "英国SAS");
    ArrayPushString(g_aCTModels, "models/player/urban/urban.mdl");
    ArrayPushString(g_aCTModelNames, "美国城市特警");

    ArrayPushString(g_aKnifeModels, "models/v_knife.mdl");
    ArrayPushString(g_aKnifeModelNames, "默认刀");
    ArrayPushString(g_aKnifeThirdModels, "models/p_knife.mdl");

    ArrayPushString(g_aUSPModels, "models/v_usp.mdl");
    ArrayPushString(g_aUSPModelNames, "默认USP");

    ArrayPushString(g_aSmokeModels, "models/v_smokegrenade.mdl");
    ArrayPushString(g_aSmokeModelNames, "默认烟雾弹");

    ArrayPushString(g_aFlashModels, "models/v_flashbang.mdl");
    ArrayPushString(g_aFlashModelNames, "默认闪光弹");
}

//  === 预缓存 ===
stock precache_all_models() {
    new szModel[MAX_MODEL_NAME];
    new i, iSize;

    iSize = ArraySize(g_aTModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aTModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    iSize = ArraySize(g_aCTModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aCTModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    iSize = ArraySize(g_aKnifeModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aKnifeModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    // 预缓存手动指定的第三人称刀模型 (非空项)
    iSize = ArraySize(g_aKnifeThirdModels);
    for (i = 0; i < iSize; i++) {
        ArrayGetString(g_aKnifeThirdModels, i, szModel, charsmax(szModel));
        if (szModel[0] != EOS) precache_model(szModel);
    }
    iSize = ArraySize(g_aUSPModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aUSPModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
}

//  === 模型应用 ===
public OnTeamInfoChange(const iMsgId, const iMsgDest, const iEntity) {
    new id = get_msg_arg_int(1);
    if (id < 1 || id > MAX_PLAYERS) {
        return;
    }
    if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id)) {
        return;
    }
    set_task(0.2, "task_apply_model", id);
}

public OnPlayerSpawn(const id) {
    set_task(0.15, "task_apply_model", id);
}

public task_apply_model(const id) {
    if (!is_user_alive(id)) {
        return;
    }
    apply_model(id);
}

stock bool:is_shared_mode() {
    return get_pcvar_num(g_pShared) != 0;
}

stock apply_model(const id) {
    if (!is_user_alive(id)) {
        return;
    }

    new TeamName:iTeam = get_member(id, m_iTeam);

    // --- 身体模型 ---
    if (is_shared_mode()) {
        if (g_iSelectedT[id] >= 0) {
            new iSize = ArraySize(g_aTModels);
            if (g_iSelectedT[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                new szFolder[MAX_MODEL_NAME];
                ArrayGetString(g_aTModels, g_iSelectedT[id], szPath, charsmax(szPath));
                extract_folder_from_path(szPath, szFolder, charsmax(szFolder));
                rg_set_user_model(id, szFolder, true);
            }
        } else {
            rg_reset_user_model(id);
        }
    }
    else if (iTeam == TEAM_TERRORIST) {
        if (g_iSelectedT[id] >= 0) {
            new iSize = ArraySize(g_aTModels);
            if (g_iSelectedT[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                new szFolder[MAX_MODEL_NAME];
                ArrayGetString(g_aTModels, g_iSelectedT[id], szPath, charsmax(szPath));
                extract_folder_from_path(szPath, szFolder, charsmax(szFolder));
                rg_set_user_model(id, szFolder, true);
            }
        } else {
            rg_reset_user_model(id);
        }
    }
    else if (iTeam == TEAM_CT) {
        if (g_iSelectedCT[id] >= 0) {
            new iSize = ArraySize(g_aCTModels);
            if (g_iSelectedCT[id] < iSize) {
                new szPath[MAX_MODEL_NAME];
                new szFolder[MAX_MODEL_NAME];
                ArrayGetString(g_aCTModels, g_iSelectedCT[id], szPath, charsmax(szPath));
                extract_folder_from_path(szPath, szFolder, charsmax(szFolder));
                rg_set_user_model(id, szFolder, true);
            }
        } else {
            rg_reset_user_model(id);
        }
    }

    // --- 刀模型 ---
    if (g_iSelectedKnife[id] >= 0) {
        new iSize = ArraySize(g_aKnifeModels);
        if (g_iSelectedKnife[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aKnifeModels, g_iSelectedKnife[id], szPath, charsmax(szPath));
            set_player_knife_view(id, szPath);
        }
    }

    // --- USP模型 ---
    if (g_iSelectedUSP[id] >= 0) {
        new iSize = ArraySize(g_aUSPModels);
        if (g_iSelectedUSP[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aUSPModels, g_iSelectedUSP[id], szPath, charsmax(szPath));
            set_player_usp_view(id, szPath);
        }
    }

    // --- 烟雾弹模型 ---
    if (g_iSelectedSmoke[id] >= 0) {
        new iSize = ArraySize(g_aSmokeModels);
        if (g_iSelectedSmoke[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aSmokeModels, g_iSelectedSmoke[id], szPath, charsmax(szPath));
            set_player_smoke_view(id, szPath);
        }
    }

    // --- 闪光弹模型 ---
    if (g_iSelectedFlash[id] >= 0) {
        new iSize = ArraySize(g_aFlashModels);
        if (g_iSelectedFlash[id] < iSize) {
            new szPath[MAX_MODEL_NAME];
            ArrayGetString(g_aFlashModels, g_iSelectedFlash[id], szPath, charsmax(szPath));
            set_player_flash_view(id, szPath);
        }
    }
}

// 从路径提取文件夹名
stock extract_folder_from_path(const szPath[], szFolder[], iLen) {
    new iLastSlash = 0;
    new i, len = strlen(szPath);
    for (i = 0; i < len; i++) {
        if (szPath[i] == '/' || szPath[i] == 92) {
            iLastSlash = i;
        }
    }
    if (iLastSlash <= 0) {
        copy(szFolder, iLen, szPath);
        return;
    }
    new szTemp[MAX_MODEL_NAME];
    copy(szTemp, charsmax(szTemp), szPath[iLastSlash + 1]);
    if (contain(szTemp, "v_knife") >= 0 || contain(szTemp, "v_") >= 0) {
        new szDir[MAX_MODEL_NAME];
        copy(szDir, charsmax(szDir), szPath);
        szDir[iLastSlash] = EOS;
        new iPrevSlash = 0;
        for (i = 0; i < iLastSlash; i++) {
            if (szDir[i] == '/' || szDir[i] == 92) {
                iPrevSlash = i;
            }
        }
        if (iPrevSlash > 0) {
            copy(szFolder, iLen, szDir[iPrevSlash + 1]);
        } else {
            copy(szFolder, iLen, szDir);
        }
    } else {
        new iExt = contain(szTemp, ".mdl");
        if (iExt > 0) {
            szTemp[iExt] = EOS;
        }
        copy(szFolder, iLen, szTemp);
    }
}

//  === 皮肤选择菜单 ===
public srvCmdGiveAllSkins() {
    new szUserId[8], szType[16];
    read_argv(1, szUserId, charsmax(szUserId));
    read_argv(2, szType, charsmax(szType));

    new id = find_player("k", str_to_num(szUserId));
    if (!id || !is_user_connected(id)) return PLUGIN_HANDLED;

    if (equali(szType, "T")) {
        new iTotal = ArraySize(g_aTModels);
        g_iOwnedTCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedT[id][i] = i; g_iOwnedTCount[id]++; }
        if (g_iSelectedT[id] < 0) g_iSelectedT[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部T皮肤给你(%d个)", iTotal);
    } else if (equali(szType, "CT")) {
        new iTotal = ArraySize(g_aCTModels);
        g_iOwnedCTCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedCT[id][i] = i; g_iOwnedCTCount[id]++; }
        if (g_iSelectedCT[id] < 0) g_iSelectedCT[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部CT皮肤给你(%d个)", iTotal);
    } else if (equali(szType, "Knife")) {
        new iTotal = ArraySize(g_aKnifeModels);
        g_iOwnedKnifeCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedKnife[id][i] = i; g_iOwnedKnifeCount[id]++; }
        if (g_iSelectedKnife[id] < 0) g_iSelectedKnife[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部刀皮肤给你(%d个)", iTotal);
    } else if (equali(szType, "USP")) {
        new iTotal = ArraySize(g_aUSPModels);
        g_iOwnedUSPCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedUSP[id][i] = i; g_iOwnedUSPCount[id]++; }
        if (g_iSelectedUSP[id] < 0) g_iSelectedUSP[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部USP皮肤给你(%d个)", iTotal);
    } else if (equali(szType, "Smoke")) {
        new iTotal = ArraySize(g_aSmokeModels);
        g_iOwnedSmokeCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedSmoke[id][i] = i; g_iOwnedSmokeCount[id]++; }
        if (g_iSelectedSmoke[id] < 0) g_iSelectedSmoke[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部烟雾弹皮肤给你(%d个)", iTotal);
    } else if (equali(szType, "Flash")) {
        new iTotal = ArraySize(g_aFlashModels);
        g_iOwnedFlashCount[id] = 0;
        for (new i = 0; i < iTotal && i < MAX_OWNED_SKINS; i++) { g_iOwnedFlash[id][i] = i; g_iOwnedFlashCount[id]++; }
        if (g_iSelectedFlash[id] < 0) g_iSelectedFlash[id] = 0;
        save_player_skins(id);
        client_print(id, print_chat, "[SkinSystem] 管理员已发放全部闪光弹皮肤给你(%d个)", iTotal);
    }

    if (is_user_alive(id)) apply_model(id);
    return PLUGIN_HANDLED;
}

public srvCmdGiveSkinMenu() {
    new szAdminId[8], szTargetId[8], szType[16];
    read_argv(1, szAdminId, charsmax(szAdminId));
    read_argv(2, szTargetId, charsmax(szTargetId));
    read_argv(3, szType, charsmax(szType));

    new id = find_player("k", str_to_num(szAdminId));
    new iTarget = find_player("k", str_to_num(szTargetId));
    if (!id || !is_user_connected(id)) return PLUGIN_HANDLED;
    if (!iTarget || !is_user_connected(iTarget)) return PLUGIN_HANDLED;

    g_iGiveTarget[id] = iTarget;
    g_iGivePage[id] = 0;

    if (equali(szType, "T")) { g_iGiveType[id] = 1; }
    else if (equali(szType, "CT")) { g_iGiveType[id] = 2; }
    else if (equali(szType, "Knife")) { g_iGiveType[id] = 3; }
    else if (equali(szType, "USP")) { g_iGiveType[id] = 4; }
    else if (equali(szType, "Smoke")) { g_iGiveType[id] = 5; }
    else if (equali(szType, "Flash")) { g_iGiveType[id] = 6; }
    else return PLUGIN_HANDLED;

    showGiveSkinListMenu(id);
    return PLUGIN_HANDLED;
}

public cmdSkinSelectT(const id) {
    g_iSkinSelectType[id] = 0;
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}
public cmdSkinSelectCT(const id) {
    if (is_shared_mode()) {
        g_iSkinSelectType[id] = 0;
    } else {
        g_iSkinSelectType[id] = 1;
    }
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}
public cmdSkinSelectKnife(const id) {
    g_iSkinSelectType[id] = 2;
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}
public cmdSkinSelectUSP(const id) {
    g_iSkinSelectType[id] = 3;
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}
public cmdSkinSelectSmoke(const id) {
    g_iSkinSelectType[id] = 4;
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}
public cmdSkinSelectFlash(const id) {
    g_iSkinSelectType[id] = 5;
    g_iSkinSelectPage[id] = 0;
    showSkinSelectMenu(id);
    return PLUGIN_HANDLED;
}

bool:is_skin_owned(const id, const iType, const iModelIdx) {
    new iOwnedCount, iOwned[MAX_OWNED_SKINS];
    if (iType == 0) {
        iOwnedCount = g_iOwnedTCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedT[id][i];
    } else if (iType == 1) {
        iOwnedCount = g_iOwnedCTCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedCT[id][i];
    } else if (iType == 2) {
        iOwnedCount = g_iOwnedKnifeCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedKnife[id][i];
    } else if (iType == 3) {
        iOwnedCount = g_iOwnedUSPCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedUSP[id][i];
    } else if (iType == 4) {
        iOwnedCount = g_iOwnedSmokeCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedSmoke[id][i];
    } else {
        iOwnedCount = g_iOwnedFlashCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedFlash[id][i];
    }
    for (new i = 0; i < iOwnedCount; i++) {
        if (iOwned[i] == iModelIdx) return true;
    }
    return false;
}

stock count_owned_skins(const id, const iType) {
    new iCount;
    if (iType == 0)      iCount = g_iOwnedTCount[id];
    else if (iType == 1) iCount = g_iOwnedCTCount[id];
    else if (iType == 2) iCount = g_iOwnedKnifeCount[id];
    else if (iType == 3) iCount = g_iOwnedUSPCount[id];
    else if (iType == 4) iCount = g_iOwnedSmokeCount[id];
    else                 iCount = g_iOwnedFlashCount[id];
    return iCount;
}

showSkinSelectMenu(const id) {
    if (!is_user_connected(id)) return;

    new iType = g_iSkinSelectType[id];
    new iPage = g_iSkinSelectPage[id];

    new Array:aModels;
    new iSelected, szTitle[32];

    if (iType == 0) {
        aModels = g_aTModels;
        iSelected = g_iSelectedT[id];
        tr_key(id, is_shared_mode() ? "MENU_PERSON" : "MENU_T_PERSON", szTitle, charsmax(szTitle));
    }
    else if (iType == 1) {
        aModels = g_aCTModels;
        iSelected = g_iSelectedCT[id];
        tr_key(id, "MENU_CT_PERSON", szTitle, charsmax(szTitle));
    }
    else if (iType == 2) {
        aModels = g_aKnifeModels;
        iSelected = g_iSelectedKnife[id];
        tr_key(id, "MENU_KNIFE", szTitle, charsmax(szTitle));
    }
    else if (iType == 3) {
        aModels = g_aUSPModels;
        iSelected = g_iSelectedUSP[id];
        tr_key(id, "MENU_USP", szTitle, charsmax(szTitle));
    }
    else if (iType == 4) {
        aModels = g_aSmokeModels;
        iSelected = g_iSelectedSmoke[id];
        tr_key(id, "MENU_SMOKE", szTitle, charsmax(szTitle));
    }
    else if (iType == 5) {
        aModels = g_aFlashModels;
        iSelected = g_iSelectedFlash[id];
        tr_key(id, "MENU_FLASH", szTitle, charsmax(szTitle));
    }

    new iTotalModels = ArraySize(aModels);
    if (iTotalModels <= 0) {
        new szMsg[64];
        tr_key(id, "SKINSYS_NOSKIN", szMsg, charsmax(szMsg));
        client_print(id, print_chat, "[SkinSystem] %s", szMsg);
        return;
    }

    new iStart = iPage * 8;
    new iEnd = iStart + 8;
    if (iEnd > iTotalModels) iEnd = iTotalModels;

    new szMenu[512], iLen;
    new szOwnedInfo[64], szSysTitle[24], szUnlocked[24], szPageTxt[48], szPageFmt[32], szNext[16], szPrev[16], szExit[16], szNotOwned[24];
    tr_key(id, "SKIN_SYS_TITLE", szSysTitle, charsmax(szSysTitle));
    tr_key(id, "SKIN_UNLOCKED", szUnlocked, charsmax(szUnlocked));
    tr_key(id, "MENU_PAGE", szPageFmt, charsmax(szPageFmt));
    tr_key(id, "MENU_NEXT", szNext, charsmax(szNext));
    tr_key(id, "MENU_PREV", szPrev, charsmax(szPrev));
    tr_key(id, "MENU_EXIT", szExit, charsmax(szExit));
    tr_key(id, "SKIN_NOTOWNED", szNotOwned, charsmax(szNotOwned));

    new iOwnedCount = count_owned_skins(id, iType);
    formatex(szOwnedInfo, charsmax(szOwnedInfo), "\g%d\w/\d%d \w%s", iOwnedCount, iTotalModels, szUnlocked);
    formatex(szPageTxt, charsmax(szPageTxt), szPageFmt, iPage + 1, (iTotalModels + 7) / 8);
    iLen = formatex(szMenu, charsmax(szMenu), "\w%s \y- \w%s^n\y──── \w%s ^1%s \y────────^n^n", szSysTitle, szTitle, szPageTxt, szOwnedInfo);

    new szName[64], iModelIdx;
    new bool:bOwned;
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9);

    for (new i = iStart; i < iEnd; i++) {
        iModelIdx = i;
        get_skin_display_name(iType, iModelIdx, szName, charsmax(szName), id);
        bOwned = is_skin_owned(id, iType, iModelIdx);

        new iSlot = i - iStart + 1;
        new szMarker[8] = "";
        if (iModelIdx == iSelected) copy(szMarker, charsmax(szMarker), " ✓");

        if (bOwned) {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s%s^n", iSlot, szName, szMarker);
        } else {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \d%s \r(%s)^n", iSlot, szName, szNotOwned);
        }
    }

    for (new i = iEnd; i < iStart + 8; i++) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y────────^n");

    if (iTotalModels > iEnd) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \w%s^n", szNext);
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    }
    if (iPage > 0) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b0. \w%s^n", szPrev);
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b0. \w%s\n", szExit);
    }

    show_menu(id, iKeys, szMenu, -1, "HnsSkinSkinSelect");
}

public handleSkinSelectMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new iType = g_iSkinSelectType[id];
    new iPage = g_iSkinSelectPage[id];

    new Array:aModels;
    if (iType == 0) aModels = g_aTModels;
    else if (iType == 1) aModels = g_aCTModels;
    else if (iType == 2) aModels = g_aKnifeModels;
    else if (iType == 3) aModels = g_aUSPModels;
    else if (iType == 4) aModels = g_aSmokeModels;
    else aModels = g_aFlashModels;
    new iTotalModels = ArraySize(aModels);

    if (key == 8) { // 9 键 -> 下一页
        new iMaxPage = ((iTotalModels - 1) / 8);
        if (iPage < iMaxPage) {
            g_iSkinSelectPage[id]++;
            showSkinSelectMenu(id);
        } else {
            new szMsg[64];
            tr_key(id, "SKINSYS_LASTPAGE", szMsg, charsmax(szMsg));
            client_print_color(id, print_team_default, "^4[HnsSkin] ^1%s", szMsg);
        }
        return PLUGIN_HANDLED;
    }
    if (key == 9) { // 0 键 -> 退出 / 上一页
        if (iPage > 0) {
            g_iSkinSelectPage[id]--;
            showSkinSelectMenu(id);
        } else {
            // 第一页按0 -> 回到主菜单(避免"没反应")
            cmdSkinMain(id);
        }
        return PLUGIN_HANDLED;
    }

    new iSlot = key;
    new iModelIdx = iPage * 8 + iSlot;

    new iMaxPage = ((iTotalModels - 1) / 8);
    if (g_iSkinSelectPage[id] > iMaxPage) g_iSkinSelectPage[id] = iMaxPage;
    if (g_iSkinSelectPage[id] < 0) g_iSkinSelectPage[id] = 0;

    if (iModelIdx >= 0 && iModelIdx < iTotalModels) {
        if (!is_skin_owned(id, iType, iModelIdx)) {
            new szMsg[96];
            tr_key(id, "SKINSYS_LOCKED", szMsg, charsmax(szMsg));
            client_print(id, print_chat, "[SkinSystem] %s", szMsg);
            showSkinSelectMenu(id);
            return PLUGIN_HANDLED;
        }

        if (iType == 0) {
            g_iSelectedT[id] = iModelIdx;
            if (is_shared_mode()) {
                g_iSelectedCT[id] = iModelIdx;
            }
            save_player_skins(id);
            play_skin_apply_sfx(id);   // 换肤提示音
            apply_model(id);
        }
        else if (iType == 1) {
            g_iSelectedCT[id] = iModelIdx;
            save_player_skins(id);
            play_skin_apply_sfx(id);
            apply_model(id);
        }
        else if (iType == 2) {
            g_iSelectedKnife[id] = iModelIdx;
            save_player_skins(id);
            g_bKnifeSndOn[id] = true;   // 主动换刀皮肤 -> 出刀时播提示音
            apply_model(id);
        }
        else if (iType == 3) {
            g_iSelectedUSP[id] = iModelIdx;
            save_player_skins(id);
            play_menu_click_sfx(id);
            apply_model(id);
        }
        else if (iType == 4) {
            g_iSelectedSmoke[id] = iModelIdx;
            save_player_skins(id);
            play_menu_click_sfx(id);
            apply_model(id);
        }
        else if (iType == 5) {
            g_iSelectedFlash[id] = iModelIdx;
            save_player_skins(id);
            play_menu_click_sfx(id);
            apply_model(id);
        }

        set_task(0.1, "taskRefreshSkinMenu", id);
    }

    return PLUGIN_HANDLED;
}

public taskRefreshSkinMenu(const id) {
    if (is_user_connected(id)) {
        showSkinSelectMenu(id);
    }
}

//  === M键玩家菜单 ===
public cmdMenu(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_CONTINUE;
    }
    client_cmd(id, "chooseteam");
    return PLUGIN_HANDLED;
}

//  === 批量发放全部皮肤 (/giveallskins) ===
public cmdGiveAllSkins(const id) {
    if (!is_user_connected(id)) return PLUGIN_CONTINUE;

    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证管理员才能发放皮肤");
        return PLUGIN_HANDLED;
    }

    new szArgs[256];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    new szTemp[256];
    copy(szTemp, charsmax(szTemp), szArgs);
    new iPos = contain(szTemp, "giveallskins ");
    if (iPos >= 0) {
        copy(szArgs, charsmax(szArgs), szTemp[iPos + 13]);
        trim(szArgs);
    }

    new szTargetName[32], szTypeStr[16];
    parse(szArgs, szTargetName, charsmax(szTargetName), szTypeStr, charsmax(szTypeStr));

    if (szTargetName[0] == EOS || szTypeStr[0] == EOS) {
        client_print(id, print_chat, "[SkinSystem] 用法: /giveallskins <玩家名> <T/CT/Knife/all>");
        return PLUGIN_HANDLED;
    }

    new iTarget = find_player_by_name(szTargetName);
    if (iTarget == 0) {
        client_print(id, print_chat, "[SkinSystem] 找不到玩家: %s", szTargetName);
        return PLUGIN_HANDLED;
    }

    new szAdminName[32], szTargetRealName[32];
    get_user_name(id, szAdminName, charsmax(szAdminName));
    get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));

    new iCount = 0;
    new bool:bT = false, bool:bCT = false, bool:bKnife = false, bool:bUSP = false, bool:bSmoke = false, bool:bFlash = false;

    if (equali(szTypeStr, "all")) {
        bT = true; bCT = true; bKnife = true; bUSP = true; bSmoke = true; bFlash = true;
    } else if (equali(szTypeStr, "T") || equali(szTypeStr, "t")) {
        bT = true;
    } else if (equali(szTypeStr, "CT") || equali(szTypeStr, "ct")) {
        bCT = true;
    } else if (equali(szTypeStr, "Knife") || equali(szTypeStr, "knife") || equali(szTypeStr, "刀")) {
        bKnife = true;
    } else if (equali(szTypeStr, "USP") || equali(szTypeStr, "usp")) {
        bUSP = true;
    } else if (equali(szTypeStr, "Smoke") || equali(szTypeStr, "smoke") || equali(szTypeStr, "烟雾")) {
        bSmoke = true;
    } else if (equali(szTypeStr, "Flash") || equali(szTypeStr, "flash") || equali(szTypeStr, "闪光")) {
        bFlash = true;
    } else {
        client_print(id, print_chat, "[SkinSystem] 无效类型: %s, 请用 T/CT/Knife/USP/Smoke/Flash/all", szTypeStr);
        return PLUGIN_HANDLED;
    }

    if (bT) {
        new iSize = ArraySize(g_aTModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 0, i)) { give_skin(iTarget, 0, i); iCount++; }
        }
    }
    if (bCT) {
        new iSize = ArraySize(g_aCTModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 1, i)) { give_skin(iTarget, 1, i); iCount++; }
        }
    }
    if (bKnife) {
        new iSize = ArraySize(g_aKnifeModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 2, i)) { give_skin(iTarget, 2, i); iCount++; }
        }
    }
    if (bUSP) {
        new iSize = ArraySize(g_aUSPModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 3, i)) { give_skin(iTarget, 3, i); iCount++; }
        }
    }
    if (bSmoke) {
        new iSize = ArraySize(g_aSmokeModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 4, i)) { give_skin(iTarget, 4, i); iCount++; }
        }
    }
    if (bFlash) {
        new iSize = ArraySize(g_aFlashModels);
        for (new i = 0; i < iSize; i++) {
            if (!has_skin(iTarget, 5, i)) { give_skin(iTarget, 5, i); iCount++; }
        }
    }

    save_player_skins(iTarget);

    client_print(id, print_chat, "[SkinSystem] 已向 %s 发放 %s类型全部皮肤 (%d个)", szTargetRealName, szTypeStr, iCount);
    client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了 %s类型全部皮肤 (%d个)", szAdminName, szTypeStr, iCount);

    return PLUGIN_HANDLED;
}

//  === 管理员给指定玩家发放皮肤 - 菜单方式 (/giveskin) ===
public cmdGiveSkinMenuStart(const id) {
    if (!is_user_connected(id)) return PLUGIN_CONTINUE;

    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证管理员才能发放皮肤");
        return PLUGIN_HANDLED;
    }

    g_iGivePage[id] = 0;
    showGiveSelectPlayerMenu(id);
    return PLUGIN_HANDLED;
}

showGiveSelectPlayerMenu(const id) {
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ch");

    if (iNum == 0) {
        client_print(id, print_chat, "[SkinSystem] 当前没有在线玩家");
        return;
    }

    new iPage = g_iGivePage[id];
    new iStart = iPage * 8;
    new iEnd = iStart + 8;
    if (iEnd > iNum) iEnd = iNum;

    new szMenu[512], iLen, szName[32], iPlayer;
    iLen = formatex(szMenu, charsmax(szMenu), "\y选择要发放皮肤的目标玩家^n\y─────── 第%d页 ───────^n^n", iPage + 1);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9);

    for (new i = iStart; i < iEnd; i++) {
        iPlayer = iPlayers[i];
        get_user_name(iPlayer, szName, charsmax(szName));
        new iSlot = i - iStart + 1;
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s^n", iSlot, szName);
    }

    for (new i = iEnd; i < iStart + 8; i++) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y───────^n");
    if (iPage > 0) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w上一页^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回^n");
    }
    if (iNum > iEnd) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \w下一页^n");
    }

    show_menu(id, iKeys, szMenu, -1, "HnsSkinGiveSelectPlayer");
}

public handleGiveSelectPlayer(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ch");

    if (key == 8) {
        g_iGivePage[id]++;
        showGiveSelectPlayerMenu(id);
        return PLUGIN_HANDLED;
    }
    if (key == 9) {
        if (g_iGivePage[id] > 0) {
            g_iGivePage[id]--;
            showGiveSelectPlayerMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new iAbsIndex = g_iGivePage[id] * 8 + key;
    if (iAbsIndex >= 0 && iAbsIndex < iNum) {
        g_iGiveTarget[id] = iPlayers[iAbsIndex];
        g_iGivePage[id] = 0;
        showGiveSelectTypeMenu(id);
    }

    return PLUGIN_HANDLED;
}

showGiveSelectTypeMenu(const id) {
    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return PLUGIN_HANDLED;
    }

    new szTargetName[32];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));

    new szMenu[256];
    formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放皮肤^n^n\r1. \w单个发放皮肤^n\r2. \w全部发放皮肤^n^n\r0. \w返回", szTargetName);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinGiveSelectType");
}

public handleGiveSelectType(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    if (key == 9) {
        showGiveSelectPlayerMenu(id);
        return PLUGIN_HANDLED;
    }

    if (key == 0) {
        g_iGiveType[id] = 0;
        g_iGivePage[id] = 0;
        showGiveSkinTypeMenu(id);
    } else if (key == 1) {
        showGiveAllTypeMenu(id);
    }

    return PLUGIN_HANDLED;
}

showGiveSkinTypeMenu(const id) {
    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return;
    }
    new szTargetName[32];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));

    new szMenu[256];
    formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放单个皮肤^n选择皮肤类型:^n^n\r1. \wT(土匪)皮肤^n\r2. \wCT(警察)皮肤^n\r3. \w刀皮肤^n\r4. \wUSP皮肤^n\r5. \w烟雾弹皮肤^n\r6. \w闪光弹皮肤^n^n\r0. \w返回", szTargetName);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinGiveSelectSkin");
}

showGiveAllTypeMenu(const id) {
    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return;
    }
    new szTargetName[32];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));

    new szMenu[256];
    formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放全部皮肤^n选择类型:^n^n\r1. \wT(土匪)全部^n\r2. \wCT(警察)全部^n\r3. \w刀全部^n\r4. \wUSP全部^n\r5. \w全部类型(含烟雾/闪光)^n^n\r0. \w返回", szTargetName);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinGiveSelectSkin");
}

public handleGiveSelectSkin(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return PLUGIN_HANDLED;
    }

    if (key == 9) {
        showGiveSelectTypeMenu(id);
        return PLUGIN_HANDLED;
    }

    if (g_iGiveType[id] == 0) {
        // 单个皮肤: 选择类型后进入该类型的皮肤列表
        if (key == 0) { g_iGiveType[id] = 1; }       // T
        else if (key == 1) { g_iGiveType[id] = 2; }  // CT
        else if (key == 2) { g_iGiveType[id] = 3; }  // 刀
        else if (key == 3) { g_iGiveType[id] = 4; }  // USP
        else if (key == 4) { g_iGiveType[id] = 5; }  // 烟雾
        else if (key == 5) { g_iGiveType[id] = 6; }  // 闪光
        g_iGivePage[id] = 0;
        showGiveSkinListMenu(id);
        return PLUGIN_HANDLED;
    }

    // "发放全部" 模式
    new szAdminName[32], szTargetRealName[32];
    get_user_name(id, szAdminName, charsmax(szAdminName));
    get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));
    new iCount = 0;
    new szTypeStr[32];
    szTypeStr = "全部";

    if (key == 0) {
        give_all_of_type(iTarget, 0, g_aTModels, iCount);   // T
        szTypeStr = "T";
    } else if (key == 1) {
        give_all_of_type(iTarget, 1, g_aCTModels, iCount);  // CT
        szTypeStr = "CT";
    } else if (key == 2) {
        give_all_of_type(iTarget, 2, g_aKnifeModels, iCount); // 刀
        szTypeStr = "Knife";
    } else if (key == 3) {
        give_all_of_type(iTarget, 3, g_aUSPModels, iCount);  // USP
        szTypeStr = "USP";
    } else if (key == 4) {
        // 全部 (含烟雾/闪光)
        give_all_of_type(iTarget, 0, g_aTModels, iCount);
        give_all_of_type(iTarget, 1, g_aCTModels, iCount);
        give_all_of_type(iTarget, 2, g_aKnifeModels, iCount);
        give_all_of_type(iTarget, 3, g_aUSPModels, iCount);
        give_all_of_type(iTarget, 4, g_aSmokeModels, iCount);
        give_all_of_type(iTarget, 5, g_aFlashModels, iCount);
        szTypeStr = "全部";
    }

    save_player_skins(iTarget);

    client_print(id, print_chat, "[SkinSystem] 已向 %s 发放 %s类型全部皮肤 (%d个)", szTargetRealName, szTypeStr, iCount);
    client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了 %s类型全部皮肤 (%d个)", szAdminName, szTypeStr, iCount);

    return PLUGIN_HANDLED;
}

showGiveSkinListMenu(const id) {
    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return;
    }

    new iType = g_iGiveType[id] - 1;
    new Array:aModels, Array:aModelNames;
    new szTypeName[8];
    if (iType == 0) { aModels = g_aTModels; aModelNames = g_aTModelNames; copy(szTypeName, charsmax(szTypeName), "T"); }
    else if (iType == 1) { aModels = g_aCTModels; aModelNames = g_aCTModelNames; copy(szTypeName, charsmax(szTypeName), "CT"); }
    else if (iType == 2) { aModels = g_aKnifeModels; aModelNames = g_aKnifeModelNames; copy(szTypeName, charsmax(szTypeName), "Knife"); }
    else if (iType == 3) { aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; copy(szTypeName, charsmax(szTypeName), "USP"); }
    else if (iType == 4) { aModels = g_aSmokeModels; aModelNames = g_aSmokeModelNames; copy(szTypeName, charsmax(szTypeName), "烟雾"); }
    else { aModels = g_aFlashModels; aModelNames = g_aFlashModelNames; copy(szTypeName, charsmax(szTypeName), "闪光"); }

    new iTotal = ArraySize(aModels);
    new iPage = g_iGivePage[id];
    new iStart = iPage * 7;
    new iEnd = iStart + 7;
    if (iEnd > iTotal) iEnd = iTotal;

    new szTargetName[32];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));

    new szMenu[512], iLen, szName[64];
    iLen = formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放 %s 皮肤^n\y─────── 第%d页 ───────^n^n", szTargetName, szTypeName, iPage + 1);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9);

    for (new i = iStart; i < iEnd; i++) {
        ArrayGetString(aModelNames, i, szName, charsmax(szName));
        new iSlot = i - iStart + 1;
        new bool:bOwned = has_skin(iTarget, iType, i);
        if (bOwned) {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \d%s \r(已拥有)^n", iSlot, szName);
        } else {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s^n", iSlot, szName);
        }
    }

    for (new i = iEnd; i < iStart + 7; i++) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y───────^n");
    if (iPage > 0) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w上一页^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回^n");
    }
    if (iTotal > iEnd) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \w下一页^n");
    }

    show_menu(id, iKeys, szMenu, -1, "HnsSkinGiveSelectSkinList");
}

public handleGiveSelectSkinList(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new iTarget = g_iGiveTarget[id];
    if (!is_user_connected(iTarget)) {
        client_print(id, print_chat, "[SkinSystem] 目标玩家已离线");
        return PLUGIN_HANDLED;
    }

    new iType = g_iGiveType[id] - 1;
    new Array:aModels, Array:aModelNames;
    if (iType == 0) { aModels = g_aTModels; aModelNames = g_aTModelNames; }
    else if (iType == 1) { aModels = g_aCTModels; aModelNames = g_aCTModelNames; }
    else if (iType == 2) { aModels = g_aKnifeModels; aModelNames = g_aKnifeModelNames; }
    else if (iType == 3) { aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; }
    else if (iType == 4) { aModels = g_aSmokeModels; aModelNames = g_aSmokeModelNames; }
    else { aModels = g_aFlashModels; aModelNames = g_aFlashModelNames; }

    if (key == 8) {
        g_iGivePage[id]++;
        showGiveSkinListMenu(id);
        return PLUGIN_HANDLED;
    }
    if (key == 9) {
        if (g_iGivePage[id] > 0) {
            g_iGivePage[id]--;
            showGiveSkinListMenu(id);
        } else {
            showGiveSkinTypeMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new iTotal = ArraySize(aModels);
    new iSkinIndex = g_iGivePage[id] * 7 + key;
    if (iSkinIndex >= 0 && iSkinIndex < iTotal) {
        if (has_skin(iTarget, iType, iSkinIndex)) {
            new szModelName[MAX_SKIN_NAME];
            ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));
            client_print(id, print_chat, "[SkinSystem] 玩家已拥有该皮肤: %s", szModelName);
            set_task(0.1, "taskRefreshGiveSkinMenu", id);
            return PLUGIN_HANDLED;
        }

        give_skin(iTarget, iType, iSkinIndex);
        save_player_skins(iTarget);

        new szAdminName[32], szTargetRealName[32], szModelName[MAX_SKIN_NAME];
        get_user_name(id, szAdminName, charsmax(szAdminName));
        get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));
        ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));
        new szTypeStr[8];
        if (iType == 0) copy(szTypeStr, charsmax(szTypeStr), "T");
        else if (iType == 1) copy(szTypeStr, charsmax(szTypeStr), "CT");
        else if (iType == 2) copy(szTypeStr, charsmax(szTypeStr), "Knife");
        else if (iType == 3) copy(szTypeStr, charsmax(szTypeStr), "USP");
        else if (iType == 4) copy(szTypeStr, charsmax(szTypeStr), "烟雾");
        else copy(szTypeStr, charsmax(szTypeStr), "闪光");

        client_print(id, print_chat, "[SkinSystem] 已向 %s 发放皮肤: %s (%s)", szTargetRealName, szModelName, szTypeStr);
        client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了皮肤: %s (%s)", szAdminName, szModelName, szTypeStr);

        set_task(0.1, "taskRefreshGiveSkinMenu", id);
    }

    return PLUGIN_HANDLED;
}

public taskRefreshGiveSkinMenu(const id) {
    if (is_user_connected(id)) {
        showGiveSkinListMenu(id);
    }
}

// 命令行方式发放单个皮肤（保留兼容）
public cmdGiveSkinCmd(const id) {
    if (!is_user_connected(id)) return PLUGIN_CONTINUE;

    if (!is_official_admin(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证管理员才能发放皮肤");
        return PLUGIN_HANDLED;
    }

    new szArgs[256];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    new szTemp[256];
    copy(szTemp, charsmax(szTemp), szArgs);
    new iPos = contain(szTemp, "giveskinid ");
    if (iPos >= 0) {
        copy(szArgs, charsmax(szArgs), szTemp[iPos + 11]);
        trim(szArgs);
    }

    new szTargetName[32], szTypeStr[16], szSkinName[MAX_SKIN_NAME];
    parse(szArgs, szTargetName, charsmax(szTargetName), szTypeStr, charsmax(szTypeStr));
    new iTypeLen = strlen(szTypeStr);
    new iRemaining = strlen(szArgs) - (strlen(szTargetName) + 1 + iTypeLen);
    if (iRemaining > 0) {
        copy(szSkinName, charsmax(szSkinName), szArgs[strlen(szTargetName) + 1 + iTypeLen + 1]);
        trim(szSkinName);
    }

    if (szTargetName[0] == EOS || szTypeStr[0] == EOS || szSkinName[0] == EOS) {
        client_print(id, print_chat, "[SkinSystem] 用法: /giveskinid <玩家名|#id> <T|CT|Knife|USP> <皮肤名>");
        client_print(id, print_chat, "[SkinSystem] 示例: /giveskinid Player T 北极战士");
        client_print(id, print_chat, "[SkinSystem] 提示: 使用 /giveskin 可以打开菜单选择界面");
        return PLUGIN_HANDLED;
    }

    new iTarget = cmd_target(id, szTargetName, CMDTARGET_OBEY_IMMUNITY | CMDTARGET_ALLOW_SELF);
    if (!iTarget) return PLUGIN_HANDLED;

    new iType = -1;
    new Array:aModels, Array:aModelNames;
    if (equali(szTypeStr, "T") || equali(szTypeStr, "t")) { iType = 0; aModels = g_aTModels; aModelNames = g_aTModelNames; }
    else if (equali(szTypeStr, "CT") || equali(szTypeStr, "ct")) { iType = 1; aModels = g_aCTModels; aModelNames = g_aCTModelNames; }
    else if (equali(szTypeStr, "Knife") || equali(szTypeStr, "knife") || equali(szTypeStr, "刀")) { iType = 2; aModels = g_aKnifeModels; aModelNames = g_aKnifeModelNames; }
    else if (equali(szTypeStr, "USP") || equali(szTypeStr, "usp")) { iType = 3; aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; }

    if (iType == -1 || aModels == Invalid_Array) {
        client_print(id, print_chat, "[SkinSystem] 无效类型: %s, 请用 T/CT/Knife/USP", szTypeStr);
        return PLUGIN_HANDLED;
    }

    new iSkinIndex = -1;
    new iSize = ArraySize(aModels);
    new szModelName[MAX_SKIN_NAME];
    for (new i = 0; i < iSize; i++) {
        ArrayGetString(aModelNames, i, szModelName, charsmax(szModelName));
        if (containi(szModelName, szSkinName) != -1) { iSkinIndex = i; break; }
    }

    if (iSkinIndex == -1) {
        client_print(id, print_chat, "[SkinSystem] 找不到皮肤: %s (类型: %s)", szSkinName, szTypeStr);
        client_print(id, print_chat, "[SkinSystem] 可用皮肤列表:");
        for (new i = 0; i < iSize; i++) {
            ArrayGetString(aModelNames, i, szModelName, charsmax(szModelName));
            client_print(id, print_chat, "[SkinSystem]   %d. %s", i + 1, szModelName);
        }
        return PLUGIN_HANDLED;
    }

    if (has_skin(iTarget, iType, iSkinIndex)) {
        ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));
        client_print(id, print_chat, "[SkinSystem] 玩家已拥有该皮肤: %s", szModelName);
        return PLUGIN_HANDLED;
    }

    give_skin(iTarget, iType, iSkinIndex);
    save_player_skins(iTarget);

    new szAdminName[32], szTargetRealName[32];
    get_user_name(id, szAdminName, charsmax(szAdminName));
    get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));
    ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));

    client_print(id, print_chat, "[SkinSystem] 已向 %s 发放皮肤: %s (%s)", szTargetRealName, szModelName, szTypeStr);
    client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了皮肤: %s (%s)", szAdminName, szModelName, szTypeStr);

    return PLUGIN_HANDLED;
}

//  /take - 收回皮肤 (仅服主)
public cmdTakeSkin(const id) {
    if (!is_user_connected(id)) return PLUGIN_CONTINUE;

    if (!is_official_owner(id)) {
        client_print(id, print_chat, "[SkinSystem] 只有官方认证服主才能收回皮肤");
        return PLUGIN_HANDLED;
    }

    new szArgs[256];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    new szTemp[256];
    copy(szTemp, charsmax(szTemp), szArgs);
    new iPos = contain(szTemp, "take ");
    if (iPos >= 0) {
        copy(szArgs, charsmax(szArgs), szTemp[iPos + 5]);
        trim(szArgs);
    }

    new szTargetName[32], szTypeStr[16], szSkinName[MAX_SKIN_NAME];
    parse(szArgs, szTargetName, charsmax(szTargetName), szTypeStr, charsmax(szTypeStr));
    new iTypeLen = strlen(szTypeStr);
    new iRemaining = strlen(szArgs) - (strlen(szTargetName) + 1 + iTypeLen);
    if (iRemaining > 0) {
        copy(szSkinName, charsmax(szSkinName), szArgs[strlen(szTargetName) + 1 + iTypeLen + 1]);
        trim(szSkinName);
    }

    if (szTargetName[0] == EOS || szTypeStr[0] == EOS || szSkinName[0] == EOS) {
        client_print(id, print_chat, "[SkinSystem] 用法: /take <玩家名|#id> <T|CT|Knife|USP> <皮肤名>");
        return PLUGIN_HANDLED;
    }

    new iTarget = cmd_target(id, szTargetName, CMDTARGET_OBEY_IMMUNITY | CMDTARGET_ALLOW_SELF);
    if (!iTarget) return PLUGIN_HANDLED;

    new iType = -1;
    new Array:aModels, Array:aModelNames;
    if (equali(szTypeStr, "T") || equali(szTypeStr, "t")) { iType = 0; aModels = g_aTModels; aModelNames = g_aTModelNames; }
    else if (equali(szTypeStr, "CT") || equali(szTypeStr, "ct")) { iType = 1; aModels = g_aCTModels; aModelNames = g_aCTModelNames; }
    else if (equali(szTypeStr, "Knife") || equali(szTypeStr, "knife") || equali(szTypeStr, "刀")) { iType = 2; aModels = g_aKnifeModels; aModelNames = g_aKnifeModelNames; }
    else if (equali(szTypeStr, "USP") || equali(szTypeStr, "usp")) { iType = 3; aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; }

    if (iType == -1 || aModels == Invalid_Array) {
        client_print(id, print_chat, "[SkinSystem] 无效类型: %s, 请用 T/CT/Knife/USP", szTypeStr);
        return PLUGIN_HANDLED;
    }

    new iSkinIndex = -1;
    new iSize = ArraySize(aModels);
    new szModelName[MAX_SKIN_NAME];
    for (new i = 0; i < iSize; i++) {
        ArrayGetString(aModelNames, i, szModelName, charsmax(szModelName));
        if (containi(szModelName, szSkinName) != -1) { iSkinIndex = i; break; }
    }

    if (iSkinIndex == -1) {
        client_print(id, print_chat, "[SkinSystem] 找不到皮肤: %s (类型: %s)", szSkinName, szTypeStr);
        return PLUGIN_HANDLED;
    }

    if (!has_skin(iTarget, iType, iSkinIndex)) {
        ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));
        client_print(id, print_chat, "[SkinSystem] 玩家未拥有该皮肤: %s", szModelName);
        return PLUGIN_HANDLED;
    }

    take_skin(iTarget, iType, iSkinIndex);
    save_player_skins(iTarget);

    new szAdminName[32], szTargetRealName[32];
    get_user_name(id, szAdminName, charsmax(szAdminName));
    get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));
    ArrayGetString(aModelNames, iSkinIndex, szModelName, charsmax(szModelName));

    client_print(id, print_chat, "[SkinSystem] 已收回 %s 的皮肤: %s (%s)", szTargetRealName, szModelName, szTypeStr);
    client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 收回了你的皮肤: %s (%s)", szAdminName, szModelName, szTypeStr);

    return PLUGIN_HANDLED;
}

//  === 存档 ===
stock save_player_skins(const id) {
    if (!is_user_connected(id)) {
        return;
    }

    new szIdentifier[MAX_AUTHID_LENGTH];
    get_player_identifier(id, szIdentifier, charsmax(szIdentifier));
    if (szIdentifier[0] == EOS) {
        return;
    }

    new szData[1280];
    new szAuth[MAX_AUTHID_LENGTH], szIP[MAX_AUTHID_LENGTH], szName[32];
    get_user_authid(id, szAuth, charsmax(szAuth));
    get_user_ip(id, szIP, charsmax(szIP), 1);
    get_user_name(id, szName, charsmax(szName));

    new szQuote[2] = {34, 0}; replace_all(szName, charsmax(szName), szQuote, "'");

    new iLen = 0;
    iLen += format(szData[iLen], charsmax(szData) - iLen, "{^"auth^":^"%s^",^"ip^":^"%s^",^"name^":^"%s^",^"t^":[", szAuth, szIP, szName);

    for (new i = 0; i < g_iOwnedTCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedT[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "],^"ct^":[");

    for (new i = 0; i < g_iOwnedCTCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedCT[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "],^"knife^":[");

    for (new i = 0; i < g_iOwnedKnifeCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedKnife[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "],^"usp^":[");

    for (new i = 0; i < g_iOwnedUSPCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedUSP[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "],^"smoke^":[");
    for (new i = 0; i < g_iOwnedSmokeCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedSmoke[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "],^"flash^":[");

    for (new i = 0; i < g_iOwnedFlashCount[id]; i++) {
        if (i > 0) iLen += format(szData[iLen], charsmax(szData) - iLen, ",");
        iLen += format(szData[iLen], charsmax(szData) - iLen, "%d", g_iOwnedFlash[id][i]);
    }
    iLen += format(szData[iLen], charsmax(szData) - iLen, "]}");

    new szKey[128];
    format(szKey, charsmax(szKey), "skinsys_skin_%s", szIdentifier);
    nvault_set(g_iVault, szKey, szData);

    new szNumStr[32];
    format(szKey, charsmax(szKey), "skinsys_skin_sel_t_%s", szIdentifier);
    num_to_str(g_iSelectedT[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);
    format(szKey, charsmax(szKey), "skinsys_skin_sel_ct_%s", szIdentifier);
    num_to_str(g_iSelectedCT[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);
    format(szKey, charsmax(szKey), "skinsys_skin_sel_knife_%s", szIdentifier);
    num_to_str(g_iSelectedKnife[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);
    format(szKey, charsmax(szKey), "skinsys_skin_sel_usp_%s", szIdentifier);
    num_to_str(g_iSelectedUSP[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);
    format(szKey, charsmax(szKey), "skinsys_skin_sel_smoke_%s", szIdentifier);
    num_to_str(g_iSelectedSmoke[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);
    format(szKey, charsmax(szKey), "skinsys_skin_sel_flash_%s", szIdentifier);
    num_to_str(g_iSelectedFlash[id], szNumStr, charsmax(szNumStr));
    nvault_set(g_iVault, szKey, szNumStr);

    save_skin_data_to_file();
    sql_write_skins(id);
}

stock load_player_skins(const id) {
    if (!is_user_connected(id)) {
        return;
    }

    new szIdentifier[MAX_AUTHID_LENGTH];
    get_player_identifier(id, szIdentifier, charsmax(szIdentifier));
    if (szIdentifier[0] == EOS) {
        return;
    }

    new szKey[128];
    new szData[1280];
    new szAuth[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuth, charsmax(szAuth));

    new bool:bLoaded = false;

    if (!equal(szAuth, "STEAM_ID_LAN") && !equal(szAuth, "VALVE_ID_LAN")) {
        format(szKey, charsmax(szKey), "skinsys_skin_%s", szAuth);
        if (nvault_get(g_iVault, szKey, szData, charsmax(szData))) {
            bLoaded = true;
        }
    }

    if (!bLoaded) {
        new szIP[MAX_AUTHID_LENGTH];
        get_user_ip(id, szIP, charsmax(szIP), 1);
        format(szKey, charsmax(szKey), "skinsys_skin_%s", szIP);
        if (nvault_get(g_iVault, szKey, szData, charsmax(szData))) {
            bLoaded = true;
        }
    }

    if (!bLoaded) {
        new szName[32];
        get_user_name(id, szName, charsmax(szName));
        format(szKey, charsmax(szKey), "skinsys_skin_%s", szName);
        if (nvault_get(g_iVault, szKey, szData, charsmax(szData))) {
            bLoaded = true;
        }
    }

    if (!bLoaded) {
        load_skin_data_from_file_for_player(id);
    }

    if (bLoaded) {
        parse_skin_json(id, szData);
    }

    format(szKey, charsmax(szKey), "skinsys_skin_sel_t_%s", szIdentifier);
    new szNumBuf[32];
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedT[id] = str_to_num(szNumBuf);
    }
    format(szKey, charsmax(szKey), "skinsys_skin_sel_ct_%s", szIdentifier);
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedCT[id] = str_to_num(szNumBuf);
    }
    format(szKey, charsmax(szKey), "skinsys_skin_sel_knife_%s", szIdentifier);
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedKnife[id] = str_to_num(szNumBuf);
    }
    format(szKey, charsmax(szKey), "skinsys_skin_sel_usp_%s", szIdentifier);
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedUSP[id] = str_to_num(szNumBuf);
    }
    format(szKey, charsmax(szKey), "skinsys_skin_sel_smoke_%s", szIdentifier);
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedSmoke[id] = str_to_num(szNumBuf);
    }
    format(szKey, charsmax(szKey), "skinsys_skin_sel_flash_%s", szIdentifier);
    if (nvault_get(g_iVault, szKey, szNumBuf, charsmax(szNumBuf))) {
        g_iSelectedFlash[id] = str_to_num(szNumBuf);
    }

    // 云端优先: 若已连接 MySQL, 以云端数据覆盖 (云端载入后再补默认)
    sql_load_skins(id);
    ensure_default_skins(id);
}

stock save_skin_data_to_file() {
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/skin_data.txt", szPath);

    new f = fopen(szPath, "wt");
    if (!f) {
        log_amx("[SkinSystem] 无法打开皮肤数据文件进行写入: %s", szPath);
        return;
    }

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    for (new p = 0; p < iNum; p++) {
        new pid = iPlayers[p];

        new szAuth[MAX_AUTHID_LENGTH], szIP[MAX_AUTHID_LENGTH], szName[32];
        get_user_authid(pid, szAuth, charsmax(szAuth));
        get_user_ip(pid, szIP, charsmax(szIP), 1);
        get_user_name(pid, szName, charsmax(szName));

        new szQuote[2] = {34, 0}; replace_all(szName, charsmax(szName), szQuote, "'");

        new szLine[1280];
        new iLen = 0;

        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "{^"auth^":^"%s^",^"ip^":^"%s^",^"name^":^"%s^",^"t^":[", szAuth, szIP, szName);

        for (new i = 0; i < g_iOwnedTCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedT[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "],^"ct^":[");

        for (new i = 0; i < g_iOwnedCTCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedCT[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "],^"knife^":[");

        for (new i = 0; i < g_iOwnedKnifeCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedKnife[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "],^"usp^":[");

        for (new i = 0; i < g_iOwnedUSPCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedUSP[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "],^"smoke^":[");

        for (new i = 0; i < g_iOwnedSmokeCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedSmoke[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "],^"flash^":[");

        for (new i = 0; i < g_iOwnedFlashCount[pid]; i++) {
            if (i > 0) iLen += format(szLine[iLen], charsmax(szLine) - iLen, ",");
            iLen += format(szLine[iLen], charsmax(szLine) - iLen, "%d", g_iOwnedFlash[pid][i]);
        }
        iLen += format(szLine[iLen], charsmax(szLine) - iLen, "]}");

        fprintf(f, "%s^n", szLine);
    }

    fclose(f);
}

stock load_skin_data_from_file_for_player(const id) {
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/skin_data.txt", szPath);

    new f = fopen(szPath, "rt");
    if (!f) {
        return;
    }

    new szAuth[MAX_AUTHID_LENGTH], szIP[MAX_AUTHID_LENGTH], szName[32];
    get_user_authid(id, szAuth, charsmax(szAuth));
    get_user_ip(id, szIP, charsmax(szIP), 1);
    get_user_name(id, szName, charsmax(szName));

    new szLine[1280];
    new bool:bFound = false;

    while (!feof(f) && !bFound) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (szLine[0] == EOS) {
            continue;
        }

        if (contain(szLine, szAuth) == -1) {
            continue;
        }
        if (contain(szLine, szIP) == -1) {
            continue;
        }
        if (contain(szLine, szName) == -1) {
            continue;
        }

        parse_skin_json(id, szLine);
        bFound = true;

        new szIdentifier[MAX_AUTHID_LENGTH];
        get_player_identifier(id, szIdentifier, charsmax(szIdentifier));
        new szKey[128];
        format(szKey, charsmax(szKey), "skinsys_skin_%s", szIdentifier);
        nvault_set(g_iVault, szKey, szLine);
    }

    fclose(f);
}

// 解析皮肤JSON数据
stock parse_skin_json(const id, const szData[]) {
    new szTSection[256];
    if (extract_json_array(szData, "t", szTSection, charsmax(szTSection))) {
        parse_skin_array(szTSection, g_iOwnedT[id], g_iOwnedTCount[id]);
    }
    new szCTSection[256];
    if (extract_json_array(szData, "ct", szCTSection, charsmax(szCTSection))) {
        parse_skin_array(szCTSection, g_iOwnedCT[id], g_iOwnedCTCount[id]);
    }
    new szKnifeSection[256];
    if (extract_json_array(szData, "knife", szKnifeSection, charsmax(szKnifeSection))) {
        parse_skin_array(szKnifeSection, g_iOwnedKnife[id], g_iOwnedKnifeCount[id]);
    }
    new szUSPSection[256];
    if (extract_json_array(szData, "usp", szUSPSection, charsmax(szUSPSection))) {
        parse_skin_array(szUSPSection, g_iOwnedUSP[id], g_iOwnedUSPCount[id]);
    }
    new szSmokeSection[256];
    if (extract_json_array(szData, "smoke", szSmokeSection, charsmax(szSmokeSection))) {
        parse_skin_array(szSmokeSection, g_iOwnedSmoke[id], g_iOwnedSmokeCount[id]);
    }
    new szFlashSection[256];
    if (extract_json_array(szData, "flash", szFlashSection, charsmax(szFlashSection))) {
        parse_skin_array(szFlashSection, g_iOwnedFlash[id], g_iOwnedFlashCount[id]);
    }
}

stock bool:extract_json_array(const szJson[], const szKey[], szOut[], iOutLen) {
    new szSearch[32];
    formatex(szSearch, charsmax(szSearch), "^"%s^":[", szKey);

    new iPos = contain(szJson, szSearch);
    if (iPos == -1) {
        return false;
    }
    iPos += strlen(szSearch);

    new iEnd = contain(szJson[iPos], "]");
    if (iEnd == -1) {
        return false;
    }

    new iCopyLen = iEnd;
    if (iCopyLen >= iOutLen) {
        iCopyLen = iOutLen - 1;
    }
    copy(szOut, iCopyLen + 1, szJson[iPos]);

    return true;
}

stock parse_skin_array(const szArray[], iOut[], &iOutCount) {
    iOutCount = 0;

    new szTemp[256];
    copy(szTemp, charsmax(szTemp), szArray);
    trim(szTemp);

    if (szTemp[0] == EOS) {
        return;
    }

    new iLen = strlen(szTemp);
    new iStart = 0;

    for (new i = 0; i <= iLen && iOutCount < MAX_OWNED_SKINS; i++) {
        if (szTemp[i] == ',' || szTemp[i] == EOS) {
            if (i > iStart) {
                new szNum[16];
                new iNumLen = i - iStart;
                if (iNumLen >= charsmax(szNum)) {
                    iNumLen = charsmax(szNum) - 1;
                }
                copy(szNum, iNumLen + 1, szTemp[iStart]);
                trim(szNum);
                if (szNum[0] != EOS) {
                    iOut[iOutCount] = str_to_num(szNum);
                    iOutCount++;
                }
            }
            iStart = i + 1;
        }
    }
}

stock ensure_default_skins(const id) {
    if (!has_skin(id, 0, 0)) {
        give_skin(id, 0, 0);
    }
    if (g_iSelectedT[id] < 0) {
        g_iSelectedT[id] = 0;
    }
    if (!has_skin(id, 1, 0)) {
        give_skin(id, 1, 0);
    }
    if (g_iSelectedCT[id] < 0) {
        g_iSelectedCT[id] = 0;
    }
    if (!has_skin(id, 2, 0)) {
        give_skin(id, 2, 0);
    }
    if (g_iSelectedKnife[id] < 0) {
        g_iSelectedKnife[id] = 0;
    }
    if (!has_skin(id, 3, 0)) {
        give_skin(id, 3, 0);
    }
    if (g_iSelectedUSP[id] < 0) {
        g_iSelectedUSP[id] = 0;
    }
    if (!has_skin(id, 4, 0)) {
        give_skin(id, 4, 0);
    }
    if (g_iSelectedSmoke[id] < 0) {
        g_iSelectedSmoke[id] = 0;
    }
    if (!has_skin(id, 5, 0)) {
        give_skin(id, 5, 0);
    }
    if (g_iSelectedFlash[id] < 0) {
        g_iSelectedFlash[id] = 0;
    }
}

//  === 工具函数 ===
stock bool:has_skin(const id, const iType, const iSkinIndex) {
    if (iType == 0) {
        for (new i = 0; i < g_iOwnedTCount[id]; i++) {
            if (g_iOwnedT[id][i] == iSkinIndex) return true;
        }
    } else if (iType == 1) {
        for (new i = 0; i < g_iOwnedCTCount[id]; i++) {
            if (g_iOwnedCT[id][i] == iSkinIndex) return true;
        }
    } else if (iType == 2) {
        for (new i = 0; i < g_iOwnedKnifeCount[id]; i++) {
            if (g_iOwnedKnife[id][i] == iSkinIndex) return true;
        }
    } else if (iType == 3) {
        for (new i = 0; i < g_iOwnedUSPCount[id]; i++) {
            if (g_iOwnedUSP[id][i] == iSkinIndex) return true;
        }
    } else if (iType == 4) {
        for (new i = 0; i < g_iOwnedSmokeCount[id]; i++) {
            if (g_iOwnedSmoke[id][i] == iSkinIndex) return true;
        }
    } else if (iType == 5) {
        for (new i = 0; i < g_iOwnedFlashCount[id]; i++) {
            if (g_iOwnedFlash[id][i] == iSkinIndex) return true;
        }
    }
    return false;
}

stock give_skin(const id, const iType, const iSkinIndex) {
    if (has_skin(id, iType, iSkinIndex)) {
        return;
    }
    if (iType == 0) {
        if (g_iOwnedTCount[id] < MAX_OWNED_SKINS) { g_iOwnedT[id][g_iOwnedTCount[id]] = iSkinIndex; g_iOwnedTCount[id]++; }
    } else if (iType == 1) {
        if (g_iOwnedCTCount[id] < MAX_OWNED_SKINS) { g_iOwnedCT[id][g_iOwnedCTCount[id]] = iSkinIndex; g_iOwnedCTCount[id]++; }
    } else if (iType == 2) {
        if (g_iOwnedKnifeCount[id] < MAX_OWNED_SKINS) { g_iOwnedKnife[id][g_iOwnedKnifeCount[id]] = iSkinIndex; g_iOwnedKnifeCount[id]++; }
    } else if (iType == 3) {
        if (g_iOwnedUSPCount[id] < MAX_OWNED_SKINS) { g_iOwnedUSP[id][g_iOwnedUSPCount[id]] = iSkinIndex; g_iOwnedUSPCount[id]++; }
    } else if (iType == 4) {
        if (g_iOwnedSmokeCount[id] < MAX_OWNED_SKINS) { g_iOwnedSmoke[id][g_iOwnedSmokeCount[id]] = iSkinIndex; g_iOwnedSmokeCount[id]++; }
    } else if (iType == 5) {
        if (g_iOwnedFlashCount[id] < MAX_OWNED_SKINS) { g_iOwnedFlash[id][g_iOwnedFlashCount[id]] = iSkinIndex; g_iOwnedFlashCount[id]++; }
    }
}

// 批量发放某一类型的全部皮肤
stock give_all_of_type(const id, const iType, Handle:arrModels, &iCount) {
    new iSize = ArraySize(arrModels);
    for (new i = 0; i < iSize; i++) {
        if (!has_skin(id, iType, i)) {
            give_skin(id, iType, i);
            iCount++;
        }
    }
}

// 后台离线发放皮肤: 不依赖目标玩家在线, 直接改存储层。
// szIdentifier 为该玩家的 SteamID 或 IP(与 get_player_identifier 一致)。
// 读取 nvault 存档 JSON -> 追加 / 校验该类型皮肤索引 -> 写回 nvault 并 REPLACE 到云端。
// 返回 1=新发放, 0=已拥有, -1=失败/越界。
stock grant_skin_offline(const szIdentifier[], const iType, const iSkinIndex) {
    if (szIdentifier[0] == EOS || iType < 0 || iType > 5 || iSkinIndex < 0) {
        return -1;
    }

    // 校验索引在该类型的配置范围内
    new iTotal = 0;
    if (iType == 0) iTotal = ArraySize(g_aTModels);
    else if (iType == 1) iTotal = ArraySize(g_aCTModels);
    else if (iType == 2) iTotal = ArraySize(g_aKnifeModels);
    else if (iType == 3) iTotal = ArraySize(g_aUSPModels);
    else if (iType == 4) iTotal = ArraySize(g_aSmokeModels);
    else if (iType == 5) iTotal = ArraySize(g_aFlashModels);
    if (iSkinIndex >= iTotal) {
        return -1;
    }

    // 从 nvault 读取该玩家完整存档 JSON
    new szKey[128], szData[1280];
    format(szKey, charsmax(szKey), "skinsys_skin_%s", szIdentifier);
    new bool:bHasRecord = bool:nvault_get(g_iVault, szKey, szData, charsmax(szData));

    // 六类皮肤索引 (离线解析用), 及各自数量
    new aOwned[6][MAX_OWNED_SKINS];
    new iCounts[6];
    new x;

    if (bHasRecord) {
        new szSection[256];
        new szKeyName[8];
        new keys[6][8] = { {"t"}, {"ct"}, {"knife"}, {"usp"}, {"smoke"}, {"flash"} };
        for (x = 0; x < 6; x++) {
            copy(szKeyName, charsmax(szKeyName), keys[x]);
            if (extract_json_array(szData, szKeyName, szSection, charsmax(szSection))) {
                parse_skin_array(szSection, aOwned[x], iCounts[x]);
            }
        }
    }

    // 检查 / 追加目标类型
    new bool:bOwned = false;
    for (x = 0; x < iCounts[iType]; x++) {
        if (aOwned[iType][x] == iSkinIndex) { bOwned = true; break; }
    }
    if (!bOwned) {
        if (iCounts[iType] >= MAX_OWNED_SKINS) {
            return -1;
        }
        aOwned[iType][iCounts[iType]] = iSkinIndex;
        iCounts[iType]++;
    }

    // 重建 JSON 并写回 nvault
    new szNewData[1280];
    new iLen = 0;
    iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, "{^"auth^":^"%s^",^"ip^":^"%s^",^"name^":^"^",", szIdentifier, szIdentifier);
    new i;
    new keys2[6][8] = { {"t"}, {"ct"}, {"knife"}, {"usp"}, {"smoke"}, {"flash"} };
    new szTypeKey[8];
    for (x = 0; x < 6; x++) {
        copy(szTypeKey, charsmax(szTypeKey), keys2[x]);
        iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, "^"%s^":[", szTypeKey);
        for (i = 0; i < iCounts[x]; i++) {
            if (i > 0) iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, ",");
            iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, "%d", aOwned[x][i]);
        }
        iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, "]");
        if (x < 5) iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, ",");
    }
    iLen += format(szNewData[iLen], charsmax(szNewData) - iLen, "}");

    nvault_set(g_iVault, szKey, szNewData);

#if SKINSYS_SQLX == 1
    if (g_bSqlConnected && g_hSqlTuple != Empty_Handle) {
        new szEscId[128], szEscData[1600];
        copy(szEscId, charsmax(szEscId), szIdentifier);
        copy(szEscData, charsmax(szEscData), szNewData);
        replace_all(szEscId, charsmax(szEscId), "'", "''");
        replace_all(szEscData, charsmax(szEscData), "'", "''");
        new szQ[2048];
        format(szQ, charsmax(szQ), "REPLACE INTO %s (authid, skin_json) VALUES ('%s', '%s')", SQL_TABLE, szEscId, szEscData);
        SQL_ThreadQuery(g_hSqlTuple, "sql_ignore_result", szQ);
    }
#endif

    return bOwned ? 0 : 1;
}

// 离线发放后, 若该 SteamID 玩家恰好在线, 重读存档刷新内存与外观
stock sync_online_skin_by_identifier(const szIdentifier[]) {
    new iPlayers[MAX_PLAYERS], iNum, szId[MAX_AUTHID_LENGTH];
    get_players(iPlayers, iNum, "ch");
    for (new i = 0; i < iNum; i++) {
        new pid = iPlayers[i];
        get_player_identifier(pid, szId, charsmax(szId));
        if (equal(szId, szIdentifier)) {
            load_player_skins(pid);
            if (is_user_alive(pid)) apply_model(pid);
            client_print(pid, print_chat, "[SkinSystem] 管理员已向你离线发放皮肤, 已刷新");
            break;
        }
    }
}

stock take_skin(const id, const iType, const iSkinIndex) {
    if (iType == 0) {
        for (new i = 0; i < g_iOwnedTCount[id]; i++) {
            if (g_iOwnedT[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedTCount[id] - 1; j++) g_iOwnedT[id][j] = g_iOwnedT[id][j + 1];
                g_iOwnedTCount[id]--;
                if (g_iSelectedT[id] == iSkinIndex) g_iSelectedT[id] = 0;
                break;
            }
        }
    } else if (iType == 1) {
        for (new i = 0; i < g_iOwnedCTCount[id]; i++) {
            if (g_iOwnedCT[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedCTCount[id] - 1; j++) g_iOwnedCT[id][j] = g_iOwnedCT[id][j + 1];
                g_iOwnedCTCount[id]--;
                if (g_iSelectedCT[id] == iSkinIndex) g_iSelectedCT[id] = 0;
                break;
            }
        }
    } else if (iType == 2) {
        for (new i = 0; i < g_iOwnedKnifeCount[id]; i++) {
            if (g_iOwnedKnife[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedKnifeCount[id] - 1; j++) g_iOwnedKnife[id][j] = g_iOwnedKnife[id][j + 1];
                g_iOwnedKnifeCount[id]--;
                if (g_iSelectedKnife[id] == iSkinIndex) g_iSelectedKnife[id] = 0;
                break;
            }
        }
    } else if (iType == 3) {
        for (new i = 0; i < g_iOwnedUSPCount[id]; i++) {
            if (g_iOwnedUSP[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedUSPCount[id] - 1; j++) g_iOwnedUSP[id][j] = g_iOwnedUSP[id][j + 1];
                g_iOwnedUSPCount[id]--;
                if (g_iSelectedUSP[id] == iSkinIndex) g_iSelectedUSP[id] = 0;
                break;
            }
        }
    } else if (iType == 4) {
        for (new i = 0; i < g_iOwnedSmokeCount[id]; i++) {
            if (g_iOwnedSmoke[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedSmokeCount[id] - 1; j++) g_iOwnedSmoke[id][j] = g_iOwnedSmoke[id][j + 1];
                g_iOwnedSmokeCount[id]--;
                if (g_iSelectedSmoke[id] == iSkinIndex) g_iSelectedSmoke[id] = 0;
                break;
            }
        }
    } else if (iType == 5) {
        for (new i = 0; i < g_iOwnedFlashCount[id]; i++) {
            if (g_iOwnedFlash[id][i] == iSkinIndex) {
                for (new j = i; j < g_iOwnedFlashCount[id] - 1; j++) g_iOwnedFlash[id][j] = g_iOwnedFlash[id][j + 1];
                g_iOwnedFlashCount[id]--;
                if (g_iSelectedFlash[id] == iSkinIndex) g_iSelectedFlash[id] = 0;
                break;
            }
        }
    }
}

// 获取玩家标识（SteamID/IP）
stock get_player_identifier(const id, szOut[], iLen) {
    new szAuth[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuth, charsmax(szAuth));

    if (!equal(szAuth, "STEAM_ID_LAN") && !equal(szAuth, "VALVE_ID_LAN")) {
        copy(szOut, iLen, szAuth);
        return;
    }
    new szIP[MAX_AUTHID_LENGTH];
    get_user_ip(id, szIP, charsmax(szIP), 1);
    copy(szOut, iLen, szIP);
}

stock find_player_by_name(const szName[]) {
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    for (new i = 0; i < iNum; i++) {
        new szPlayerName[32];
        get_user_name(iPlayers[i], szPlayerName, charsmax(szPlayerName));
        if (equal(szPlayerName, szName)) {
            return iPlayers[i];
        }
    }
    for (new i = 0; i < iNum; i++) {
        new szPlayerName[32];
        get_user_name(iPlayers[i], szPlayerName, charsmax(szPlayerName));
        if (containi(szPlayerName, szName) >= 0) {
            return iPlayers[i];
        }
    }
    return 0;
}

//  官方 AMXX 认证管理员判定（users.ini）
stock load_official_admins() {
    if (g_bOfficialLoaded) {
        return;
    }
    g_bOfficialLoaded = true;
    g_iOfficialAdminCount = 0;

    new szConfigsDir[256];
    get_localinfo("amxx_configsdir", szConfigsDir, charsmax(szConfigsDir));

    new szPath[320];
    formatex(szPath, charsmax(szPath), "%s/users.ini", szConfigsDir);

    if (!file_exists(szPath)) {
        log_amx("[SkinSystem] 未找到 users.ini (%s)，皮肤发放/收回已关闭", szPath);
        return;
    }

    new szLine[192];
    new iFile = fopen(szPath, "rt");
    if (!iFile) {
        return;
    }

    while (g_iOfficialAdminCount < MAX_OFFICIAL_ADMINS && fgets(iFile, szLine, charsmax(szLine))) {
        trim(szLine);
        if (szLine[0] == EOS || szLine[0] == ';' || (szLine[0] == '/' && szLine[1] == '/')) {
            continue;
        }

        new szAuth[MAX_AUTH_LEN], szPass[MAX_AUTH_LEN], szAccess[MAX_FLAG_LEN], szAccount[MAX_FLAG_LEN];
        parse(szLine, szAuth, charsmax(szAuth), szPass, charsmax(szPass), szAccess, charsmax(szAccess), szAccount, charsmax(szAccount));

        remove_quotes(szAuth);
        remove_quotes(szPass);
        remove_quotes(szAccess);
        remove_quotes(szAccount);

        if (szAuth[0] == EOS) {
            continue;
        }
        if (szAccess[0] == EOS) {
            continue;
        }

        copy(g_szOfficialAuth[g_iOfficialAdminCount], MAX_AUTH_LEN - 1, szAuth);
        g_iOfficialAccess[g_iOfficialAdminCount] = read_flags(szAccess);
        g_iOfficialAdminCount++;
    }
    fclose(iFile);

    log_amx("[SkinSystem] 已加载 %d 个官方认证管理员", g_iOfficialAdminCount);
}

stock bool:auth_matches(const szIdentity[], const szPattern[]) {
    new iStar = contain(szPattern, "*");
    if (iStar >= 0) {
        for (new i = 0; i < iStar; i++) {
            if (szIdentity[i] == EOS || szIdentity[i] != szPattern[i]) {
                return false;
            }
        }
        return true;
    }
    return equal(szIdentity, szPattern);
}

stock bool:is_official_admin(const id) {
    if (!g_bOfficialLoaded) {
        load_official_admins();
    }
    if (g_iOfficialAdminCount <= 0) {
        return false;
    }

    new szAuth[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuth, charsmax(szAuth));

    if (equal(szAuth, "STEAM_ID_LAN") || equal(szAuth, "VALVE_ID_LAN")) {
        get_user_ip(id, szAuth, charsmax(szAuth), 1);
    }

    for (new i = 0; i < g_iOfficialAdminCount; i++) {
        if (auth_matches(szAuth, g_szOfficialAuth[i])) {
            return true;
        }
    }
    return false;
}

stock bool:is_official_owner(const id) {
    if (!g_bOfficialLoaded) {
        load_official_admins();
    }
    if (g_iOfficialAdminCount <= 0) {
        return false;
    }

    new szAuth[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuth, charsmax(szAuth));

    if (equal(szAuth, "STEAM_ID_LAN") || equal(szAuth, "VALVE_ID_LAN")) {
        get_user_ip(id, szAuth, charsmax(szAuth), 1);
    }

    for (new i = 0; i < g_iOfficialAdminCount; i++) {
        if (auth_matches(szAuth, g_szOfficialAuth[i])) {
            new iFlags = g_iOfficialAccess[i];
            if (iFlags & read_flags("o")) {
                return true;
            }
        }
    }
    return false;
}

// 清理动态数组
stock cleanup_arrays() {
    if (g_aTModels != Invalid_Array) { ArrayDestroy(g_aTModels); g_aTModels = Invalid_Array; }
    if (g_aTModelNames != Invalid_Array) { ArrayDestroy(g_aTModelNames); g_aTModelNames = Invalid_Array; }
    if (g_aCTModels != Invalid_Array) { ArrayDestroy(g_aCTModels); g_aCTModels = Invalid_Array; }
    if (g_aCTModelNames != Invalid_Array) { ArrayDestroy(g_aCTModelNames); g_aCTModelNames = Invalid_Array; }
    if (g_aKnifeModels != Invalid_Array) { ArrayDestroy(g_aKnifeModels); g_aKnifeModels = Invalid_Array; }
    if (g_aKnifeModelNames != Invalid_Array) { ArrayDestroy(g_aKnifeModelNames); g_aKnifeModelNames = Invalid_Array; }
    if (g_aKnifeThirdModels != Invalid_Array) { ArrayDestroy(g_aKnifeThirdModels); g_aKnifeThirdModels = Invalid_Array; }
    if (g_aUSPModels != Invalid_Array) { ArrayDestroy(g_aUSPModels); g_aUSPModels = Invalid_Array; }
    if (g_aUSPModelNames != Invalid_Array) { ArrayDestroy(g_aUSPModelNames); g_aUSPModelNames = Invalid_Array; }
}