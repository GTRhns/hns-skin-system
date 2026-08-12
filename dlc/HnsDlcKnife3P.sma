/*
 * HnsDlcKnife3P - DLC 第三人称刀皮映射扩展插件
 * ============================================
 * 为 HnsSkin 刀皮系统提供第三人称模型自定义映射：
 *   每个第一人称刀皮 (v_* 模型) 可单独指定一个第三人称显示模型 (p_* 模型)。
 *   HnsSkin 默认将 v_knife 自动转成 p_knife，本 DLC 允许服主为每个刀皮
 *   手动指定第三人称模型，覆盖默认自动转换。
 *
 * 配置: addons/amxmodx/configs/mixsystem/dlc_knife3p.ini
 * 模型: 放在 cstrike/models/ 目录下
 *
 * 依赖:
 *   - ReGameDLL (pev_viewmodel2 / pev_weaponmodel2)
 *   - addon_weapon_player_model.amxx (提供 api_wpn_player_model_set native)
 *   - HnsSkin.amxx (提供第一人称刀皮，本 DLC 读取其 pev_viewmodel2)
 *
 * 命令:
 *   /knife3p        - 查看当前玩家自己刀皮的第三人称映射 (所有人)
 *   /knife3p_cfg    - 查看全局刀皮映射配置 (所有人)
 *   /knife3p_reload - 重新加载配置 (ADMIN_RCON)
 */

#include <amxmodx>
#include <fakemeta>
#include <amxmisc>
#include <hamsandwich>
#include <reapi>
#include <engine>
#include <api_weapon_player_model>

// ============================================================
//  插件信息
// ============================================================
#define PLUGIN_NAME "HNS DLC Knife3P"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR "DLC Extension"

// ============================================================
//  常量定义
// ============================================================
#define MAX_MODEL_PATH      192
#define MAX_SKIN_NAME       64
#define MAX_LINE_LENGTH     512
#define MAX_ENTRIES         64

// ============================================================
//  全局变量 - 第三人称刀皮映射配置
// ============================================================
new Array:g_a3PModelNames;      // 刀皮显示名称 (与 player_models.ini [Knife] 一致)
new Array:g_a3PModelPaths;      // 刀皮第一人称模型路径 (v_*)
new Array:g_a3PThirdPaths;      // 刀皮第三人称模型路径 (p_*) 服主指定
new g_i3PCount = 0;

// 玩家当前刀皮第一人称模型缓存
new g_szPlayerKnifeModel[MAX_PLAYERS + 1][MAX_MODEL_PATH];

// ============================================================
//  plugin_precache - 预缓存所有第三人称刀皮模型
// ============================================================
public plugin_precache() {
    // 初始化数组
    g_a3PModelNames = ArrayCreate(MAX_SKIN_NAME, 1);
    g_a3PModelPaths = ArrayCreate(MAX_MODEL_PATH, 1);
    g_a3PThirdPaths = ArrayCreate(MAX_MODEL_PATH, 1);

    // 加载配置
    load_knife3p_config();

    // 预缓存所有第三人称模型
    precache_all_3p_models();

    server_print("[DLC-Knife3P] plugin_precache: 第三人称刀皮映射=%d", g_i3PCount);
}

// ============================================================
//  plugin_init - 注册命令和事件
// ============================================================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // 注册命令
    register_clcmd("say /knife3p", "cmdKnife3P");
    register_clcmd("say_team /knife3p", "cmdKnife3P");
    register_clcmd("say /knife3p_cfg", "cmdKnife3PCfg");
    register_clcmd("say_team /knife3p_cfg", "cmdKnife3PCfg");
    register_clcmd("say /knife3p_reload", "cmdKnife3PReloadChat");
    register_concmd("knife3p_reload", "cmdKnife3PReload", ADMIN_RCON, " - 重新加载第三人称刀皮映射配置");

    // 切刀时应用第三人称刀皮 (Ham_Item_Deploy post)
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "Knife_Deploy_Post", true);
    // CurWeapon 消息钩子 (切刀时)
    register_message(get_user_msgid("CurWeapon"), "FM_CurWeapon");

    log_amx("[DLC-Knife3P] DLC 第三人称刀皮映射已加载 (映射=%d)", g_i3PCount);
}

// ============================================================
//  配置加载
// ============================================================
stock load_knife3p_config() {
    // 清空旧数据
    ArrayClear(g_a3PModelNames);
    ArrayClear(g_a3PModelPaths);
    ArrayClear(g_a3PThirdPaths);
    g_i3PCount = 0;

    // 构建配置文件路径
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/dlc_knife3p.ini", szPath);

    // 打开文件
    new f = fopen(szPath, "rt");
    if (!f) {
        log_amx("[DLC-Knife3P] 配置文件不存在: %s, 使用默认空配置", szPath);
        return;
    }

    new szLine[MAX_LINE_LENGTH];
    new iLineNum = 0;

    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        iLineNum++;

        // 跳过注释和空行
        if (szLine[0] == ';' || szLine[0] == '/' && szLine[1] == '/' || szLine[0] == EOS) {
            continue;
        }

        // 跳过段头 (如 [Knife3P])
        if (szLine[0] == '[') {
            continue;
        }

        // 解析映射行
        parse_knife3p_line(szLine, iLineNum);
    }

    fclose(f);

    log_amx("[DLC-Knife3P] 配置加载完成: 映射=%d 条", g_i3PCount);
}

// 解析第三人称刀皮映射行
// 格式: "刀皮名称" "第一人称模型路径" "第三人称模型路径"
stock parse_knife3p_line(const szLine[], iLineNum) {
    new szName[MAX_SKIN_NAME];
    new szView[MAX_MODEL_PATH];
    new szThird[MAX_MODEL_PATH];

    new iLen = strlen(szLine);
    new iQuoteCount = 0;
    new iStart = -1;
    new iSegment = 0;

    // 逐字符解析引号对
    for (new i = 0; i <= iLen; i++) {
        if (szLine[i] == '"') {
            if (iStart == -1) {
                iStart = i + 1;  // 引号后的内容开始
            } else {
                new iSegLen = i - iStart;
                if (iSegLen > 0 && iSegment < 3) {
                    new iCopyLen;
                    switch (iSegment) {
                        case 0: {
                            iCopyLen = iSegLen + 1;
                            if (iCopyLen > MAX_SKIN_NAME) iCopyLen = MAX_SKIN_NAME;
                            copy(szName, iCopyLen, szLine[iStart]);
                            if (iSegLen < MAX_SKIN_NAME - 1) szName[iSegLen] = EOS;
                            else szName[MAX_SKIN_NAME - 1] = EOS;
                        }
                        case 1: {
                            iCopyLen = iSegLen + 1;
                            if (iCopyLen > MAX_MODEL_PATH) iCopyLen = MAX_MODEL_PATH;
                            copy(szView, iCopyLen, szLine[iStart]);
                            if (iSegLen < MAX_MODEL_PATH - 1) szView[iSegLen] = EOS;
                            else szView[MAX_MODEL_PATH - 1] = EOS;
                        }
                        case 2: {
                            iCopyLen = iSegLen + 1;
                            if (iCopyLen > MAX_MODEL_PATH) iCopyLen = MAX_MODEL_PATH;
                            copy(szThird, iCopyLen, szLine[iStart]);
                            if (iSegLen < MAX_MODEL_PATH - 1) szThird[iSegLen] = EOS;
                            else szThird[MAX_MODEL_PATH - 1] = EOS;
                        }
                    }
                    iSegment++;
                }
                iQuoteCount++;
                iStart = -1;
            }
        }
    }

    // 验证数据: 名称和第一人称模型是必须的
    if (szName[0] == EOS || szView[0] == EOS) {
        log_amx("[DLC-Knife3P] Line %d: bad format (expected 名称 第一人称模型 第三人称模型), skipped", iLineNum);
        return;
    }

    // 第三人称模型缺省时自动转: v_knife → p_knife
    if (szThird[0] == EOS) {
        copy(szThird, charsmax(szThird), szView);
        new iPos = containi(szThird, "v_knife");
        if (iPos >= 0) {
            szThird[iPos] = 'p';
        }
    }

    // 添加到数组
    ArrayPushString(g_a3PModelNames, szName);
    ArrayPushString(g_a3PModelPaths, szView);
    ArrayPushString(g_a3PThirdPaths, szThird);
    g_i3PCount++;
}

// ============================================================
//  模型预缓存
// ============================================================
stock precache_all_3p_models() {
    new szModel[MAX_MODEL_PATH];
    new i, iSize;

    iSize = ArraySize(g_a3PThirdPaths);
    for (i = 0; i < iSize; i++) {
        ArrayGetString(g_a3PThirdPaths, i, szModel, charsmax(szModel));
        if (szModel[0] != EOS) {
            precache_model(szModel);
        }
    }
}

// ============================================================
//  切刀应用第三人称刀皮
// ============================================================
public Knife_Deploy_Post(iItem) {
    new id = get_member(iItem, m_pPlayer);
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }

    // 延迟应用，确保 HnsSkin 已设置第一人称模型 (pev_viewmodel2)
    set_task(0.05, "task_apply_knife3p", id);
}

public FM_CurWeapon(id) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return FMRES_IGNORED;
    }

    // 仅在切换到刀时应用
    new iWeapon = get_msg_arg_int(1);
    if (iWeapon == CSW_KNIFE) {
        set_task(0.05, "task_apply_knife3p", id);
    }

    return FMRES_IGNORED;
}

public task_apply_knife3p(const id) {
    if (!is_user_connected(id) || !is_user_alive(id)) {
        return;
    }
    if (get_user_weapon(id) != CSW_KNIFE) {
        return;
    }

    // 读取玩家当前第一人称刀皮模型 (pev_viewmodel2, 由 HnsSkin 设置)
    new szView[MAX_MODEL_PATH];
    entity_get_string(id, pev_viewmodel2, szView, charsmax(szView));

    if (szView[0] == EOS) {
        return;
    }

    // 在映射配置里查找该第一人称模型对应的第三人称模型
    new szThird[MAX_MODEL_PATH];
    if (!find_knife3p_third(szView, szThird, charsmax(szThird))) {
        return;
    }

    // 安全检查: 模型文件必须真实存在，否则回退默认刀第三人称
    if (!file_exists(szThird)) {
        log_amx("[DLC-Knife3P] 第三人称模型不存在, 已跳过: %s", szThird);
        return;
    }

    // 缓存玩家刀皮
    copy(g_szPlayerKnifeModel[id], charsmax(g_szPlayerKnifeModel[]), szView);

    // 用 WPM API 渲染第三人称刀皮 (独立 follow 实体, 不受玩家模型影响)
    new Float:flAttach[2] = { 0.0, 0.0 };
    api_wpn_player_model_set(id, szThird, 0, 0, 0, flAttach);

    // 同时设置 pev_weaponmodel2 (传统方式, 兼容不支持 WPM 的环境)
    set_pev(id, pev_weaponmodel2, szThird);
}

// 查找第一人称模型对应的第三人称模型
stock bool:find_knife3p_third(const szView[], szThird[], iLen) {
    new iSize = ArraySize(g_a3PModelPaths);
    for (new i = 0; i < iSize; i++) {
        new szEntry[MAX_MODEL_PATH];
        ArrayGetString(g_a3PModelPaths, i, szEntry, charsmax(szEntry));
        if (equal(szEntry, szView)) {
            ArrayGetString(g_a3PThirdPaths, i, szThird, iLen);
            return szThird[0] != EOS;
        }
    }

    // 未配置时, 尝试自动 v_knife → p_knife
    copy(szThird, iLen, szView);
    new iPos = containi(szThird, "v_knife");
    if (iPos >= 0) {
        szThird[iPos] = 'p';
        return true;
    }

    return false;
}

// ============================================================
//  命令 - 查看玩家自己的刀皮映射
// ============================================================
public cmdKnife3P(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    // 读取玩家当前第一人称刀皮
    new szView[MAX_MODEL_PATH];
    entity_get_string(id, pev_viewmodel2, szView, charsmax(szView));

    if (szView[0] == EOS) {
        client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 你当前未持有刀 (或刀皮未应用)");
        return PLUGIN_HANDLED;
    }

    new szThird[MAX_MODEL_PATH];
    new bool:bCustom = find_knife3p_third(szView, szThird, charsmax(szThird));

    client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 你的第一人称刀皮:^3 %s", szView);
    client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 对应第三人称显示:^3 %s^1 (^4%s^1)",
        szThird, bCustom ? "自定义映射" : "自动转换");

    return PLUGIN_HANDLED;
}

// ============================================================
//  命令 - 查看全局映射配置
// ============================================================
public cmdKnife3PCfg(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    if (g_i3PCount <= 0) {
        client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 当前没有配置任何刀皮映射");
        return PLUGIN_HANDLED;
    }

    client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 第三方称刀皮映射配置 (共 %d 条):", g_i3PCount);

    for (new i = 0; i < g_i3PCount; i++) {
        new szName[MAX_SKIN_NAME];
        new szThird[MAX_MODEL_PATH];
        ArrayGetString(g_a3PModelNames, i, szName, charsmax(szName));
        ArrayGetString(g_a3PThirdPaths, i, szThird, charsmax(szThird));
        client_print_color(id, print_team_default, "^4  %d.^3 %s^1 →^3 %s", i + 1, szName, szThird);
    }

    return PLUGIN_HANDLED;
}

// ============================================================
//  命令 - 重新加载配置
// ============================================================
public cmdKnife3PReload(const id, const level, const cid) {
    if (!cmd_access(id, level, cid, 1)) {
        return PLUGIN_HANDLED;
    }

    // 重新加载配置
    load_knife3p_config();

    // 重新预缓存新模型
    precache_all_3p_models();

    // 通知
    new szName[32];
    if (id == 0) {
        copy(szName, charsmax(szName), "SERVER");
    } else {
        get_user_name(id, szName, charsmax(szName));
    }

    log_amx("[DLC-Knife3P] %s 重新加载了第三人称刀皮映射 (映射=%d)", szName, g_i3PCount);

    if (id > 0) {
        console_print(id, "[DLC-Knife3P] 配置已重新加载! 映射=%d 条", g_i3PCount);
    }

    return PLUGIN_HANDLED;
}

public cmdKnife3PReloadChat(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    // 检查权限
    if (!(get_user_flags(id) & ADMIN_RCON)) {
        client_print_color(id, print_team_default, "^4[DLC-Knife3P]^1 你没有权限执行此命令 (需要 ADMIN_RCON)");
        return PLUGIN_HANDLED;
    }

    server_cmd("knife3p_reload");
    return PLUGIN_HANDLED;
}

// ============================================================
//  玩家断开 - 清理 WPM 实体
// ============================================================
public client_disconnected(id) {
    api_wpn_player_model_remove(id);
    g_szPlayerKnifeModel[id][0] = EOS;
}

// ============================================================
//  plugin_end - 清理
// ============================================================
public plugin_end() {
    ArrayDestroy(g_a3PModelNames);
    ArrayDestroy(g_a3PModelPaths);
    ArrayDestroy(g_a3PThirdPaths);
}