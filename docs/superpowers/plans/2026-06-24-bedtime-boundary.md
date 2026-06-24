# 阶段 6：bedtime 时段边界（活动不跨 day_part）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 活动执行不跨 day_part 边界（duration clamp 到时段剩余），消除 evening 长活动溢出到 night 占睡眠，night sleeping 18→≥22/24。

**Architecture:** TimeManager 抽 DAY_PART_BOUNDS const（边界单一来源）+ get_day_part 重构查表（behavior-preserving）+ 新增 get_day_part_remaining_hours；Character_Class.select_best_activity 选中后 remaining_hours = min(duration, 时段剩余)。calculate_utility/effects/tick 主体/活动表不动。

**Tech Stack:** Godot 4.x（4.7 run / 4.6.2 import）/ GDScript / 无 GUT（execute_gdscript 断言 + run_and_verify）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-24-bedtime-boundary-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 执行前建分支：`git checkout -b stage6`（main HEAD 258e9a9）
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import）；run_and_verify 用 4.7
- GDScript tab 缩进
- 无 GUT；测试用 `mcp__godot__script` execute_gdscript（load_autoloads=true）+ `mcp__godot__validation` run_and_verify
- 测试 set 单独行（GDScript 一行多 set 致首项不生效，stage3 踩过）
- get_day_part 重构是 behavior-preserving，**必须有守护测试**（§6 重构守护 8 边界）才能改
- const DAY_PART_BOUNDS 区间互斥全覆盖 0-23，遍历顺序无关（N2 push back 已确认）
- 不主动 commit（项目规则，commit 由用户确认）

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `TimeManager.gd` | DAY_PART_BOUNDS const + get_day_part 重构查表（行为保持）+ get_day_part_remaining_hours | 改 |
| `Character_Class.gd` | select_best_activity remaining_hours clamp 到时段剩余 | 改 |
| `docs/superpowers/specs/2026-06-24-bedtime-boundary-design.md` | spec status | 改（implemented） |
| `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-24 阶段6-bedtime边界.md` | 开发日志 | 新建 |
| `D:\workspace\Obsidian\CharacterLifeSimulator\任务看板.md` | 看板 | 改 |
| calculate_utility / effects / tick 主体 / 活动表 / Main / 场景 | 不动 | — |

---

### Task 1: TimeManager 边界单一来源（const + get_day_part 重构 + get_day_part_remaining）+ 单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\TimeManager.gd`（加 const、重构 get_day_part、加 get_day_part_remaining_hours）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: `TimeManager.DAY_PART_BOUNDS`（const Dictionary）、`TimeManager.get_day_part()`（重构，签名不变 `-> String`）、`TimeManager.get_day_part_remaining_hours() -> float`（当前 day_part 到下一边界剩余小时）

- [ ] **Step 1: 写失败测试（get_day_part 8 边界守护 + get_day_part_remaining 各时段算术）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）。set 单独行：

```gdscript
var tm = TimeManager
var fail = []
tm.game_minutes = 21 * 60 + 59
if tm.get_day_part() != "evening": fail.append("21:59 -> %s != evening" % tm.get_day_part())
tm.game_minutes = 22 * 60
if tm.get_day_part() != "night": fail.append("22:00 -> %s != night" % tm.get_day_part())
tm.game_minutes = 5 * 60 + 59
if tm.get_day_part() != "night": fail.append("05:59 -> %s != night" % tm.get_day_part())
tm.game_minutes = 6 * 60
if tm.get_day_part() != "morning": fail.append("06:00 -> %s != morning" % tm.get_day_part())
tm.game_minutes = 11 * 60 + 59
if tm.get_day_part() != "morning": fail.append("11:59 -> %s != morning" % tm.get_day_part())
tm.game_minutes = 12 * 60
if tm.get_day_part() != "afternoon": fail.append("12:00 -> %s != afternoon" % tm.get_day_part())
tm.game_minutes = 17 * 60 + 59
if tm.get_day_part() != "afternoon": fail.append("17:59 -> %s != afternoon" % tm.get_day_part())
tm.game_minutes = 18 * 60
if tm.get_day_part() != "evening": fail.append("18:00 -> %s != evening" % tm.get_day_part())
tm.game_minutes = 21 * 60
if abs(tm.get_day_part_remaining_hours() - 1.0) > 0.01: fail.append("21:00 remaining %s != 1.0" % str(tm.get_day_part_remaining_hours()))
tm.game_minutes = 22 * 60
if abs(tm.get_day_part_remaining_hours() - 8.0) > 0.01: fail.append("22:00 remaining %s != 8.0" % str(tm.get_day_part_remaining_hours()))
tm.game_minutes = 23 * 60
if abs(tm.get_day_part_remaining_hours() - 7.0) > 0.01: fail.append("23:00 remaining %s != 7.0" % str(tm.get_day_part_remaining_hours()))
tm.game_minutes = 8 * 60
if abs(tm.get_day_part_remaining_hours() - 4.0) > 0.01: fail.append("08:00 remaining %s != 4.0" % str(tm.get_day_part_remaining_hours()))
tm.game_minutes = 14 * 60
if abs(tm.get_day_part_remaining_hours() - 4.0) > 0.01: fail.append("14:00 remaining %s != 4.0" % str(tm.get_day_part_remaining_hours()))
print("===STAGE6UNIT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（get_day_part_remaining_hours 方法不存在，报 Invalid method 'get_day_part_remaining_hours'）

- [ ] **Step 3: 实现 const + 重构 get_day_part + get_day_part_remaining**

Edit `TimeManager.gd`（tab 缩进）：

3a. `const BASE_MIN_PER_SEC` 后加 const：
```gdscript
const DAY_PART_BOUNDS = {
	"night": [22, 6],     # [start, end]；end < start 表示跨日。4 区间互斥全覆盖 0-23，遍历顺序无关
	"morning": [6, 12],
	"afternoon": [12, 18],
	"evening": [18, 22],
}
```

3b. 替换 get_day_part（behavior-preserving 查表，签名不变）：
```gdscript
func get_day_part() -> String:
	var h := get_hour()
	for dp in DAY_PART_BOUNDS:
		var s: int = DAY_PART_BOUNDS[dp][0]
		var e: int = DAY_PART_BOUNDS[dp][1]
		if e > s:
			if h >= s and h < e:
				return dp
		else:
			if h >= s or h < e:
				return dp
	return "night"
```

3c. 文件末尾（toggle_pause 之后）加：
```gdscript
func get_day_part_remaining_hours() -> float:
	var end_hour: int = DAY_PART_BOUNDS[get_day_part()][1]
	var cur_min := float(int(floor(game_minutes)) % 1440)
	var diff := float(end_hour * 60) - cur_min
	if diff <= 0.0:
		diff += 1440.0
	return diff / 60.0
```

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（8 边界 get_day_part 不变 + 5 个 remaining 算术正确：21:00→1.0、22:00→8.0、23:00→7.0、08:00→4.0、14:00→4.0）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add TimeManager.gd && git commit -m "refactor(stage6): extract DAY_PART_BOUNDS const, add get_day_part_remaining_hours"
```

---

### Task 2: select_best_activity clamp + 集成测试（night sleeping + 不回归）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（select_best_activity remaining_hours clamp）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Consumes: Task 1 的 `TimeManager.get_day_part_remaining_hours() -> float`

- [ ] **Step 1: 写集成测试（3 天 night sleeping ≥22 + T2a evening 不跨夜 + 不回归）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var SPENDING = ["eating_out","socializing_at_cafe","going_fishing","playing_sports","playing_video_games","going_to_a_museum","grocery_shopping","watching_movie","going_to_the_beach","going_to_a_party","online_shopping","going_to_a_concert","going_to_the_gym","visiting_a_spa","going_to_doctor"]
var LONG = ["going_to_a_party","going_to_a_concert","going_to_the_beach","visiting_a_spa","going_to_a_museum","going_fishing","volunteering"]
func run_3day():
	var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2})
	jane.RECENCY_PENALTY = 10.0
	var tm = TimeManager
	tm.game_minutes = 480.0
	tm._last_consumed_game_minutes = 480.0
	tm.paused = false
	var night_sleep = 0.0
	var work_count = 0
	var spend_kinds = {}
	var money_min = 100.0
	var money_max = 0.0
	var overflow = false
	for i in 72:
		var dp = tm.get_day_part()
		var was_idle = not jane.is_busy
		jane.tick(60.0, dp)
		if dp == "night":
			if jane.is_busy and jane.current_activity == "sleeping":
				night_sleep += 1.0
			if jane.is_busy and LONG.has(jane.current_activity):
				overflow = true
		if was_idle and jane.is_busy:
			var act = jane.current_activity
			if act == "working_overtime":
				work_count += 1
			elif SPENDING.has(act):
				spend_kinds[act] = true
		money_min = min(money_min, jane.money)
		money_max = max(money_max, jane.money)
		tm.game_minutes += 60.0
	return {"night_sleep": night_sleep, "work": work_count, "kinds": spend_kinds.size(), "mmin": money_min, "mmax": money_max, "overflow": overflow}
var r = run_3day()
var fail = []
if r["night_sleep"] < 22: fail.append("night sleeping %.0f/24 < 22" % r["night_sleep"])
if r["overflow"]: fail.append("T2a evening 长活动溢出到 night")
if r["kinds"] < 2: fail.append("消费多样回归 kinds=%d < 2" % r["kinds"])
if r["work"] < 1 or r["work"] > 6: fail.append("work %d 不在 1-6" % r["work"])
if r["mmin"] <= 0: fail.append("money 卡 0 mmin=%s" % r["mmin"])
print("===STAGE6INT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("night_sleep=%.0f/24 overflow=%s kinds=%d work=%d money[min=%.0f max=%.0f]" % [r["night_sleep"], r["overflow"], r["kinds"], r["work"], r["mmin"], r["mmax"]])
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（当前 select 不 clamp，evening 选的 3h party 溢出到 night：night_sleep≈18 < 22 且 overflow=true）

- [ ] **Step 3: 实现 select clamp（remaining_hours 一行改）**

Edit `Character_Class.gd` select_best_activity（第 174-178 行 `if best_activity != "":` 块），remaining_hours 改 clamp：

```gdscript
if best_activity != "":
	current_activity = best_activity
	activity_recency[best_activity] = 1.0
	remaining_hours = min(list_of_activities[best_activity].get("duration_hours", DEFAULT_DURATION_HOURS), TimeManager.get_day_part_remaining_hours())
	is_busy = true
```

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（night_sleep ≥ 22、overflow=false、kinds ≥ 2、work 1-6、money 不卡 0）

若 FAIL：
- night_sleep <22 或 overflow=true：检查 Task 1 get_day_part_remaining 算术 + Task 2 select clamp 是否生效（TimeManager 耦合是否通）
- 消费/ money 回归（kinds<2 或 money 卡0）：clamp 改了活动时长可能扰动 stage4-5 标定——先确认非 clamp bug（如 evening 短活动是否仍可选），再判断是否标定回归（超 stage6 范围则记看板待办，不盲调）

- [ ] **Step 5: run_and_verify 回归**

`mcp__godot__validation`（action=run_and_verify, timeout=15）。Expected: `hasErrors: false`。

- [ ] **Step 6: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage6): clamp activity duration to day_part remaining (no night overflow)"
```

---

### Task 3: 收尾（spec implemented + 日志 + 看板）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-24-bedtime-boundary-design.md`
- Create: `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-24 阶段6-bedtime边界.md`
- Modify: `D:\workspace\Obsidian\CharacterLifeSimulator\任务看板.md`

- [ ] **Step 1: spec status → implemented**

Edit spec 第 5 行 `- 状态：已确认（待写实施计划）` → `- 状态：已实现（implemented 2026-06-24；活动 duration clamp 到 day_part 剩余，night sleeping=<实测>/24，evening 长活动不跨夜）`（填 Task 2 实测 night_sleep）

- [ ] **Step 2: 写 Obsidian 开发日志**

Create `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-24 阶段6-bedtime边界.md`，frontmatter（date/project/systems/status:done）+ callouts：
- summary：stage6 活动不跨 day_part（duration clamp 到时段剩余），消除 evening 长活动（party 等）溢出到 night，night sleeping 18→≥22/24
- check：TimeManager.gd（DAY_PART_BOUNDS const + get_day_part 重构 + get_day_part_remaining_hours）、Character_Class.gd（select clamp）、spec、日志、看板
- bug：无机制 bug；tip：① behavior-preserving refactor 必须先写守护测试（get_day_part 8 边界）再改 ② const 区间互斥全覆盖，遍历顺序无关（reviewer N2 push back，勿加误导性"顺序敏感"注释）
- todo：stage7（消费多样 need 调标定 / money clamp 非单调 / 多职业体系）

- [ ] **Step 3: 更新任务看板**

`任务看板.md`：bedtime 时段边界从「待办」移到「已完成」；frontmatter 计数（done 5→6, todo 4→3）

- [ ] **Step 4: Commit + push（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "docs(stage6): finalize bedtime boundary + spec implemented"
git push origin stage6
```

---

## Self-Review 已完成

- **Spec 覆盖**：spec §4.1（const + get_day_part 重构 + get_day_part_remaining）→ Task 1 Step 3；§4.2（select clamp）→ Task 2 Step 3；§6 单元（8 边界守护 + clamp 算术）→ Task 1 Step 1；§6 集成（T1 night sleeping actual hours + T2a evening 不跨夜 + T2b work/money + 不回归）→ Task 2 Step 1；§7 Done（含 const/重构/守护，N1 补全）→ Task 1-2；§8 限制（耦合/Q2）→ Task 2 FAIL 处理 + Task 3 日志。无遗漏。
- **Placeholder**：无 TBD/TODO；const/get_day_part/get_day_part_remaining/select clamp 代码完整；commit hash 标"执行时填"（产物）。
- **类型一致**：`DAY_PART_BOUNDS` const（Dictionary）/ `get_day_part() -> String`（签名不变）/ `get_day_part_remaining_hours() -> float` 跨 Task/spec 一致；测试 set 单独行（避 stage3 一行多 set bug）；Task 2 select clamp 调用 Task 1 产出的 `TimeManager.get_day_part_remaining_hours()`。
- **已知风险**：Task 1 get_day_part 重构 behavior-preserving（8 边界守护测试 Step 1 保证，先写测试再重构）。Task 2 clamp 改活动执行时长，可能扰动 stage4-5 消费/money 标定——Task 2 Step 4 FAIL 处理区分 clamp bug vs 标定回归，后者记看板不盲调。
