# HNS IC 点系统 v1.0.0（独立版）

- 独立发行版，不打包进皮肤系统。
- 赏金局积分兑换皮肤。
- 依赖: HnsMatchSystem.amxx / PersistentDataStorage / player_models.ini
- 加载顺序: 在 HnsMenuNew.amxx 之后

## 功能
- N 键打开 IC 独立菜单（优先级高于 menu new）
- 娱乐局/赏金局，各含 6 种比赛模式
- 赏金局比赛画面上方显示 [赏金局] 标记
- 比赛结束仅在赏金局分配 IC 积分（赢 +10 / 输 +5）
- IC 积分与已兑换皮肤持久化（PDS）
- 积分兑换皮肤：人物 500 / 刀 300
- 兑换皮肤直接应用模型，一个月后自动清除

## 命令
- N 键 / `/ic` / `/icpoint` — 打开 IC 点主菜单
- `/givetic` / `/giveic` / `/addic` — 管理员给予 IC 点

## CVAR
| CVAR | 默认 |
|------|------|
| ic_pts_win | 10 |
| ic_pts_loss | 5 |
| ic_skin_person | 500 |
| ic_skin_knife | 300 |
