/*
 * ============================================================
 *  HnsSkin+IC - 皮肤系统 × IC 点系统 融合版 v3.0.0
 * ============================================================
 *  融合说明:
 *   本插件将原有「独立皮肤系统 HnsSkin (v2.02)」与
 *   「IC 点系统 HnsICPointMenu (v2.0.0)」合二为一，
 *   取各自长处:
 *
 *   来自皮肤系统的长处:
 *     - 完整的多类型皮肤选择(人物T/CT、刀、USP)
 *     - 共享皮肤模式(KZ服 CT/T 共用一套人物皮肤)
 *     - 管理员发放/收回皮肤(仅认 users.ini 官方认证)
 *     - 选择持久化(nvault)，重连自动恢复
 *     - 纯标准字段方案，兼容性好
 *
 *   来自 IC 点系统的长处:
 *     - IC 积分体系(打比赛/活动获得，可累计)
 *     - 积分兑换皮肤(直接用积分解锁皮肤)
 *     - 对外 native 接口(ic_add_points / ic_get_points)，
 *       比赛系统可自行对接，在自己认为合适的时机发分
 *     - 管理员直接给予 IC 点(/givetic)
 *
 *   融合后的整合点:
 *     - /skin 主菜单增加「IC积分兑换」入口并实时显示当前积分
 *     - 用 IC 分兑换的皮肤会直接解锁为玩家已拥有皮肤(永久)，
 *       走皮肤系统的统一选择/应用/持久化流程
 *     - 皮肤与 IC 分共用同一个 nvault 存档，零额外依赖
 *
 *  命令一览:
 *    玩家:
 *      /skin /skins /models /model   - 皮肤主菜单(含IC积分兑换)
 *      /skin_t /skin_ct /skin_knife /skin_usp - 直达对应皮肤
 *      /ic /icpoint /N键            - IC点菜单(查看积分/兑换)
 *    管理员(users.ini 认证):
 *      /givetic <玩家|@ALL> <数量>  - 直接给予IC点
 *      /giveallskins <玩家> <T/CT/Knife/USP/all>
 *      /giveskin /giveskinmenu      - 菜单发放
 *      /giveskinid <玩家> <类型> <皮肤名> - 命令行发放
 *    服主(users.ini 含 'o' 权限):
 *      /take <玩家> <类型> <皮肤名>  - 收回皮肤
 *
 *  依赖: 仅 amxmodx / fakemeta / amxmisc / reapi / hamsandwich /
 *        engine / nvault (全部内置)
 *  注意: 不依赖任何比赛系统; 比赛系统通过 ic_add_points native 对接
 * ============================================================
 */

#include <amxmodx>
#include <fakemeta>
#include <amxmisc>
#include <reapi>
#include <nvault>
#include <hamsandwich>
#include <engine>

// 前向声明
stock bool:has_skin(const id, const iType, const iSkinIndex);
stock give_skin(const id, const iType, const iSkinIndex);

// ============================================================
//  插件信息
// ============================================================
#define PLUGIN_NAME "HnsSkin+IC Skin System"
#define PLUGIN_VERSION "3.0.0"
#define PLUGIN_AUTHOR "OpenSkin"

// ============================================================
//  常量定义
// ============================================================
#define MAX_AUTHID_LENGTH    64
#define MAX_MODEL_NAME      128
#define MAX_SKIN_NAME       64
#define MAX_OWNED_SKINS     64
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

// ============================================================
//  全局变量 - 官方管理员判定
// ============================================================
new g_szOfficialAuth[MAX_OFFICIAL_ADMINS][MAX_AUTH_LEN];
new g_iOfficialAccess[MAX_OFFICIAL_ADMINS];
new g_iOfficialAdminCount;
new bool:g_bOfficialLoaded;

// ============================================================
//  全局变量 - 皮肤模型数组
// ============================================================
new Array:g_aTModels;          // T模型路径
new Array:g_aTModelNames;      // T模型显示名称
new Array:g_aCTModels;         // CT模型路径
new Array:g_aCTModelNames;     // CT模型显示名称
new Array:g_aKnifeModels;      // 刀模型路径
new Array:g_aKnifeModelNames;  // 刀模型显示名称
new Array:g_aUSPModels;        // USP模型路径
new Array:g_aUSPModelNames;    // USP模型显示名称

// 玩家已拥有的皮肤索引数组
new g_iOwnedT[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedTCount[MAX_PLAYERS + 1];
new g_iOwnedCT[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedCTCount[MAX_PLAYERS + 1];
new g_iOwnedKnife[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedKnifeCount[MAX_PLAYERS + 1];
new g_iOwnedUSP[MAX_PLAYERS + 1][MAX_OWNED_SKINS];
new g_iOwnedUSPCount[MAX_PLAYERS + 1];

// 玩家当前选择的皮肤索引
new g_iSelectedT[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedCT[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedKnife[MAX_PLAYERS + 1] = {-1, ...};
new g_iSelectedUSP[MAX_PLAYERS + 1] = {-1, ...};

// 共享皮肤模式(KZ): CT/T 共用同一套角色皮肤 (默认开启)
new g_pShared;

// 皮肤选择菜单临时变量
new g_iSkinSelectType[MAX_PLAYERS + 1];   // 0=T, 1=CT, 2=Knife, 3=USP
new g_iSkinSelectPage[MAX_PLAYERS + 1];

// 全局变量 - 皮肤发放
new g_iGiveTarget[MAX_PLAYERS + 1];
new g_iGiveType[MAX_PLAYERS + 1];
new g_iGivePage[MAX_PLAYERS + 1];

// ============================================================
//  全局变量 - IC 点系统
// ============================================================
new g_iICPoints[MAX_PLAYERS + 1];
new bool:g_bICLoaded[MAX_PLAYERS + 1];
new g_iICTargetType[MAX_PLAYERS + 1];   // 兑换时选择的皮肤类型 0=T 1=CT 2=Knife
new g_iICSkinPage[MAX_PLAYERS + 1];

new pcvar_person_pts, pcvar_knife_pts;

// ============================================================
//  全局变量 - 玩家标识
// ============================================================
new g_szPlayerAuth[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH];
new g_szPlayerIP[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH];
new g_szPlayerName[MAX_PLAYERS + 1][32];

// nvault 句柄
new g_iVault = INVALID_HANDLE;

// ============================================================
//  Native 接口: 供外部系统 (如比赛系统) 对接发放/查询 IC 点
//  用法(在外部插件中):
//    #include <ic_points>
//    ic_add_points(id, 10);   // 给玩家 +10 IC 点
//    new pts = ic_get_points(id); // 查询玩家当前 IC 点
// ============================================================
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

// ============================================================
//  plugin_precache - 加载模型配置并预缓存
// ============================================================
public plugin_precache() {
    load_player_models();
    precache_all_models();
}

// ============================================================
//  plugin_init - 注册命令、菜单、事件
// ============================================================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // 注册CVAR：标记高级皮肤系统已激活
    register_cvar("skinsys_advanced", "1");

    // CVAR：共享皮肤模式 (默认开启: CT/T 共用一套人物皮肤，用于KZ服)
    g_pShared = register_cvar("skinsys_shared", "1");

    // IC 点兑换价格 (CVAR 可配置)
    pcvar_person_pts = register_cvar("ic_skin_person", "500", FCVAR_SERVER);
    pcvar_knife_pts  = register_cvar("ic_skin_knife",  "300", FCVAR_SERVER);

    // 武器切换消息 — 刀/USP皮肤每次切换时重新应用
    register_message(get_user_msgid("CurWeapon"), "FM_CurWeapon");
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "Knife_Deploy_Post", true);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "USP_Deploy_Post", true);

    // 打开 nvault 数据库 (皮肤 + IC 分共用)
    g_iVault = nvault_open("skinsys_skin_vault");

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

    register_clcmd("say /skinmenu", "cmdMenu");

    register_srvcmd("skinsys_giveallskins_menu", "srvCmdGiveAllSkins");
    register_srvcmd("skinsys_giveskin_menu", "srvCmdGiveSkinMenu");

    register_clcmd("say /giveallskins", "cmdGiveAllSkins");
    register_clcmd("say /giveskin", "cmdGiveSkinMenuStart");
    register_clcmd("say /giveskinmenu", "cmdGiveSkinMenuStart");
    register_clcmd("say /giveskinid", "cmdGiveSkinCmd");
    register_clcmd("say /take", "cmdTakeSkin");

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
    register_menucmd(register_menuid("HnsSkinSkinSelect"), 1023, "handleSkinSelectMenu");
    register_menucmd(register_menuid("HnsSkinGiveSelectPlayer"), 1023, "handleGiveSelectPlayer");
    register_menucmd(register_menuid("HnsSkinGiveSelectType"), 1023, "handleGiveSelectType");
    register_menucmd(register_menuid("HnsSkinGiveSelectSkin"), 1023, "handleGiveSelectSkin");
    register_menucmd(register_menuid("HnsSkinGiveSelectSkinList"), 1023, "handleGiveSelectSkinList");

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

    log_amx("[SkinSystem] 融合版插件加载完成 (v%s)", PLUGIN_VERSION);
}

// ============================================================
//  统一主菜单 - /skin (含 IC 积分兑换入口)
// ============================================================
public cmdSkinMain(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_CONTINUE;
    }
    if (!g_bICLoaded[id]) load_player_ic(id);

    new szMenu[512];
    new iLen = formatex(szMenu, charsmax(szMenu), "\bHnsSkin \w- \d融合版皮肤系统^n^n");

    // ─── 皮肤选择 ───
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y──────── \w皮肤选择 \y────────^n");
    if (is_shared_mode()) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g1. \w人物皮肤 \d(CT/T共用)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g2. \w刀皮肤 \d(近战武器)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g3. \wUSP皮肤 \d(手枪)^n^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g1. \wT 土匪皮肤 \d(隐藏大师)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g2. \wCT 警察皮肤 \d(反恐精英)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g3. \w刀皮肤 \d(近战武器)^n");
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g4. \wUSP皮肤 \d(手枪)^n^n");
    }

    // ─── IC 积分 ───
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y──────── \wIC 积分 \y────────^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r5. \wIC积分兑换 \d(当前 \y%d\r分)^n", g_iICPoints[id]);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r6. \w查看积分 \d(当前 \y%d\r分)^n^n", g_iICPoints[id]);

    // ─── 帮助 ───
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y──────── \w帮助 \y────────^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b8. \w帮助说明^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w退出^n");

    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<8)|(1<<9);
    show_menu(id, iKeys, szMenu, -1, "HnsSkinMainMenu");
    return PLUGIN_HANDLED;
}

public handleSkinMainMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    switch (key) {
        case 0: { // 人物皮肤 (共享) 或 T皮肤
            g_iSkinSelectType[id] = 0;
            g_iSkinSelectPage[id] = 0;
            showSkinSelectMenu(id);
        }
        case 1: { // 刀皮肤 (共享) 或 CT皮肤
            g_iSkinSelectType[id] = is_shared_mode() ? 2 : 1;
            g_iSkinSelectPage[id] = 0;
            showSkinSelectMenu(id);
        }
        case 2: { // USP皮肤 (共享) 或 刀皮肤 (非共享)
            g_iSkinSelectType[id] = is_shared_mode() ? 3 : 2;
            g_iSkinSelectPage[id] = 0;
            showSkinSelectMenu(id);
        }
        case 3: { // USP皮肤 (非共享)
            if (!is_shared_mode()) {
                g_iSkinSelectType[id] = 3;
                g_iSkinSelectPage[id] = 0;
                showSkinSelectMenu(id);
            }
        }
        case 4: { // IC 积分兑换
            showRedeemMenu(id);
        }
        case 5: { // 查看积分
            showICPointsInfo(id);
        }
        case 8: { // 帮助说明
            showSkinHelp(id);
        }
    }
    return PLUGIN_HANDLED;
}

// ============================================================
//  皮肤系统帮助说明
// ============================================================
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

// ============================================================
//  IC 点查看菜单
// ============================================================
public showICPointsInfo(const id) {
    if (!is_user_connected(id)) return;
    if (!g_bICLoaded[id]) load_player_ic(id);

    client_print_color(id, print_team_default, "^4[IC点] ^1你当前拥有 ^3%d^1 IC 积分", g_iICPoints[id]);
    client_print_color(id, print_team_default, "^4[IC点] ^1在 /^3skin^1 菜单选择「IC积分兑换」即可用积分解锁皮肤");
    client_print_color(id, print_team_default, "^4[IC点] ^1也能按 ^3N^1 键 或输入 /^3ic^1 打开 IC 菜单");
}

// ============================================================
//  IC 点主菜单 (N 键 / /ic)
// ============================================================
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

// ============================================================
//  管理员直接给予 IC 点
//  用法: /givetic <玩家名|@ALL> <数量>
//  权限: users.ini 官方认证管理员 (is_user_admin)
// ============================================================
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

// ============================================================
//  IC 积分兑换: 选择皮肤类型
// ============================================================
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

// ============================================================
//  IC 辅助: 按类型取模型总数 / 名称
// ============================================================
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

// ============================================================
//  IC 积分持久化 (nvault)
// ============================================================
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

// ============================================================
//  plugin_end - 清理
// ============================================================
public plugin_end() {
    if (g_iVault != INVALID_HANDLE) {
        nvault_close(g_iVault);
    }
    cleanup_arrays();
}

// ============================================================
//  刀 / USP 模型应用 (标准字段方案)
// ============================================================
stock set_player_knife_view(const id, const szPath[]) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }
    new szPathP[MAX_MODEL_NAME];
    new bool:bHasThird = bool:get_knife_thirdperson_path(szPath, szPathP, charsmax(szPathP));
    new iEnt = find_ent_by_owner(-1, "weapon_knife", id);
    if (!iEnt) {
        return;
    }
    set_pev(iEnt, pev_viewmodel, szPath);
    if (bHasThird && file_exists(szPathP)) {
        set_pev(iEnt, pev_weaponmodel, szPathP);
    }
}
stock get_knife_thirdperson_path(const szPath[], output[], const iLen) {
    copy(output, iLen, szPath);
    new iPos = containi(output, "v_knife");
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
    return FMRES_IGNORED;
}

// ============================================================
//  client_putinserver - 初始化+加载存档
// ============================================================
public client_putinserver(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        g_iSelectedT[id] = 0;
        g_iSelectedCT[id] = 0;
        g_iSelectedKnife[id] = 0;
        g_iOwnedTCount[id] = 0;
        g_iOwnedCTCount[id] = 0;
        g_iOwnedKnifeCount[id] = 0;
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
        return;
    }

    reset_player_data(id);

    get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]));
    get_user_ip(id, g_szPlayerIP[id], charsmax(g_szPlayerIP[]), 1);
    get_user_name(id, g_szPlayerName[id], charsmax(g_szPlayerName[]));

    load_player_skins(id);
    load_player_ic(id);
}

// ============================================================
//  client_disconnected - 保存存档
// ============================================================
public client_disconnected(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }
    save_player_skins(id);
    save_player_ic(id);
    g_bICLoaded[id] = false;
}

// ============================================================
//  client_authorized - Steam验证后重新加载
// ============================================================
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
    }
}

// ============================================================
//  重置玩家数据
// ============================================================
stock reset_player_data(id) {
    g_iOwnedTCount[id] = 0;
    g_iOwnedCTCount[id] = 0;
    g_iOwnedKnifeCount[id] = 0;
    g_iOwnedUSPCount[id] = 0;
    g_iSelectedT[id] = -1;
    g_iSelectedCT[id] = -1;
    g_iSelectedKnife[id] = -1;
    g_iSelectedUSP[id] = -1;
    g_iSkinSelectType[id] = 0;
    g_iSkinSelectPage[id] = 0;
    g_iGiveTarget[id] = 0;
    g_iGiveType[id] = 0;
    g_iGivePage[id] = 0;
    g_iICPoints[id] = 0;
    g_bICLoaded[id] = false;
    g_iICTargetType[id] = 0;
    g_iICSkinPage[id] = 0;
    g_szPlayerAuth[id][0] = EOS;
    g_szPlayerIP[id][0] = EOS;
    g_szPlayerName[id][0] = EOS;
}

// ============================================================
//  === 配置加载 ===
// ============================================================
stock load_player_models() {
    g_aTModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aTModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aCTModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aCTModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aKnifeModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aKnifeModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_aUSPModels = ArrayCreate(MAX_MODEL_NAME, 1);
    g_aUSPModelNames = ArrayCreate(MAX_SKIN_NAME, 1);

    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/player_models.ini", szPath);

    new f = fopen(szPath, "rt");
    if (!f) {
        log_amx("[SkinSystem] 皮肤配置文件不存在: %s, 使用内置默认模型", szPath);
        load_default_player_models();
        return;
    }

    new szLine[512];
    new bool:bInT = false, bool:bInCT = false, bool:bInKnife = false, bool:bInUSP = false;

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
                bInT = true; bInCT = false; bInKnife = false; bInUSP = false;
            } else if (equali(szLine, "CT") || equali(szLine, "Counter-Terrorist") || equali(szLine, "CounterTerrorist")) {
                bInCT = true; bInT = false; bInKnife = false; bInUSP = false;
            } else if (equali(szLine, "Knife") || equali(szLine, "Knives")) {
                bInKnife = true; bInT = false; bInCT = false; bInUSP = false;
            } else if (equali(szLine, "USP") || equali(szLine, "Usp") || equali(szLine, "usp")) {
                bInUSP = true; bInT = false; bInCT = false; bInKnife = false;
            } else {
                bInT = false; bInCT = false; bInKnife = false; bInUSP = false;
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
        else if (bInKnife) { ArrayPushString(g_aKnifeModels, szModelPath); ArrayPushString(g_aKnifeModelNames, szName); }
        else if (bInUSP) { ArrayPushString(g_aUSPModels, szModelPath); ArrayPushString(g_aUSPModelNames, szName); }
    }
    fclose(f);

    log_amx("[SkinSystem] 普通皮肤: T=%d, CT=%d, Knife=%d, USP=%d",
        ArraySize(g_aTModels), ArraySize(g_aCTModels), ArraySize(g_aKnifeModels), ArraySize(g_aUSPModels));
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

    ArrayPushString(g_aUSPModels, "models/v_usp.mdl");
    ArrayPushString(g_aUSPModelNames, "默认USP");
}

// ============================================================
//  === 预缓存 ===
// ============================================================
stock precache_all_models() {
    new szModel[MAX_MODEL_NAME];
    new i, iSize;

    iSize = ArraySize(g_aTModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aTModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    iSize = ArraySize(g_aCTModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aCTModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    iSize = ArraySize(g_aKnifeModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aKnifeModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
    iSize = ArraySize(g_aUSPModels);
    for (i = 0; i < iSize; i++) { ArrayGetString(g_aUSPModels, i, szModel, charsmax(szModel)); precache_model(szModel); }
}

// ============================================================
//  === 模型应用 ===
// ============================================================
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

// ============================================================
//  === 皮肤选择菜单 ===
// ============================================================
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
    } else {
        iOwnedCount = g_iOwnedUSPCount[id];
        for (new i = 0; i < iOwnedCount; i++) iOwned[i] = g_iOwnedUSP[id][i];
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
    else                 iCount = g_iOwnedUSPCount[id];
    return iCount;
}

showSkinSelectMenu(const id) {
    if (!is_user_connected(id)) return;

    new iType = g_iSkinSelectType[id];
    new iPage = g_iSkinSelectPage[id];

    new Array:aModels, Array:aModelNames;
    new iSelected, szTitle[32];

    if (iType == 0) {
        aModels = g_aTModels;
        aModelNames = g_aTModelNames;
        iSelected = g_iSelectedT[id];
        if (is_shared_mode()) {
            copy(szTitle, charsmax(szTitle), "人物皮肤(CT/T共用)");
        } else {
            copy(szTitle, charsmax(szTitle), "T(土匪)皮肤");
        }
    }
    else if (iType == 1) {
        aModels = g_aCTModels;
        aModelNames = g_aCTModelNames;
        iSelected = g_iSelectedCT[id];
        copy(szTitle, charsmax(szTitle), "CT(警察)皮肤");
    }
    else if (iType == 2) {
        aModels = g_aKnifeModels;
        aModelNames = g_aKnifeModelNames;
        iSelected = g_iSelectedKnife[id];
        copy(szTitle, charsmax(szTitle), "刀皮肤");
    }
    else if (iType == 3) {
        aModels = g_aUSPModels;
        aModelNames = g_aUSPModelNames;
        iSelected = g_iSelectedUSP[id];
        copy(szTitle, charsmax(szTitle), "USP皮肤");
    }

    new iTotalModels = ArraySize(aModels);
    if (iTotalModels <= 0) {
        client_print(id, print_chat, "[SkinSystem] 暂无可用皮肤");
        return;
    }

    new iStart = iPage * 7;
    new iEnd = iStart + 7;
    if (iEnd > iTotalModels) iEnd = iTotalModels;

    new szMenu[512], iLen;
    new szOwnedInfo[64];
    new iOwnedCount = count_owned_skins(id, iType);
    formatex(szOwnedInfo, charsmax(szOwnedInfo), "\g%d\w/\d%d \w已解锁", iOwnedCount, iTotalModels);
    iLen = formatex(szMenu, charsmax(szMenu), "\bHnsSkin \w- \y%s^n\y──── \w第%d/%d页 ^1%s \y────────^n^n", szTitle, iPage + 1, (iTotalModels + 6) / 7, szOwnedInfo);

    new szName[64], iModelIdx;
    new bool:bOwned;
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9);

    for (new i = iStart; i < iEnd; i++) {
        iModelIdx = i;
        ArrayGetString(aModelNames, iModelIdx, szName, charsmax(szName));
        bOwned = is_skin_owned(id, iType, iModelIdx);

        new iSlot = i - iStart + 1;
        new szMarker[8] = "";
        if (iModelIdx == iSelected) copy(szMarker, charsmax(szMarker), " ✓");

        if (bOwned) {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\g%d. \w%s%s^n", iSlot, szName, szMarker);
        } else {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \d%s \r(未解锁)^n", iSlot, szName);
        }
    }

    for (new i = iEnd; i < iStart + 7; i++) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y────────^n");

    if (iPage > 0) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b0. \w上一页^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b0. \w返回^n");
    }
    if (iTotalModels > iEnd) {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\b9. \w下一页^n");
    } else {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
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
    else aModels = g_aUSPModels;
    new iTotalModels = ArraySize(aModels);

    if (key == 8) {
        new iMaxPage = ((iTotalModels - 1) / 7);
        if (iPage < iMaxPage) {
            g_iSkinSelectPage[id]++;
        }
        showSkinSelectMenu(id);
        return PLUGIN_HANDLED;
    }
    if (key == 9) {
        if (iPage > 0) {
            g_iSkinSelectPage[id]--;
            showSkinSelectMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new iSlot = key;
    new iModelIdx = iPage * 7 + iSlot;

    new iMaxPage = ((iTotalModels - 1) / 7);
    if (g_iSkinSelectPage[id] > iMaxPage) g_iSkinSelectPage[id] = iMaxPage;
    if (g_iSkinSelectPage[id] < 0) g_iSkinSelectPage[id] = 0;

    if (iModelIdx >= 0 && iModelIdx < iTotalModels) {
        if (!is_skin_owned(id, iType, iModelIdx)) {
            client_print(id, print_chat, "[SkinSystem] 该皮肤尚未解锁！请联系管理员获取或在 /skin 中用IC积分兑换");
            showSkinSelectMenu(id);
            return PLUGIN_HANDLED;
        }

        if (iType == 0) {
            g_iSelectedT[id] = iModelIdx;
            if (is_shared_mode()) {
                g_iSelectedCT[id] = iModelIdx;
            }
            save_player_skins(id);
            apply_model(id);
        }
        else if (iType == 1) {
            g_iSelectedCT[id] = iModelIdx;
            save_player_skins(id);
            apply_model(id);
        }
        else if (iType == 2) {
            g_iSelectedKnife[id] = iModelIdx;
            save_player_skins(id);
            apply_model(id);
        }
        else if (iType == 3) {
            g_iSelectedUSP[id] = iModelIdx;
            save_player_skins(id);
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

// ============================================================
//  === M键玩家菜单 ===
// ============================================================
public cmdMenu(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_CONTINUE;
    }
    client_cmd(id, "chooseteam");
    return PLUGIN_HANDLED;
}

// ============================================================
//  === 批量发放全部皮肤 (/giveallskins) ===
// ============================================================
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
    new bool:bT = false, bool:bCT = false, bool:bKnife = false, bool:bUSP = false;

    if (equali(szTypeStr, "all")) {
        bT = true; bCT = true; bKnife = true; bUSP = true;
    } else if (equali(szTypeStr, "T") || equali(szTypeStr, "t")) {
        bT = true;
    } else if (equali(szTypeStr, "CT") || equali(szTypeStr, "ct")) {
        bCT = true;
    } else if (equali(szTypeStr, "Knife") || equali(szTypeStr, "knife") || equali(szTypeStr, "刀")) {
        bKnife = true;
    } else if (equali(szTypeStr, "USP") || equali(szTypeStr, "usp")) {
        bUSP = true;
    } else {
        client_print(id, print_chat, "[SkinSystem] 无效类型: %s, 请用 T/CT/Knife/USP/all", szTypeStr);
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

    save_player_skins(iTarget);

    client_print(id, print_chat, "[SkinSystem] 已向 %s 发放 %s类型全部皮肤 (%d个)", szTargetRealName, szTypeStr, iCount);
    client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了 %s类型全部皮肤 (%d个)", szAdminName, szTypeStr, iCount);

    return PLUGIN_HANDLED;
}

// ============================================================
//  === 管理员给指定玩家发放皮肤 - 菜单方式 (/giveskin) ===
// ============================================================
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
    formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放单个皮肤^n选择皮肤类型:^n^n\r1. \wT(土匪)皮肤^n\r2. \wCT(警察)皮肤^n\r3. \w刀皮肤^n\r4. \wUSP皮肤^n^n\r0. \w返回", szTargetName);
    new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<9);
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
    formatex(szMenu, charsmax(szMenu), "\y向 \r%s \y发放全部皮肤^n选择类型:^n^n\r1. \wT(土匪)全部^n\r2. \wCT(警察)全部^n\r3. \w刀全部^n\r4. \wUSP全部^n\r5. \w全部类型^n^n\r0. \w返回", szTargetName);
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
        switch (key) {
            case 0: { g_iGiveType[id] = 1; g_iGivePage[id] = 0; showGiveSkinListMenu(id); }
            case 1: { g_iGiveType[id] = 2; g_iGivePage[id] = 0; showGiveSkinListMenu(id); }
            case 2: { g_iGiveType[id] = 3; g_iGivePage[id] = 0; showGiveSkinListMenu(id); }
            case 3: { g_iGiveType[id] = 4; g_iGivePage[id] = 0; showGiveSkinListMenu(id); }
        }
        return PLUGIN_HANDLED;
    } else {
        new szAdminName[32], szTargetRealName[32];
        get_user_name(id, szAdminName, charsmax(szAdminName));
        get_user_name(iTarget, szTargetRealName, charsmax(szTargetRealName));
        new iCount = 0;
        new szTypeStr[32];

        switch (key) {
            case 0: {
                new iSize = ArraySize(g_aTModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 0, i)) { give_skin(iTarget, 0, i); iCount++; } }
                szTypeStr = "T";
            }
            case 1: {
                new iSize = ArraySize(g_aCTModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 1, i)) { give_skin(iTarget, 1, i); iCount++; } }
                szTypeStr = "CT";
            }
            case 2: {
                new iSize = ArraySize(g_aKnifeModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 2, i)) { give_skin(iTarget, 2, i); iCount++; } }
                szTypeStr = "Knife";
            }
            case 3: {
                new iSize = ArraySize(g_aUSPModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 3, i)) { give_skin(iTarget, 3, i); iCount++; } }
                szTypeStr = "USP";
            }
            case 4: {
                new iSize;
                iSize = ArraySize(g_aTModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 0, i)) { give_skin(iTarget, 0, i); iCount++; } }
                iSize = ArraySize(g_aCTModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 1, i)) { give_skin(iTarget, 1, i); iCount++; } }
                iSize = ArraySize(g_aKnifeModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 2, i)) { give_skin(iTarget, 2, i); iCount++; } }
                iSize = ArraySize(g_aUSPModels);
                for (new i = 0; i < iSize; i++) { if (!has_skin(iTarget, 3, i)) { give_skin(iTarget, 3, i); iCount++; } }
                szTypeStr = "全部";
            }
        }

        save_player_skins(iTarget);

        client_print(id, print_chat, "[SkinSystem] 已向 %s 发放 %s类型全部皮肤 (%d个)", szTargetRealName, szTypeStr, iCount);
        client_print(iTarget, print_chat, "[SkinSystem] 管理员 %s 向你发放了 %s类型全部皮肤 (%d个)", szAdminName, szTypeStr, iCount);
    }

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
    else { aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; copy(szTypeName, charsmax(szTypeName), "USP"); }

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
    else { aModels = g_aUSPModels; aModelNames = g_aUSPModelNames; }

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
        else copy(szTypeStr, charsmax(szTypeStr), "USP");

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

// ============================================================
//  /take - 收回皮肤 (仅服主)
// ============================================================
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

// ============================================================
//  === 存档 ===
// ============================================================
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

    save_skin_data_to_file();
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
}

// ============================================================
//  === 工具函数 ===
// ============================================================
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

// ============================================================
//  官方 AMXX 认证管理员判定（users.ini）
// ============================================================
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
    if (g_aUSPModels != Invalid_Array) { ArrayDestroy(g_aUSPModels); g_aUSPModels = Invalid_Array; }
    if (g_aUSPModelNames != Invalid_Array) { ArrayDestroy(g_aUSPModelNames); g_aUSPModelNames = Invalid_Array; }
}