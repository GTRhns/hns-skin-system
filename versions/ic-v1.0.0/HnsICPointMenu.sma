/*
 * ============================================================
 *  HNS IC Point Match System - 独立N键菜单插件 v1.0.0
 * ============================================================
 *  功能:
 *   1. 拦截 N 键 (nightvision) 打开独立菜单 (优先级高于 menu new)
 *   2. 开启比赛: 选择 娱乐局(不奖励) 或 赏金局(奖励), 各含 6 种比赛模式
 *   3. 赏金局比赛画面顶部显示 [赏金局] 标记
 *   4. 比赛结束仅在赏金局分配 IC 积分 (赢家 +10 / 输家 +5, CVAR 可配置)
 *   5. IC 积分与已兑换皮肤持久化 (PDS)
 *   6. 积分兑换皮肤: 人物500分 / 刀300分 (CVAR 可配置)
 *   7. 兑换皮肤直接应用模型 (rg_set_user_model), 一个月后自动清除
 *
 *  依赖: HnsMatchSystem.amxx / PersistentDataStorage / player_models.ini
 *  注意: 不修改 HnsMatchSkinSystem.amxx; 加载顺序需在 menu new 之后
 * ============================================================
 */
#include <amxmodx>
#include <amxmisc>
#include <string>
#include <reapi>
#include <PersistentDataStorage>
#include <hns_matchsystem>

#define m_szViewModel (m_szModel + 128)
#define MAX_MODEL_NAME    128
#define MAX_SKIN_NAME     64
#define MAX_AUTHID_LENGTH 64
#define MAX_OWNED         8
#define MONTH_SECONDS     2592000
#define MENU_IC_MAIN      10101
#define MENU_IC_SKIN      10102
#define MENU_IC_SKINLIST  10103
#define MENU_IC_TYPE      10104
#define MENU_IC_MODE      10105
#define MENU_IC_RECORD    10106
#define TASK_BOUNTY_HUD   9501

// 个人战绩每场记录字段 (紧凑)
#define MAX_STATS        12            // 每人最多保存最近 N 场
#define STATS_STRIP      (MAX_STATS*22+32)

// 皮肤类型: 0=T 1=CT 2=刀
enum _:SKIN_TYPE { SKIN_T=0, SKIN_CT, SKIN_KNIFE };

new Array:g_aModels[3];
new Array:g_aNames[3];

new g_iICPoints[MAX_PLAYERS+1];
new bool:g_bICLoaded[MAX_PLAYERS+1];
new g_iSkinType[MAX_PLAYERS+1];
new g_iSkinPage[MAX_PLAYERS+1];
new g_szPlayerAuth[MAX_PLAYERS+1][MAX_AUTHID_LENGTH];

// 已兑换皮肤 (按类型索引, 消除三套重复)
new g_iRedeemed[MAX_PLAYERS+1][3][MAX_OWNED];
new g_iRedeemedExp[MAX_PLAYERS+1][3][MAX_OWNED];
new g_iRedeemedCount[MAX_PLAYERS+1][3];

new pcvar_win_pts, pcvar_loss_pts, pcvar_person_pts, pcvar_knife_pts;

// true = 赏金局(奖励IC点), false = 娱乐局(不奖励)
new bool:g_bBountyMatch;

// 本场参赛玩家 (hns_player_join/leave_inmatch 维护)
new bool:g_bInMatch[MAX_PLAYERS+1];

// 赞助积分赛: 当前赏金局奖池
new g_iSponsorPool;
new g_iSponsorCount;

// PDS 皮肤键后缀
new const g_szTypeKey[3][2] = {"t","c","k"};

// 模式名映射 (与菜单顺序一致)
new const g_szModeNames[6][10] = {"MR","计时","决斗","突围","吸血","回合制"};

public plugin_init() {
    register_plugin("HNS IC Point Menu","1.0.0","HNS IC System");
    register_clcmd("nightvision","cmdICMenu");
    register_clcmd("say /ic","cmdICMenu");
    register_clcmd("say_team /ic","cmdICMenu");
    register_clcmd("say /icpoint","cmdICMenu");
    register_clcmd("say_team /icpoint","cmdICMenu");
    // 管理员直接给予 IC 点
    register_clcmd("say /givetic","cmdGiveIC");
    register_clcmd("say /giveic","cmdGiveIC");
    register_clcmd("say /addic","cmdGiveIC");
    register_clcmd("say_team /givetic","cmdGiveIC");
    register_clcmd("say_team /giveic","cmdGiveIC");
    register_clcmd("say_team /addic","cmdGiveIC");
    pcvar_win_pts   = register_cvar("ic_pts_win",     "10", FCVAR_SERVER);
    pcvar_loss_pts  = register_cvar("ic_pts_loss",    "5",  FCVAR_SERVER);
    pcvar_person_pts= register_cvar("ic_skin_person", "500", FCVAR_SERVER);
    pcvar_knife_pts = register_cvar("ic_skin_knife",  "300", FCVAR_SERVER);
    load_models();
    register_menucmd(register_menuid("HnsICMain"),(1<<0)|(1<<1)|(1<<9),"icMainHandler");
    register_menucmd(register_menuid("HnsICSkin"),(1<<0)|(1<<1)|(1<<2)|(1<<9),"icSkinHandler");
    register_menucmd(register_menuid("HnsICSkinList"),511|(1<<8)|(1<<9),"icSkinListHandler");
    register_menucmd(register_menuid("HnsICType"),(1<<0)|(1<<1)|(1<<9),"icTypeHandler");
    register_menucmd(register_menuid("HnsICMode"),(1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<9),"icModeHandler");
    register_menucmd(register_menuid("HnsICRecord"),(1<<0)|(1<<1)|(1<<9),"icRecordHandler");
    register_menucmd(register_menuid("HnsICRecordSub"),(1<<0)|(1<<9),"icRecordSubHandler");
    // 玩家赞助积分赛
    register_clcmd("say /sponsor","cmdSponsor");
    register_clcmd("say_team /sponsor","cmdSponsor");
    register_clcmd("say /support","cmdSponsor");
    register_clcmd("say_team /support","cmdSponsor");
    set_task(60.0,"task_check_expiry",0,.flags="b");
}

// ============================================================
//  N 键菜单
// ============================================================
public cmdICMenu(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!g_bICLoaded[id]) load_player_ic(id);
    showMainMenu(id);
    return PLUGIN_HANDLED;
}
public icMainHandler(id,key) {
    if (key==9) return PLUGIN_HANDLED;
    if (key==0) {
        if (!isUserWatcher(id) && !is_user_admin(id)) {
            client_print_color(id,print_team_default,"^4[IC点] ^3你没有权限开启比赛");
            showMainMenu(id);
            return PLUGIN_HANDLED;
        }
        new MATCH_STATUS:iSt=hns_get_status();
        if (iSt==MATCH_STARTED)   { client_print_color(id,print_team_default,"^4[IC点] ^3比赛已在进行中"); showMainMenu(id); return PLUGIN_HANDLED; }
        if (iSt==MATCH_WAITCONNECT||iSt==MATCH_CAPTAINPICK) { client_print_color(id,print_team_default,"^4[IC点] ^3比赛准备阶段中"); showMainMenu(id); return PLUGIN_HANDLED; }
        showMatchTypeMenu(id);
    }
    else if (key==1) showRedeemMenu(id);
    else if (key==2) showRecordMenu(id);
    return PLUGIN_HANDLED;
}
stock showMainMenu(id) {
    new szMenu[512], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * IC 点 比 赛 系 统 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前积分: \w%d^n",g_iICPoints[id]);
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前奖池: \w%d^n",g_iSponsorPool);
    new szStatus[32];
    get_match_status_str(szStatus,charsmax(szStatus));
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前状态: \w%s^n",szStatus);
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \w开启比赛 \y▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r2. \w积分兑换皮肤 \y▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r3. \w比赛记录/赞助 \y▶^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w关闭 \y✕");
    show_menu(id,(1<<0)|(1<<1)|(1<<2)|(1<<9),szMenu,-1,"HnsICMain");
}

// 当前比赛状态文字
stock get_match_status_str(szBuffer[], iLen) {
    new MATCH_STATUS:iSt=hns_get_status();
    if (iSt==MATCH_STARTED)       copy(szBuffer,iLen,"比赛进行中");
    else if (iSt==MATCH_WAITCONNECT)   copy(szBuffer,iLen,"准备阶段(等玩家)");
    else if (iSt==MATCH_CAPTAINPICK)   copy(szBuffer,iLen,"准备阶段(选队长)");
    else copy(szBuffer,iLen,"空闲");
}

// ============================================================
//  比赛类型菜单 (娱乐局/赏金局)
// ============================================================
public icTypeHandler(id,key) {
    if (key==9) { showMainMenu(id); return PLUGIN_HANDLED; }
    g_bBountyMatch = (key==1);
    showModeMenu(id);
    return PLUGIN_HANDLED;
}
stock showMatchTypeMenu(id) {
    new szMenu[512], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 选 择 比 赛 类 型 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \w娱乐局^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   └ 不奖励IC点 轻松练练^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r2. \w赏金局^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   └ 获胜\w+%d\y 失败\w+%d\y 可赞助^n^n",get_pcvar_num(pcvar_win_pts),get_pcvar_num(pcvar_loss_pts));
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<1)|(1<<9),szMenu,-1,"HnsICType");
}

// ============================================================
//  模式选择菜单 (6 种比赛模式)
// ============================================================
public icModeHandler(id,key) {
    if (key==9) { showMatchTypeMenu(id); return PLUGIN_HANDLED; }
    start_hns_mode(id,key+1);
    return PLUGIN_HANDLED;
}
stock showModeMenu(id) {
    new szMenu[512], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * %s * * *^n^n",g_bBountyMatch?"赏 金 局 - 选 择 模 式":"娱 乐 局 - 选 择 模 式");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \wMR \y└ 最大回合数^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r2. \w计时 \y└ 限时对抗^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r3. \w决斗 \y└ 1v1对决^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r4. \w突围 \y└ 逃跑突围^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r5. \w吸血 \y└ 吸血生存^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r6. \w回合 \y└ 回合积分^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<9),szMenu,-1,"HnsICMode");
}

// ============================================================
//  触发对应比赛模式
//  MR/计时/决斗: 通过 say 命令在比赛系统内部设置规则, 再启动混合赛
//  突围/吸血/回合: 直接调用 hns_set_mode native
// ============================================================
stock start_hns_mode(id,iMode) {
    new szModeName[24];
    switch (iMode) {
        case 1: { copy(szModeName,charsmax(szModeName),"MR");   client_cmd(id,"say /mr");    set_task(0.3,"task_start_mix",id); }
        case 2: { copy(szModeName,charsmax(szModeName),"计时"); client_cmd(id,"say /timer"); set_task(0.3,"task_start_mix",id); }
        case 3: { copy(szModeName,charsmax(szModeName),"决斗"); client_cmd(id,"say /duel");  set_task(0.3,"task_start_mix",id); }
        case 4: { copy(szModeName,charsmax(szModeName),"突围"); hns_set_mode(MODE_ASCENSION); }
        case 5: { copy(szModeName,charsmax(szModeName),"吸血"); hns_set_mode(MODE_VAMP); }
        case 6: { copy(szModeName,charsmax(szModeName),"回合制"); hns_set_mode(MODE_ROUNDS); }
    }
    if (g_bBountyMatch) {
        client_print_color(0,print_team_default,"^4[IC点] ^1%n ^3开启赏金局^1[%s]! 获胜^4+%d^1/失败^4+%d",
            id,szModeName,get_pcvar_num(pcvar_win_pts),get_pcvar_num(pcvar_loss_pts));
    } else {
        client_print_color(0,print_team_default,"^4[IC点] ^1%n ^3开启娱乐局^1[%s]! 不奖励IC点",id,szModeName);
    }
}
public task_start_mix(id) {
    if (is_user_connected(id)) hns_set_mode(MODE_MIX);
}

// ============================================================
//  比赛记录菜单 (个人战绩 / 最近比赛 / 赞助)
// ============================================================
public icRecordHandler(id,key) {
    if (key==9) { showMainMenu(id); return PLUGIN_HANDLED; }
    if (key==0) showMyStats(id);
    else if (key==1) showRecentMatches(id);
    return PLUGIN_HANDLED;
}
public icRecordSubHandler(id,key) {
    if (key==9) { showMainMenu(id); return PLUGIN_HANDLED; }
    return PLUGIN_HANDLED;
}
stock showRecordMenu(id) {
    new szMenu[256], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 记 录 与 赞 助 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \w我的战绩 \y▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r2. \w最近比赛 \y▶^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r9. \w赞助积分赛 \y▶^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<1)|(1<<8)|(1<<9),szMenu,-1,"HnsICRecord");
}

// --- 我的战绩 ---
stock showMyStats(id) {
    if (!g_bICLoaded[id]) load_player_ic(id);
    new szStats[STATS_STRIP], szKey[160];
    copy(szKey,charsmax(szKey),"hnsic_stats_");
    add(szKey,charsmax(szKey),g_szPlayerAuth[id]);
    new szMenu[512], iLen, iTotal=0, pos=0;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 我 的 战 绩 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    new iWin=0;
    if (PDS_GetString(szKey,szStats,charsmax(szStats)) && szStats[0]) {
        new iEntry=0;
        while (pos < strlen(szStats)) {
            if (szStats[pos]!='T') break;
            pos++;
            new ts=0; while (pos<strlen(szStats) && szStats[pos]>='0'&&szStats[pos]<='9'){ts=ts*10+(szStats[pos]-'0');pos++;}
            new mode=0; if (szStats[pos]=='M'){pos++; while(pos<strlen(szStats)&&szStats[pos]>='0'&&szStats[pos]<='9'){mode=mode*10+(szStats[pos]-'0');pos++;}}
            new win=0;  if (szStats[pos]=='W'){pos++; win=(szStats[pos]=='1')&&!0; pos++;}
            new pts=0;  if (szStats[pos]=='P'){pos++; while(pos<strlen(szStats)&&szStats[pos]>='0'&&szStats[pos]<='9'){pts=pts*10+(szStats[pos]-'0');pos++;}}
            if (pos<strlen(szStats)&&szStats[pos]==';') pos++;
            iTotal++;
            if (win) iWin++;
            if (iEntry<7) {
                new szDate[24];
                format_time(szDate,charsmax(szDate),"%m-%d %H:%M",ts);
                iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r%d. \w%s \y[%s]\w %s^n",
                    iEntry+1,szDate,(mode>=0&&mode<6)?g_szModeNames[mode]:"未知",win?"\w胜\y✓":"\r负");
                iEntry++;
            }
        }
        if (iTotal==0) iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   暂无战绩^n");
        else iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"^n\y  共 %d 场 胜 %d 场^n",iTotal,iWin);
    } else {
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   暂无战绩^n");
    }
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"^n\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<9),szMenu,-1,"HnsICRecordSub");
}

// --- 最近比赛 (全局) ---
stock showRecentMatches(id) {
    new szPath[256];
    get_localinfo("amxx_configsdir",szPath,charsmax(szPath));
    add(szPath,charsmax(szPath),"/mixsystem/match_history.txt");
    new szMenu[512], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 最 近 比 赛 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    new f=fopen(szPath,"rt");
    if (f) {
        new szLines[8][128], iLine=0, szLine[256];
        while (!feof(f)) {
            fgets(f,szLine,charsmax(szLine));
            trim(szLine);
            if (szLine[0]==0) continue;
            if (iLine<8) copy(szLines[iLine],127,szLine);
            else { for (new j=0;j<7;j++) copy(szLines[j],127,szLines[j+1]); copy(szLines[7],127,szLine); }
            if (iLine<8) iLine++;
        }
        fclose(f);
        if (iLine==0) iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   暂无记录^n");
        else {
            for (new i=0;i<iLine;i++) {
                new ts=0, mode=0, bounty=0, pts=0, pos=0;
                if (szLines[i][pos]=='T') {
                    pos++;
                    while (pos<strlen(szLines[i]) && szLines[i][pos]>='0'&&szLines[i][pos]<='9'){ts=ts*10+(szLines[i][pos]-'0');pos++;}
                    if (szLines[i][pos]=='M'){pos++; mode=szLines[i][pos]-'0'; pos++;}
                    if (szLines[i][pos]=='B'){pos++; bounty=szLines[i][pos]-'0'; pos++;}
                    if (szLines[i][pos]=='P'){pos++; while(pos<strlen(szLines[i])&&szLines[i][pos]>='0'&&szLines[i][pos]<='9'){pts=pts*10+(szLines[i][pos]-'0');pos++;}}
                    new szDate[24];
                    format_time(szDate,charsmax(szDate),"%m-%d %H:%M",ts);
                    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r%d. \w%s \y[%s]%s^n",
                        i+1,szDate,mode>=0&&mode<6?g_szModeNames[mode]:"未知",bounty?"\w(赏金)":"");
                }
            }
        }
    } else {
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y   暂无记录^n");
    }
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"^n\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<9),szMenu,-1,"HnsICRecordSub");
}

// ============================================================
//  赞助积分赛
// ============================================================
public cmdSponsor(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!g_bICLoaded[id]) load_player_ic(id);
    new szArg[16];
    read_argv(1,szArg,charsmax(szArg));
    if (szArg[0]==0) {
        // 打开赞助菜单
        new szMenu[256], iLen;
        iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 赞 助 积 分 赛 * * *^n^n");
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前积分: \w%d^n",g_iICPoints[id]);
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前奖池: \w%d^n^n",g_iSponsorPool);
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  └ 聊天框输入: \w/sponsor 数量^n");
        iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  └ 例: \w/sponsor 100^n^n\r0. \w关闭 \y✕");
        show_menu(id,(1<<0)|(1<<9),szMenu,-1,"HnsICRecordSub");
        return PLUGIN_HANDLED;
    }
    new iAmount = str_to_num(szArg);
    if (iAmount<=0) { client_print_color(id,print_team_default,"^4[IC点] ^3赞助数量必须大于0"); return PLUGIN_HANDLED; }
    if (!g_bBountyMatch) {
        client_print_color(id,print_team_default,"^4[IC点] ^3当前没有进行中的赏金局, 无法赞助");
        return PLUGIN_HANDLED;
    }
    if (hns_get_status()!=MATCH_STARTED) {
        client_print_color(id,print_team_default,"^4[IC点] ^3比赛尚未开始, 无法赞助");
        return PLUGIN_HANDLED;
    }
    if (g_iICPoints[id] < iAmount) {
        client_print_color(id,print_team_default,"^4[IC点] ^3积分不足 需要\w%d^3(当前\w%d^3)",iAmount,g_iICPoints[id]);
        return PLUGIN_HANDLED;
    }
    // 扣除赞助
    g_iICPoints[id]-=iAmount;
    save_player_ic(id);
    g_iSponsorPool+=iAmount;
    g_iSponsorCount++;
    client_print_color(0,print_team_default,"^4[IC点] ^1%n ^3赞助赏金局 ^4+%d^1 IC点! 当前奖池^4%d^1",id,iAmount,g_iSponsorPool);
    return PLUGIN_HANDLED;
}

// ============================================================
//  IC 积分持久化
// ============================================================
stock get_player_identifier(id, szBuffer[], iLen) {
    if (g_szPlayerAuth[id][0]==0) get_user_authid(id,g_szPlayerAuth[id],MAX_AUTHID_LENGTH-1);
    copy(szBuffer,iLen,g_szPlayerAuth[id]);
}
stock load_player_ic(const id) {
    if (!is_user_connected(id)) return;
    new szId[MAX_AUTHID_LENGTH], szKey[160];
    get_player_identifier(id,szId,charsmax(szId));
    if (szId[0]==0) return;
    copy(szKey,charsmax(szKey),"hnsic_icpts_");
    add(szKey,charsmax(szKey),szId);
    g_iICPoints[id] = 0;
    PDS_GetCell(szKey, g_iICPoints[id]);
    load_redeemed_skins(id,szId);
    g_bICLoaded[id]=true;
}
stock save_player_ic(const id) {
    new szId[MAX_AUTHID_LENGTH], szKey[160];
    get_player_identifier(id,szId,charsmax(szId));
    if (szId[0]==0) return;
    copy(szKey,charsmax(szKey),"hnsic_icpts_");
    add(szKey,charsmax(szKey),szId);
    PDS_SetCell(szKey,g_iICPoints[id]);
    save_redeemed_skins(id,szId);
}

// ============================================================
//  比赛结束分配积分 (仅赏金局) + 记录 + 分发赞助奖池
// ============================================================
// 统一判定: 某参赛者是否为本场获胜方 (基于其当前队伍)
// 仅在线且有明确队伍者参与发分/记录, 与战绩口径完全一致
stock bool:is_match_winner(id,iWinTeam) {
    if (!is_user_connected(id)) return false;
    new TeamName:t=get_member(id,m_iTeam);
    if (t==TEAM_TERRORIST) return (iWinTeam==1);
    if (t==TEAM_CT) return (iWinTeam==2);
    return false;
}

public hns_match_finished(iWinTeam) {
    new iWP,iLP;
    iWP=get_pcvar_num(pcvar_win_pts); iLP=get_pcvar_num(pcvar_loss_pts);
    // 赞助奖池: 分给 g_bInMatch 参赛者中的获胜者 (平分)
    if (g_iSponsorPool>0) {
        new iWNum=0;
        for (new i=1;i<=MAX_PLAYERS;i++)
            if (g_bInMatch[i] && is_match_winner(i,iWinTeam)) iWNum++;
        if (iWNum>0) {
            new iShare=g_iSponsorPool/iWNum;
            for (new i=1;i<=MAX_PLAYERS;i++)
                if (g_bInMatch[i] && is_match_winner(i,iWinTeam)) add_ic_points(i,iShare);
            client_print_color(0,print_team_default,"^4[IC点] ^3赞助奖池 ^4%d^3 分给获胜队伍 %d 人, 每人 ^4+%d",g_iSponsorPool,iWNum,iShare);
        } else {
            client_print_color(0,print_team_default,"^4[IC点] ^3赞助奖池 ^4%d^3 无人领取已清空",g_iSponsorPool);
        }
    }
    // 发分: 仅赏金局, 只给 g_bInMatch 参赛者
    if (g_bBountyMatch) {
        for (new i=1;i<=MAX_PLAYERS;i++) {
            if (!g_bInMatch[i]) continue;
            if (is_match_winner(i,iWinTeam)) add_ic_points(i,iWP);
            else add_ic_points(i,iLP);
        }
    }
    record_match(iWinTeam,g_bBountyMatch);
    g_bBountyMatch=false;
    clear_match_tracking();
}

// ============================================================
//  参赛玩家追踪
// ============================================================
public hns_player_join_inmatch(id,bool:bReplaced) {
    if (is_user_connected(id)) g_bInMatch[id]=true;
}
public hns_player_leave_inmatch(id) {
    g_bInMatch[id]=false;
}
stock clear_match_tracking() {
    g_iSponsorPool=0;
    g_iSponsorCount=0;
    for (new i=1;i<=MAX_PLAYERS;i++) g_bInMatch[i]=false;
    if (task_exists(TASK_BOUNTY_HUD)) remove_task(TASK_BOUNTY_HUD);
}

// ============================================================
//  记录本场比赛 (全局文件 + 参赛玩家个人战绩)
// ============================================================
stock record_match(iWinTeam,bool:bBounty) {
    new iMode = -1;
    new HNS_MODES:m = hns_get_mode();
    switch (m) {
        case MODE_MIX: iMode=0;
        case MODE_ASCENSION: iMode=3;
        case MODE_VAMP: iMode=4;
        case MODE_ROUNDS: iMode=5;
        default: iMode=0;
    }
    if (iMode<0) iMode=0;
    // 全局历史文件: T<ts>M<mode>B<bounty>P<sponsorPool>
    new szPath[256];
    get_localinfo("amxx_configsdir",szPath,charsmax(szPath));
    add(szPath,charsmax(szPath),"/mixsystem/match_history.txt");
    new f=fopen(szPath,"at");
    if (f) {
        new szLine[96];
        formatex(szLine,charsmax(szLine),"T%dM%dB%dP%d\r\n",get_systime(),iMode,bBounty?1:0,g_iSponsorPool);
        fputs(f,szLine);
        fclose(f);
    }
    // 个人战绩: 只记录 g_bInMatch 参赛者, 与发分口径一致
    for (new id=1;id<=MAX_PLAYERS;id++) {
        if (!g_bInMatch[id]) continue;
        if (!is_user_connected(id)) continue;
        save_stat_entry(id,iMode,is_match_winner(id,iWinTeam));
    }
}

// ============================================================
//  写入单个玩家的战绩记录 (PDS, 保留最多 MAX_STATS 场)
// ============================================================
stock save_stat_entry(id,iMode,bool:bWin) {
    if (!is_user_connected(id)) return;
    if (!g_bICLoaded[id]) load_player_ic(id);
    new szKey[160];
    copy(szKey,charsmax(szKey),"hnsic_stats_");
    add(szKey,charsmax(szKey),g_szPlayerAuth[id]);
    new szOld[STATS_STRIP], szNew[STATS_STRIP];
    if (!PDS_GetString(szKey,szOld,charsmax(szOld)) || !szOld[0]) szOld[0]=0;
    new szEntry[40];
    formatex(szEntry,charsmax(szEntry),"T%dM%dW%dP0;",get_systime(),iMode,bWin?1:0);
    copy(szNew,charsmax(szNew),szEntry);
    add(szNew,charsmax(szNew),szOld);
    // 截断到最近 MAX_STATS 场
    new iCount=0, pos=0;
    while (pos<strlen(szNew)) {
        if (szNew[pos]=='T') iCount++;
        if (iCount>MAX_STATS) { szNew[pos]=0; break; }
        pos++;
    }
    PDS_SetString(szKey,szNew);
}

// ============================================================
//  比赛生命周期: 赏金局顶部标记
// ============================================================
public hns_match_started() {
    if (g_bBountyMatch && !task_exists(TASK_BOUNTY_HUD))
        set_task(1.0,"task_bounty_hud",TASK_BOUNTY_HUD,.flags="b");
}
public hns_match_canceled() {
    if (g_iSponsorPool>0) client_print_color(0,print_team_default,"^4[IC点] ^3比赛取消, 赞助奖池 ^4%d^3 已返还",g_iSponsorPool);
    g_bBountyMatch=false;
    clear_match_tracking();
}
public task_bounty_hud() {
    if (!g_bBountyMatch || hns_get_status()!=MATCH_STARTED) {
        if (task_exists(TASK_BOUNTY_HUD)) remove_task(TASK_BOUNTY_HUD);
        return;
    }
    set_hudmessage(255,215,0,-1.0,0.02,0,0.0,1.2,0.1,0.1,-1);
    show_hudmessage(0,"[赏金局]");
}
stock add_ic_points(id,iAmount) {
    if (!is_user_connected(id)||iAmount<=0) return;
    if (!g_bICLoaded[id]) load_player_ic(id);
    g_iICPoints[id]+=iAmount;
    save_player_ic(id);
    client_print_color(id,print_team_default,"^4[IC点] ^1本场\w+%d^1分 (当前\w%d^1)",iAmount,g_iICPoints[id]);
}

// ============================================================
//  管理员直接给予 IC 点
//  用法: /givetic <玩家名|@ALL> <数量>
//  权限: users.ini 官方认证管理员 (is_user_admin)
// ============================================================
public cmdGiveIC(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!is_user_admin(id)) {
        client_print_color(id,print_team_default,"^4[IC点] ^3只有管理员才能直接给予IC点");
        return PLUGIN_HANDLED;
    }
    new szArg1[33], szArg2[16];
    read_argv(1,szArg1,charsmax(szArg1));
    read_argv(2,szArg2,charsmax(szArg2));
    if (szArg1[0]==0 || szArg2[0]==0) {
        client_print_color(id,print_team_default,"^4[IC点] ^3用法: /givetic <玩家名|@ALL> <数量>");
        return PLUGIN_HANDLED;
    }
    new iAmount = str_to_num(szArg2);
    if (iAmount<=0) {
        client_print_color(id,print_team_default,"^4[IC点] ^3数量必须大于0");
        return PLUGIN_HANDLED;
    }
    // 批量给予所有在线玩家
    if (equali(szArg1,"@ALL")||equali(szArg1,"@all")||equali(szArg1,"*")||equali(szArg1,"ALL")) {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers,iNum,"ch");
        for (new i=0;i<iNum;i++) if (is_user_connected(iPlayers[i])) add_ic_points(iPlayers[i],iAmount);
        client_print_color(0,print_team_default,"^4[IC点] ^1管理员 %n ^3给予在线所有玩家 ^4+%d^1 IC点",id,iAmount);
        return PLUGIN_HANDLED;
    }
    // 单个玩家: 支持部分名字匹配
    new target = find_player("bl",szArg1);
    if (!is_user_connected(target)) {
        client_print_color(id,print_team_default,"^4[IC点] ^3找不到玩家 ^4%s",szArg1);
        return PLUGIN_HANDLED;
    }
    add_ic_points(target,iAmount);
    client_print_color(0,print_team_default,"^4[IC点] ^1管理员 %n ^3给予 %n ^4+%d^1 IC点",id,target,iAmount);
    return PLUGIN_HANDLED;
}

// ============================================================
//  皮肤兑换菜单
// ============================================================
public icSkinHandler(id,key) {
    if (key==9) { showMainMenu(id); return PLUGIN_HANDLED; }
    if (key==0) g_iSkinType[id]=SKIN_T;
    else if (key==1) g_iSkinType[id]=SKIN_CT;
    else if (key==2) g_iSkinType[id]=SKIN_KNIFE;
    g_iSkinPage[id]=0;
    showSkinList(id);
    return PLUGIN_HANDLED;
}
stock showRedeemMenu(id) {
    new szMenu[256], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * IC 积 分 兑 换 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前积分: \w%d^n",g_iICPoints[id]);
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \w人物皮肤  \y(T) ▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r2. \w人物皮肤  \y(CT) ▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r3. \w刀皮肤     \y(高价) ▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    show_menu(id,(1<<0)|(1<<1)|(1<<2)|(1<<9),szMenu,-1,"HnsICSkin");
}
stock showSkinList(id) {
    new iType=g_iSkinType[id];
    if (ArraySize(g_aModels[iType])<=0) { client_print_color(id,print_team_default,"^4[IC点] ^3皮肤列表为空"); showRedeemMenu(id); return; }
    new iTotal=ArraySize(g_aModels[iType]), ip=g_iSkinPage[id], per=8, st=ip*per, en=st+per;
    if (en>iTotal) en=iTotal;
    new szMenu[512], iLen, szName[MAX_SKIN_NAME], k=0;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * 皮 肤 列 表 * * *^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  └ %s 第 %d/%d 页^n^n",iType==SKIN_T?"T阵营":(iType==SKIN_CT?"CT阵营":"刀"),ip+1,(iTotal+per-1)/per);
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    for (new i=st;i<en;i++) {
        ArrayGetString(g_aNames[iType],i,szName,charsmax(szName));
        if (is_skin_owned(id,iType,st+k))
            iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r%d. \w%s \y✓已拥有^n",++k,szName);
        else {
            new cost=(iType==SKIN_KNIFE)?get_pcvar_num(pcvar_knife_pts):get_pcvar_num(pcvar_person_pts);
            iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r%d. \w%s \y(%d分)^n",++k,szName,cost);
        }
    }
    if (en<iTotal) iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    if (en<iTotal) iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r9. \w下一页 \y▶^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w返回 \y◀");
    new keys=0;
    for (new i=0;i<en-st;i++) keys|=(1<<i);
    if (en<iTotal) keys|=(1<<8);
    keys|=(1<<9);
    show_menu(id,keys,szMenu,-1,"HnsICSkinList");
}
public icSkinListHandler(id,key) {
    if (key==9) { showRedeemMenu(id); return PLUGIN_HANDLED; }
    if (key==8) { g_iSkinPage[id]++; showSkinList(id); return PLUGIN_HANDLED; }
    new iType=g_iSkinType[id], idx=g_iSkinPage[id]*8+key;
    if (idx>=ArraySize(g_aModels[iType])) { showSkinList(id); return PLUGIN_HANDLED; }
    if (is_skin_owned(id,iType,idx)) { client_print_color(id,print_team_default,"^4[IC点] ^3已拥有该皮肤"); showSkinList(id); return PLUGIN_HANDLED; }
    new cost=(iType==SKIN_KNIFE)?get_pcvar_num(pcvar_knife_pts):get_pcvar_num(pcvar_person_pts);
    if (g_iICPoints[id]<cost) { client_print_color(id,print_team_default,"^4[IC点] ^3积分不足 需要\w%d^3(当前\w%d^3)",cost,g_iICPoints[id]); showSkinList(id); return PLUGIN_HANDLED; }
    redeem_skin(id,iType,idx,cost);
    showSkinList(id);
    return PLUGIN_HANDLED;
}

// ============================================================
//  兑换 + 应用模型
// ============================================================
stock bool:is_skin_owned(id,iType,iIndex) {
    for (new i=0;i<g_iRedeemedCount[id][iType];i++)
        if (g_iRedeemed[id][iType][i]==iIndex && g_iRedeemedExp[id][iType][i]>get_systime()) return true;
    return false;
}
stock redeem_skin(id,iType,iIndex,iCost) {
    g_iICPoints[id]-=iCost;
    save_player_ic(id);
    if (g_iRedeemedCount[id][iType]<MAX_OWNED) {
        g_iRedeemed[id][iType][g_iRedeemedCount[id][iType]]=iIndex;
        g_iRedeemedExp[id][iType][g_iRedeemedCount[id][iType]]=get_systime()+MONTH_SECONDS;
        g_iRedeemedCount[id][iType]++;
        save_redeemed_skins(id,"");
    }
    client_print_color(id,print_team_default,"^4[IC点] ^1兑换成功 扣除\w%d^1分 有效期\y30天",iCost);
    apply_all_models(id);
}
stock extract_folder_from_path(const szPath[],szFolder[],iLen) {
    new iLast=0, i, len=strlen(szPath);
    for (i=0;i<len;i++) if (szPath[i]=='/'||szPath[i]==92) iLast=i;
    if (iLast<=0) { copy(szFolder,iLen,szPath); return; }
    new szTemp[MAX_MODEL_NAME];
    copy(szTemp,charsmax(szTemp),szPath[iLast+1]);
    new bool:bKnife=false, tl=strlen(szTemp);
    for (new zi=0;zi<tl-1;zi++) if (szTemp[zi]=='v'&&szTemp[zi+1]=='_') { bKnife=true; break; }
    if (bKnife) {
        new szDir[MAX_MODEL_NAME];
        copy(szDir,charsmax(szDir),szPath);
        szDir[iLast]=0;
        new iPrev=0;
        for (i=0;i<iLast;i++) if (szDir[i]=='/'||szDir[i]==92) iPrev=i;
        if (iPrev>0) copy(szFolder,iLen,szDir[iPrev+1]);
        else copy(szFolder,iLen,szDir);
    } else copy(szFolder,iLen,szTemp);
}
stock apply_all_models(const id) {
    if (!is_user_alive(id)) return;
    new TeamName:t=get_member(id,m_iTeam);
    new iType=(t==TEAM_TERRORIST)?SKIN_T:((t==TEAM_CT)?SKIN_CT:-1);
    if (iType>=0) {
        new iBest=-1;
        for (new i=0;i<g_iRedeemedCount[id][iType];i++)
            if (g_iRedeemedExp[id][iType][i]>get_systime()) { iBest=g_iRedeemed[id][iType][i]; break; }
        if (iBest>=0 && iBest<ArraySize(g_aModels[iType])) {
            new szPath[MAX_MODEL_NAME], szFolder[MAX_MODEL_NAME];
            ArrayGetString(g_aModels[iType],iBest,szPath,charsmax(szPath));
            extract_folder_from_path(szPath,szFolder,charsmax(szFolder));
            rg_set_user_model(id,szFolder);
        } else rg_set_user_model(id,"");
    }
    new iK=-1;
    for (new i=0;i<g_iRedeemedCount[id][SKIN_KNIFE];i++)
        if (g_iRedeemedExp[id][SKIN_KNIFE][i]>get_systime()) { iK=g_iRedeemed[id][SKIN_KNIFE][i]; break; }
    if (iK>=0 && iK<ArraySize(g_aModels[SKIN_KNIFE])) {
        new szPath[MAX_MODEL_NAME];
        ArrayGetString(g_aModels[SKIN_KNIFE],iK,szPath,charsmax(szPath));
        set_member(id,m_szViewModel,szPath);
    }
}

// ============================================================
//  到期清除
// ============================================================
public task_check_expiry() {
    new iNow=get_systime(), iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers,iNum,"ch");
    for (new i=0;i<iNum;i++) purge_expired_skins(iPlayers[i],iNow);
}
stock purge_expired_skins(id,iNow) {
    for (new t=0;t<3;t++)
        for (new i=0;i<g_iRedeemedCount[id][t];i++)
            if (g_iRedeemedExp[id][t][i]<=iNow) {
                for (new j=i;j<g_iRedeemedCount[id][t]-1;j++) {
                    g_iRedeemed[id][t][j]=g_iRedeemed[id][t][j+1];
                    g_iRedeemedExp[id][t][j]=g_iRedeemedExp[id][t][j+1];
                }
                g_iRedeemedCount[id][t]--;
                i--;
            }
}

// ============================================================
//  加载 player_models.ini
// ============================================================
stock load_models() {
    for (new t=0;t<3;t++) { g_aModels[t]=ArrayCreate(MAX_MODEL_NAME,1); g_aNames[t]=ArrayCreate(MAX_SKIN_NAME,1); }
    new szPath[256];
    get_localinfo("amxx_configsdir",szPath,charsmax(szPath));
    add(szPath,charsmax(szPath),"/mixsystem/player_models.ini");
    new f=fopen(szPath,"rt");
    if (!f) { log_amx("[ICPoint] 皮肤配置文件不存在: %s",szPath); return; }
    new szLine[512], ty=-1;
    while (!feof(f)) {
        fgets(f,szLine,charsmax(szLine));
        trim(szLine);
        if (szLine[0]==';'||(szLine[0]=='/'&&szLine[1]=='/')||szLine[0]==0) continue;
        if (szLine[0]=='[') {
            new len=strlen(szLine);
            if (szLine[len-1]==']') szLine[--len]=0;
            szLine[len]=0;
            if (equali(szLine,"[T")||equali(szLine,"[Terrorist")||equali(szLine,"[TT")) ty=SKIN_T;
            else if (equali(szLine,"[CT")||equali(szLine,"[Counter-Terrorist")||equali(szLine,"[CounterTerrorist")) ty=SKIN_CT;
            else if (equali(szLine,"[Knife")||equali(szLine,"[Knives")) ty=SKIN_KNIFE;
            else ty=-1;
            continue;
        }
        if (ty<0) continue;
        new szName[MAX_SKIN_NAME], szModel[MAX_MODEL_NAME], sp=-1;
        for (new zi=0;zi<strlen(szLine);zi++) if (szLine[zi]==' ') { sp=zi; break; }
        if (sp<=0) continue;
        copy(szName,sp+1,szLine);
        copy(szModel,charsmax(szModel),szLine[sp+1]);
        trim(szName); trim(szModel);
        if (szName[0]==0||szModel[0]==0) continue;
        ArrayPushString(g_aModels[ty],szModel);
        ArrayPushString(g_aNames[ty],szName);
    }
    fclose(f);
    log_amx("[ICPoint] 皮肤 T=%d CT=%d Knife=%d",ArraySize(g_aModels[SKIN_T]),ArraySize(g_aModels[SKIN_CT]),ArraySize(g_aModels[SKIN_KNIFE]));
}

// ============================================================
//  玩家生命期
// ============================================================
public client_putinserver(id) {
    g_szPlayerAuth[id][0]=0;
    get_user_authid(id,g_szPlayerAuth[id],MAX_AUTHID_LENGTH-1);
    g_bICLoaded[id]=false;
    g_iICPoints[id]=0;
    for (new t=0;t<3;t++) g_iRedeemedCount[id][t]=0;
    load_player_ic(id);
}
public client_disconnected(id) {
    save_player_ic(id);
    g_bICLoaded[id]=false;
}
public rgPlayerSpawn(id,dead) {
    if (is_user_alive(id)&&g_bICLoaded[id]) set_task(0.1,"task_apply_model",id);
}
public task_apply_model(const id) {
    if (is_user_alive(id)&&g_bICLoaded[id]) apply_all_models(id);
}

// ============================================================
//  皮肤持久化 (紧凑 JSON)
// ============================================================
stock save_redeemed_skins(const id,const szIdI[]) {
    new szId[MAX_AUTHID_LENGTH];
    if (szIdI[0]==0) get_player_identifier(id,szId,charsmax(szId));
    else copy(szId,charsmax(szId),szIdI);
    if (szId[0]==0) return;
    new szData[512], szKey[160];
    for (new t=0;t<3;t++) {
        new iLen=0;
        copy(szKey,charsmax(szKey),"hnsic_icskin_");
        add(szKey,charsmax(szKey),g_szTypeKey[t]);
        add(szKey,charsmax(szKey),"_");
        add(szKey,charsmax(szKey),szId);
        szData[iLen]='['; iLen++;
        for (new i=0;i<g_iRedeemedCount[id][t];i++) {
            if (i>0){ szData[iLen]=','; iLen++; }
            szData[iLen]='{'; iLen++;
            copy(szData[iLen],charsmax(szData)-iLen,"i"); iLen+=1;
            szData[iLen]=':'; iLen++;
            formatex(szData[iLen],charsmax(szData)-iLen,"%d",g_iRedeemed[id][t][i]); iLen=strlen(szData);
            szData[iLen]=','; iLen++;
            copy(szData[iLen],charsmax(szData)-iLen,"e"); iLen+=1;
            szData[iLen]=':'; iLen++;
            formatex(szData[iLen],charsmax(szData)-iLen,"%d",g_iRedeemedExp[id][t][i]); iLen=strlen(szData);
            szData[iLen]='}'; iLen++;
        }
        szData[iLen]=']'; iLen++;
        PDS_SetString(szKey,szData);
    }
}
stock load_redeemed_skins(const id,const szId[]) {
    new szData[512], szKey[160];
    for (new t=0;t<3;t++) {
        g_iRedeemedCount[id][t]=0;
        copy(szKey,charsmax(szKey),"hnsic_icskin_");
        add(szKey,charsmax(szKey),g_szTypeKey[t]);
        add(szKey,charsmax(szKey),"_");
        add(szKey,charsmax(szKey),szId);
        if (PDS_GetString(szKey,szData,charsmax(szData))) parse_skin_json(id,t,szData);
    }
}
stock parse_skin_json(id,iType,const szData[]) {
    new iNow=get_systime(), iPos=1, iLen=strlen(szData), idx, exp;
    while (iPos<iLen) {
        while (iPos<iLen && szData[iPos]!='{') iPos++;
        if (iPos>=iLen) break;
        iPos++;
        while (iPos<iLen && szData[iPos]!=':') iPos++;
        iPos++;
        idx=0;
        while (iPos<iLen && szData[iPos]>='0' && szData[iPos]<='9') { idx=idx*10+(szData[iPos]-'0'); iPos++; }
        while (iPos<iLen && szData[iPos]!=':') iPos++;
        iPos++;
        exp=0;
        while (iPos<iLen && szData[iPos]>='0' && szData[iPos]<='9') { exp=exp*10+(szData[iPos]-'0'); iPos++; }
        if (exp>iNow && g_iRedeemedCount[id][iType]<MAX_OWNED) {
            g_iRedeemed[id][iType][g_iRedeemedCount[id][iType]]=idx;
            g_iRedeemedExp[id][iType][g_iRedeemedCount[id][iType]]=exp;
            g_iRedeemedCount[id][iType]++;
        }
    }
}