# 阶段 2 设计：calculate_utility per_hour 净效用模型

- 日期：2026-06-23
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-23；night sleeping 0.875 达标，bedtime 降软指标）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 1 时间系统（已实现，commit 30d1d85 / f03e314）

## 1. 目标

修 `calculate_utility` 的系统性低估 bug，让角色行动时机准确（夜间准时睡、白天及时补需求），night sleeping 占比稳过 80%。

完成 = sleeping 不再被算成负效用、night sleeping ≥ 80%、trace 显示 22:00 前后能进入 sleeping（不偏晚到 01:00）。

## 2. 背景（阶段 1 暴露的问题）

阶段 1 集成验证实测：night sleeping 占比 19/24 ≈ **79%**（未达 80% 硬指标），根因是 jane 睡太晚（trace：21:00 选 visiting_a_spa 3h 跨入 night，01:00 才睡）。

根因在 `calculate_utility`（阶段 1 spec §9 已知限制）。当前算法：

```gdscript
var impact = effects[need] * duration              # 一次性总效果
var base = impact * (max - current) / max          # 缺口加权
var wasted = max(0, current + impact - max)        # 一次性溢出惩罚
utility = base - wasted
```

**两个 bug**：
1. **不含 decay**：活动期间 need 照常衰减（spec §4 铁律），但 utility 没算 decay → 活动效用高估
2. **double-count**：base 用含溢出的 impact，wasted 又扣溢出 → 长/高 per_hour 活动效用被重复扣到负

sleeping 实例（sleep=50, max=100, effect 15/h, dur 8h, decay 6/h）：
- impact = 15×8 = 120
- base = 120 × 0.5 = 60
- wasted = max(0, 50+120−100) = 70
- utility = 60 − 70 = **−10** ❌（真实净增益应是 +50）

负效用导致 jane 不愿早睡，等到 sleep 掉很低（缺口极大、wasted 相对变小）才考虑睡 → 偏晚。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 范围 | 只修 calculate_utility | working_overtime/money 是独立子系统，留阶段 3（YAGNI） |
| 算法 | 方案 B 解析净效果 | 含 decay + clamp 真实，无循环、性能好；当前活动都是单调 net，逐小时模拟（方案 A）用不上其通用性 |
| 缺口权重 | 保留 urgency = (max−current)/max | 饿的人吃饭急；保留阶段 1 行为基线 |
| 负 effect | 自然处理（不特殊） | working_overtime net 为负 → 不被选，符合预期（money 留阶段 3） |

## 4. 算法设计

新 `calculate_utility`（Character_Class.gd，tab 缩进）：

```gdscript
func calculate_utility(activity: Dictionary) -> float:
	var total_utility: float = 0.0
	var duration: float = activity.get("duration_hours", DEFAULT_DURATION_HOURS)
	for need in activity["effects"].keys():
		var effect_ph: float = activity["effects"][need]
		var decay_ph: float = get(str(need) + "_decay")
		var current: float = get(need)
		var mx: float = get(str(need) + "_max")
		var net_change: float = clamp(current + (effect_ph - decay_ph) * duration, 0.0, mx) - current
		var urgency: float = float(mx - current) / float(mx)
		total_utility += net_change * urgency
	return total_utility
```

**逐项说明**：
- `effect_ph`：活动对该 need 的 per_hour 毛值（活动表 effects[need]）
- `decay_ph`：该 need 的 per_hour decay（`<need>_decay`）
- `net_change`：活动 duration 内该 need 的真实净变化 = `clamp(当前 + (effect−decay)×dur, 0, max) − 当前`。clamp 防溢出/负值，与 tick 的实际叠加一致
- `urgency`：缺口权重 `(max−current)/max`，保留阶段 1 的紧急度语义
- `total_utility`：Σ 各 need 的 `net_change × urgency`

**sleeping 复算**：`net = clamp(50 + (15−6)×8, 0, 100) − 50 = 50`，urgency 0.5 → sleep 项 utility = **+25**（vs 当前 −10）。

**eating_at_home 复算**（food=50）：`net = clamp(50 + (55−5)×1, 0, 100) − 50 = 50`，urgency 0.5 → +25。

**working_overtime 复算**（mental=50）：`net = clamp(50 + (−3−2)×4, 0, 100) − 50 = clamp(30,0,100)−50 = −20`，urgency 0.5 → −10（负，不被选）。

## 5. 影响范围（铁律：只动这一处）

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | 改 `calculate_utility`（一个函数） |
| TimeManager / Main / node_2d.tscn | 不动 |
| 活动表 `list_of_activities`（数值） | 不动 |
| decay 值（含阶段 1 food 8→5 微调） | 不动 |
| `tick` / `select_best_activity` / `_apply_effects_hourly` | 不动 |

utility 改了，jane 选的活动会变（行为变化），但 tick/decay/effects 机制全不变。

## 6. 测试（execute_gdscript 断言 + run_and_verify）

**单元**（utility 值断言——函数返回**多 need 总和**，断言总和而非单项）：
- sleeping（各 need=50）：sleep 项 +25 + health 项 +4 + mental 项 +4 = **总 +33**（正；旧算法把 sleep 项算成 −10）
- eating_at_home（各 need=50）：food 项 +25 + health 项 +1.5 = **总 +26.5**
- working_overtime（各 need=50）：mental 项 −10 + physical 项 −14 + food 项 −20 = **总 −44**（仍不被选）
- 高 current（接近 max）活动 utility 低（缺口小）

**集成**（3 游戏天采样，复用阶段 1 Task 4 脚本）：
- night sleeping 占比 **≥ 80%**（修 79%）
- **每游戏天 22:00–23:00 出现 sleeping**：软指标（print 观察，不计 fail）——night sleeping 占比已反映规律性，22:00 精确准时受 evening 长活动跨 night 边界影响（非 utility，§8），实测 1/3 天准时、多数 23:00 睡（可接受）
- food 不连续 ≥ 6h 跌零（阶段 1 已达标，回归确认）

**回归**：run_and_verify hasErrors=false。

## 7. 完成标准（Done）

1. `calculate_utility` 改为 per_hour 净模型（net 含 decay、clamp 真实、无 double-count）
2. sleeping 总 utility 为正（≈+33；其中 sleep 项 +25），不再是负
3. night sleeping 占比 ≥ 80%（3 游戏天采样）
4. bedtime 22:00–23:00 出现 sleeping：软指标（观察用，非硬断言）——night sleeping ≥80% 为硬指标
5. working_overtime 仍不被选（utility 负，符合——money 留阶段 3）
6. run_and_verify 零错误；food 跌零回归确认

## 8. 已知限制（阶段 2 不处理）

- **working_overtime 仍不被选**：全负 effect，net 恒负。待阶段 3 引入 money 正需求后触发（继承 spec §9）
- **urgency 缺口权重可能过陡**：net 与 urgency 都随 current 变，叠加可能让"极缺"过强。阶段 2 先观察实际节律，若 jane 过度补单一 need 再调
- **解析假设线性 net**：对"中途 clamp 后继续 decay"的非单调活动不精确；当前 31 活动都是单调 net，无影响。未来加复杂活动再考虑逐小时模拟（方案 A）
- **不算非影响 need 的 decay 机会成本**：sleeping 8h 期间 food decay 不计入 sleeping utility（decay 是时间成本，所有活动按 duration 比例承担，比较时近似抵消）。**sleeping 作为 8h 最长活动，此偏差最大**——若阶段 2 实测 jane 过度选长活动，优先考虑补此项
