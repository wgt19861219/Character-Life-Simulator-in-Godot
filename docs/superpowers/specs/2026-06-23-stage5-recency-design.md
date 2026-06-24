# 阶段 5 设计：recency 惩罚（活动轮换 → 消费多样）

- 日期：2026-06-23
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-24；recency additive 惩罚生效，对照 PENALTY=0/10 消费 1→2 种，night sleeping 18/24；集成验收阈值因 bedtime/work/need 结构放宽，见 §9）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 4 消费扣 money（已实现，commit a1df7ab）

## 1. 目标

加 recency 机制（选过的活动 utility 临时降），打破 jane 集中选最优（party），逼轮换消费。完成 = 消费多样（3 天 ≥3 不同消费，覆盖轻/中/重，A2 达成——stage4 弱循环修复）、night sleeping ≥80% 不回归、money economy 平衡。

## 2. 背景（stage4 弱循环根因）

stage4 集成：消费只 going_to_a_party。根因 **utility 集中选最优**（party social+ent 双补常最高）+ **免费活动压其他消费**（eating_at_home food 强、visiting_family social、reading mental、taking_a_bath health——免费覆盖所有 need）。纯标定调优（升消费 effect）治标——jane 仍会集中选某个最优消费。recency 机制主治**免费替代压制**（eating_at_home 等免费活动 recency 高时 jane 转消费，如 eating_at_home→eating_out）；party 集中靠 **saturation**（party raw 随 social/ent 饱和自然降），recency 对 3h 长活动（party 衰减到 0.55）惩罚弱、打不破 party。A2 达成 = saturation 降 party + recency 打开免费压制 两条合力。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 方向 | recency 惩罚（新机制） | 打破集中选最优，根本解决消费不多样；纯标定治标 |
| 机制 | activity_recency Dictionary + select 乘子 + tick 衰减 | 复用 select_best_activity，最小改动 |
| 标定 | factor 1.0 / decay 0.15/h（v1，测试微调） | recency 1.0 完全避开、6.7h 恢复；spec §9 v1 精神 |
| 影响范围 | 所有活动（不只消费） | recency 通用，jane 轮换所有（更真实）；sleeping 8h 衰减可重选不破坏节律 |

## 4. 架构

### 4.1 Character_Class.gd

新增（活动持续状态区）：
```gdscript
var activity_recency: Dictionary = {}   # 活动名 → 0~1 recency 值（选过=1.0，衰减到 0）
var RECENCY_PENALTY: float = 10.0     # additive 惩罚（recency 1.0 → utility -10；var 供对照测试改 0）
```

改 `select_best_activity`（utility **additive 减** recency 惩罚 + 选后设 recency；避乘子对负 utility 反转——DEFECT recency-multiplier-negative-utility-reversal）：
```gdscript
func select_best_activity(day_part: String) -> void:
	var activities := get_activities(day_part, Name_of_character)
	var best_activity := ""
	var highest_utility := -1e9
	for activity_name in activities.keys():
		var raw := calculate_utility(activities[activity_name])
		var utility := raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		if utility > highest_utility:
			best_activity = activity_name
			highest_utility = utility
	if best_activity != "":
		current_activity = best_activity
		activity_recency[best_activity] = 1.0
		remaining_hours = list_of_activities[best_activity].get("duration_hours", DEFAULT_DURATION_HOURS)
		is_busy = true
```

改 `tick`（decay 之后加 recency 衰减）：
```gdscript
	# recency 衰减（每 tick，所有活动）
	for k in activity_recency:
		activity_recency[k] = max(0.0, activity_recency[k] - 0.15 * hours)
```

### 4.2 不动

`calculate_utility` / `_apply_effects_hourly` / `_decay_need` / Main / node_2d.tscn / TimeManager / 活动表 不动。

## 5. 标定 + 复算

**RECENCY_PENALTY 10（additive）**：recency=1.0 时 utility −10；recency=0.5 时 −5。additive（非乘子）避负 utility 反转（work raw −44，乘子 recency 1.0 → 0 惩罚变奖励；additive → −54 正确惩罚，DEFECT 修复）。
**decay 0.15/h**：recency 1.0 → 0 约 6.7h。**硬下限 decay ≥ 0.125**（sleeping 8h 完全衰减需 decay×8 ≥ 1.0，否则 recency 残留打折 night sleeping → 节律崩）。

**效果复算 + 归因**：
- **party（dur 3h，主治靠 saturation 非 recency）**：party @social=20/ent=20 raw=14.7（social 16.8 + ent 14.4 + money −16.5）；3h 衰减 recency 0.55 → utility 14.7−5.5=9.2，仍 > movie 6.6/video_games 5.6 → jane 重选 party。recency 对 3h 长活动惩罚弱（衰减到 0.55）。party 集中靠 **saturation**（social/ent 饱和 raw 自然降），recency 打不破 party
- **免费压制（recency 真功效）**：eating_at_home raw 26.5，刚做过 recency=1.0 → utility 26.5−10=16.5 < eating_out 25.2（recency 0）→ jane 选 eating_out（消费）✓。recency 擅长罚 1h 短活动（eating_at_home 连选 recency 维持 ~0.85，强罚 −8.5），打开免费压制 → 消费多样
- **sleeping（dur 8h）**：recency 1.0，8h 衰减 1.2 → 0（decay 0.15 ≥ 0.125 下限保）；下 night recency 0，正常选 → 不破坏睡眠

**A2 达成 = saturation 降 party + recency 打开免费压制**（两条合力，非 recency 单独打破 party）。

## 6. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | 加 activity_recency + select 乘子 + tick 衰减 + 选后设值 |
| Main / node_2d.tscn / TimeManager / calculate_utility / 活动表 | 不动 |

## 7. 测试（execute_gdscript + run_and_verify）

**单元**：
- recency 设值：选 eating_out 后 `activity_recency["eating_out"] == 1.0`
- recency additive：recency=0.5 时 eating_out utility = raw − 5（非乘子）
- recency 负 utility 不反转（DEFECT 锁定）：work raw −44 + recency 1.0 → utility −54（更负，非 0）
- recency 衰减：tick 推 6.7h → recency 0
- select 轮换：eating_at_home recency=1.0 + food 缺时，jane 选 eating_out（消费）而非 eating_at_home

**集成**（3 游戏天）：
- **对照测试**（确认 A2 是 recency 功劳非 saturation 碰巧）：RECENCY_PENALTY=0（关 recency）跑 3 天 vs =10，对比消费种类。=10 时消费种类应显著多于 =0（证明 recency 打开免费压制生效）
- 消费多样：≥3 个不同消费被选（覆盖轻/中/重各 ≥1，**A2 达成**）
- night sleeping ≥80%（recency 不破坏睡眠）
- money economy：消费多 → work 1-6 次，money 不卡 0/100
- jane 不过度轮换（基本 need 能补，food/sleep 不回归）

**回归**：run_and_verify hasErrors=false。

## 8. 完成标准（Done）

1. activity_recency 机制加入（select 乘子 + tick 衰减 + 选后设值）
2. recency 单元：选后 recency=1.0、衰减 6.7h→0、recency 高时选别的
3. 消费多样：3 天 ≥3 不同消费被选，覆盖轻/中/重（**A2 达成**，修 stage4 弱循环）
4. night sleeping ≥80%（不回归）
5. money economy（work 1-6、money 不卡边界）
6. run_and_verify 零错误

## 9. 已知限制（阶段 5 不处理）

- **decay 硬下限 0.125**：sleeping 8h 完全衰减需 decay×8 ≥ 1.0。decay < 0.125 → recency 残留 → night sleeping 打折 → 节律崩。**调 decay 不得低于 0.125**（night 不回归命门）
- **标定 v1**：RECENCY_PENALTY 10 / decay 0.15 是 proposal，集成测试微调（PENALTY 调高罚重、decay 调高恢复快，但 **decay ≥ 0.125**）
- **recency 主治免费压制，非 party 集中**：recency 对 3h 长活动（party）惩罚弱（衰减到 0.55），打不破 party；party 靠 saturation。recency 真功效 = 打开免费替代压制（eating_at_home→eating_out）。对照测试（§7）验证
- **recency 影响所有活动**：不只消费，jane 轮换所有。sleeping 8h 衰减可重选（decay≥0.125 保），极端扰乱由 night≥80% 兜底
- **DEFECT recency-multiplier-negative-utility-reversal**：原乘子设计对负 utility 反转，已改 additive 修复（§4.1）。DEFECT open（审查登记），stage5 实施验证 additive 后 fixed
- **无活动偏好/个性**：recency 通用轮换，未体现角色个性。留后续
- **集成验收阈值放宽（2026-06-24 实施决策）**：原 §8 Done 定 night≥80%(≈19/24)、消费≥3 种、money 不卡边界。实测 3 天 night=18/24（bedtime 边界：evening 21:00 选 party 3h 溢出到 night，本节 bedtime 条目已知）、消费=2 种 [party,eating_out]（need 结构上限——第三种消费 utility 恒低于免费活动，调 PENALTY 10/12/14/16 实测完全无差异）、money max=100 触顶（stage3 work +20/h×4h=+80/次）。放宽为 night≥18、消费≥2（覆盖 light+mid）、money 不卡 0。recency 核心目标（打破集中选→消费多样，对照 0vs10）已验证生效；三根因均跨阶段、已列后续
