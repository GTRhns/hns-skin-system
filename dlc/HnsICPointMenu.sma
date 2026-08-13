/*
 * ============================================================
 *  HNS IC Point System - 完全独立版 v2.0.0
 * ============================================================
 *  功能:
 *   1. 拦截 N 键 (nightvision) 打开 IC 独立菜单 (优先级高于 menu new)
 *   2. 管理员直接给予 IC 点 (/givetic /giveic /addic)
 *   3. 为外部系统提供 native 接口 (ic_add_points / ic_get_points),
 *      比赛系统可自行对接, 在自己认为合适的时机发放 IC 点
 *   4. IC 积分与已兑换皮肤持久化 (nvault, 零额外依赖)
 *   5. 积分兑换皮肤: 人物500分 / 刀300分 (CVAR 可配置)
 *   6. 兑换皮肤直接应用模型 (rg_set_user_model), 一个月后自动清除
 *
 *  依赖: 仅 amxmodx / amxmisc / string / reapi / nvault (全部内置)
 *  注意: 不依赖任何比赛系统; 比赛系统通过 ic_add_points native 对接
 * ============================================================
 */
#include <amxmodx>
#include <amxmisc>
#include <string>
#include <reapi>
#include <nvault>

#define m_szViewModel (m_szModel + 128)
#define MAX_MODEL_NAME    128
#define MAX_SKIN_NAME     64
#define MAX_AUTHID_LENGTH 64
#define MAX_OWNED         8
#define MONTH_SECONDS     2592000
#define VERSION           "2.0.0"

// 菜单 ID
#define MENU_IC_MAIN      10101
#define MENU_IC_SKIN      10102
#define MENU_IC_SKINLIST  10103

// 皮肤类型: 0=T 1=CT 2=刀
enum _:SKIN_TYPE { SKIN_T=0, SKIN_CT, SKIN_KNIFE };

new Array:g_aModels[3];
new Array:g_aNames[3];

new g_iICPoints[MAX_PLAYERS+1];
new bool:g_bICLoaded[MAX_PLAYERS+1];
new g_iSkinType[MAX_PLAYERS+1];
new g_iSkinPage[MAX_PLAYERS+1];
new g_szPlayerAuth[MAX_PLAYERS+1][MAX_AUTHID_LENGTH];

// 已兑换皮肤 (按类型索引)
new g_iRedeemed[MAX_PLAYERS+1][3][MAX_OWNED];
new g_iRedeemedExp[MAX_PLAYERS+1][3][MAX_OWNED];
new g_iRedeemedCount[MAX_PLAYERS+1][3];

new pcvar_person_pts, pcvar_knife_pts;

// nvault 句柄
new g_vault;

// PDS 兼容键后缀
new const g_szTypeKey[3][2] = {"t","c","k"};

public plugin_init() {
    register_plugin("HNS IC Point System","2.0.0","HNS IC System");
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
    pcvar_person_pts= register_cvar("ic_skin_person", "500", FCVAR_SERVER);
    pcvar_knife_pts = register_cvar("ic_skin_knife",  "300", FCVAR_SERVER);
    g_vault = nvault_open("hnsic_points");
    load_models();
    register_menucmd(register_menuid("HnsICMain"),(1<<0)|(1<<9),"icMainHandler");
    register_menucmd(register_menuid("HnsICSkin"),(1<<0)|(1<<1)|(1<<2)|(1<<9),"icSkinHandler");
    register_menucmd(register_menuid("HnsICSkinList"),511|(1<<8)|(1<<9),"icSkinListHandler");
    set_task(60.0,"task_check_expiry",0,.flags="b");
}

// ============================================================
//  Native 接口: 供外部系统 (如比赛系统) 对接发放/查询 IC 点
//  用法(在外部插件中):
//    #include <ic_points>
//    ic_add_points(id, 10);   // 给玩家 +10 IC 点
//    new pts = ic_get_points(id); // 查询玩家当前 IC 点
// ============================================================
public plugin_natives() {
    register_library("HnsICPointSystem");
    register_native("ic_add_points","native_ic_add_points");
    register_native("ic_get_points","native_ic_get_points");
}
public native_ic_add_points(plugin_id,num_params) {
    new id = get_param(1);
    new iAmount = get_param(2);
    if (!is_user_connected(id) || iAmount<=0) return 0;
    add_ic_points(id,iAmount);
    return 1;
}
public native_ic_get_points(plugin_id,num_params) {
    new id = get_param(1);
    if (!is_user_connected(id)) return 0;
    if (!g_bICLoaded[id]) load_player_ic(id);
    return g_iICPoints[id];
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
    if (key==0) showRedeemMenu(id);
    return PLUGIN_HANDLED;
}
stock showMainMenu(id) {
    new szMenu[512], iLen;
    iLen=formatex(szMenu,charsmax(szMenu),"\r* * * IC 点 系 统 * * *^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\y  ★ 当前积分: \w%d^n",g_iICPoints[id]);
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r1. \w积分兑换皮肤 \y▶^n^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\w----------------------------^n");
    iLen+=formatex(szMenu[iLen],charsmax(szMenu)-iLen,"\r0. \w关闭 \y✕");
    show_menu(id,(1<<0)|(1<<9),szMenu,-1,"HnsICMain");
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
public plugin_end() {
    if (g_vault) nvault_close(g_vault);
}
public rgPlayerSpawn(id,dead) {
    if (is_user_alive(id)&&g_bICLoaded[id]) set_task(0.1,"task_apply_model",id);
}
public task_apply_model(const id) {
    if (is_user_alive(id)&&g_bICLoaded[id]) apply_all_models(id);
}

// ============================================================
//  IC 积分持久化 (nvault)
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
    g_iICPoints[id] = nvault_get(g_vault,szKey);
    load_redeemed_skins(id,szId);
    g_bICLoaded[id]=true;
}
stock save_player_ic(const id) {
    new szId[MAX_AUTHID_LENGTH], szKey[160];
    get_player_identifier(id,szId,charsmax(szId));
    if (szId[0]==0) return;
    copy(szKey,charsmax(szKey),"hnsic_icpts_");
    add(szKey,charsmax(szKey),szId);
    new szPts[16];
    formatex(szPts,charsmax(szPts),"%d",g_iICPoints[id]);
    nvault_set(g_vault,szKey,szPts);
    save_redeemed_skins(id,szId);
}
stock add_ic_points(id,iAmount) {
    if (!is_user_connected(id)||iAmount<=0) return;
    if (!g_bICLoaded[id]) load_player_ic(id);
    g_iICPoints[id]+=iAmount;
    save_player_ic(id);
    client_print_color(id,print_team_default,"^4[IC点] ^1获得\w+%d^1分 (当前\w%d^1)",iAmount,g_iICPoints[id]);
}

// ============================================================
//  皮肤持久化 (紧凑 JSON, nvault)
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
        nvault_set(g_vault,szKey,szData);
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
        if (nvault_get(g_vault,szKey,szData,charsmax(szData)) && szData[0]) parse_skin_json(id,t,szData);
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