#if defined _ic_points_included
    #endinput
#endif
#define _ic_points_included

#pragma reqlib HnsICPointSystem
#if !defined AMXMODX_NOAUTOLOAD
    #pragma loadlib HnsICPointSystem
#endif

// ============================================================
//  HNS IC Point System Native 接口
//  供外部系统 (如比赛系统) 对接发放/查询 IC 点
//
//  用法:
//    #include <ic_points>
//    ic_add_points(id, 10);   // 给玩家 +10 IC 点
//    new pts = ic_get_points(id); // 查询玩家当前 IC 点
//
//  说明: IC 点系统本身不依赖任何比赛系统,
//        具体的发分时机/条件由调用方 (你的比赛系统) 自行决定。
// ============================================================

// 给指定玩家增加 IC 点 (id=玩家索引, iAmount=正数)。成功返回 1, 失败返回 0。
native ic_add_points(id, iAmount);

// 查询指定玩家当前 IC 点。
native ic_get_points(id);