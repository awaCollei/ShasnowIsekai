# 回合制战斗模块

## 进入战斗

- 玩家在局外按普通攻击并命中 `Enemy`：我方先手，首次行动伤害 `+25%`。
- 史莱姆的攻击动画命中玩家：敌方先手，首次敌方行动伤害 `+25%`。
- `BattleManager` 会收集发起者周围 `join_radius` 内、与玩家同 `sub_scene` 的敌人。
- 默认每波最多 3 名敌人，多余敌人自动排入下一波。
- 战斗是叠加在当前世界上的独立场景。世界在战斗期间冻结，胜利后原地恢复；被击败的敌人才从世界移除。
- 命中信号可能来自物理回调，因此 `BattleManager` 会先锁定战斗请求，再用 `call_deferred()` 在安全时机冻结碰撞对象。

## 地图战斗背景

战斗会按触发时的地图 ID 自动加载：

```text
res://assets/<scene_id>/battlefield.png
```

例如 `city1` 使用 `res://assets/city1/battlefield.png`。如果专属战斗图尚不存在，会临时回退到同目录的 `background2.png`；两者都不存在时才使用内置深色背景。

训练木桩设置了 `battle_enabled = false`，仍沿用原有无限生命受击反馈，不会进入无法结束的战斗。

## 当前行动

| 行动 | MP | 效果 | 表现 |
|---|---:|---|---|
| 普通攻击 | 0 | 12 伤害、回复 18 MP | 跑到目标面前攻击后返回 |
| 魔法之刃 | 30 | 44 单体伤害 | 近战突进 |
| 霜晶枪 | 18 | 28 单体伤害 | 冰色投射物 |
| 星焰爆裂 | 42 | 全体 32 伤害 | 扩大的星焰法球 |

行动定义暂时集中在 `battle_scene.gd` 的 `ACTIONS`。后续技能数量增多时，可无损迁移为自定义 `Resource`（技能 ID、消耗、目标类型、伤害公式、动画策略）。

## 扩展新敌人

继承 `Enemy` 后配置：

- `battle_name`
- `battle_visual_id`
- `battle_damage`，或覆写 `get_battle_damage()`
- `max_hp`
- 不应进入普通战斗的设施设置 `battle_enabled = false`

新素材的战斗代理动画在 `battle_actor_view.gd::setup_enemy()` 中按 `battle_visual_id` 注册。世界 AI 可以保持完整；只需在其命中帧调用：

```gdscript
BattleManager.begin_battle(player, self, false)
```

## 主要文件

- `battle_manager.gd`：参战收集、波次入口、世界冻结与恢复、战斗生命周期兜底。
- `battle_scene.tscn` / `battle_scene.gd`：回合状态、菜单、目标选择、伤害与波次推进。
- `battle_actor_view.gd`：复用逐帧素材的纯表现代理及移动、受击动画。
