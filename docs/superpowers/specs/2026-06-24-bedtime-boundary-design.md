# 阶段 6 设计：bedtime 时段边界（活动不跨 day_part）

- 日期：2026-06-24
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-24；活动 duration clamp 到 day_part 剩余，night sleeping=22/24（18→22），evening 长活动不跨夜 overflow=false，消费多样 kinds=2→3；money 卡 0 为 clamp 副作用（活动变短频次高）+ stage3 work 时机标定，记看板待办）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 5 recency 轮换（已实现，main 258e9a9）

## 1. 目标

活动执行不跨 day_part 边界（duration clamp 到时段剩余），消除 evening 长活动（party 等）溢出到 night 占睡眠。完成 = night sleeping 从 18/24 提升到 ≥22/24，sleeping 22:00 准时睡满 8h，消费多样/recency/money 不回归，run_and_verify 零错误。

## 2. 背景（night 18/24 根因）

stage5 集成诊断：night sleeping 18/24。NIGHT_ACTS={party:3, "":3, sleeping:18}。根因：evening 21:00 jane 选 3h party（utility 最高，recency 首选=0 罚不到），tick 里活动持续到 remaining_hours=0 **不检查 day_part 变化**，party 跨到 night 22:00-00:00（3h 溢出，占走 2h 睡眠 + 边界 idle）。

recency 调标实测无效（PENALTY 10/12/14/16 完全无差异）——因 party 首选 recency=0。根因是**时段边界无约束**，非 utility 标定。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 方向 | 活动不跨 day_part（机制层） | 根治溢出主因，最小改动；vs sleeping 优先（不阻溢出）/ 中断式（改动大） |
| 长活动不够剩余 | duration clamp 到时段剩余（非排除/非例外） | 统一规则无死锁；排除式会无活动可选，sleeping 例外分两类 |
| 边界范围 | 所有 day_part 边界统一 clamp | 行为一致（不只 night） |
| sleeping 恢复 | clamp 不补足（晚选恢复略少） | evening 不溢出保证 22:00 准时选 sleeping 8h 满；晚选 clamp 是边际情况 |

## 4. 架构

### 4.1 TimeManager.gd：抽 const 单一来源 + 两函数查表

边界真相单一来源（Q1B，消除 get_day_part 与 get_day_part_remaining 的边界重复）：
```gdscript
const DAY_PART_BOUNDS = {
	"night": [22, 6],     # [start, end]；end < start 表示跨日
	"morning": [6, 12],
	"afternoon": [12, 18],
	"evening": [18, 22],
}

# get_day_part 重构为查表（behavior-preserving，边界 22/6/12/18 与原 if/elif 一致，§6 测试守护）
func get_day_part() -> String:
	var h := get_hour()
	for dp in DAY_PART_BOUNDS:
		var s: int = DAY_PART_BOUNDS[dp][0]
		var e: int = DAY_PART_BOUNDS[dp][1]
		if e > s:
			if h >= s and h < e:
				return dp
		else:
			if h >= s or h < e:   # 跨日（night: 22-24 或 0-6）
				return dp
	return "night"   # fallback（理论不可达）

func get_day_part_remaining_hours() -> float:
	var end_hour: int = DAY_PART_BOUNDS[get_day_part()][1]
	var cur_min := float(int(floor(game_minutes)) % 1440)
	var diff := float(end_hour * 60) - cur_min
	if diff <= 0.0:
		diff += 1440.0   # night 跨日
	return diff / 60.0
```

### 4.2 Character_Class.select_best_activity 改动

选中后 remaining_hours clamp 到时段剩余：
```gdscript
if best_activity != "":
	current_activity = best_activity
	activity_recency[best_activity] = 1.0
	remaining_hours = min(list_of_activities[best_activity].get("duration_hours", DEFAULT_DURATION_HOURS), TimeManager.get_day_part_remaining_hours())
	is_busy = true
```

### 4.3 不动

calculate_utility / _apply_effects_hourly / _decay_need / tick 主体 / 活动表 / node_2d.tscn / Main 不动。tick 里 `actual = min(hours, remaining_hours)` 已有，clamp 后自动按截断时长算 effects。

> 注：get_day_part 重构为查 const 表（§4.1），behavior-preserving——边界 22/6/12/18 与原 if/elif 完全一致，由 §6 单元测试守护（T2 重构守护）。

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `TimeManager.gd` | + DAY_PART_BOUNDS const + get_day_part_remaining_hours() + 重构 get_day_part 查表（行为保持，§6 测试守护） |
| `Character_Class.gd` | select_best_activity remaining_hours clamp |
| calculate_utility / effects / 活动表 / tick 主体 / Main / 场景 | 不动 |

## 6. 测试（execute_gdscript + run_and_verify）

**单元**：
- **get_day_part 重构守护**：各时段边界前后返回值不变——21:59→evening、22:00→night、05:59→night、06:00→morning、11:59→morning、12:00→afternoon、17:59→afternoon、18:00→evening（守护 §4.1 refactor）
- evening 边界：game_minutes=21:00（1260），select 后 remaining_hours ≤ 1.0（party 3h clamp 到 1h）
- night 满：game_minutes=22:00（1320），select sleeping → remaining_hours ≈ 8.0
- night clamp：game_minutes=23:00（1380），select sleeping → remaining_hours ≈ 7.0
- morning/afternoon 边界：剩余正确（8:00→4h 到 12:00、14:00→4h 到 18:00）

**集成**（3 游戏天，沿用 stage5 集成测试框架）：
- **T1 night sleeping 测量**：占比 = Σ(sleeping 在 night 的 actual hours) / (3天×8 night 小时) ≥ 22/24（沿用 stage5 NIGHT_ACTS 累计器；party 不溢出 → sleeping 22:00 准时睡满）
- **T2a evening 长活动 clamp**：party/concert/spa 在 evening 选时 clamp ≤ evening 剩余，不跨夜（night 时段无 evening 溢出活动）
- **T2b afternoon work clamp**：working_overtime 被选时 clamp ≤ afternoon 剩余，3 天 money 仍流动（work 1-6、不卡 0、不异常触顶）
- 消费多样不回归（kinds ≥ 2，recency 仍生效）
- jane 节律正常（food/sleep 不崩）

**回归**：run_and_verify hasErrors=false。

## 7. 完成标准（Done）

1. TimeManager：+ DAY_PART_BOUNDS const + get_day_part_remaining_hours()（night 跨日正确）+ get_day_part 重构查表；get_day_part 重构守护测试通过（8 边界返回值不变）
2. select_best_activity remaining_hours clamp 到时段剩余
3. 单元：evening/night/morning/afternoon 边界 remaining 正确（含 get_day_part 重构守护）
4. 集成：night sleeping ≥ 22/24（从 18 提升）
5. 不回归：消费多样/recency/money/节律
6. run_and_verify 零错误

## 8. 已知限制（本阶段不处理）

- **sleeping 晚选 clamp 不补足**：jane 若晚于 22:00 选 sleeping，时长 clamp 到 night 剩余（<8h），恢复略少。由 evening 不溢出保证准时选，属边际情况
- **tick 步进粒度**：测试 1h 步进、运行 real-time。clamp 在 select 时算（基于 game_minutes），粒度内一致
- **不引入 bedtime 概念/中断**：本阶段只 clamp 时长，不做"22:00 强制中断"（中断式否决）。bedtime 语义靠 night sleeping（night idle 已选 sleeping）+ 不溢出达成
- **night 跨日边界 06:00**：get_day_part_remaining night 算到 06:00（与 get_day_part night 定义 22:00-06:00 一致）
- **Character_Class → TimeManager 耦合**：select_best_activity 调 TimeManager.get_day_part_remaining_hours()（autoload 查时间源，选最小改动 vs 改 tick 签名传参）。Q2 死初始化（var 初始化后必被赋值）等小项 plan 阶段顺手处理
