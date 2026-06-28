# 阶段 10：每日品质配额（ent/phys proactive 保底，L1.5 层）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 给 jane 的 select 加每日品质配额 L1.5 层，让 ent/phys 每天 proactive 稳定获得补给保底时间（各 3h/天），使 3 游戏天集成「配额执行率 ≥80% + ent/phys avg 较 stage9 基线提升」，且不回归 stage1-9 任何硬指标。

**Architecture:** `select_best_activity` 在 L1 survival 与 L2 deficit 之间插入 L1.5 `_pick_quota_activity`（今日未达配额的 ent/phys + survival 守卫满足 → 强制补给，绕过单步贪心不分配品质时间）。配额按 actual 执行小时累计（tick busy 分支），跨天在 tick 开头重置（修跨天 busy 时序 bug）。新增 `_best_replenish_safe(need, day_part)`（effect 最高 + food 预算过滤），L1.5 与 L2 共用（L2 内联替换，行为不变）。

**Tech Stack:** Godot 4.7 stable / GDScript（tab 缩进）/ 无 GUT（测试用入树脚本 `test/*.tscn` 挂 `extends Node` + `run_and_verify`；execute_gdscript 对 Node 非确定已弃，见 spec §4.1/§6）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-28-stage10-quality-quota-design.md`

## Global Constraints（沿用 stage1-9）

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- Godot 4.7 stable（run_and_verify 用）
- GDScript 用 **tab 缩进**（项目惯例，不可用空格）
- 不引入 GUT 测试框架；测试用入树脚本（`test/quota_test.tscn` 挂 `test/quota_test.gd` extends Node）+ `mcp__godot__validation` 的 `run_and_verify`（`scene=res://test/quota_test.tscn`）；execute_gdscript 对 Character_Class（Node 不入树）属性/字典访问非确定，已弃（stage8 §9.2 / stage9 §9.2）
- jane config decay（Main.gd，测试须一致）：sleep=6/food=5/ent=4/social=3/health=1/physical=3/mental=2/money=1.5；所有 max=100
- 中节奏：1 现实秒 = 5 游戏分
- stage1-9 全不动：L1 `_pick_survival_activity`、L2 选 need 逻辑（forced_need + last_forced_need 轮换 + 守卫）、L3 utility 兜底、`calculate_utility`、活动表 `list_of_activities`、tick 的 decay/deficit 更新、stage8 deficit const、stage7 money 处理、Main、node_2d.tscn
- 每个 Task 的 commit 命令给出，但**是否 commit 由用户在执行 handoff 时确认**（项目全局规则：不主动 commit）
- 用户偏好 **inline 执行**（跳过 subagent，直接接手）

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `TimeManager.gd` | 时间系统 | + `get_day()`（game_minutes/1440） |
| `Character_Class.gd` | 角色调度 | + 6 配额 var + `_pick_quota_activity` + `_best_replenish_safe`（L1.5/L2 共用）+ tick 跨天重置 + tick busy 累计 + select 插入 L1.5 + L2 选活动改调 helper（行为不变） |
| `test/quota_test.gd`+`.tscn` | 单元测试 | 新建：get_day / 累计 / 跨天重置 / 跨天 busy actual / 守卫 / L1.5 effect 最高 |
| `test/exp.gd` | 集成 runner | 改：加配额执行率 + ent/phys avg 断言 |
| spec / Obsidian 日志 / 看板 | 归档 | spec 状态改 implemented；新增日志；推进看板 |

不动：L1/L3/calculate_utility/活动表/tick decay-deficit/Main/场景。

---

### Task 1: TimeManager.get_day() + 单元测试框架

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\TimeManager.gd`（+ `get_day`，约 60 行后）
- Create: `D:\GitHub\Character-Life-Simulator-in-Godot\test\quota_test.gd`（测试脚本）
- Create: `D:\GitHub\Character-Life-Simulator-in-Godot\test\quota_test.tscn`（root Node 挂 quota_test.gd）

**Interfaces:**
- Produces: `TimeManager.get_day() -> int`（public，返回 game_minutes/1440 的 floor）。Task 2 的 tick 跨天重置消费它。

- [ ] **Step 1: 写失败测试（quota_test.gd + 建 .tscn）**

创建 `test/quota_test.gd`：

```gdscript
extends Node

func _ready() -> void:
	var fail: Array = []
	_test_get_day(fail)
	print("QUOTA_TEST PASS" if fail.is_empty() else "QUOTA_TEST FAIL " + str(fail))
	get_tree().quit()

# Task 1：get_day 基于 game_minutes/1440
func _test_get_day(fail: Array) -> void:
	TimeManager.game_minutes = 480.0    # 第0天 8:00
	if TimeManager.get_day() != 0:
		fail.append("get_day(480)=期望0 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 1440.0   # 第1天 0:00
	if TimeManager.get_day() != 1:
		fail.append("get_day(1440)=期望1 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 1920.0   # 第1天 8:00
	if TimeManager.get_day() != 1:
		fail.append("get_day(1920)=期望1 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 2880.0   # 第2天 0:00
	if TimeManager.get_day() != 2:
		fail.append("get_day(2880)=期望2 得%d" % TimeManager.get_day())
```

建场景 `test/quota_test.tscn`（root Node 挂 `res://test/quota_test.gd`）：用 `mcp__godot__scene` `quick_scene`（scene_path=`res://test/quota_test.tscn`, root_node_type=`Node`, root_node_name=`QuotaTest`, script_path=`res://test/quota_test.gd`）。

- [ ] **Step 2: 跑测试，确认 FAIL（get_day 未定义）**

`mcp__godot__validation` `run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=true`，含 `Identifier "get_day" not declared`（方法不存在）。

- [ ] **Step 3: 实现 get_day**

`TimeManager.gd`，在 `get_day_part_remaining_hours` 之后追加：

```gdscript
func get_day() -> int:
	return int(floor(game_minutes / 1440.0))
```

- [ ] **Step 4: 跑测试，确认 PASS**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=false`，输出含 `QUOTA_TEST PASS`。

- [ ] **Step 5: Commit（待用户确认）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add TimeManager.gd test/quota_test.gd test/quota_test.tscn && git commit -m "feat(stage10): add TimeManager.get_day + quota unit test harness"
```

---

### Task 2: 配额状态 + tick 跨天重置 + busy 累计 + 单元（累计 / 跨天重置 / 跨天 busy actual）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（+ 6 var 约 60 行；tick 跨天重置约 138 行；tick busy 累计约 161 行）
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\test\quota_test.gd`（+ 3 个 _test_*）

**Interfaces:**
- Consumes: Task 1 的 `TimeManager.get_day()`
- Produces: 6 配额成员（`entertainment_quota_target/done`、`physical_quota_target/done`、`_last_day`）；tick 每步跨天重置 + busy 按 actual 累计。Task 4 的 `_pick_quota_activity` 消费 `*_done`/`*_target`。

- [ ] **Step 1: 写失败测试（追加 3 个 _test_*）**

`test/quota_test.gd` 的 `_ready` 改为：

```gdscript
func _ready() -> void:
	var fail: Array = []
	_test_get_day(fail)
	_test_quota_accrual(fail)
	_test_quota_day_reset(fail)
	_test_quota_cross_day_busy(fail)
	print("QUOTA_TEST PASS" if fail.is_empty() else "QUOTA_TEST FAIL " + str(fail))
	get_tree().quit()
```

追加测试函数（cfg 与 Main.gd 一致）：

```gdscript
const CFG := {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":1.5}

# Task 2：按 actual 累计品质配额（reading: ent+5；2h actual → done=2）
func _test_quota_accrual(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.current_activity = "reading"
	j.is_busy = true
	j.remaining_hours = 2.0
	TimeManager.game_minutes = 600.0    # 第0天 10:00 afternoon
	for i in range(2):
		j.tick(60.0, "afternoon")       # 2 步 ×1h actual
	if abs(j.entertainment_quota_done - 2.0) > 0.01:
		fail.append("accrual: ent done=期望2.0 得%.2f" % j.entertainment_quota_done)

# Task 2：跨天重置（get_day 跳变 → done 清零）
func _test_quota_day_reset(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.entertainment_quota_done = 2.5
	j.physical_quota_done = 1.0
	j._last_day = 0
	TimeManager.game_minutes = 1440.0   # 跳到第1天
	j.tick(60.0, "night")               # tick 开头检测跨天 → 重置
	if abs(j.entertainment_quota_done) > 0.01 or abs(j.physical_quota_done) > 0.01:
		fail.append("day_reset: 未清零 ent=%.2f phys=%.2f" % [j.entertainment_quota_done, j.physical_quota_done])

# Task 2：跨天 busy 时 actual 归新 day（M3 回归——不丢失）
func _test_quota_cross_day_busy(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.current_activity = "reading"      # ent+5，跨夜持续
	j.is_busy = true
	j.remaining_hours = 3.0
	j.entertainment_quota_done = 2.0    # 旧 day 已累计 2h
	j._last_day = 0
	TimeManager.game_minutes = 1440.0   # 第1天 0:00（刚跨天）；tick 不推进 game_minutes，故直接设跨天后
	j.tick(60.0, "night")               # tick 开头: today=1≠0 → 重置 done=0；busy actual=1h → done=1.0（归新 day）
	if j._last_day != 1:
		fail.append("cross_day: _last_day=期望1 得%d" % j._last_day)
	# 重置后从 0 计 actual=1h：证明跨天 actual 归新 day（M3 修正正确；未修则 2.0+1.0=3.0 混入旧 day）
	if abs(j.entertainment_quota_done - 1.0) > 0.01:
		fail.append("cross_day: ent done=期望1.0(归新day) 得%.2f" % j.entertainment_quota_done)
```

- [ ] **Step 2: 跑测试，确认 FAIL（配额成员未定义）**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=true`，含 `Identifier "entertainment_quota_done" not declared`。

- [ ] **Step 3: 加 6 个配额成员**

`Character_Class.gd`，在 `FORCE_DEFICIT_THRESHOLD` 那行（约 60 行）之后插入：

```gdscript
# stage10：每日品质配额（只 ent/phys —— 目标 need；social/mental/health 仍走 L2 deficit）
# 直接成员变量（非 Dictionary）：execute_gdscript 对 Node 字典/属性非确定，直接属性稳定（stage8 §4.1 教训）
var entertainment_quota_target: float = 3.0   # 每天 ent 补给目标 h（Task5 集成调）
var physical_quota_target: float = 3.0
var entertainment_quota_done: float = 0.0     # 今日已补给 h
var physical_quota_done: float = 0.0
var _last_day: int = -1                       # 跨天重置用（tick 开头判定）
```

- [ ] **Step 4: tick 加跨天重置（开头）+ busy 累计**

`Character_Class.gd` 的 `tick`，把开头：

```gdscript
	var hours: float = delta_minutes / 60.0
	if hours <= 0.0:
		return
	_decay_need("sleep", hours)
```

改为：

```gdscript
	var hours: float = delta_minutes / 60.0
	if hours <= 0.0:
		return
	# stage10：跨天重置（tick 开头，修跨天 busy actual 归属）
	var today: int = TimeManager.get_day()
	if today != _last_day:
		_last_day = today
		entertainment_quota_done = 0.0
		physical_quota_done = 0.0
	_decay_need("sleep", hours)
```

再把 is_busy 分支：

```gdscript
	if is_busy:
		var actual: float = min(hours, remaining_hours)
		_apply_effects_hourly(list_of_activities[current_activity]["effects"], actual)
		remaining_hours -= hours
		if remaining_hours <= 0.0:
			is_busy = false
			current_activity = ""
```

改为：

```gdscript
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
```

- [ ] **Step 5: 跑测试，确认 PASS**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=false`，输出含 `QUOTA_TEST PASS`。

- [ ] **Step 6: Commit（待用户确认）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add Character_Class.gd test/quota_test.gd && git commit -m "feat(stage10): quota state + tick day-reset + busy accrual"
```

---

### Task 3: `_best_replenish_safe` helper（effect 最高 + food 过滤）+ L2 改调 + 单元

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（+ `_best_replenish_safe` 约 213 行后；L2 内联替换约 254-275 行）
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\test\quota_test.gd`（+ `_test_best_replenish_safe`）

**Interfaces:**
- Consumes: 无新依赖（复用 `get_activities`/`calculate_utility`/活动表）
- Produces: `_best_replenish_safe(need_name: String, day_part: String) -> String`（该 need 正 effect + food_after≥15 活动里 effect 值最高）。Task 4 的 L1.5 消费它；L2 改调它（行为不变）。

- [ ] **Step 1: 写失败测试（effect 最高 + food 过滤）**

`test/quota_test.gd` 的 `_ready` 追加 `_test_best_replenish_safe(fail)`，并加函数：

```gdscript
# Task 3：_best_replenish_safe 选 effect 最高（非 utility 最高）+ food 预算过滤（M1）
func _test_best_replenish_safe(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	# 场景：ent 低 + mental 也低 → reading(ent+5/mental+12) utility 可能高，但 effect 最高是 watching_movie(ent+10)
	var j = C.new(CFG)
	j.entertainment = 10.0
	j.mental = 10.0
	j.food = 80.0      # food 充足，不触发 food 预算过滤
	j.money = 80.0
	var picked = j._best_replenish_safe("entertainment", "afternoon")
	if picked != "watching_movie":
		fail.append("effect_max: 期望watching_movie(ent+10) 得%s" % picked)
	# food 预算过滤：food 低时 ent 活动跌穿 15 → 返回 ""
	var j2 = C.new(CFG)
	j2.entertainment = 10.0
	j2.food = 16.0     # watching_movie 2h 期间 food 16-5*2=6 <15 → 过滤
	j2.money = 80.0
	var picked2 = j2._best_replenish_safe("entertainment", "afternoon")
	if picked2 != "":
		fail.append("food_filter: 期望'' 得%s" % picked2)
```

- [ ] **Step 2: 跑测试，确认 FAIL（helper 未定义）**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=true`，含 `Identifier "_best_replenish_safe" not declared`。

- [ ] **Step 3: 实现 `_best_replenish_safe`**

`Character_Class.gd`，在 `_best_replenish` 之后（约 213 行后）追加：

```gdscript
# stage10：该 need 正 effect 活动里 effect 值最高、且 food 不跌穿 15 的（food 预算过滤）
# L1.5 配额层与 L2 deficit 层共用（强制补给层统一 effect 最高策略）
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

- [ ] **Step 4: 跑测试，确认 PASS**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=false`，输出含 `QUOTA_TEST PASS`。

- [ ] **Step 5: L2 选活动内联替换为调用 helper（行为不变）**

`Character_Class.gd` 的 `select_best_activity`，把 L2 选活动块：

```gdscript
	if forced_need != "" and food >= 35.0 and money >= 20.0:
		var f_acts := get_activities(day_part, Name_of_character)
		var f_best := ""
		var f_effect := -1e9
		var f_names := f_acts.keys()
		f_names.sort()
		for an in f_names:
			var feff = f_acts[an]["effects"]
			if not (feff.has(forced_need) and float(feff[forced_need]) > 0.0):
				continue
			var dur := float(f_acts[an].get("duration_hours", DEFAULT_DURATION_HOURS))
			var food_after := float(food) + (float(feff.get("food", 0.0)) - float(food_decay)) * dur
			if food_after < 15.0:
				continue
			if float(feff[forced_need]) > f_effect:
				f_effect = float(feff[forced_need])
				f_best = an
		if f_best != "":
			last_forced_need = forced_need
			_commit_activity(f_best)
			return
```

替换为：

```gdscript
	if forced_need != "" and food >= 35.0 and money >= 20.0:
		var f_best := _best_replenish_safe(forced_need, day_part)
		if f_best != "":
			last_forced_need = forced_need
			_commit_activity(f_best)
			return
```

（行为不变：`_best_replenish_safe` 内部 = 原 L2 选活动逻辑。）

- [ ] **Step 6: 跑测试 + run_and_verify 确认无回归**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=false`，`QUOTA_TEST PASS`（L2 改调未破坏）。

- [ ] **Step 7: Commit（待用户确认）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add Character_Class.gd test/quota_test.gd && git commit -m "feat(stage10): _best_replenish_safe (effect-max + food filter), L2 uses it"
```

---

### Task 4: `_pick_quota_activity` + select 插入 L1.5 + 单元（守卫 / owe / 强制）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（+ `_pick_quota_activity` 约 225 行后；select 插入 L1.5 约 228-231 行后）
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\test\quota_test.gd`（+ `_test_pick_quota`）

**Interfaces:**
- Consumes: Task 2 的 `*_done`/`*_target`/`*_deficit`；Task 3 的 `_best_replenish_safe`
- Produces: `_pick_quota_activity(day_part: String) -> String`（L1.5 层）；`select_best_activity` 完整四层（L1/L1.5/L2/L3）。

- [ ] **Step 1: 写失败测试（L1.5 强制 + 守卫让位 + 配额满 fallback）**

`test/quota_test.gd` 的 `_ready` 追加 `_test_pick_quota(fail)`，并加函数：

```gdscript
# Task 4：L1.5 配额层——未达配额 + 守卫满足 → 强制补；守卫紧 → ""；配额满 → ""
func _test_pick_quota(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	# ① ent owe（done=0 < target=3）+ 守卫满足（food≥35/money≥20）→ 返回 ent effect 最高活动
	var j = C.new(CFG)
	j.entertainment_quota_done = 0.0
	j.physical_quota_done = 3.0   # phys 已满
	j.food = 80.0
	j.money = 80.0
	var picked = j._pick_quota_activity("afternoon")
	var ents = j.list_of_activities[picked]["effects"].get("entertainment", 0) if picked != "" else 0
	if ents <= 0:
		fail.append("force_ent: 期望ent活动 得%s(ent=%d)" % [picked, ents])
	# ② 守卫紧（food<35）→ 返回 ""（让位 survival/L2/L3）
	var j2 = C.new(CFG)
	j2.entertainment_quota_done = 0.0
	j2.food = 30.0     # <35
	j2.money = 80.0
	if j2._pick_quota_activity("afternoon") != "":
		fail.append("guard_food: 期望'' 得%s" % j2._pick_quota_activity("afternoon"))
	# ③ 配额全满 → 返回 ""（fallback L2）
	var j3 = C.new(CFG)
	j3.entertainment_quota_done = 3.0
	j3.physical_quota_done = 3.0
	j3.food = 80.0
	j3.money = 80.0
	if j3._pick_quota_activity("afternoon") != "":
		fail.append("quota_full: 期望'' 得%s" % j3._pick_quota_activity("afternoon"))
```

- [ ] **Step 2: 跑测试，确认 FAIL（_pick_quota_activity 未定义）**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=true`，含 `Identifier "_pick_quota_activity" not declared`。

- [ ] **Step 3: 实现 `_pick_quota_activity`**

`Character_Class.gd`，在 `_pick_survival_activity` 之后（约 225 行后）追加：

```gdscript
# stage10 L1.5 品质配额：今日未达配额的 ent/phys，守卫满足则强制补给（proactive 保底）
func _pick_quota_activity(day_part: String) -> String:
	# 跨天重置已在 tick 开头完成，此处只读 owe
	var ent_owe: bool = entertainment_quota_done < entertainment_quota_target
	var phys_owe: bool = physical_quota_done < physical_quota_target
	var need: String = ""
	if ent_owe and phys_owe:
		# 都欠时选 deficit 高的（谁更亏先补谁）
		need = "entertainment" if entertainment_deficit >= physical_deficit else "physical"
	elif ent_owe:
		need = "entertainment"
	elif phys_owe:
		need = "physical"
	if need == "":
		return ""    # 配额满 → fallback L2
	# survival 守卫（沿用 L2：food>=35 / money>=20）
	if food < 35.0 or money < 20.0:
		return ""    # survival 紧 → 让位
	return _best_replenish_safe(need, day_part)    # effect 最高 + food 过滤；无候选 → "" → fallback L2
```

- [ ] **Step 4: select_best_activity 插入 L1.5**

`Character_Class.gd` 的 `select_best_activity` 开头，把：

```gdscript
	# L1 survival 强制（双层调度）：刚需优先于品质/utility（治 v2 night 崩 + 强化 food/money/sleep）
	var surv := _pick_survival_activity(day_part)
	if surv != "":
		_commit_activity(surv)
		return
	# L2 品质 deficit 轮换（stage9 v2）...
```

改为（在 L1 return 之后、L2 之前插 L1.5）：

```gdscript
	# L1 survival 强制（双层调度）：刚需优先于品质/utility
	var surv := _pick_survival_activity(day_part)
	if surv != "":
		_commit_activity(surv)
		return
	# L1.5 品质配额（stage10）：今日未达配额的 ent/phys，守卫满足则 proactive 强制补给
	var quota := _pick_quota_activity(day_part)
	if quota != "":
		_commit_activity(quota)
		return
	# L2 品质 deficit 轮换（stage9 v2）...
```

- [ ] **Step 5: 跑测试，确认 PASS**

`run_and_verify`（scene=`res://test/quota_test.tscn`, timeout=15）。
Expected：`hasErrors=false`，输出含 `QUOTA_TEST PASS`。

- [ ] **Step 6: Commit（待用户确认）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add Character_Class.gd test/quota_test.gd && git commit -m "feat(stage10): L1.5 quota layer in select_best_activity"
```

---

### Task 5: 集成测试（3 游戏天）+ 配额执行率 / avg 提升 / 不回归 + 调参

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\test\exp.gd`（+ 配额执行率 + ent/phys avg 断言）

**Interfaces:**
- Consumes: Task 1-4 完整 L1.5 配额机制

- [ ] **Step 1: 改 exp.gd 加配额执行率 + avg 断言**

`test/exp.gd` 是 stage9 的 72h 集成 runner。在现有 night/food/mz/kinds 统计基础上，加：
- ent/phys avg（`ent_sum/phys_sum` 累加 / 72）
- 配额执行率：跨天重置后逐天记录 `entertainment_quota_done`/`physical_quota_done`，3 天平均 / target=3.0
- 断言：ent/phys 配额执行率 ≥ 0.8、ent/phys avg 较 stage9 基线（7~8）提升、不回归（night≥0.8/food_zero<6h/mz<6h/kinds≥2）

参照 stage9 exp.gd 结构，加（具体代码按 exp.gd 现有变量命名补；核心新增）：

```gdscript
# 配额执行率：每天记录 done（跨天重置后），3天平均
var ent_done_sum := 0.0
var phys_done_sum := 0.0
var prev_day := -1
var days := 0
# ... 在 72 tick 循环里：
var d := TimeManager.get_day()
if d != prev_day:
	if prev_day != -1:
		ent_done_sum += jane.entertainment_quota_done
		phys_done_sum += jane.physical_quota_done
		days += 1
	prev_day = d
# 循环结束后补最后一天：
ent_done_sum += jane.entertainment_quota_done
phys_done_sum += jane.physical_quota_done
days += 1
var ent_exec := (ent_done_sum / days) / 3.0   # target=3.0
var phys_exec := (phys_done_sum / days) / 3.0
# 断言
if ent_exec < 0.8: fail.append("ent_exec=%.2f<0.8" % ent_exec)
if phys_exec < 0.8: fail.append("phys_exec=%.2f<0.8" % phys_exec)
if ent_avg < 8.0: fail.append("ent_avg=%.0f 未较stage9基线(7~8)提升" % ent_avg)
if phys_avg < 8.0: fail.append("phys_avg=%.0f 未较stage9基线(7~8)提升" % phys_avg)
# 不回归沿用 stage9 断言（mz<6h/food_zero<6h/night≥0.8/kinds≥2）
print("PASS ent[avg=%.0f,exec=%.0f%%] phys[avg=%.0f,exec=%.0f%%] mz=%dh food=%dh night=%.2f kinds=%d" % ...)
```

（exp.gd 现有结构保留，仅加 ent/phys avg 累加 + 配额执行率统计 + 上述断言；具体行号按 exp.gd 实际。）

- [ ] **Step 2: 跑集成，观察当前（配额 3h / 守卫 35-20）**

`run_and_verify`（scene=`res://test/exp.tscn`, timeout=20）。
判定分支：
- `PASS`（执行率≥80% + avg 提升 + 不回归）→ 配额/守卫选定，Step 5
- `FAIL ent/phys_exec<0.8` → 配额执行不到，Step 3 松守卫（35→30）或查 night 占比
- `FAIL ent/phys_avg 未提升` → L1.5 增量不足，记录实测值，Step 4 评估
- `FAIL mz/food/night` → 回归，Step 3 紧守卫或降配额

- [ ] **Step 3: 调参分支——守卫 35→30（松，给配额更多窗口）或紧守卫/降配额**

按 Step 2 判定：
- 执行率低 → 改 `Character_Class.gd` L1.5 守卫 `food < 35.0` → `food < 30.0`，重跑
- food/money 崩 → 守卫紧回 35 或配额 3.0→2.5，重跑

- [ ] **Step 4: avg 未显著提升 → 记录实测，STOP 找用户**

若 avg 提升不显著（如 ent/phys avg 仍 ~8，L1.5 proactive 增量小），**STOP**：记录 stage9 基线 vs stage10 实测 avg/执行率，向用户报告「配额制在当前标定下增量有限」，让用户裁决（接受小幅改进 / 调标定 / 收尾）。不擅自改机制。

- [ ] **Step 5: 选定参数，跑最终集成确认 PASS**

记录选定的配额/守卫值 + 实测（执行率/avg/mz/food/night/kinds）。`run_and_verify` 确认 `PASS`。

- [ ] **Step 6: Commit（待用户确认；仅当参数 ≠ v1 才需）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add Character_Class.gd test/exp.gd && git commit -m "feat(stage10): integration pass (quota exec + avg up, no regression)"
```

---

### Task 6: 全回归 + spec/日志/看板 收尾

**Files:**
- Modify: spec 状态、Obsidian 日志、任务看板
- Test: `run_and_verify`

**Interfaces:**
- Consumes: Task 1-5 完整机制 + 选定参数

- [ ] **Step 1: run_and_verify 零错误（主场景）**

`mcp__godot__validation` `run_and_verify`（scene=主场景 node_2d.tscn 或默认, timeout=15）。
Expected：`hasErrors=false`，`errors: []`，`warnings: []`。

- [ ] **Step 2: 重跑 Task1-4 单元 + Task5 集成，确认全 PASS**

`run_and_verify`（scene=`res://test/quota_test.tscn`）→ `QUOTA_TEST PASS`；
`run_and_verify`（scene=`res://test/exp.tscn`）→ `PASS`。

- [ ] **Step 3: 更新 spec 状态**

`docs/superpowers/specs/2026-06-28-stage10-quality-quota-design.md` 第 5 行状态：
`- 状态：设计中（designing ...）` → `- 状态：已实现（implemented 2026-06-28；L1.5 配额层 + _best_replenish_safe；配额=[选定]h / 守卫 food≥[选定]；ent[exec/avg 实测] phys[exec/avg 实测]；不回归）`

- [ ] **Step 4: 写 Obsidian 开发日志**

`D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-28 stage10-品质配额L1.5.md`。frontmatter（date: 2026-06-28 / project / systems: [[双层调度select]]/[[品质配额L1.5]]/[[max-choose第二名陷阱]]/[[execute-gdscript非确定bug]] / status: done）+ callouts（[!summary]/[!check]/[!bug]+[!tip]/[!todo]）。内容：审查 REJECT 转折（avg≥30 标定天花板）、降目标、L1.5 proactive、M1/M3 修正、实测执行率/avg。日志后按需更新 wiki/MOC + 系统状态。

- [ ] **Step 5: 更新任务看板**

`D:\workspace\Obsidian\CharacterLifeSimulator\任务看板.md`：
- 「待办」`ent/phys 多步规划` → 移到「已完成」，标实测执行率/avg + 「avg≥30 标定天花板」认知更新
- 更新 frontmatter 计数（total/done/doing/todo）

- [ ] **Step 6: Commit docs（待用户确认）**

```bash
git -C "D:/GitHub/Character-Life-Simulator-in-Godot" add docs/superpowers/specs/2026-06-28-stage10-quality-quota-design.md docs/superpowers/plans/2026-06-28-stage10-quality-quota.md && git commit -m "docs(stage10): mark quality-quota implemented + finalize plan"
```

（spec + plan 一起 add；Obsidian 日志/看板在 vault 不入此 repo。）

---

## Self-Review 已完成

- **Spec 覆盖**：spec §3 决策（配额机制/只ent-phys/3h/L1.5位置/effect最高/get_day/tick重置/守卫/actual累计）→ Task1 get_day + Task2 状态/重置/累计 + Task3 helper + Task4 L1.5；§4 架构（4.1状态/4.2 get_day/4.3 select L1.5/4.4 _pick_quota/4.5 tick/4.6 _best_replenish_safe/4.7 不动）→ Task1-4 逐步实现；§6 测试（单元 get_day/累计/跨天/守卫/effect最高 + 集成执行率+avg+不回归）→ 各 Task Step1 + Task5；§7 完成标准（实现/单元/执行率/avg提升/不回归/零错/看板）→ Task1-6 全覆盖；§8 已知限制（avg标定天花板/调参/night占比）→ Task5 Step3-4 调参与 STOP 分支。无遗漏。
- **Placeholder**：无 TBD/TODO。Task5 exp.gd 改动给核心新增代码 + 「按现有结构补」（exp.gd 是 stage9 已有文件，沿用其变量命名，非占位）；Task5 Step3 调参给具体守卫值改动；Step4 STOP 给明确上报动作。
- **类型一致**：`TimeManager.get_day()->int`；6 配额成员命名（`entertainment_quota_target/done`、`physical_quota_target/done`、`_last_day`）Task2 定义、Task4/Task5 消费一致；`_best_replenish_safe(need_name:String,day_part:String)->String`、`_pick_quota_activity(day_part:String)->String`、`select_best_activity(day_part:String)->void` 签名 spec-plan-code 一致；tick 跨天重置点（开头，hours<=0 之后、decay 之前）+ busy 累计点（apply 之后、remaining 之前）与 spec §4.5 一致；测试 cfg 的 decay 值与 Main.gd（money=1.5）一致。
- **审查修正覆盖**：B1 目标降级（§1/§7 配额执行率+avg 提升，非 avg≥30）→ Task5 断言；M1 effect 最高（Task3 helper + 测试 effect_max）→ 覆盖；M3 跨天重置移 tick（Task2 + 测试 cross_day_busy）→ 覆盖；m2 跨天 busy 测试用例（Task2 _test_quota_cross_day_busy）→ 覆盖；m1/m3/m4/n1-n3 文档/类型（plan 代码用 `var eff: Dictionary`、spec §4.1 引用 stage8 教训、§4.2 get_day 语义说明）→ 覆盖。
- **已知风险**：① Task5 avg 提升幅度可能小（标定约束），Step4 STOP 找用户裁决，不擅自改机制。② 配额执行率受 night 占 1/3 影响（白天 16h 窗口），80% 阈值若严可调。③ L2 改调 `_best_replenish_safe`（Task3 Step5）须确认行为不变——已逐行对照原 L2 内联逻辑。④ execute_gdscript 非确定，测试走 run_and_verify + 入树脚本（spec §4.1/§6）。
