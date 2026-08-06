/*
 * HnsDlcSkin - DLC 皮肤音效扩展插件
 * ============================================
 * 为 HnsSkin 皮肤系统提供扩展功能：
 *   1. 死亡音效替换 - 根据不同玩家模型播放不同的死亡音效
 *   2. 刀击音效替换 - 根据不同刀模型播放不同的挥砍/击中/重击音效
 *
 * 配置: addons/amxmodx/configs/mixsystem/dlc_skin.ini
 * 音效: 放在 cstrike/sound/ 目录下
 *
 * 依赖: ReGameDLL (用于 pev_viewmodel2/pev_weaponmodel2)
 * 兼容: 独立插件，与 HnsSkin.sma / HnsMatchSkin.sma 一起使用
 *
 * 命令:
 *   /dlc_reload - 重新加载 DLC 配置 (ADMIN_RCON 权限)
 */

#include <amxmodx>
#include <fakemeta>
#include <amxmisc>
#include <hamsandwich>
#include <reapi>
#include <engine>

// ============================================================
//  插件信息
// ============================================================
#define PLUGIN_NAME "HNS DLC Skin Sound"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR "DLC Extension"

// ============================================================
//  常量定义
// ============================================================
#define MAX_PATH_LENGTH     192
#define MAX_SOUND_NAME      128
#define MAX_LINE_LENGTH     512
#define MAX_CONFIG_ENTRIES  64

// 音效索引
#define SOUND_SLASH         0
#define SOUND_HIT           1
#define SOUND_STAB          2
#define MAX_KNIFE_SOUNDS    3

// ============================================================
//  全局变量 - 死亡音效配置
// ============================================================
new Array:g_aDeathModelPaths;      // 玩家模型路径 (如 "models/player/arctic/arctic.mdl")
new Array:g_aDeathSoundPaths;      // 死亡音效路径 (如 "dlc/death_arctic.wav")
new g_iDeathSoundCount = 0;

// ============================================================
//  全局变量 - 刀击音效配置
// ============================================================
new Array:g_aKnifeModelPaths;      // 刀模型路径 (如 "models/v_knife.mdl")
new Array:g_aKnifeSounds[MAX_KNIFE_SOUNDS];  // 0=挥砍, 1=击中, 2=重击
new g_iKnifeSoundCount = 0;

// 玩家当前刀模型路径缓存 (用于快速查找)
new g_szPlayerKnifeModel[MAX_PLAYERS + 1][MAX_PATH_LENGTH];

// 玩家模型路径缓存 (用于死亡音效)
new g_szPlayerModelPath[MAX_PLAYERS + 1][MAX_PATH_LENGTH];

// ============================================================
//  plugin_precache - 预缓存所有音效
// ============================================================
public plugin_precache() {
    // 初始化数组
    g_aDeathModelPaths = ArrayCreate(MAX_PATH_LENGTH, 1);
    g_aDeathSoundPaths = ArrayCreate(MAX_SOUND_NAME, 1);
    g_aKnifeModelPaths = ArrayCreate(MAX_PATH_LENGTH, 1);
    g_aKnifeSounds[SOUND_SLASH] = ArrayCreate(MAX_SOUND_NAME, 1);
    g_aKnifeSounds[SOUND_HIT] = ArrayCreate(MAX_SOUND_NAME, 1);
    g_aKnifeSounds[SOUND_STAB] = ArrayCreate(MAX_SOUND_NAME, 1);

    // 加载配置
    load_dlc_config();

    // 预缓存所有音效
    precache_all_sounds();

    server_print("[DLC-Skin] plugin_precache: 死亡音效=%d, 刀音效=%d",
        g_iDeathSoundCount, g_iKnifeSoundCount);
}

// ============================================================
//  plugin_init - 注册事件钩子
// ============================================================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // 注册重新加载命令
    register_concmd("dlc_reload", "cmdDlcReload", ADMIN_RCON, " - 重新加载 DLC 音效配置");

    // 注册客户端命令
    register_clcmd("say /dlc_reload", "cmdDlcReloadChat");
    register_clcmd("say /dlcreload", "cmdDlcReloadChat");

    // === 死亡音效钩子 ===
    // 玩家死亡时播放自定义死亡音效
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled_Post", true);

    // === 刀击音效钩子 ===
    // 武器切换时缓存玩家刀模型
    register_message(get_user_msgid("CurWeapon"), "FM_CurWeapon");

    // 鼠标左键挥砍
    RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "OnKnifePrimaryAttack_Post", true);
    // 鼠标右键重击
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "OnKnifeSecondaryAttack_Post", true);
    // 刀击中目标
    RegisterHam(Ham_TraceAttack, "player", "OnPlayerTraceAttack_Post", true);

    // 玩家生成时更新模型缓存
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn_Post", true);

    log_amx("[DLC-Skin] DLC 皮肤音效扩展已加载 (死亡音效=%d, 刀音效=%d)",
        g_iDeathSoundCount, g_iKnifeSoundCount);
}

// ============================================================
//  配置加载
// ============================================================
stock load_dlc_config() {
    // 清空旧数据
    ArrayClear(g_aDeathModelPaths);
    ArrayClear(g_aDeathSoundPaths);
    ArrayClear(g_aKnifeModelPaths);
    ArrayClear(g_aKnifeSounds[SOUND_SLASH]);
    ArrayClear(g_aKnifeSounds[SOUND_HIT]);
    ArrayClear(g_aKnifeSounds[SOUND_STAB]);
    g_iDeathSoundCount = 0;
    g_iKnifeSoundCount = 0;

    // 构建配置文件路径
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/mixsystem/dlc_skin.ini", szPath);

    // 打开文件
    new f = fopen(szPath, "rt");
    if (!f) {
        log_amx("[DLC-Skin] 配置文件不存在: %s, 使用默认空配置", szPath);
        return;
    }

    new szLine[MAX_LINE_LENGTH];
    new bool:bInDeath = false;
    new bool:bInKnife = false;
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
            // 去掉开头的 [
            if (szLine[0] == '[') {
                copy(szLine, charsmax(szLine), szLine[1]);
            }

            if (equali(szLine, "DeathSounds") || equali(szLine, "Death")) {
                bInDeath = true;
                bInKnife = false;
            } else if (equali(szLine, "KnifeSounds") || equali(szLine, "Knife")) {
                bInDeath = false;
                bInKnife = true;
            } else {
                bInDeath = false;
                bInKnife = false;
            }
            continue;
        }

        // 解析死亡音效: "模型路径" "音效路径"
        if (bInDeath) {
            parse_death_sound_line(szLine, iLineNum);
        }
        // 解析刀音效: "模型路径" "挥砍音效" "击中音效" "重击音效"
        else if (bInKnife) {
            parse_knife_sound_line(szLine, iLineNum);
        }
    }

    fclose(f);

    log_amx("[DLC-Skin] 配置加载完成: 死亡音效=%d 条, 刀音效=%d 条",
        g_iDeathSoundCount, g_iKnifeSoundCount);
}

// 解析死亡音效行
stock parse_death_sound_line(const szLine[], iLineNum) {
    // 格式: "模型路径" "音效路径"
    // 用引号分割: 找到第一个 " 和第二个 " 之间的内容为模型路径
    // 第三个 " 和第四个 " 之间的内容为音效路径

    new szModel[MAX_PATH_LENGTH];
    new szSound[MAX_SOUND_NAME];
    new iLen = strlen(szLine);
    new iQuoteCount = 0;
    new iStart = -1;

    // 逐字符解析引号对
    for (new i = 0; i <= iLen; i++) {
        if (szLine[i] == '"') {
            if (iStart == -1) {
                iStart = i + 1;  // 引号后的内容开始
            } else {
                // 引号结束
                new iSegLen = i - iStart;
                if (iSegLen > 0) {
                    if (iQuoteCount == 0) {
                        // 第一个引号对: 模型路径
                        new iCopyLen = iSegLen + 1;
                        if (iCopyLen > MAX_PATH_LENGTH) iCopyLen = MAX_PATH_LENGTH;
                        copy(szModel, iCopyLen, szLine[iStart]);
                        if (iSegLen < MAX_PATH_LENGTH - 1) szModel[iSegLen] = EOS;
                        else szModel[MAX_PATH_LENGTH - 1] = EOS;
                    } else if (iQuoteCount == 1) {
                        // 第二个引号对: 音效路径
                        new iCopyLen = iSegLen + 1;
                        if (iCopyLen > MAX_SOUND_NAME) iCopyLen = MAX_SOUND_NAME;
                        copy(szSound, iCopyLen, szLine[iStart]);
                        if (iSegLen < MAX_SOUND_NAME - 1) szSound[iSegLen] = EOS;
                        else szSound[MAX_SOUND_NAME - 1] = EOS;
                    }
                }
                iQuoteCount++;
                iStart = -1;
            }
        }
    }

    // 验证数据
    if (szModel[0] == EOS || szSound[0] == EOS) {
        log_amx("[DLC-Skin] Line %d: bad format (expected ModelPath SoundPath), skipped", iLineNum);
        return;
    }

    // 直接添加新条目 (允许同一模型配多个音效, 死亡时随机播放)
    ArrayPushString(g_aDeathModelPaths, szModel);
    ArrayPushString(g_aDeathSoundPaths, szSound);
    g_iDeathSoundCount++;
}

// 解析刀音效行
stock parse_knife_sound_line(const szLine[], iLineNum) {
    // 格式: "模型路径" "挥砍音效" "击中音效" "重击音效"
    new szModel[MAX_PATH_LENGTH];
    new szSounds[MAX_KNIFE_SOUNDS][MAX_SOUND_NAME];
    new iLen = strlen(szLine);
    new iQuoteCount = 0;
    new iStart = -1;
    new iSegment = 0;

    // 逐字符解析引号对
    for (new i = 0; i <= iLen; i++) {
        if (szLine[i] == '"') {
            if (iStart == -1) {
                iStart = i + 1;
            } else {
                new iSegLen = i - iStart;
                if (iSegLen > 0 && iSegment < MAX_KNIFE_SOUNDS + 1) {
                    if (iSegment == 0) {
                        // 第一个引号对: 模型路径
                        new iCopyLen = iSegLen + 1;
                        if (iCopyLen > MAX_PATH_LENGTH) iCopyLen = MAX_PATH_LENGTH;
                        copy(szModel, iCopyLen, szLine[iStart]);
                        if (iSegLen < MAX_PATH_LENGTH - 1) szModel[iSegLen] = EOS;
                        else szModel[MAX_PATH_LENGTH - 1] = EOS;
                    } else if (iSegment <= MAX_KNIFE_SOUNDS) {
                        // 第2-4个引号对: 音效路径
                        new iCopyLen = iSegLen + 1;
                        if (iCopyLen > MAX_SOUND_NAME) iCopyLen = MAX_SOUND_NAME;
                        copy(szSounds[iSegment - 1], iCopyLen, szLine[iStart]);
                        if (iSegLen < MAX_SOUND_NAME - 1) szSounds[iSegment - 1][iSegLen] = EOS;
                        else szSounds[iSegment - 1][MAX_SOUND_NAME - 1] = EOS;
                    }
                    iSegment++;
                }
                iQuoteCount++;
                iStart = -1;
            }
        }
    }

    // 验证数据
    if (szModel[0] == EOS) {
        log_amx("[DLC-Skin] Line %d: bad format (expected KnifeModel Slash Hit Stab), skipped", iLineNum);
        return;
    }

    // 检查是否已存在相同模型
    new iSize = ArraySize(g_aKnifeModelPaths);
    for (new i = 0; i < iSize; i++) {
        new szExisting[MAX_PATH_LENGTH];
        ArrayGetString(g_aKnifeModelPaths, i, szExisting, charsmax(szExisting));
        if (equal(szExisting, szModel)) {
            // 更新已有条目
            for (new j = 0; j < MAX_KNIFE_SOUNDS; j++) {
                if (szSounds[j][0] != EOS) {
                    ArraySetString(g_aKnifeSounds[j], i, szSounds[j]);
                }
            }
            return;
        }
    }

    // 添加新条目
    ArrayPushString(g_aKnifeModelPaths, szModel);
    for (new j = 0; j < MAX_KNIFE_SOUNDS; j++) {
        ArrayPushString(g_aKnifeSounds[j], szSounds[j]);
    }
    g_iKnifeSoundCount++;
}

// ============================================================
//  音效预缓存
// ============================================================
stock precache_all_sounds() {
    new szSound[MAX_SOUND_NAME];
    new i, iSize;

    // 预缓存死亡音效
    iSize = ArraySize(g_aDeathSoundPaths);
    for (i = 0; i < iSize; i++) {
        ArrayGetString(g_aDeathSoundPaths, i, szSound, charsmax(szSound));
        if (szSound[0] != EOS) {
            precache_sound(szSound);
        }
    }

    // 预缓存刀音效
    for (new j = 0; j < MAX_KNIFE_SOUNDS; j++) {
        iSize = ArraySize(g_aKnifeSounds[j]);
        for (i = 0; i < iSize; i++) {
            ArrayGetString(g_aKnifeSounds[j], i, szSound, charsmax(szSound));
            if (szSound[0] != EOS) {
                precache_sound(szSound);
            }
        }
    }
}

// ============================================================
//  死亡音效 - 玩家死亡时播放自定义音效
// ============================================================
public OnPlayerKilled_Post(const id, const inflictor, const attacker, const Float:damage, const bits) {
    // id = 死亡玩家
    if (!is_user_connected(id)) {
        return;
    }

    // 查找该玩家的模型是否有配置死亡音效
    new szModelPath[MAX_PATH_LENGTH];
    if (!get_player_model_path(id, szModelPath, charsmax(szModelPath))) {
        return;
    }

    // 在死亡音效配置中查找匹配项
    new szSound[MAX_SOUND_NAME];
    if (!find_death_sound(szModelPath, szSound, charsmax(szSound))) {
        return;
    }

    // 播放死亡音效给周围玩家
    emit_sound(id, CHAN_VOICE, szSound, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

// 获取玩家当前身体模型路径
stock bool:get_player_model_path(const id, szPath[], iLen) {
    // 获取玩家模型文件夹名 (如 "arctic", "terror", "gsg9")
    new szModel[32];
    get_user_info(id, "model", szModel, charsmax(szModel));

    if (szModel[0] == EOS) {
        return false;
    }

    // 构建完整路径: models/player/xxx/xxx.mdl
    format(szPath, iLen, "models/player/%s/%s.mdl", szModel, szModel);
    return true;
}

// 查找模型对应的死亡音效 (随机选一个)
stock bool:find_death_sound(const szModelPath[], szSound[], iLen) {
    new iSize = ArraySize(g_aDeathModelPaths);
    new iMatchCount = 0;
    new iMatches[MAX_CONFIG_ENTRIES];

    // 收集所有匹配的音效索引
    for (new i = 0; i < iSize; i++) {
        new szEntry[MAX_PATH_LENGTH];
        ArrayGetString(g_aDeathModelPaths, i, szEntry, charsmax(szEntry));

        if (equal(szEntry, szModelPath)) {
            iMatches[iMatchCount++] = i;
            if (iMatchCount >= MAX_CONFIG_ENTRIES) break;
        }
    }

    if (iMatchCount == 0) {
        return false;
    }

    // 从匹配的音效中随机选一个
    new iPick = random(iMatchCount);
    ArrayGetString(g_aDeathSoundPaths, iMatches[iPick], szSound, iLen);
    return szSound[0] != EOS;
}

// ============================================================
//  刀击音效 - 武器切换时缓存刀模型
// ============================================================
public FM_CurWeapon(const id) {
    if (!is_user_alive(id) || !is_user_connected(id)) {
        return FMRES_IGNORED;
    }

    // 第1个参数是武器ID
    new iWeapon = get_msg_arg_int(1);

    if (iWeapon == CSW_KNIFE) {
        // 缓存当前刀模型路径
        cache_player_knife_model(id);
    }

    return FMRES_IGNORED;
}

// 缓存玩家当前刀模型
stock cache_player_knife_model(const id) {
    // 从玩家实体读取 pev_viewmodel2 (由 HnsSkin 设置)
    new szViewModel[MAX_PATH_LENGTH];
    entity_get_string(id, pev_viewmodel2, szViewModel, charsmax(szViewModel));

    // 如果为空，尝试默认模型
    if (szViewModel[0] == EOS) {
        copy(szViewModel, charsmax(szViewModel), "models/v_knife.mdl");
    }

    copy(g_szPlayerKnifeModel[id], charsmax(g_szPlayerKnifeModel[]), szViewModel);
}

// ============================================================
//  刀击音效 - 鼠标左键挥砍
// ============================================================
public OnKnifePrimaryAttack_Post(const iWeaponEnt) {
    // 获取武器持有者
    new id = get_weapon_owner(iWeaponEnt);
    if (id <= 0 || id > MAX_PLAYERS) {
        return;
    }

    // 播放自定义挥砍音效
    play_knife_sound(id, SOUND_SLASH);
}

// ============================================================
//  刀击音效 - 鼠标右键重击
// ============================================================
public OnKnifeSecondaryAttack_Post(const iWeaponEnt) {
    new id = get_weapon_owner(iWeaponEnt);
    if (id <= 0 || id > MAX_PLAYERS) {
        return;
    }

    // 播放自定义重击音效
    play_knife_sound(id, SOUND_STAB);
}

// ============================================================
//  刀击音效 - 刀击中目标
// ============================================================
public OnPlayerTraceAttack_Post(const iVictim, const iAttacker, const Float:flDamage, const Float:flDirection[3], const iTr, const iBits) {
    // 检查攻击者是否为有效玩家
    if (iAttacker <= 0 || iAttacker > MAX_PLAYERS) {
        return;
    }

    if (!is_user_connected(iAttacker)) {
        return;
    }

    // 检查攻击者是否拿着刀
    if (get_user_weapon(iAttacker) != CSW_KNIFE) {
        return;
    }

    // 播放自定义击中音效
    play_knife_sound(iAttacker, SOUND_HIT);
}

// ============================================================
//  刀击音效 - 播放
// ============================================================
stock play_knife_sound(const id, const iSoundType) {
    // 检查模型缓存
    if (g_szPlayerKnifeModel[id][0] == EOS) {
        cache_player_knife_model(id);
        if (g_szPlayerKnifeModel[id][0] == EOS) {
            return;
        }
    }

    // 查找刀模型对应的音效
    new szSound[MAX_SOUND_NAME];
    if (!find_knife_sound(g_szPlayerKnifeModel[id], iSoundType, szSound, charsmax(szSound))) {
        return;
    }

    // 播放音效
    // 用 CHAN_STATIC 或 CHAN_WEAPON 通道播放，让玩家能听到
    emit_sound(id, CHAN_WEAPON, szSound, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

// 查找刀模型对应的音效
stock bool:find_knife_sound(const szModelPath[], const iSoundType, szSound[], iLen) {
    new iSize = ArraySize(g_aKnifeModelPaths);
    for (new i = 0; i < iSize; i++) {
        new szEntry[MAX_PATH_LENGTH];
        ArrayGetString(g_aKnifeModelPaths, i, szEntry, charsmax(szEntry));

        if (equal(szEntry, szModelPath)) {
            ArrayGetString(g_aKnifeSounds[iSoundType], i, szSound, iLen);
            return szSound[0] != EOS;
        }
    }
    return false;
}

// ============================================================
//  工具函数
// ============================================================

// 获取武器实体的持有者
stock get_weapon_owner(const iWeaponEnt) {
    return get_ent_data(iWeaponEnt, "CBasePlayerItem", "m_pPlayer");
}

// 玩家生成时更新模型缓存
public OnPlayerSpawn_Post(const id) {
    // 延迟一小段时间确保模型已应用
    set_task(0.2, "task_update_player_cache", id);
}

public task_update_player_cache(const id) {
    if (!is_user_connected(id)) {
        return;
    }

    // 更新玩家模型路径缓存
    get_player_model_path(id, g_szPlayerModelPath[id], charsmax(g_szPlayerModelPath[]));

    // 如果玩家拿着刀，更新刀模型缓存
    if (is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE) {
        cache_player_knife_model(id);
    }
}

// ============================================================
//  命令 - 重新加载配置
// ============================================================
public cmdDlcReload(const id, const level, const cid) {
    if (!cmd_access(id, level, cid, 1)) {
        return PLUGIN_HANDLED;
    }

    // 重新加载配置
    load_dlc_config();

    // 重新预缓存新音效
    precache_all_sounds();

    // 通知
    new szName[32];
    if (id == 0) {
        copy(szName, charsmax(szName), "SERVER");
    } else {
        get_user_name(id, szName, charsmax(szName));
    }

    log_amx("[DLC-Skin] %s 重新加载了 DLC 配置 (死亡音效=%d, 刀音效=%d)",
        szName, g_iDeathSoundCount, g_iKnifeSoundCount);

    if (id > 0) {
        console_print(id, "[DLC-Skin] 配置已重新加载! 死亡音效=%d 条, 刀音效=%d 条",
            g_iDeathSoundCount, g_iKnifeSoundCount);
    }

    return PLUGIN_HANDLED;
}

public cmdDlcReloadChat(const id) {
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }

    // 检查权限
    if (!(get_user_flags(id) & ADMIN_RCON)) {
        console_print(id, "[DLC-Skin] 你没有权限执行此命令 (需要 ADMIN_RCON)");
        return PLUGIN_HANDLED;
    }

    // 执行重新加载
    new szCmd[64];
    formatex(szCmd, charsmax(szCmd), "dlc_reload");
    server_cmd(szCmd);

    return PLUGIN_HANDLED;
}

// ============================================================
//  plugin_end - 清理
// ============================================================
public plugin_end() {
    // 清理数组
    cleanup_arrays();
}

stock cleanup_arrays() {
    ArrayDestroy(g_aDeathModelPaths);
    ArrayDestroy(g_aDeathSoundPaths);
    ArrayDestroy(g_aKnifeModelPaths);
    for (new j = 0; j < MAX_KNIFE_SOUNDS; j++) {
        ArrayDestroy(g_aKnifeSounds[j]);
    }
}