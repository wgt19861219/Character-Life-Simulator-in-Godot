# 阶段 4：消费活动扣 money（money 赚-花循环）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 给 15 个消费活动加 money 负 effect（分档 −5/−9/−14），形成 money 赚（work）-花（消费）完整循环，jane 缺钱时少消费多工作，且消费活动真的被选（避空转）。

**Architecture:** 只改 Character_Class.gd 活动表（15 活动 effects 加 money 负值）。tick/calculate_utility 自动覆盖（money 已是 need）。Main/场景/TimeManager 不动。

**Tech Stack:** Godot 4.x（4.7 run / 4.6.2 import）/ GDScript / 无 GUT（execute_gdscript 断言 + run_and_verify）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage4-spending-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 执行前建分支：`git checkout -b stage4`（main HEAD 1bb7886）
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import）；run_and_verify 用 4.7
- GDScript tab 缩进
- 无 GUT；测试用 `mcp__godot__script` execute_gdscript（load_autoloads=true）+ `mcp__godot__validation` run_and_verify
- money decay 2/h（阶段 3 已定）；消费标定 轻 −5 / 中 −9 / 重 −14 per_hour
- 测试 set 必须单独行（GDScript 一行多 set 致首项不生效，阶段 3 踩过）
- 不主动 commit（项目规则，commit 由用户确认）
- DEFECT `money-utility-clamp-nonmonotonic`（`D:\workspace\review\.claude\knowledge\defects.md`，open）阶段 4 单元断言锁定（不根治）

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | 15 消费活动 effects 加 money 负值 | 改（15 处） |
| `docs/superpowers/specs/2026-06-23-stage4-spending-design.md` | spec status | 改（implemented） |
| `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段4-消费扣money.md` | 开发日志 | 新建 |
| Main / node_2d.tscn / TimeManager / tick / calculate_utility | 不动 | — |

---

### Task 1: 15 消费活动加 money 负 effect + 单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（list_of_activities 的 15 个消费活动条目）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: 15 消费活动 effects 含 money 负值（轻 −5 / 中 −9 / 重 −14）。calculate_utility 自动算 money 项（jane 缺钱时消费 utility 降）

- [ ] **Step 1: 写失败测试（消费 utility + A1 消费vs免费 + B clamp）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）。注意 set 单独行：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2})
var fail = []
jane.money = 80.0
jane.sleep = 50.0
jane.food = 50.0
jane.entertainment = 50.0
jane.social = 50.0
jane.health = 50.0
jane.physical = 50.0
jane.mental = 50.0
var u_eat80 = jane.calculate_utility(jane.list_of_activities["eating_out"])
if abs(u_eat80 - 25.2) > 0.1: fail.append("eating_out money=80 got %s want 25.2" % str(u_eat80))
jane.money = 20.0
var u_eat20 = jane.calculate_utility(jane.list_of_activities["eating_out"])
if abs(u_eat20 - 16.8) > 0.1: fail.append("eating_out money=20 got %s want 16.8" % str(u_eat20))
# A1: eating_out@social=10 money=80 (26.8) > eating_at_home (26.5)
jane.money = 80.0
jane.social = 10.0
var u_eat_s10 = jane.calculate_utility(jane.list_of_activities["eating_out"])
var u_home = jane.calculate_utility(jane.list_of_activities["eating_at_home"])
if u_eat_s10 <= u_home: fail.append("A1: eating_out@social=10 %.2f <= eating_at_home %.2f" % [u_eat_s10, u_home])
# B: eating_out money=0 → 28 (clamp 非单调锁定)
jane.money = 0.0
jane.social = 50.0
var u_eat0 = jane.calculate_utility(jane.list_of_activities["eating_out"])
if abs(u_eat0 - 28.0) > 0.1: fail.append("eating_out money=0 got %s want 28 (clamp)" % str(u_eat0))
print("===STAGE4UNIT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("eat80=%.2f eat20=%.2f eat_s10=%.2f home=%.2f eat0=%.2f" % [u_eat80, u_eat20, u_eat_s10, u_home, u_eat0])
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（当前 eating_out 无 money effect，utility = food+social+ent = 28 不含 money 项；eating_out money=80 期望 25.2 但实际 28）

- [ ] **Step 3: 15 消费活动 effects 加 money 负值**

Edit `Character_Class.gd` 的 list_of_activities，15 处（每处 effects dict 加 `"money": X`）：

```gdscript
# 轻 −5（6 个）
"eating_out": {"effects": {"food": 30, "social": 5, "entertainment": 5, "money": -5}, "duration_hours": 2},
"socializing_at_cafe": {"effects": {"social": 8, "food": 10, "money": -5}, "duration_hours": 2},
"going_fishing": {"effects": {"entertainment": 5, "mental": 4, "money": -5}, "duration_hours": 3},
"playing_sports": {"effects": {"physical": 12, "social": 5, "health": 4, "money": -5}, "duration_hours": 2},
"playing_video_games": {"effects": {"entertainment": 10, "mental": -2, "money": -5}, "duration_hours": 2},
"going_to_a_museum": {"effects": {"entertainment": 5, "mental": 6, "money": -5}, "duration_hours": 3},
# 中 −9（7 个）
"grocery_shopping": {"effects": {"food": 15, "physical": 5, "money": -9}, "duration_hours": 2},
"watching_movie": {"effects": {"entertainment": 10, "mental": -1, "money": -9}, "duration_hours": 2},
"going_to_the_beach": {"effects": {"entertainment": 5, "health": 4, "money": -9}, "duration_hours": 3},
"going_to_a_party": {"effects": {"social": 10, "entertainment": 10, "money": -9}, "duration_hours": 3},
"online_shopping": {"effects": {"entertainment": 8, "mental": -1, "money": -9}, "duration_hours": 1},
"going_to_a_concert": {"effects": {"entertainment": 8, "social": 5, "money": -9}, "duration_hours": 3},
"going_to_the_gym": {"effects": {"physical": 12, "health": 5, "money": -9}, "duration_hours": 2},
# 重 −14（2 个）
"visiting_a_spa": {"effects": {"health": 8, "mental": 6, "money": -14}, "duration_hours": 3},
"going_to_doctor": {"effects": {"health": 12, "money": -14}, "duration_hours": 2},
```

每条用 Edit 替换对应旧行（旧 effects dict → 新 effects dict 含 money）。

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（eating_out money=80 → 25.2、money=20 → 16.8、A1 26.8>26.5、B money=0 → 28）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage4): add money cost to 15 spending activities (tier -5/-9/-14)"
```

---

### Task 2: 集成验证（money 赚-花循环 + 消费被选覆盖 + 节律不回归）

**Files:**
- Test only（不改代码，除非验证暴露标定问题）

**Interfaces:**
- Consumes: Task 1 的 15 消费活动 money 负 effect

- [ ] **Step 1: 写集成测试（3 天采样，含 A2 消费被选 + A3 扣 money 总量）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2})
var tm = TimeManager
tm.game_minutes = 480.0
tm._last_consumed_game_minutes = 480.0
tm.paused = false
var SPENDING = ["eating_out","socializing_at_cafe","going_fishing","playing_sports","playing_video_games","going_to_a_museum","grocery_shopping","watching_movie","going_to_the_beach","going_to_a_party","online_shopping","going_to_a_concert","going_to_the_gym","visiting_a_spa","going_to_doctor"]
var LIGHT = ["eating_out","socializing_at_cafe","going_fishing","playing_sports","playing_video_games","going_to_a_museum"]
var MID = ["grocery_shopping","watching_movie","going_to_the_beach","going_to_a_party","online_shopping","going_to_a_concert","going_to_the_gym"]
var HEAVY = ["visiting_a_spa","going_to_doctor"]
var night_samples = 0
var night_sleeping = 0
var food_zero_run = 0
var food_max_zero_run = 0
var work_count = 0
var money_zero_run = 0
var money_max_zero_run = 0
var money_full_run = 0
var money_max_full_run = 0
var spend_chosen = {}
var money_before = jane.money
var money_spend_total = 0.0
for i in 72:
	var dp = tm.get_day_part()
	var was_idle = not jane.is_busy
	var money_pre = jane.money
	jane.tick(60.0, dp)
	if was_idle and jane.is_busy:
		var act = jane.current_activity
		if act == "working_overtime":
			work_count += 1
		elif SPENDING.has(act):
			spend_chosen[act] = true
			# 估算消费扣的 money（effect money × actual，actual≈1h 采样）
			var meff = jane.list_of_activities[act]["effects"].get("money", 0)
			money_spend_total += abs(meff) * 1.0
	if dp == "night":
		night_samples += 1
		if jane.is_busy and jane.current_activity == "sleeping":
			night_sleeping += 1
	if jane.food <= 0.0:
		food_zero_run += 1
		food_max_zero_run = max(food_max_zero_run, food_zero_run)
	else:
		food_zero_run = 0
	if jane.money <= 0.0:
		money_zero_run += 1
		money_max_zero_run = max(money_max_zero_run, money_zero_run)
	else:
		money_zero_run = 0
	if jane.money >= 100.0:
		money_full_run += 1
		money_max_full_run = max(money_max_full_run, money_full_run)
	else:
		money_full_run = 0
	tm.game_minutes += 60.0
var fail = []
var ratio = float(night_sleeping) / float(night_samples) if night_samples > 0 else 0.0
if work_count < 1 or work_count > 6: fail.append("work 次数 %d 不在 1-6" % work_count)
if night_sleeping < 20: fail.append("night sleeping %d/24 < 20" % night_sleeping)
if food_max_zero_run >= 6: fail.append("food 连续 %dh 跌零" % food_max_zero_run)
if money_max_zero_run >= 6: fail.append("money 卡 0 连续 %dh" % money_max_zero_run)
if money_max_full_run >= 6: fail.append("money 卡 100 连续 %dh" % money_max_full_run)
# A2: 消费被选覆盖轻/中/重各 ≥1
var light_hit = false; var mid_hit = false; var heavy_hit = false
for a in spend_chosen.keys():
	if LIGHT.has(a): light_hit = true
	if MID.has(a): mid_hit = true
	if HEAVY.has(a): heavy_hit = true
if not (light_hit and mid_hit and heavy_hit): fail.append("消费覆盖不足 light=%s mid=%s heavy=%s" % [light_hit, mid_hit, heavy_hit])
if spend_chosen.size() < 3: fail.append("消费活动被选种类 %d < 3" % spend_chosen.size())
# A3: 消费扣 money 总量 > 0
if money_spend_total <= 0.0: fail.append("消费扣 money 总量 %.1f <= 0（消费空转）" % money_spend_total)
print("===STAGE4INT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("work=%d night=%d/24 food_zero=%d money[zero_run=%d full_run=%d] spend_kinds=%d spend_money=%.0f light=%s mid=%s heavy=%s" % [work_count, night_sleeping, food_max_zero_run, money_max_zero_run, money_max_full_run, spend_chosen.size(), money_spend_total, light_hit, mid_hit, heavy_hit])
```

- [ ] **Step 2: 跑测试确认 PASS**

Expected: `PASS`（work 1-6、night ≥20/24、food/money 流动、消费覆盖轻/中/重各≥1、消费种类≥3、消费扣 money>0）

若 FAIL：
- 消费覆盖不足（light/mid/heavy 某档没被选）：该档活动 utility 偏低，可能 need 缺口不够或 money 惩罚太重。先看 spend_kinds 哪些被选；若重档（spa/doctor）从不被选，可接受（贵服务少用），放宽 A2 为轻+中各≥1（重档可选）
- 消费空转（money_spend_total=0）：消费全不被选，说明免费替代总更优 → 降消费档 money 惩罚或升消费 need effect
- money 卡 0：消费+decay > work earn，jane 破产 → 降消费档或升 work
- money 卡 100：消费不够，money 涨满 → 升消费档
- night/food 回归：查消费是否扰乱 select

- [ ] **Step 3: run_and_verify 回归**

`run_and_verify`（timeout=15）。Expected: `hasErrors: false`。

- [ ] **Step 4: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "test(stage4): verify spending loop + coverage + no regression"
```

---

### Task 3: 收尾（spec implemented + 日志）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage4-spending-design.md`
- Create: `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段4-消费扣money.md`

- [ ] **Step 1: spec status → implemented**

Edit spec 第 5 行 `- 状态：已确认（待写实施计划）` → `- 状态：已实现（implemented 2026-06-23；消费覆盖 light/mid/heavy = <实测>）`（填 Task 2 实测）

- [ ] **Step 2: 写 Obsidian 开发日志**

Create `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段4-消费扣money.md`，frontmatter + callouts（summary/check/bug/tip/todo）：
- summary：阶段4 给 15 消费活动加 money 负 effect（分档 −5/−9/−14），money 赚-花循环
- check：Character_Class.gd、spec、日志
- bug：审查抓出消费空转漏洞（免费替代 utility 常更高 + money 流动可仅靠 decay）→ 补 A2/A3 验收
- tip：A1 消费 vs 免费断言（social 低时消费反超）；clamp 非单调 DEFECT 锁定
- todo：阶段5（多工作/职业）、spa vs bath 差异化、clamp 非单调根治

- [ ] **Step 3: Commit + push（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "docs(stage4): finalize spending loop + spec implemented"
git push origin stage4
```

---

## Self-Review 已完成

- **Spec 覆盖**：spec §4.1（15 活动 money）→ Task 1 Step 3；§5 复算（25.2/16.8/26.8/28）→ Task 1 Step 1；§7 单元（A1+B）→ Task 1 Step 1；§7 集成（A2 消费覆盖 + A3 扣 money + money 流动 + work + 节律）→ Task 2 Step 1；§8 Done #1-8 → Task 1-2；§9 限制（不修，标定微调 + clamp DEFECT）→ Task 2 FAIL 处理。无遗漏。
- **Placeholder**：无 TBD/TODO；15 活动新 effects 完整列出；commit hash 标"执行时填"（产物）。
- **类型一致**：money effect 负值 −5/−9/−14 跨 Task/spec 一致；测试 set 单独行（避阶段 3 一行多 set bug）；A2 用 LIGHT/MID/HEAVY 数组与 spec §4 分档一致。
- **已知风险**：Task 1 改 15 活动 effects 即时生效（select 自动用新 utility），run_project 行为变。Task 1 单元测试验证 utility；Task 2 集成验证消费被选（A2，避空转）。A2 重档（spa/doctor）可能少被选（贵服务），FAIL 处理允许放宽到轻+中各≥1。
