-- ============================================================
-- HNS 皮肤系统 独立数据库 (默认库名: skins, 不与其他插件共用)
-- 通过 phpMyAdmin / HeidiSQL 执行本文件即可, 会自动:
--   1) 创建独立数据库 skins
--   2) 创建三张表 (cpm_skins / cpm_player_skins / cpm_player_current)
-- 插件连接配置: configs/mixsystem/skinsql.cfg (sk_host/sk_user/sk_pass/sk_db)
-- ============================================================

-- 0) 创建皮肤系统自己的独立库 (若库名改了, 同步修改 skinsql.cfg 的 sk_db)
CREATE DATABASE IF NOT EXISTS skins DEFAULT CHARACTER SET utf8mb4;
USE skins;

-- 1) 皮肤池: 管理员维护的上架皮肤 (一行 = 一个阵营款式, 名字全服唯一)
--    每款属于 T 或 C 阵营, 各自有一个模型 + 一个可复用死亡音效,
--    玩家只看到/购买自己阵营的款。
CREATE TABLE IF NOT EXISTS cpm_skins (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    model_key   VARCHAR(32)  NOT NULL,             -- 唯一 key, 如 'hunan_t' / 'hunan_c'
    team        CHAR(1)      NOT NULL DEFAULT '',  -- 'T'=恐怖分子款 'C'=反恐精英款
    model       VARCHAR(64)  NOT NULL,             -- 模型路径 (models/ 下)
    body        TINYINT      NOT NULL DEFAULT 0,   -- 子模型
    skin        TINYINT      NOT NULL DEFAULT 0,   -- 皮肤序号
    price       INT          NOT NULL DEFAULT 0,   -- 价格(ICGB金币), 0 = 免费
    flags       VARCHAR(16)  NOT NULL DEFAULT '',  -- 权限要求, 空=所有人
    death_sound VARCHAR(80)  NOT NULL DEFAULT '',  -- 死亡音效 (sound/ 下), 可多个款复用, 空=不播
    active      TINYINT      NOT NULL DEFAULT 1,   -- 1=上架(可被选择/预缓存)  0=下架
    created     INT          NOT NULL DEFAULT 0,
    updated     INT          NOT NULL DEFAULT 0,
    UNIQUE KEY uk_key (model_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2) 玩家-皮肤 拥有关系: 哪个玩家拥有了哪个皮肤 (★ 你要查的这张表)
--    expire_at: 到期时间戳(UNIX秒), 0 = 永久
--      购买默认写入 现在+租期天数; 升级永久 / 管理员发放 写 0
CREATE TABLE IF NOT EXISTS cpm_player_skins (
    authid    VARCHAR(64) NOT NULL,              -- STEAM_0:x:y / VALVE / BOT
    model_key VARCHAR(32) NOT NULL,
    bought_at INT         NOT NULL DEFAULT 0,    -- 购买/发放时间
    expire_at INT         NOT NULL DEFAULT 0,    -- 0=永久, >0=租期到期时间戳
    PRIMARY KEY (authid, model_key),
    KEY idx_authid (authid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3) 玩家当前选用的皮肤 (TT/CT 各一行)
CREATE TABLE IF NOT EXISTS cpm_player_current (
    authid    VARCHAR(64) NOT NULL,
    team      CHAR(1)     NOT NULL DEFAULT '',   -- 'T' / 'C'
    model_key VARCHAR(32) NOT NULL DEFAULT '',
    updated   INT         NOT NULL DEFAULT 0,
    PRIMARY KEY (authid, team)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- 老库升级 (已经建过 cpm_player_skins 的, 只需执行下面这一句):
--   ALTER TABLE cpm_player_skins ADD COLUMN expire_at INT NOT NULL DEFAULT 0;
--   (插件启动时也会自动补这一列, 手动执行可保证数据库先行一致)
-- ============================================================
-- 常用查询示例 (在独立的 skins 库里执行):
--   SELECT * FROM cpm_player_skins;                       -- 所有玩家拥有哪些皮肤
--   SELECT * FROM cpm_player_skins WHERE authid='STEAM_0:1:123';  -- 指定玩家
--   SELECT * FROM cpm_player_skins WHERE expire_at=0;     -- 全部永久皮肤
--   SELECT * FROM cpm_player_skins WHERE expire_at>0;     -- 全部租期皮肤
--   SELECT * FROM cpm_skins;                              -- 皮肤池全部上架款
-- ============================================================