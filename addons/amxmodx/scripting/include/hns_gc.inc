#if defined _hns_gc_included
  #endinput
#endif
#define _hns_gc_included

/**
 * 皮肤商店自己的点数。只读 HnsSponsorLocal 的 skin_gc 金库。
 * 不调用比赛插件的 hns_gc_sql，也不读比赛库。
 */

native skin_gc_local_available();
native skin_gc_local_get(id);
native skin_gc_local_set(id, iAmount);
native skin_gc_local_add_steamid(const szSteam[], iDelta);

stock bool:hns_gc_is_sql() {
	return false;
}

stock bool:hns_gc_available() {
	return LibraryExists("skin_gc_local", LibType_Library) && bool:skin_gc_local_available();
}

stock bool:hns_gc_player_ready(id) {
	#pragma unused id
	return hns_gc_available();
}

stock hns_gc_get_player(id) {
	if (!hns_gc_available())
		return 0;
	return skin_gc_local_get(id);
}

stock hns_gc_set_player(id, iAmount) {
	if (!hns_gc_available())
		return;
	if (iAmount < 0)
		iAmount = 0;
	skin_gc_local_set(id, iAmount);
}

/* 给玩家加/减 ICGB (负数为扣) */
stock hns_gc_add_player(id, iDelta) {
	if (!iDelta)
		return hns_gc_get_player(id);
	new iNew = hns_gc_get_player(id) + iDelta;
	if (iNew < 0)
		iNew = 0;
	hns_gc_set_player(id, iNew);
	return iNew;
}

stock hns_gc_add_steamid(const szSteam[], iDelta) {
	if (!szSteam[0] || !iDelta || !hns_gc_available())
		return 0;
	return skin_gc_local_add_steamid(szSteam, iDelta);
}

stock hns_gc_set_steamid(const szSteam[], iAmount) {
	#pragma unused szSteam, iAmount
	return 0;
}
