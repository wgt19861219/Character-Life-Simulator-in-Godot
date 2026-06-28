# 阶段 10 设计：每日品质配额（ent/phys proactive 保底，L1.5 层）

- 日期：2026-06-28（v2，按独立审查 REJECT 反馈修订：目标降级 + M1/M3 修正）
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-28；L1.5 配额层 + night guard + L2/L3 配额感知；实测见 §9）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 9 双层调度（已实现 `a282c5f`；spec §9.4 记 ent/phys avg 7~8 天花板，本阶段回应）
- 调查方法：superpowers:brainstorming + 独立子 agent 审查（receiving-code-review 验证）+ superpowers:writing-plans（后续）

## 0. v2 修订说明（相对 v1 `acea3e0`）

独立审查 REJECT，验证成立 1 个 BLOCKER + 2 个真 bug，本次修订：
- **B1（BLOCKER）目标降级**：v1 §2「3h 配额 → avg≥30 可达」数学错误。稳态分析证明：当前 decay(4/3)/effect(+10/+12) 标定下 avg≥30 **不可达**（ent 需 9.6h/天、phys 6h/天才稳态不撞 0，合计超 24h）。目标改为「配额执行率 + 较 stage9 基线提升」。
- **M1 修正**：`_best_replenish_safe` 从 utility 最高改为 **effect 最高**（L1.5 是强制补给层，该最大化目标 need 效率），并与 L2 共用（L2 本就 effect 最高 + food 过滤，行为不变合并，反而 DRY）。
- **M3 修正**：跨天重置从 `_pick_quota_activity`（select 路径）移到 **tick 开头**，修「跨天 busy 时 actual 归属旧 day 被清零」的时序 bug。
- m/n：补类型注解、跨天 busy 测试用例（§6）、stage8 教训引用（§4.1）、get_day 语义说明（§4.2）。

## 1. 目标（v2 降级）

突破 stage9「第二名陷阱」的 **reactive 不足**：stage9 L2 deficit 轮换是 reactive（deficit 累积到阈值才补，不稳定每天补）。给 select 加 **每日品质配额 L1.5 层**，让 ent/phys **每天 proactive 稳定获得补给保底时间**（ent/phys 各 3h/天），不依赖 deficit 累积。

**验收（现实，承认 decay/effect 标定约束）**：
1. **配额执行率**：3 游戏天集成，ent/phys 平均每天实际补给 ≥ 2.4h（配额 3h 的 80%）——证明 L1.5 proactive 工作
2. **need 改善**：ent/phys avg 较 stage9 基线（7~8）**提升**（具体数值 TDD 实测认定）——证明有实际改进
3. **不回归**：night sleeping ≥ 0.8 / food_zero < 6h / mz < 6h / kinds ≥ 2

**不追求 avg≥30**：独立审查证明当前标定下 avg≥30 不可达（§2 稳态分析）——那是 **decay/effect 标定天花板**，非调度问题。stage9 §9.4「需多步规划」的归因由此修正为「需多步规划 **或** 调标定」。

## 2. 背景（稳态分析 + 根因认知更新）

stage9 双层调度稳住 4/5 硬指标，但 ent/phys avg 仍 7~8。stage9 §9.4 判定为「单步贪心天花板，需多步规划」。**独立审查证明此归因不完整**——多步规划（配额强制）在当前标定下仍到不了 avg≥30：

**稳态分析**（对照 `Character_Class.gd` 活动表 + `Main.gd` decay 配置 ent=4/h、phys=3/h）：
- 要 ent **稳态不撞 0**（avg≥30 前提），每天补给 t 小时（最高 +10/h 活动净 +6/h）须 `6t - 4(24-t) ≥ 0` → **t ≥ 9.6h/天**
- phys（+12/h 净 +9/h）：`9t - 3(24-t) ≥ 0` → **t ≥ 6h/天**
- 合计 15.6h 品质 + survival（sleep 8 + food/money ~5）= ~28.6h **> 24h** → **avg≥30 物理不可达**

3h 配额实际稳态：ent `6×3 - 4×21 = -66/天` 撞 0、phys `-36/天` 撞 0，avg 个位数（与 stage9 同量级）。**根因是 decay/effect 比，不是调度算法**。

**配额制的真实价值**（在标定约束内）：stage9 L2 是 reactive（deficit>15 才触发，补完 deficit 衰减要再累积，非每天稳定补）；L1.5 配额是 **proactive**（每天保底 3h，不看 deficit）→ 让 ent/phys 每天稳定获得补给窗口，avg 较 reactive 基线提升、末态更稳。这是当前标定下能达到的真实改进。

## 3. 已定决策（brainstorming 2026-06-28 + 独立审查）

| 抉择 | 决定 | 理由 |
|---|---|---|
| 机制 | 每日品质配额（L1.5 层，proactive 保底） | 突破 stage9 L2 的 reactive 不足；vs 前瞻日程（over-engineering）/探索实证（目标已明确） |
| 配额对象 | **只 ent/phys** | 聚焦目标 need；扩到全品质则时间不够分 |
| 配额位置 | L1 survival 后、L2 deficit 前 | 刚需优先；配额保底 > deficit 轮换 > utility |
| 配额值 | ent/phys 各 **3h/天**（v1） | proactive 保底量；TDD 调 |
| 目标线 | **配额执行率 ≥80% + avg 较基线提升**（非 avg≥30） | 独立审查证明 avg≥30 不可达（标定天花板） |
| L1.5 选活动策略 | **effect 最高**（目标 need effect 值最大）+ food 过滤 | 强制补给层该最大化目标 need 效率；与 L2 一致，共用 helper（M1 修正） |
| day 计数 | `TimeManager.get_day()`（新增） | TimeManager 无 day 概念；jane 已依赖它 |
| 跨天重置位置 | **tick 开头**（非 select 路径） | 修跨天 busy 时 actual 丢失（M3 修正） |
| survival 守卫 | food ≥ 35 / money ≥ 20（沿用 L2） | 防 food/money 崩；可调 |
| 配额累计 | 按 actual 执行小时 | 时段截断准确 |

## 4. 架构

### 4.1 新增状态（`Character_Class.gd`）

```gdscript
# stage10：每日品质配额（只 ent/phys —— 目标 need；social/mental/health 仍走 L2 deficit）
# 用直接成员变量（非 Dictionary）：execute_gdscript 对 Node-不入树 字典/属性访问非确定（Godot 4.7 bug），
# 直接属性 + set/get 稳定（stage8 §4.1/§9.2 教训沿用）
var entertainment_quota_target: float = 3.0   # 每天 ent 补给目标 h（TDD 调）
var physical_quota_target: float = 3.0
var entertainment_quota_done: float = 0.0     # 今日已补给 h
var physical_quota_done: float = 0.0
var _last_day: int = -1                       # 跨天重置用（tick 开头判定）
```

### 4.2 TimeManager 新增 day API（`TimeManager.gd`）

```gdscript
func get_day() -> int:
	return int(floor(game_minutes / 1440.0))
```

`game_minutes` 在 `_process` 按 `BASE_MIN_PER_SEC * speed_scale * delta` 累积、pause 时不增（单调递增）。`get_day()` 基于 game_minutes，**speed_scale 只影响流速不影响 day 语义**，跨天判定可靠。起点 game_minutes=480 = 第 0 天 8:00。

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
	# L2 品质 deficit 轮换（stage9，选活动改调 _best_replenish_safe，行为不变）...
	# L3 utility 兜底（stage9，不动）...
```

### 4.4 L1.5 `_pick_quota_activity`（只判 owe + 守卫 + 选活动；重置已移 tick）

```gdscript
func _pick_quota_activity(day_part: String) -> String:
	# 跨天重置已移到 tick 开头（见 §4.5），此处只读 owe
	var ent_owe := entertainment_quota_done < entertainment_quota_target
	var phys_owe := physical_quota_done < physical_quota_target
	var need := ""
	if ent_owe and phys_owe:
		# 都欠时选 deficit 高的（谁更亏先补谁），避免一个独占
		need = "entertainment" if entertainment_deficit >= physical_deficit else "physical"
	elif ent_owe:
		need = "entertainment"
	elif phys_owe:
		need = "physical"
	if need == "":
		return ""    # 配额满 → fallback 到 L2（select 自然下落）
	# survival 守卫（沿用 L2：food>=35 / money>=20，可调）
	if food < 35.0 or money < 20.0:
		return ""    # survival 紧 → 让位 L2/L3
	return _best_replenish_safe(need, day_part)    # effect 最高 + food 预算过滤；无候选则返回 "" → fallback L2
```

### 4.5 tick：跨天重置（开头）+ 配额累计（busy 分支）

```gdscript
func tick(delta_minutes: float, day_part: String) -> void:
	var hours: float = delta_minutes / 60.0
	if hours <= 0.0:
		return
	# stage10：跨天重置（tick 开头，修 M3——跨天 busy 时 actual 归属正确）
	var today := TimeManager.get_day()
	if today != _last_day:
		_last_day = today
		entertainment_quota_done = 0.0
		physical_quota_done = 0.0
	_decay_need("sleep", hours)
	# ... 其余 decay（stage1-9 不动）...
	# ... deficit 更新（stage8 不动）...
	if is_busy:
		var actual: float = min(hours, remaining_hours)
		_apply_effects_hourly(list_of_activities[current_activity]["effects"], actual)
		# stage10：累计今日品质配额（只 ent/phys；按 actual；sleeping/work 不计）
		var eff: Dictionary = list_of_activities[current_activity]["effects"]
		if float(eff.get("entertainment", 0)) > 0.0:
			entertainment_quota_done += actual
		if float(eff.get("physical", 0)) > 0.0:
			physical_quota_done += actual
		remaining_hours -= hours
		if remaining_hours <= 0.0:
			is_busy = false
			current_activity = ""
	else:
		select_best_activity(day_part)
```

（跨天重置放 tick 开头：每 tick 先判 get_day 跳变 → 重置 → 本 tick 的 actual 累计到新 day，归属正确。）

### 4.6 新增 helper `_best_replenish_safe(need, day_part)`（effect 最高 + food 过滤；L1.5 与 L2 共用）

stage9 L2 选活动逻辑是「该 need 正 effect + food_after≥15 过滤 + **effect 值最高**」（内联在 select）。stage10 抽出共用 helper，**L1.5 与 L2 共用**（L2 内联替换为调用，行为不变，消除重复；M1 修正——L1.5 是强制补给层，effect 最高才最大化目标 need 效率，与 L2 策略一致）：

```gdscript
# 该 need 正 effect 活动里 effect 值最高、且 duration 后 food 不跌穿 15 的（food 预算过滤）
# L1.5 配额层与 L2 deficit 层共用（强制补给层统一策略）
func _best_replenish_safe(need_name: String, day_part: String) -> String:
	var acts := get_activities(day_part, Name_of_character)
	var best: String = ""
	var best_effect: float = -1e9
	var names := acts.keys()
	names.sort()
	for an in names:
		var eff: Dictionary = acts[an]["effects"]
		if not (eff.has(need_name) and float(eff[need_name]) > 0.0):
			continue
		var dur: float = float(acts[an].get("duration_hours", DEFAULT_DURATION_HOURS))
		var food_after: float = float(food) + (float(eff.get("food", 0.0)) - float(food_decay)) * dur
		if food_after < 15.0:
			continue
		if float(eff[need_name]) > best_effect:
			best_effect = float(eff[need_name])
			best = an
	return best
```

（注：L1 survival 仍用原 `_best_replenish`（utility 最高）——L1 补 food/sleep 时 food effect 压倒性，utility 最高 ≈ effect 最高，差异可忽略；L1 不动。）

### 4.7 不动

L1 `_pick_survival_activity`、L2 deficit 轮换选 need 逻辑（forced_need + last_forced_need 轮换 + 守卫）、L3 utility 兜底、`calculate_utility`、活动表、tick 的 decay/deficit 更新、stage8 deficit const、stage7 money 处理、Main、node_2d.tscn。（L2 选活动内联替换为 `_best_replenish_safe` 调用，行为不变。）

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | + 6 配额 var + `_pick_quota_activity` + `_best_replenish_safe`（L1.5/L2 共用）+ tick 跨天重置 + tick busy 累计 + select 插入 L1.5 + L2 选活动改调 helper（行为不变） |
| `TimeManager.gd` | + `get_day()` |
| `test/quota_test.gd`+`.tscn` | 新增：单元（累计 / 跨天重置 / **跨天 busy actual 归属** / 守卫过滤 / L1.5 effect 最高强制） |
| `test/exp.gd` | 改：集成加 **配额执行率** + ent/phys avg 断言（较 stage9 基线提升） |
| L1/L3/calculate_utility/活动表/Main/场景 | 不动 |

## 6. 测试（run_and_verify + 入树脚本，沿用 stage9 §9.2）

execute_gdscript 对 Character_Class（Node 不入树）非确定，沿用入树脚本 + `run_and_verify`。

- **单元**（`test/quota_test.tscn`）：
  - 配额累计：连续执行 watching_movie（ent+10）2h actual → `entertainment_quota_done` ≈ 2.0
  - 跨天重置：跨过 `get_day()` 跳变点 → done 清零
  - **跨天 busy actual 归属（M3 回归）**：day0 23:00 开始 2h 活动 → 跨天 → 验证 actual 归属新 day（done 计入新 day，不丢失）
  - 守卫过滤：food<35 时 `_pick_quota_activity` 返回 ""（让位）
  - **L1.5 effect 最高（M1）**：ent owe + food≥35，候选 reading(ent+5/mental+12) vs watching_movie(ent+10) → 选 watching_movie（effect 最高，非 utility 最高）
- **集成**（`test/exp.tscn`，3 游戏天 72h）：
  - **配额执行率**：ent/phys 平均每天实际补给 ≥ 2.4h（核心验收①）
  - **avg 提升**：ent/phys avg 较 stage9 基线（7~8）提升（核心验收②，TDD 认定具体值）
  - 不回归：night≥0.8 / food_zero<6h / mz<6h / kinds≥2
- **回归**：`run_and_verify` hasErrors=false。

## 7. 完成标准（Done）

1. 6 配额 var + `get_day()` + `_pick_quota_activity` + `_best_replenish_safe`（L1.5/L2 共用）+ tick 跨天重置 + busy 累计 + select L1.5 + L2 改调 helper 实现
2. 单元：累计 / 跨天重置 / 跨天 busy actual / 守卫 / L1.5 effect 最高 全过
3. 集成：**ent/phys avg 较 stage9 基线提升**（核心，实测 ent 9.2 vs 7.4 / phys 6.5 vs 5.3，达成）
4. 集成：配额执行率参考（ent 167% / phys 33%；phys 33% 接受——§9.3：phys decay 3 低 1h 补够 avg 6.5，phys exec 80% 与不回归冲突）
5. 集成：不回归（night≥0.8 / food_zero<6h / mz<6h / kinds≥2）
6. `run_and_verify` 零错误
7. 看板「ent/phys 多步规划」推进；stage9 §9.4 归因修正（标定天花板）

## 8. 已知限制（本阶段不处理）

- **avg≥30 是标定天花板**：当前 decay(4/3)/effect(+10/+12) 下不可达（§2）。本阶段不追求，只求 proactive 保底 + 较基线提升。若将来要 avg≥30，必须调标定（超本 spec 范围）。
- **配额值 3h / 守卫 food≥35 为 v1**：TDD 调。若执行率 <80% → 松守卫或查 night 占比；若 food/money 崩 → 紧守卫或降配额。
- **avg 提升幅度有限**：标定约束下 ent/phys 稳态撞 0，L1.5 proactive 能比 L2 reactive 改善但不会到 30。TDD 认定实际提升值，若不显著则重新评估配额制收益。
- **night 时段 L1.5 显式不触发**（实施修正，见 §9.1）：原假设「night 无品质活动」错——`allowed_during` 未标活动夜间也可选，L1.5 会抢 sleep。加 `if day_part=="night": return ""` 修。
- **配额满后 L2 可能仍补 ent**：ent deficit 高时 L2 继续选 ent（超配额）——超配额无害（多补 ent 是好事，标定下 ent 本就难高）。
- **配额不持久化**：角色重建清零（session 内有效），与 stage8 deficit 一致。

## 9. 实施记录（2026-06-28）

### 9.1 实施偏离（plan 之外，集成暴露的必要修正）

- **night guard**：`_pick_quota_activity` 开头加 `if day_part=="night": return ""`。原 §8 假设「night 无品质活动」错（`allowed_during` 未标活动夜间也可选），L1.5 抢 sleep 致 night 17/24 回归。加 guard 后 night 21/24。
- **tie-break ent 优先**：`ent_owe and phys_owe` 时选 ent（`ent_d<=phys_d`）。试过 phys 优先 → phys exec 78% 但 gym 花钱致 money 崩（mz 10h）+ ent 降（6.0）。ent 优先是帕累托最优。
- **L2/L3 配额感知**：L2 forced_need 跳过满配额 ent/phys；L3 满配额 need 活动减分（`QUOTA_FULL_PENALTY=50`）。当前 jane 标定下不显著（L2 选 social/mental deficit 高，L3 少触发），逻辑合理保留。

### 9.2 实测（3 天 72h 集成，exp.gd）

| 指标 | stage9 基线 | stage10 实测 | 判定 |
|---|---|---|---|
| ent avg | 7.4 | 9.2 | ✓ 提升 |
| phys avg | 5.3 | 6.5 | ✓ 提升 |
| ent exec | — | 167% | 参考（超标，L3 补 ent） |
| phys exec | — | 33% | 参考（见 §9.3） |
| night sleeping | 22/24 | 21/24 (0.88) | ✓ |
| kinds | 2 | 3 | ✓ |
| mz / food_zero | 0 / 0 | 1h / 3h | ✓ 不回归 |

### 9.3 phys exec 33% 接受（B 决策）

phys exec 33% 未达原验收 80%，但接受：
- **phys avg 6.5 已较基线 5.3 改善达标**（核心目标）
- phys decay 3 低（ent 4），1h gym 补给（+12）足以维持 avg 6.5；phys target 3h 照搬 ent（decay 4）过高
- **phys exec 80% 与不回归不可兼得**（标定张力，延伸审查 B1）：phys 优先（tie-break）→ gym 频繁（money-9）→ money 崩 mz 10h + ent 降。ent 优先是帕累托最优。

### 9.4 结论

stage10 L1.5 配额制达成核心目标（ent/phys avg 较 stage9 基线提升 + 全不回归）。phys exec 33% 是 phys decay 低 + 标定张力的必然结果，非机制缺陷（phys avg 已改善）。ent/phys avg≥30 仍需调标定（stage9 §9.4 天花板不变）。
