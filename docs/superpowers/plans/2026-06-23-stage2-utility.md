# 阶段 2：calculate_utility per_hour 净效用模型 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 改 calculate_utility 为 per_hour 净效用模型（net 含 decay、clamp 真实、消 double-count），让 sleeping 不再算成负效用、night sleeping 稳过 80%、准时睡不偏晚。

**Architecture:** 只改 Character_Class.gd 的 calculate_utility 一个函数：`net_change=clamp(current+(effect_ph-decay_ph)*dur,0,max)-current, utility=Σ net_change*urgency`。tick/活动表/decay/TimeManager/Main 全不动。

**Tech Stack:** Godot 4.x（4.7 run / 4.6.2 import）/ GDScript / 无 GUT（execute_gdscript 断言 + run_and_verify）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage2-utility-per-hour-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 执行前建分支：`git checkout -b stage2`（main 已含 stage1，stage2 基于 main）
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import）；run_project/run_and_verify 用 4.7
- GDScript tab 缩进
- 无 GUT；测试用 `mcp__godot__script` execute_gdscript（load_autoloads=true）+ `mcp__godot__validation` run_and_verify
- jane config decay（per_hour）：sleep 6 / food 5 / entertainment 4 / social 3 / health 1 / physical 3 / mental 2（阶段 1 已定，food 5 为微调值）
- 各 need max=100，初始 round(max/2)=50
- 不主动 commit（项目规则，commit 由用户确认）
- DEFECT `DEFECT.project.character-life-simulator.utility-double-count-no-decay`（`D:\workspace\review\.claude\knowledge\defects.md`，status=open）阶段 2 验证后改 fixed

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | calculate_utility（约 136-146 行） | 改（一个函数） |
| `docs/superpowers/specs/2026-06-23-stage2-utility-per-hour-design.md` | spec status | 改（implemented） |
| `D:\workspace\review\.claude\knowledge\defects.md` | DEFECT status | 改（open→fixed，detect 复测） |
| `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段2-utility净模型.md` | 开发日志 | 新建 |

---

### Task 1: 改 calculate_utility 为 per_hour 净模型 + 单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（calculate_utility 函数，约 136-146 行）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: `calculate_utility(activity: Dictionary) -> float` 新契约——返回 `Σ net_change*urgency`，其中 `net_change=clamp(current+(effect_ph-decay_ph)*duration,0,max)-current`、`urgency=(max-current)/max`。各 need=50 时：sleeping 总 +33、eating_at_home +26.5、working_overtime −44

- [ ] **Step 1: 写失败测试（utility 总和断言）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2})
var fail = []
# 各 need=50（_init 后 round(100/2)=50）
var u_sleep = jane.calculate_utility(jane.list_of_activities["sleeping"])
if abs(u_sleep - 33.0) > 0.1: fail.append("sleeping utility got %s want 33" % str(u_sleep))
var u_eat = jane.calculate_utility(jane.list_of_activities["eating_at_home"])
if abs(u_eat - 26.5) > 0.1: fail.append("eating_at_home utility got %s want 26.5" % str(u_eat))
var u_work = jane.calculate_utility(jane.list_of_activities["working_overtime"])
if abs(u_work - (-44.0)) > 0.1: fail.append("working_overtime utility got %s want -44" % str(u_work))
print("===STAGE2UNIT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("sleep=%.2f eat=%.2f work=%.2f" % [u_sleep, u_eat, u_work])
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（旧算法 sleeping 总=10 非 33——旧算法 `base-wasted` double-count + 不含 decay；eating/working 也不符）

- [ ] **Step 3: 改 calculate_utility（spec §4 代码）**

Edit `Character_Class.gd` 的 calculate_utility 整函数替换（tab 缩进）：

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

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（sleeping +33、eating_at_home +26.5、working_overtime −44）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage2): rewrite calculate_utility to per_hour net utility model"
```

---

### Task 2: 集成验证（3 游戏天 night sleeping ≥80% + 准时睡 + food 回归）

**Files:**
- Test only（不改代码，除非验证暴露问题）

**Interfaces:**
- Consumes: Task 1 新 calculate_utility（select_best_activity 调用）+ 阶段 1 TimeManager/Character tick

- [ ] **Step 1: 写集成测试（3 天采样 + 22:00-23:00 时机断言）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2})
var tm = TimeManager
tm.game_minutes = 480.0
tm._last_consumed_game_minutes = 480.0
tm.paused = false
var night_samples = 0
var night_sleeping = 0
var food_zero_run = 0
var food_max_zero_run = 0
var bedtime_days = {}
for i in 72:
	var dp = tm.get_day_part()
	var hour = tm.get_hour()
	jane.tick(60.0, dp)
	if hour == 22 and jane.is_busy and jane.current_activity == "sleeping":
		bedtime_days[int(tm.game_minutes / 1440.0)] = true
	if dp == "night":
		night_samples += 1
		if jane.is_busy and jane.current_activity == "sleeping":
			night_sleeping += 1
	if jane.food <= 0.0:
		food_zero_run += 1
		food_max_zero_run = max(food_max_zero_run, food_zero_run)
	else:
		food_zero_run = 0
	tm.game_minutes += 60.0
var fail = []
var ratio = float(night_sleeping) / float(night_samples) if night_samples > 0 else 0.0
if ratio < 0.8: fail.append("night sleeping 占比 %.2f < 0.8" % ratio)
if food_max_zero_run >= 6: fail.append("food 连续 %d h 为 0 (>=6)" % food_max_zero_run)
if bedtime_days.size() < 2: fail.append("22:00-23:00 sleeping 天数 %d < 2 (容忍第1天适应期)" % bedtime_days.size())
print("===STAGE2INT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("ratio=%.2f night=%d/%d food_zero=%d bedtime_days=%d" % [ratio, night_sleeping, night_samples, food_max_zero_run, bedtime_days.size()])
```

- [ ] **Step 2: 跑测试确认 PASS**

Expected: `PASS`（ratio ≥ 0.80、food_zero < 6、bedtime_days ≥ 2）

若 FAIL：
- ratio < 0.8 或 bedtime_days < 2：查 sleeping 是否准时被选；若仍偏晚且非 utility 问题，记为 spec §8 限制（urgency 超线性 / sleeping decay 机会成本），不强行调参——如实记录，与用户确认是否进阶段 3
- food_zero ≥ 6：回归 bug（阶段 1 已修），查 food decay/effects 是否被 Task 1 间接影响（不应影响，tick 没动）

- [ ] **Step 3: run_and_verify 回归**

`mcp__godot__validation`（action=run_and_verify, timeout=15）。
Expected: `hasErrors: false`，errors/warnings 空。

- [ ] **Step 4: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "test(stage2): verify 3-day rhythm night sleeping >=80% + on-time sleep"
```

---

### Task 3: 收尾（spec status + DEFECT fixed + 日志）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage2-utility-per-hour-design.md`
- Modify: `D:\workspace\review\.claude\knowledge\defects.md`
- Create: `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段2-utility净模型.md`

- [ ] **Step 1: spec status → implemented**

Edit spec 第 5 行 `- 状态：已确认（待写实施计划）` → `- 状态：已实现（implemented 2026-06-23）`

- [ ] **Step 2: DEFECT status → fixed（重跑 detect 确认）**

重跑 detect：读 `Character_Class.gd` 的 calculate_utility，确认已无 `effects[need] * duration`（一次性 impact）/ `base` / `wasted`（旧 double-count 标记）——新算法用 `net_change` / `effect_ph` / `decay_ph`，detect 不再命中。

Edit `D:\workspace\review\.claude\knowledge\defects.md`：
- `DEFECT.project.character-life-simulator.utility-double-count-no-decay.status=open` → `=fixed`
- 加 `.fixed-in=<Task1/Task2 commit hash>`（执行时填）
- 改 `.note` 追加：`2026-06-23 复测：calculate_utility 已改 net_change 模型，旧 impact/wasted 不再存在，detect 不命中 → fixed。集成验证 night sleeping ≥80% + 22:00-23:00 准时睡`

- [ ] **Step 3: 写 Obsidian 开发日志**

Create `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段2-utility净模型.md`，frontmatter（date/project/systems/status）+ callouts（[!summary] / [!check] / [!bug] / [!tip] / [!todo]）：
- summary：阶段 2 改 calculate_utility 为 per_hour 净模型，修 double-count + 不含 decay 双 bug
- check：Character_Class.gd、spec、defects.md
- bug：旧算法 sleeping sleep 项 −10（base-wasted 双扣 + 无 decay）→ 新算法 +25
- tip：net_change 含 decay + clamp 真实，sleeping 总 +33
- todo：阶段 3 money/working_overtime

- [ ] **Step 4: Commit + push（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "docs(stage2): finalize utility per_hour model + spec implemented"
git push origin stage2
```

---

## Self-Review 已完成

- **Spec 覆盖**：spec §4 算法 → Task 1 Step 3；§6 单元断言（总和 +33/+26.5/−44）→ Task 1 Step 1；§6 集成（≥80% + 22:00-23:00 时机 + food 回归）→ Task 2 Step 1；§7 完成标准 1-6 → Task 1-2 验证；§8 限制（不修，观察）→ Task 2 FAIL 处理说明。无遗漏。
- **Placeholder**：无 TBD/TODO，所有代码/命令完整。
- **类型一致**：`calculate_utility(activity: Dictionary) -> float` 签名不变；`net_change` / `urgency` / `effect_ph` / `decay_ph` 命名跨步骤统一；测试用 `float()`（非 `as float`，避阶段 1 ratio bug）。
- **已知风险**：Task 1 改完 calculate_utility 即时生效（select_best_activity 调它），run_project 行为立即变化——预期。Task 2 集成测试验证。Task 1 单元测试与 Task 2 集成测试相互独立（单元不依赖 TimeManager 推进）。
