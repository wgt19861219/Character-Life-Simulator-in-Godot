# 阶段 10 设计：每日品质配额（ent/phys 多步规划，L1.5 层）

- 日期：2026-06-28
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：设计中（designing 2026-06-28；brainstorming 产出，待 writing-plans）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 9 双层调度（已实现 `a282c5f`；spec §9.4 记 ent/phys avg 7~8 = 单步贪心天花板，本阶段突破）
- 调查方法：superpowers:brainstorming（时间预算分析 + 方案对比）+ superpowers:writing-plans（后续）

## 1. 目标

突破 stage9 §9.4 的单步贪心天花板：给 jane 的 select 加 **每日品质配额（daily quota）**，每天强制给 ent/phys 各预留 N 小时补给时间，使 **ent/phys avg ≥ 30**（3 游戏天集成），且不回归 stage1-9 任何硬指标。

机制：在 stage9 双层调度的 L1 survival 与 L2 deficit 之间插入 **L1.5 配额层**——今日未达配额的 ent/phys，在 survival 守卫满足时强制补给，绕过单步贪心「永远把品质时间让给 survival 边际效用」的缺陷。

## 2. 背景（时间预算分析 + 根因）

stage9 双层调度稳住 4/5 硬指标，但 ent/phys avg 仍 7~8，远低于 stage8 §7 健康线 ≥30。stage9 spec §9.4 判定为单步贪心架构天花板。本阶段先做时间预算分析确认 **avg≥30 数学可达**，再用配额制突破：

**jane 一天 24h 时间账**：
- sleep 8h（night 刚需，不可压缩）
- food ~5h（decay 5/h，每 3-4h 吃一次）
- money ~3h（decay 1.5/h，1-2 天一个 4h work session 均摊）
- survival 合计 ~16h，剩 **~8h 给品质 need**

8h 够给 **ent 3h + phys 3h + 其他 2h**。ent/phys decay 4/3 per h，稳定每天 3h 配额 → ent/phys 在 20~40 区间波动 → **avg≥30 可达**。

**根因（非时间不够）**：单步贪心每步选 utility #1，survival（food/money/sleep）边际效用永远更高，品质 8h 被浪费在反复补 survival 上（stage9 §2 的 max-choose「永远的第二名」）。**瓶颈是不主动分配品质时间**。配额制 = 提前锁定「今天 ent/phys 各 3h」保底时间，survival 只占该占的。

## 3. 已定决策（brainstorming 2026-06-28）

| 抉择 | 决定 | 理由 |
|---|---|---|
| 机制 | 每日品质配额（L1.5 层，强制保底时间） | 绕过单步贪心不分配；vs 前瞻日程（jane 小规模 over-engineering）/探索实证（目标已明确，无需探索） |
| 配额对象 | **只 ent/phys** | 聚焦 avg≥30 目标 need；扩到全品质则 8h 不够分，ent/phys 反而难达 3h |
| 配额位置 | L1 survival 后、L2 deficit 前 | 刚需永远优先；配额是「保底时间」> deficit 轮换 > utility |
| 配额值 | ent/phys 各 **3h/天**（v1） | 时间预算算出；TDD 集成调 |
| day 计数 | `TimeManager.get_day()`（新增 API） | TimeManager 当前无 day 概念（只 `% 1440`）；jane 已依赖 TimeManager，加查询 API 一致 |
| survival 守卫 | food ≥ 35 / money ≥ 20（沿用 L2） | 防 food/money 崩；与 L2 守卫一致，可调 |
| 配额累计 | 按 actual 执行小时 | 活动可能被时段边界截断，actual 准确 |

## 4. 架构

### 4.1 新增状态（`Character_Class.gd`）

```gdscript
# stage10：每日品质配额（只 ent/phys —— 目标 need；social/mental/health 仍走 L2 deficit）
var entertainment_quota_target: float = 3.0   # 每天 ent 补给目标 h（TDD 调）
var physical_quota_target: float = 3.0
var entertainment_quota_done: float = 0.0     # 今日已补给 h
var physical_quota_done: float = 0.0
var _last_day: int = -1                       # 跨天重置用
```

### 4.2 TimeManager 新增 day API（`TimeManager.gd`）

```gdscript
func get_day() -> int:
	return int(floor(game_minutes / 1440.0))
```

（TimeManager 当前 `game_minutes` 起点为 480 = 第 0 天 8:00；`get_day()` 返回 0,1,2,…。jane 用它判跨天重置配额。）

### 4.3 `select_best_activity` 插入 L1.5 层

```gdscript
func select_best_activity(day_part: String) -> void:
	# L1 survival 强制（stage9，不动）
	var surv := _pick_survival_activity(day_part)
	if surv != "":
		_commit_activity(surv)
		return
	# L1.5 品质配额（stage10）：今日未达配额的 ent/phys，守卫满足则强制补给
	var quota := _pick_quota_activity(day_part)
	if quota != "":
		_commit_activity(quota)
		return
	# L2 品质 deficit 轮换（stage9，不动）...
	# L3 utility 兜底（stage9，不动）...
```

### 4.4 L1.5 `_pick_quota_activity`

```gdscript
func _pick_quota_activity(day_part: String) -> String:
	# 跨天重置（每天 0 点：get_day() 跳变）
	var today := TimeManager.get_day()
	if today != _last_day:
		_last_day = today
		entertainment_quota_done = 0.0
		physical_quota_done = 0.0
	# 找未达配额的目标 need（都欠时选 deficit 高的，避免一个独占）
	var ent_owe := entertainment_quota_done < entertainment_quota_target
	var phys_owe := physical_quota_done < physical_quota_target
	var need := ""
	if ent_owe and phys_owe:
		need = "entertainment" if entertainment_deficit >= physical_deficit else "physical"
	elif ent_owe:
		need = "entertainment"
	elif phys_owe:
		need = "physical"
	if need == "":
		return ""
	# survival 守卫（沿用 L2：food>=35 / money>=20，可调）
	if food < 35.0 or money < 20.0:
		return ""
	return _best_replenish_safe(need, day_part)
```

### 4.5 配额累计（`tick` 的 is_busy 分支）

按 actual 执行小时累加（活动可能被时段边界截断），在 `_apply_effects_hourly` 之后：

```gdscript
	if is_busy:
		var actual: float = min(hours, remaining_hours)
		_apply_effects_hourly(list_of_activities[current_activity]["effects"], actual)
		# stage10：累计今日品质配额（只 ent/phys；按 actual，sleeping/work 不计）
		var eff = list_of_activities[current_activity]["effects"]
		if float(eff.get("entertainment", 0)) > 0.0:
			entertainment_quota_done += actual
		if float(eff.get("physical", 0)) > 0.0:
			physical_quota_done += actual
		remaining_hours -= hours
		...
```

### 4.6 新增 helper `_best_replenish_safe(need, day_part)`

stage9 已有 `_best_replenish(need, day_part)`（该 need 正 effect 活动里 **utility 最高**，L1 survival 用）和 L2 内联的 `food_after >= 15` 过滤（L2 按 **effect 值最高**选，策略与 `_best_replenish` 不同）。stage10 新增 **L1.5 专用** helper：在 `_best_replenish`（utility 最高）基础上加 food 预算过滤：

```gdscript
# 该 need 正 effect 活动里 utility 最高的，且 duration 后 food 不跌穿 15（food 预算过滤）
func _best_replenish_safe(need_name: String, day_part: String) -> String:
	var acts := get_activities(day_part, Name_of_character)
	var best := ""
	var best_u := -1e9
	var names := acts.keys()
	names.sort()
	for an in names:
		var eff = acts[an]["effects"]
		if not (eff.has(need_name) and float(eff[need_name]) > 0.0):
			continue
		var dur := float(acts[an].get("duration_hours", DEFAULT_DURATION_HOURS))
		var food_after: float = float(food) + (float(eff.get("food", 0.0)) - float(food_decay)) * dur
		if food_after < 15.0:
			continue
		var u := calculate_utility(acts[an])
		if u > best_u:
			best_u = u
			best = an
	return best
```

### 4.7 不动

L1 `_pick_survival_activity`、L2 deficit 轮换逻辑、L3 utility 兜底、`calculate_utility`、活动表、tick 的 decay/deficit 更新、stage8 deficit const、stage7 money 处理、Main、node_2d.tscn。（L2 保持 stage9 原样：按 effect 值最高 + 内联 food 过滤，与 L1.5 的 utility 最高策略不同，不强行合并。）

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | + 6 个配额 var + `_pick_quota_activity` + `_best_replenish_safe`（L1.5 专用）+ tick 累计 + select 插入 L1.5；L2 不动 |
| `TimeManager.gd` | + `get_day()` |
| `test/quota_test.gd`+`.tscn` | 新增：单元（配额累计 / 跨天重置 / 守卫过滤 / L1.5 强制） |
| `test/exp.gd` | 改：集成加 ent/phys **avg** 断言（avg≥30） |
| L1/L3/calculate_utility/活动表/tick decay-defects/Main/场景 | 不动 |

## 6. 测试（run_and_verify + 入树脚本，沿用 stage9 §9.2）

execute_gdscript 对 Character_Class（Node 不入树）非确定（Godot 4.7 bug），沿用 stage9 方案：**入树脚本** + `run_and_verify`。

- **单元**（`test/quota_test.tscn`）：
  - 配额累计：连续执行 reading（ent+5）2h actual → `entertainment_quota_done` ≈ 2.0
  - 跨天重置：跨过 `get_day()` 跳变点 → done 清零
  - 守卫过滤：food<35 时 `_pick_quota_activity` 返回 ""（让位 L1 survival/L2）
  - L1.5 强制：ent 配额未达 + food≥35 → 选 ent 正 effect 活动（即使 utility 非 #1）
- **集成**（`test/exp.tscn`，3 游戏天 72h）：ent/phys **avg ≥ 30**（核心验收）+ 不回归全指标。
- **回归**：`run_and_verify` hasErrors=false。

## 7. 完成标准（Done）

1. 6 配额 var + `get_day()` + `_pick_quota_activity` + `_best_replenish_safe` + tick 累计 + select L1.5 插入 实现
2. 单元：配额累计 / 跨天重置 / 守卫过滤 / L1.5 强制 正确
3. 集成：**ent/phys avg ≥ 30**（3 天，核心目标，突破 stage9 天花板）
4. 集成：不回归（night ≥ 0.8 / food_zero < 6h / mz < 6h / kinds ≥ 2）
5. `run_and_verify` 零错误
6. 看板「ent/phys 多步规划」架构课题推进/关闭

## 8. 已知限制（本阶段不处理）

- **配额值 3h 为 v1**：TDD 集成调。若 avg 不到 30 → 升配额或松守卫；若 food/money 崩 → 降配额或紧守卫（stage8 WEIGHT 同款权衡）。
- **守卫 food≥35 偏严**：food 在 25~35 区间时 L1.5 让位（给 food buffer），可能压缩配额执行窗口；若实测 ent/phys 仍低，可松到 30。
- **night 时段 L1.5 自然不触发**：night 无 ent/phys 活动可选，L1 survival（sleep）接管，符合预期。
- **配额满后 L2 可能仍补 ent**：ent deficit 高时 L2 会继续选 ent，导致 ent 超配额——超配额无害（只是超保底），接受。
- **配额不持久化**：角色重建清零（session 内有效），与 stage8 deficit 一致。
- **若 A 实测仍达不到 avg≥30**：升级到方案 B（前瞻日程）作为 fallback，超本 spec 范围。
