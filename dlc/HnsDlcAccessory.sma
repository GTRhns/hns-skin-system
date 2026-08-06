/*
 * HnsDlcAccessory - DLC 饰品配件扩展插件
 * ============================================
 * 为 HnsSkin 皮肤系统提供饰品配件扩展功能：
 *   1. 头部饰品 (圣诞帽、头盔、角等)
 *   2. 背部饰品 (翅膀、背包、降落伞等)
 *   3. 面部饰品 (眼镜、口罩等)
 *
 * 配置: addons/amxmodx/configs/mixsystem/dlc_accessory.ini
 * 模型: 放在 cstrike/models/ 目录下
 *
 * 依赖: ReGameDLL
 * 兼容: 独立插件，与 HnsSkin.sma / HnsDlcSkin.sma 一起使用
 *
 * 命令:
 *   /acc, /accessory - 打开饰品菜单
 *   /acc_reload - 重新加载配置 (ADMIN_RCON 权限)
 */

#include <amxmodx>
#include <fakemeta>
#include <amxmisc>
#include <engine>
#include <reapi>
#include <nvault>

// ============================================================
//  插件信息
// ============================================================
#define PLUGIN_NAME "HNS DLC Accessory"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR "DLC Extension"

// ============================================================
//  常量定义
// ============================================================
#define ACC_NAME_LENGTH      64
#define MAX_MODEL_PATH      192
#define MAX_LINE_LENGTH     512
#define MAX_ACCESSORIES      64
#define MAX_SLOTS            3
#define MAX_SLOT_NAME        16
#define INVALID_HANDLE      -1

// 槽位索引
#define SLOT_HAT             0
#define SLOT_BACK            1
#define SLOT_FACE            2

// 槽位名称
new const g_szSlotNames[MAX_SLOTS][MAX_SLOT_NAME] = {"hat", "back", "face"};
new const g_szSlotDisplay[MAX_SLOTS][32] = {"头部饰品(帽子)", "背部饰品(翅膀)", "面部饰品"};

// ============================================================
//  全局变量 - 饰品配置
// ============================================================
// 每个槽位的饰品数据
new Array:g_aAccNames[MAX_SLOTS];        // 饰品显示名称
new Array:g_aAccModels[MAX_SLOTS];       // 饰品模型路径
new Array:g_aAccOffsets[MAX_SLOTS];      // 饰品偏移 "X Y Z"
new Array:g_aAccScales[MAX_SLOTS];       // 饰品缩放比例 (Float 存为 string)
new g_iAccCount[MAX_SLOTS] = {0, 0, 0};

// 玩家选择
new g_iSelectedAcc[MAX_PLAYERS + 1][MAX_SLOTS];  // -1 = 未选择/关闭
new g_iAccEntity[MAX_PLAYERS + 1][MAX_SLOTS];    // 创建的饰品实体 (-1 = 无)

// 玩家标识
new g_szPlayerAuth[MAX_PLAYERS + 1][64];
new g_bPlayerLoaded[MAX_PLAYERS + 1];

// nvault
new g_iVault = INVALID_HANDLE;

// ============================================================
//  plugin_precache - 预缓存所有饰品模型
// ============================================================
public plugin_precache() {
    // 初始化数组
    for (new i = 0; i < MAX_SLOTS; i++) {
        g_aAccNames[i] = ArrayCreate(ACC_NAME_LENGTH, 1);
        g_aAccModels[i] = ArrayCreate(MAX_MODEL_PATH, 1);
        g_aAccOffsets[i] = ArrayCreate(32, 1);
        g_aAccScales[i] = ArrayCreate(16, 1);
    }

    // 加载配置
    load_accessory_config();

    // 预缓存所有模型
    precache_all_accessory_models();

    // 初始化实体数组
    for (new i = 0; i <= MAX_PLAYERS; i++) {
        for (new j = 0; j < MAX_SLOTS; j++) {
            g_iAccEntity[i][j] = -1;
            g_iSelectedAcc[i][j] = -1;
        }
    }

    server_print("[DLC-Acc] plugin_precache: hat=%d, back=%d, face=%d",
        g_iAccCount[SLOT_HAT], g_iAccCount[SLOT_BACK], g_iAccCount[SLOT_FACE]);
}

// ============================================================
//  plugin_init - 注册命令和事件
// ============================================================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // 打开 nvault
    g_iVault = nvault_open("dlc_accessory_vault");

    // 注册命令
    register_clcmd("say /acc", "cmdAccessoryMenu");
    register_clcmd("say /accessory", "cmdAccessoryMenu");
    register_clcmd("say_team /acc", "cmdAccessoryMenu");
    register_clcmd("say_team /accessory", "cmdAccessoryMenu");
    register_concmd("acc_reload", "cmdAccReload", ADMIN_RCON, " - 重新加载饰品配置");

    // 注册菜单
    register_menucmd(register_menuid("DlcAccMain"), 1023, "handleAccMainMenu");
    register_menucmd(register_menuid("DlcAccSlot"), 1023, "handleAccSlotMenu");

    // 注册事件
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn_Post", true);

    // 定时更新饰品位置 (每 0.5 秒)
    set_task(0.5, "task_update_all_accessories", 0, _, _, "b");

    log_amx("[DLC-Acc] DLC 饰品配件扩展已加载 (hat=%d, back=%d, face=%d)",
        g_iAccCount[SLOT_HAT], g_iAccCount[SLOT_BACK], g_iAccCount[SLOT_FACE]);
}

// ============================================================
//  配置加载
// ============================================================
stock load_accessory_config() {
    // 清空旧数据
    for (new i = 0; i < MAX_SLOTS; i++) {
        ArrayClear(g_aAccNames[i]);
        ArrayClear(g_aAccModels[i]);
        ArrayClear(g_aAccOffsets[i]);
        ArrayClear(g_aAccScales[i]);
        g_iAccCount[i] = 0;
    }

    // 构建配置文件路径
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/dlc_accessory.ini", szPath);

    // 打开文件
    new f = fopen(szPath, "rt");
    if (!f) {
        log_amx("[DLC-Acc] 配置文件不存在: %s, 使用默认空配置", szPath);
        return;
    }

    new szLine[MAX_LINE_LENGTH];
    new iCurrentSlot = -1;
    new iLineNum = 0;

    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        iLineNum++;

        // 跳过注释和空行
        if (szLine[0] == ';' || szLine[0] == '/' && szLine[1] == '/' || szLine[0] == EOS) {
            continue;
        }

        // 检查段头
        if (szLine[0] == '[') {
            new len = strlen(szLine);
            if (szLine[len - 1] == ']') {
                szLine[--len] = EOS;
            }
            if (szLine[0] == '[') {
                copy(szLine, charsmax(szLine), szLine[1]);
            }

            iCurrentSlot = -1;
            for (new i = 0; i < MAX_SLOTS; i++) {
                if (equali(szLine, g_szSlotNames[i])) {
                    iCurrentSlot = i;
                    break;
                }
            }
            continue;
        }

        // 解析饰品行
        if (iCurrentSlot >= 0) {
            parse_accessory_line(szLine, iCurrentSlot, iLineNum);
        }
    }

    fclose(f);

    log_amx("[DLC-Acc] 配置加载完成: hat=%d, back=%d, face=%d",
        g_iAccCount[SLOT_HAT], g_iAccCount[SLOT_BACK], g_iAccCount[SLOT_FACE]);
}

// 解析饰品行
stock parse_accessory_line(const szLine[], iSlot, iLineNum) {
    // 格式: "名称" "模型路径" "X Y Z" "缩放"
    new szName[ACC_NAME_LENGTH];
    new szModel[MAX_MODEL_PATH];
    new szOffset[32];
    new szScale[16];

    new iLen = strlen(szLine);
    new iQuoteCount = 0;
    new iStart = -1;
    new iSegment = 0;

    for (new i = 0; i <= iLen; i++) {
        if (szLine[i] == '"') {
            if (iStart == -1) {
                iStart = i + 1;
            } else {
                new iSegLen = i - iStart;
                if (iSegLen > 0 && iSegment < 4) {
                    new iCopyLen = iSegLen + 1;
                    if (iSegment == 0) {
                        if (iCopyLen > ACC_NAME_LENGTH) iCopyLen = ACC_NAME_LENGTH;
                        copy(szName, iCopyLen, szLine[iStart]);
                        if (iSegLen < ACC_NAME_LENGTH - 1) szName[iSegLen] = EOS;
                        else szName[ACC_NAME_LENGTH - 1] = EOS;
                    } else if (iSegment == 1) {
                        if (iCopyLen > MAX_MODEL_PATH) iCopyLen = MAX_MODEL_PATH;
                        copy(szModel, iCopyLen, szLine[iStart]);
                        if (iSegLen < MAX_MODEL_PATH - 1) szModel[iSegLen] = EOS;
                        else szModel[MAX_MODEL_PATH - 1] = EOS;
                    } else if (iSegment == 2) {
                        if (iCopyLen > 31) iCopyLen = 31;
                        copy(szOffset, iCopyLen, szLine[iStart]);
                        if (iSegLen < 31) szOffset[iSegLen] = EOS;
                        else szOffset[31] = EOS;
                    } else if (iSegment == 3) {
                        if (iCopyLen > 15) iCopyLen = 15;
                        copy(szScale, iCopyLen, szLine[iStart]);
                        if (iSegLen < 15) szScale[iSegLen] = EOS;
                        else szScale[15] = EOS;
                    }
                    iSegment++;
                }
                iQuoteCount++;
                iStart = -1;
            }
        }
    }

    // 验证数据: 名称和模型是必须的
    if (szName[0] == EOS || szModel[0] == EOS) {
        log_amx("[DLC-Acc] Line %d: bad format, skipped", iLineNum);
        return;
    }

    // 默认偏移和缩放
    if (szOffset[0] == EOS) {
        copy(szOffset, charsmax(szOffset), "0 0 30");
    }
    if (szScale[0] == EOS) {
        copy(szScale, charsmax(szScale), "1.0");
    }

    // 添加到对应槽位
    ArrayPushString(g_aAccNames[iSlot], szName);
    ArrayPushString(g_aAccModels[iSlot], szModel);
    ArrayPushString(g_aAccOffsets[iSlot], szOffset);
    ArrayPushString(g_aAccScales[iSlot], szScale);
    g_iAccCount[iSlot]++;
}

// ============================================================
//  模型预缓存
// ============================================================
stock precache_all_accessory_models() {
    new szModel[MAX_MODEL_PATH];
    new i, iSize;

    for (new slot = 0; slot < MAX_SLOTS; slot++) {
        iSize = ArraySize(g_aAccModels[slot]);
        for (i = 0; i < iSize; i++) {
            ArrayGetString(g_aAccModels[slot], i, szModel, charsmax(szModel));
            if (szModel[0] != EOS) {
                precache_model(szModel);
            }
        }
    }
}

// ============================================================
//  玩家生成 - 创建饰品实体
// ============================================================
public OnPlayerSpawn_Post(const id) {
    // 延迟一小段时间等模型加载完成
    set_task(0.3, "task_create_player_accessories", id);
}

public task_create_player_accessories(const id) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return;
    }

    // 销毁旧饰品
    destroy_player_accessories(id);

    // 为每个槽位创建饰品
    for (new slot = 0; slot < MAX_SLOTS; slot++) {
        if (g_iSelectedAcc[id][slot] < 0) {
            continue; // 该槽位未选择/关闭
        }

        new iIdx = g_iSelectedAcc[id][slot];
        if (iIdx >= g_iAccCount[slot]) {
            continue;
        }

        // 创建饰品实体
        create_accessory_entity(id, slot, iIdx);
    }
}

// 创建饰品实体
stock create_accessory_entity(const id, const iSlot, const iIdx) {
    // 获取模型路径
    new szModel[MAX_MODEL_PATH];
    ArrayGetString(g_aAccModels[iSlot], iIdx, szModel, charsmax(szModel));

    if (szModel[0] == EOS) {
        return;
    }

    // 创建 info_target 实体
    new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!iEnt) {
        return;
    }

    // 设置实体名称（用于调试）
    set_pev(iEnt, pev_classname, "dlc_accessory");

    // 设置模型
    engfunc(EngFunc_SetModel, iEnt, szModel);

    // 设置渲染 - 全亮显示
    set_pev(iEnt, pev_renderfx, kRenderFxNone);
    set_pev(iEnt, pev_rendermode, kRenderNormal);
    set_pev(iEnt, pev_renderamt, 255.0);

    // 设置缩放
    new szScale[16];
    ArrayGetString(g_aAccScales[iSlot], iIdx, szScale, charsmax(szScale));
    new Float:fScale = str_to_float(szScale);
    if (fScale <= 0.0) fScale = 1.0;
    set_pev(iEnt, pev_scale, fScale);

    // 设置实体优先级，跟随玩家
    set_pev(iEnt, pev_aiment, id);
    set_pev(iEnt, pev_owner, id);
    set_pev(iEnt, pev_movetype, MOVETYPE_FOLLOW);
    set_pev(iEnt, pev_solid, SOLID_NOT);

    // 设置初始位置为玩家位置
    new Float:vecOrigin[3];
    entity_get_vector(id, EV_VEC_origin, vecOrigin);
    entity_set_origin(iEnt, vecOrigin);

    // 保存实体索引
    g_iAccEntity[id][iSlot] = iEnt;

    // 设置自定义数据：保存槽位和索引，用于位置更新
    set_pev(iEnt, pev_iuser1, id);
    set_pev(iEnt, pev_iuser2, iSlot);
    set_pev(iEnt, pev_iuser3, iIdx);
}

// 销毁玩家所有饰品
stock destroy_player_accessories(const id) {
    for (new slot = 0; slot < MAX_SLOTS; slot++) {
        if (g_iAccEntity[id][slot] > 0 && is_valid_ent(g_iAccEntity[id][slot])) {
            engfunc(EngFunc_RemoveEntity, g_iAccEntity[id][slot]);
        }
        g_iAccEntity[id][slot] = -1;
    }
}

// ============================================================
//  定时更新饰品位置 (每 0.5 秒)
// ============================================================
public task_update_all_accessories() {
    static players[32], pnum;
    get_players(players, pnum, "a");

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        if (!is_user_alive(id)) continue;

        for (new slot = 0; slot < MAX_SLOTS; slot++) {
            new iEnt = g_iAccEntity[id][slot];
            if (iEnt <= 0 || !is_valid_ent(iEnt)) continue;

            new iIdx = g_iSelectedAcc[id][slot];
            if (iIdx < 0 || iIdx >= g_iAccCount[slot]) continue;

            // 获取玩家位置和视角
            new Float:vecOrigin[3], Float:vecAngles[3];
            entity_get_vector(id, EV_VEC_origin, vecOrigin);
            entity_get_vector(id, EV_VEC_v_angle, vecAngles);

            // 获取偏移
            new szOffset[32];
            ArrayGetString(g_aAccOffsets[slot], iIdx, szOffset, charsmax(szOffset));

            new Float:flOffset[3];
            parse_offset(szOffset, flOffset);

            // 计算饰品位置
            new Float:vecAcc[3];
            vecAcc[0] = vecOrigin[0];
            vecAcc[1] = vecOrigin[1];
            vecAcc[2] = vecOrigin[2] + flOffset[2];

            // 背部饰品需要跟随玩家朝向
            if (slot == SLOT_BACK) {
                // 玩家背后偏移
                new Float:vecForward[3], Float:vecRight[3];
                angle_vector(vecAngles, ANGLEVECTOR_FORWARD, vecForward);
                angle_vector(vecAngles, ANGLEVECTOR_RIGHT, vecRight);

                vecAcc[0] = vecOrigin[0] - vecForward[0] * flOffset[0] + vecRight[0] * flOffset[1];
                vecAcc[1] = vecOrigin[1] - vecForward[1] * flOffset[0] + vecRight[1] * flOffset[1];
                vecAcc[2] = vecOrigin[2] + flOffset[2];
            }

            // 设置饰品位置
            entity_set_origin(iEnt, vecAcc);

            // 设置饰品朝向与玩家一致
            set_pev(iEnt, pev_angles, vecAngles);
        }
    }
}

// 解析偏移字符串 "X Y Z" -> Float数组
stock parse_offset(const szOffset[], Float:flOffset[3]) {
    new szParts[3][16];
    new iPart = 0, iPos = 0, iLen = strlen(szOffset);

    for (new i = 0; i <= iLen && iPart < 3; i++) {
        if (szOffset[i] == ' ' || szOffset[i] == EOS) {
            if (iPos > 0) {
                szParts[iPart][iPos] = EOS;
                iPart++;
                iPos = 0;
            }
        } else {
            szParts[iPart][iPos++] = szOffset[i];
        }
    }

    flOffset[0] = (iPart > 0) ? str_to_float(szParts[0]) : 0.0;
    flOffset[1] = (iPart > 1) ? str_to_float(szParts[1]) : 0.0;
    flOffset[2] = (iPart > 2) ? str_to_float(szParts[2]) : 0.0;
}

// ============================================================
//  饰品菜单
// ============================================================
public cmdAccessoryMenu(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    new szMenu[512];
    new iLen = formatex(szMenu, charsmax(szMenu), "\y饰品系统菜单^n\y───────────^n^n");

    for (new i = 0; i < MAX_SLOTS; i++) {
        new szStatus[32];
        if (g_iSelectedAcc[id][i] < 0) {
            copy(szStatus, charsmax(szStatus), "[关闭]");
        } else {
            new szName[ACC_NAME_LENGTH];
            ArrayGetString(g_aAccNames[i], g_iSelectedAcc[id][i], szName, charsmax(szName));
            formatex(szStatus, charsmax(szStatus), "\r[已选: %s]", szName);
        }
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s %s^n", i + 1, g_szSlotDisplay[i], szStatus);
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\r0. \w退出^n");

    show_menu(id, (1<<0)|(1<<1)|(1<<2)|(1<<9), szMenu, -1, "DlcAccMain");
    return PLUGIN_HANDLED;
}

public handleAccMainMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    if (key >= 0 && key < MAX_SLOTS) {
        show_slot_select_menu(id, key);
    }

    return PLUGIN_HANDLED;
}

// 显示某个槽位的饰品选择菜单
// 临时变量 (存储槽位)
new g_iAccSlotSelect[MAX_PLAYERS + 1];

stock show_slot_select_menu(const id, const iSlot) {
    if (g_iAccCount[iSlot] <= 0) {
        client_print_color(id, 0, "[DLC-Acc] ^3该槽位暂无可用饰品");
        return;
    }

    new szMenu[512];
    new iLen = formatex(szMenu, charsmax(szMenu), "\y%s选择^n\y───────────^n^n", g_szSlotDisplay[iSlot]);

    new iSize = g_iAccCount[iSlot];
    for (new i = 0; i < iSize && i < 9; i++) {
        new szName[ACC_NAME_LENGTH];
        ArrayGetString(g_aAccNames[iSlot], i, szName, charsmax(szName));

        // 标记已选中的
        if (i == g_iSelectedAcc[id][iSlot]) {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s \r[已选]^n", i + 1, szName);
        } else {
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \w%s^n", i + 1, szName);
        }
    }

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\r9. \w关闭此饰品^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0. \w返回上级^n");

    // 保存当前槽位
    g_iAccSlotSelect[id] = iSlot;

    show_menu(id, (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9), szMenu, -1, "DlcAccSlot");
}

public handleAccSlotMenu(const id, const key) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new iSlot = g_iAccSlotSelect[id];

    if (key == 9) {
        // 关闭此饰品
        g_iSelectedAcc[id][iSlot] = -1;
        destroy_player_accessories(id);
        client_print_color(id, 0, "[DLC-Acc] ^3%s 已关闭", g_szSlotDisplay[iSlot]);
        save_player_accessory(id, iSlot);
        show_slot_select_menu(id, iSlot);
        return PLUGIN_HANDLED;
    }

    if (key == 0) {
        // 返回上级
        cmdAccessoryMenu(id);
        return PLUGIN_HANDLED;
    }

    if (key >= 1 && key <= 8) {
        new iIdx = key - 1;
        if (iIdx < g_iAccCount[iSlot]) {
            // 选择饰品
            g_iSelectedAcc[id][iSlot] = iIdx;

            new szName[ACC_NAME_LENGTH];
            ArrayGetString(g_aAccNames[iSlot], iIdx, szName, charsmax(szName));
            client_print_color(id, 0, "[DLC-Acc] ^4已选择 ^3%s", szName);

            // 保存选择
            save_player_accessory(id, iSlot);

            // 重新创建饰品
            if (is_user_alive(id)) {
                // 先销毁旧的
                if (g_iAccEntity[id][iSlot] > 0 && is_valid_ent(g_iAccEntity[id][iSlot])) {
                    engfunc(EngFunc_RemoveEntity, g_iAccEntity[id][iSlot]);
                }
                g_iAccEntity[id][iSlot] = -1;
                // 创建新的
                create_accessory_entity(id, iSlot, iIdx);
            }

            show_slot_select_menu(id, iSlot);
        }
    }

    return PLUGIN_HANDLED;
}

// ============================================================
//  nvault 存档
// ============================================================
stock save_player_accessory(const id, const iSlot) {
    if (g_iVault == INVALID_HANDLE) return;
    if (g_szPlayerAuth[id][0] == EOS) return;

    new szKey[64];
    new szData[16];

    // 每个槽位单独保存: authid_slot
    formatex(szKey, charsmax(szKey), "%s_acc_%d", g_szPlayerAuth[id], iSlot);
    formatex(szData, charsmax(szData), "%d", g_iSelectedAcc[id][iSlot]);
    nvault_set(g_iVault, szKey, szData);
}

stock load_player_accessory(const id, const iSlot) {
    if (g_iVault == INVALID_HANDLE) return;
    if (g_szPlayerAuth[id][0] == EOS) {
        g_iSelectedAcc[id][iSlot] = -1;
        return;
    }

    new szKey[64];
    formatex(szKey, charsmax(szKey), "%s_acc_%d", g_szPlayerAuth[id], iSlot);

    new szData[16];
    nvault_get(g_iVault, szKey, szData, charsmax(szData));

    if (szData[0] != EOS) {
        g_iSelectedAcc[id][iSlot] = str_to_num(szData);
        // 检查索引是否有效
        if (g_iSelectedAcc[id][iSlot] >= g_iAccCount[iSlot]) {
            g_iSelectedAcc[id][iSlot] = -1;
        }
    } else {
        g_iSelectedAcc[id][iSlot] = -1;
    }
}

// ============================================================
//  玩家连接/断开
// ============================================================
public client_putinserver(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }

    // 重置
    for (new i = 0; i < MAX_SLOTS; i++) {
        g_iSelectedAcc[id][i] = -1;
        g_iAccEntity[id][i] = -1;
    }

    // 获取玩家标识
    get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]));
    g_bPlayerLoaded[id] = false;

    // 延迟加载存档
    set_task(0.5, "task_load_player_accessories", id);
}

public task_load_player_accessories(const id) {
    if (!is_user_connected(id)) return;
    if (g_bPlayerLoaded[id]) return;

    // 重新获取 authid
    get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]));

    // 加载所有槽位的存档
    for (new i = 0; i < MAX_SLOTS; i++) {
        load_player_accessory(id, i);
    }

    g_bPlayerLoaded[id] = true;
}

public client_disconnected(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }

    // 保存所有槽位
    for (new i = 0; i < MAX_SLOTS; i++) {
        save_player_accessory(id, i);
    }

    // 销毁饰品
    destroy_player_accessories(id);

    g_bPlayerLoaded[id] = false;
}

// ============================================================
//  命令 - 重新加载配置
// ============================================================
public cmdAccReload(const id, const level, const cid) {
    if (!cmd_access(id, level, cid, 1)) {
        return PLUGIN_HANDLED;
    }

    // 重新加载配置
    load_accessory_config();

    // 重新预缓存
    precache_all_accessory_models();

    // 通知
    new szName[32];
    if (id == 0) {
        copy(szName, charsmax(szName), "SERVER");
    } else {
        get_user_name(id, szName, charsmax(szName));
    }

    log_amx("[DLC-Acc] %s 重新加载了饰品配置 (hat=%d, back=%d, face=%d)",
        szName, g_iAccCount[SLOT_HAT], g_iAccCount[SLOT_BACK], g_iAccCount[SLOT_FACE]);

    if (id > 0) {
        console_print(id, "[DLC-Acc] 配置已重新加载! hat=%d, back=%d, face=%d",
            g_iAccCount[SLOT_HAT], g_iAccCount[SLOT_BACK], g_iAccCount[SLOT_FACE]);
    }

    return PLUGIN_HANDLED;
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

stock cleanup_arrays() {
    for (new i = 0; i < MAX_SLOTS; i++) {
        ArrayDestroy(g_aAccNames[i]);
        ArrayDestroy(g_aAccModels[i]);
        ArrayDestroy(g_aAccOffsets[i]);
        ArrayDestroy(g_aAccScales[i]);
    }
}