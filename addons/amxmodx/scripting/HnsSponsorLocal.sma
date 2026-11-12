/*
 * 皮肤商店点数。存在 nvault skin_gc，不使用比赛插件的 hns_gc。
 * 键: skin_gc_<steamid>
 */

#include <amxmodx>
#include <nvault>

#define VAULT_NAME "skin_gc"
#define VAULT_PREFIX "skin_gc_"

new g_iVault;

public plugin_init() {
	register_plugin("HNS Skin Gold", "1.0", "OpenHNS");
	register_library("skin_gc_local");

	g_iVault = nvault_open(VAULT_NAME);
}

public plugin_end() {
	nvault_close(g_iVault);
}

public plugin_natives() {
	register_native("skin_gc_local_available", "native_gc_local_available");
	register_native("skin_gc_local_get", "native_gc_local_get");
	register_native("skin_gc_local_set", "native_gc_local_set");
	register_native("skin_gc_local_add_steamid", "native_gc_add_steamid");
}

public native_gc_local_available(amxx, params) {
	#pragma unused amxx, params
	return 1;
}

public native_gc_add_steamid(amxx, params) {
	#pragma unused amxx
	new szAuth[64], szKey[96];
	get_string(1, szAuth, charsmax(szAuth));
	new iDelta = get_param(2);
	if (!szAuth[0] || !iDelta)
		return 0;
	formatex(szKey, charsmax(szKey), "%s%s", VAULT_PREFIX, szAuth);
	new iNew = nvault_get(g_iVault, szKey) + iDelta;
	if (iNew < 0)
		iNew = 0;
	nvault_set(g_iVault, szKey, fmt("%d", iNew));
	return iNew;
}

public native_gc_local_get(amxx, params) {
	enum { id = 1 };

	new szKey[48];
	gc_build_key(get_param(id), szKey, charsmax(szKey));

	return nvault_get(g_iVault, szKey);
}

public native_gc_local_set(amxx, params) {
	enum { id = 1, iAmount };

	new szKey[48];
	gc_build_key(get_param(id), szKey, charsmax(szKey));

	nvault_set(g_iVault, szKey, fmt("%d", get_param(iAmount)));

	return 1;
}

stock gc_build_key(id, szKey[], iLen) {
	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szKey, iLen, "%s%s", VAULT_PREFIX, szAuthId);
}
