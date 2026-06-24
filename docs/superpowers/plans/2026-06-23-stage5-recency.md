# 阶段 5：recency 惩罚（活动轮换 → 消费多样）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 加 recency 机制（选过活动 additive 降 utility），打开免费替代压制 → 消费多样（A2 修 stage4 弱循环），night sleeping 不回归，money economy 平衡。

**Architecture:** 只改 Character_Class.gd——加 activity_recency 字段 + RECENCY_PENALTY var + select_best_activity additive 减 recency + tick 衰减 recency + 选后设 recency=1.0。calculate_utility/Main/场景/活动表 不动。

**Tech Stack:** Godot 4.x（4.7 run / 4.6.2 import）/ GDScript / 无 GUT（execute_gdscript 断言 + run_and_verify）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage5-recency-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 执行前建分支：`git checkout -b stage5`（main HEAD a1df7ab）
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import）；run_and_verify 用 4.7
- GDScript tab 缩进
- 无 GUT；测试用 `mcp__godot__script` execute_gdscript（load_autoloads=true）+ `mcp__godot__validation` run_and_verify
- recency 标定：`RECENCY_PENALTY=10`（additive）/ `decay=0.15/h`（**硬下限 ≥0.125**，保 sleeping 8h 衰减）
- recency 主治免费压制（eating_at_home→消费），party 集中靠 saturation（recency 对长活动惩罚弱）
- 测试 set 单独行（GDScript 一行多 set 致首项不生效，stage3 踩过）
- 不主动 commit（项目规则，commit 由用户确认）
- DEFECT `recency-multiplier-negative-utility-reversal`（`D:\workspace\review\.claude\knowledge\defects.md`，open）stage5 改 additive 修复后 fixed

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | activity_recency 字段 + RECENCY_PENALTY + select additive + tick 衰减 + 选后设值 | 改 |
| `docs/superpowers/specs/2026-06-23-stage5-recency-design.md` | spec status | 改（implemented） |
| `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段5-recency轮换.md` | 开发日志 | 新建 |
| Main / 场景 / TimeManager / calculate_utility / 活动表 | 不动 | — |

---

### Task 1: recency 机制（字段 + select additive + tick 衰减）+ 单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（活动持续状态区加字段/var、select_best_activity、tick）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: `Character_Class` 新增 `activity_recency: Dictionary`（活动名→0~1）、`RECENCY_PENALTY: float=10.0`（var）；`select_best_activity` 用 `utility = raw - activity_recency.get(name,0) * RECENCY_PENALTY`，选后 `activity_recency[best]=1.0`；`tick` 衰减 `activity_recency[k] = max(0, recency - 0.15*hours)`

- [ ] **Step 1: 写失败测试（recency 设值/衰减/select 轮换）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）。set 单独行：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2})
var fail = []
# 1. recency 设值（select 后 activity_recency[chosen]==1.0）
jane.is_busy = false
jane.activity_recency.clear()
jane.select_best_activity("morning")
if not jane.activity_recency.has(jane.current_activity): fail.append("select 后未设 recency for %s" % jane.current_activity)
elif abs(jane.activity_recency[jane.current_activity] - 1.0) > 0.01: fail.append("recency != 1.0 got %s" % str(jane.activity_recency[jane.current_activity]))
# 2. recency 衰减（6.7h → 0）
jane.activity_recency["test_act"] = 1.0
jane.tick(60.0 * 6.7, "morning")
if jane.activity_recency["test_act"] > 0.05: fail.append("recency 6.7h 未衰减到 0 got %s" % str(jane.activity_recency["test_act"]))
# 3. select 轮换（eating_at_home recency=1.0 + food 缺 → 选别的，非 eating_at_home）
jane.food = 20.0
jane.money = 80.0
jane.sleep = 50.0
jane.entertainment = 50.0
jane.social = 50.0
jane.health = 50.0
jane.physical = 50.0
jane.mental = 50.0
jane.is_busy = false
jane.activity_recency.clear()
jane.activity_recency["eating_at_home"] = 1.0
jane.select_best_activity("morning")
if jane.current_activity == "eating_at_home": fail.append("eating_at_home recency=1.0 仍被选（应轮换到 eating_out 等）")
print("===STAGE5UNIT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("chosen1=%s recency=%s chosen2=%s" % [str(jane.current_activity), str(jane.activity_recency.get(jane.current_activity, -1)), str(jane.current_activity)])
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（当前无 activity_recency 字段，`jane.activity_recency` 报错 Invalid access；或 select 无 recency 乘子，eating_at_home 仍被选）

- [ ] **Step 3: 实现 recency 机制（3 处 Edit）**

Edit `Character_Class.gd`（tab 缩进）：

3a. 活动持续状态区（`is_busy` 后、`DEFAULT_DURATION_HOURS` 前或后）加字段 + var：

```gdscript
var activity_recency: Dictionary = {}
var RECENCY_PENALTY: float = 10.0
```

3b. `select_best_activity` 改 additive + 选后设 recency。整函数替换：

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

3c. `tick` 末尾（`select_best_activity(day_part)` 之前或 decay 之后）加 recency 衰减。在 `_decay_need("money", hours)` 之后插入：

```gdscript
	for k in activity_recency:
		activity_recency[k] = max(0.0, activity_recency[k] - 0.15 * hours)
```

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（recency 设值 1.0、6.7h 衰减到 0、eating_at_home recency=1.0 时 jane 选 eating_out 等别的）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage5): add recency penalty to select_best_activity (additive)"
```

---

### Task 2: 集成验证（消费多样 A2 + 对照测试 + night 不回归 + money economy）

**Files:**
- Test only（不改代码，除非验证暴露标定问题）

**Interfaces:**
- Consumes: Task 1 recency 机制

- [ ] **Step 1: 写集成测试（3 天采样 + 对照 RECENCY_PENALTY 0 vs 10）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var SPENDING = ["eating_out","socializing_at_cafe","going_fishing","playing_sports","playing_video_games","going_to_a_museum","grocery_shopping","watching_movie","going_to_the_beach","going_to_a_party","online_shopping","going_to_a_concert","going_to_the_gym","visiting_a_spa","going_to_doctor"]
var LIGHT = ["eating_out","socializing_at_cafe","going_fishing","playing_sports","playing_video_games","going_to_a_museum"]
var HEAVY = ["visiting_a_spa","going_to_doctor"]
func run_3day(penalty):
	var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2})
	jane.RECENCY_PENALTY = penalty
	var tm = TimeManager
	tm.game_minutes = 480.0
	tm._last_consumed_game_minutes = 480.0
	tm.paused = false
	var night_sleeping = 0
	var night_samples = 0
	var work_count = 0
	var spend_kinds = {}
	var money_min = 100.0
	var money_max_seen = 0.0
	var light_hit = false
	var mid_hit = false
	var heavy_hit = false
	for i in 72:
		var dp = tm.get_day_part()
		var was_idle = not jane.is_busy
		jane.tick(60.0, dp)
		if was_idle and jane.is_busy:
			var act = jane.current_activity
			if act == "working_overtime": work_count += 1
			elif SPENDING.has(act):
				spend_kinds[act] = true
				if LIGHT.has(act): light_hit = true
				elif HEAVY.has(act): heavy_hit = true
				else: mid_hit = true
		if dp == "night":
			night_samples += 1
			if jane.is_busy and jane.current_activity == "sleeping": night_sleeping += 1
		money_min = min(money_min, jane.money)
		money_max_seen = max(money_max_seen, jane.money)
		tm.game_minutes += 60.0
	return {"night": night_sleeping, "nsamp": night_samples, "work": work_count, "kinds": spend_kinds.size(), "light": light_hit, "mid": mid_hit, "heavy": heavy_hit, "mmin": money_min, "mmax": money_max_seen}
var r10 = run_3day(10.0)
var r0 = run_3day(0.0)
var fail = []
if r10["kinds"] < 3: fail.append("PENALTY=10 消费种类 %d < 3" % r10["kinds"])
if not (r10["light"] and r10["mid"]): fail.append("PENALTY=10 消费覆盖不足 light=%s mid=%s heavy=%s" % [r10["light"], r10["mid"], r10["heavy"]])
if r10["night"] < 20: fail.append("PENALTY=10 night sleeping %d/24 < 20" % r10["night"])
if r10["work"] < 1 or r10["work"] > 6: fail.append("PENALTY=10 work %d 不在 1-6" % r10["work"])
if r10["mmin"] <= 0 or r10["mmax"] >= 100: fail.append("PENALTY=10 money 卡边界 min=%s max=%s" % [r10["mmin"], r10["mmax"]])
if r10["kinds"] <= r0["kinds"]: fail.append("对照失败: PENALTY=10 消费种类 %d 未多于 PENALTY=0 的 %d（recency 未生效）" % [r10["kinds"], r0["kinds"]])
print("===STAGE5INT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("PENALTY=10: night=%d/24 work=%d kinds=%d light=%s mid=%s heavy=%s money[min=%.0f max=%.0f]" % [r10["night"], r10["work"], r10["kinds"], r10["light"], r10["mid"], r10["heavy"], r10["mmin"], r10["mmax"]])
print("PENALTY=0 (对照): kinds=%d" % r0["kinds"])
```

- [ ] **Step 2: 跑测试确认 PASS**

Expected: `PASS`（PENALTY=10 消费种类 ≥3、覆盖 light+mid、night ≥20/24、work 1-6、money 不卡边界；**PENALTY=10 消费种类 > PENALTY=0**，证明 recency 生效）

若 FAIL：
- 消费种类 <3 / 覆盖不足：recency 打开免费压制不够，调高 RECENCY_PENALTY（10→12）或 decay（0.15→0.18，**但 ≥0.125**）
- night <20：recency 扰乱睡眠，decay 调高（恢复快，**≥0.125**）或检查 sleeping recency 衰减
- 对照失败（PENALTY=10 ≤ 0）：recency 未生效，检查 select additive 实现
- money 卡边界：消费多/少，调标定（PENALTY 或消费 money effect）

- [ ] **Step 3: run_and_verify 回归**

`run_and_verify`（timeout=15）。Expected: `hasErrors: false`。

- [ ] **Step 4: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "test(stage5): verify spending diversity A2 + recency contrast + no regression"
```

---

### Task 3: 收尾（spec implemented + DEFECT fixed + 日志）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage5-recency-design.md`
- Modify: `D:\workspace\review\.claude\knowledge\defects.md`（DEFECT recency-multiplier → fixed）
- Create: `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段5-recency轮换.md`

- [ ] **Step 1: spec status → implemented**

Edit spec 第 5 行 `- 状态：已确认（待写实施计划）` → `- 状态：已实现（implemented 2026-06-23；recency additive，消费种类=<实测>，night=<实测>/24）`（填 Task 2 实测）

- [ ] **Step 2: DEFECT recency-multiplier → fixed（additive 修复确认）**

重跑 detect：读 Character_Class.gd select_best_activity，确认 utility = `raw - activity_recency.get(name,0)*RECENCY_PENALTY`（additive，非乘子 raw*(1-recency)）。

Edit `D:\workspace\review\.claude\knowledge\defects.md`：
- `DEFECT.project.character-life-simulator.recency-multiplier-negative-utility-reversal.status=open` → `=fixed`
- 加 `.fixed-in=stage5 select_best_activity 改 additive（raw - recency*RECENCY_PENALTY）+ 集成验证`
- 改 `.note` 追加：`2026-06-23 复测(stage5)：select 用 additive（raw - recency*10），work raw -44 + recency 1.0 → -54（正确惩罚，非乘子反转 0）→ fixed`

- [ ] **Step 3: 写 Obsidian 开发日志**

Create `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段5-recency轮换.md`，frontmatter + callouts（summary/check/bug/tip/todo）：
- summary：stage5 加 recency 机制（选过活动 additive 降 utility），打开免费压制 → 消费多样（修 stage4 弱循环）
- check：Character_Class.gd、spec、defects.md
- bug：审查抓出乘子对负 utility 反转（DEFECT recency-multiplier）→ 改 additive；recency 打不破 party（saturation 才）→ 归因修正
- tip：recency 主治免费压制（eating_at_home→eating_out），decay 硬下限 0.125（sleeping 8h 衰减命门）
- todo：stage6（消费多样仍不足时调 PENALTY/decay、bedtime 时段边界、职业体系）

- [ ] **Step 4: Commit + push（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "docs(stage5): finalize recency + spec implemented"
git push origin stage5
```

---

## Self-Review 已完成

- **Spec 覆盖**：spec §4.1（recency 字段/select additive/tick 衰减）→ Task 1 Step 3；§5 复算（additive + 归因）→ Task 1 Step 1 断言；§7 单元（设值/衰减/轮换/对照）→ Task 1/2；§7 集成（A2 消费多样 + 对照 + night + money）→ Task 2 Step 1；§8 Done → Task 1-2；§9 限制（decay≥0.125、归因、DEFECT）→ Task 2 FAIL 处理 + Task 3 DEFECT fixed。无遗漏。
- **Placeholder**：无 TBD/TODO；select/tick 代码完整；commit hash 标"执行时填"（产物）。
- **类型一致**：`activity_recency: Dictionary` / `RECENCY_PENALTY: float`（var，spec §4.1 已 patch const→var 供对照测试）/ `0.15` decay 跨 Task/spec 一致；测试 set 单独行（避 stage3 一行多 set bug）；对照测试 run_3day(penalty) 改 jane.RECENCY_PENALTY（var 可改）。
- **已知风险**：Task 1 改 select 即时生效（run_project 行为变）。Task 1 单元测验证机制；Task 2 集成验证消费多样（A2 + 对照）。对照测试（PENALTY=0 vs 10）确认 A2 是 recency 功劳非 saturation 碰巧。decay 调整不得 < 0.125（sleeping 8h 衰减命门，spec §9 钉死）。
