# 阶段 7：money 卡 0 根治（非单调 DEFECT + work 时机）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 根治 money 卡 0——修 `calculate_utility` 对 money 的非单调 clamp（方案 2）+ work 时机标定，使 3 游戏天集成测试 `money_zero_run < 6h` 且不回归阶段 1-6。

**Architecture:** `calculate_utility` 的 money 项 net_change 改为只 clamp 上界（`min`），消除"钱越少消费惩罚越小"的非单调；work 时机用最小标定（money_decay / work effect 微调）让 jane 白天攒钱保证 night 储备。机制兜底（缺钱 work 加成）仅当标定不达标时启用。

**Tech Stack:** Godot 4.7 stable / GDScript（tab 缩进）/ 无 GUT（用 godot MCP 的 `execute_gdscript` 断言 + `run_and_verify` 集成）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-24-stage7-money-clamp-fix-design.md`

## Global Constraints

- 项目路径:`D:\GitHub\Character-Life-Simulator-in-Godot`
- Godot 二进制:`D:\godot\Godot_v4.6.2-stable_win64.exe`(import 用;run_project/run_and_verify 用 4.7 stable)
- GDScript 用 **tab 缩进**(项目惯例,不可用空格)
- 不引入 GUT 测试框架(YAGNI);测试用 `mcp__godot__script` 的 `execute_gdscript`(load_autoloads=true)+ `mcp__godot__validation` 的 `run_and_verify`
- 中节奏:1 现实秒 = 5 游戏分
- 阶段 1 三铁律仍有效:① effects/decay per_hour 毛值独立叠加;② `actual=min(hours,remaining)` 只钳 effects;③ 活动结束只解锁
- 每个 Task 的 commit 命令给出,但**是否 commit 由用户在执行 handoff 时确认**(项目全局规则:不主动 commit)
- 用户偏好 **inline 执行**(跳过 subagent,直接接手)

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | utility 计算、活动选择 | 改 `calculate_utility`(方案2);若启用兜底改 `select_best_activity` |
| `Main.gd` | config 标定 | (仅 decay 标定时)改 `jane_config_dict.money_initial_decay` |
| `Character_Class.gd` 活动表 | working_overtime effect | (仅 effect 标定时)改 money 值 |
| `docs/superpowers/specs/2026-06-24-stage7-money-clamp-fix-design.md` | 设计 | 状态改 implemented |
| Obsidian 日志/看板 | 记录 | 新增日志 + 关 DEFECT/待办 |

---

### Task 1: 方案 2 改 calculate_utility + 非单调消除单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`(calculate_utility,约 151-162 行)
- Test: `execute_gdscript`(load_autoloads=true)

**Interfaces:**
- Produces: `calculate_utility(activity: Dictionary) -> float` 新行为——money 项 net_change 只 clamp 上界,满足度 need 维持 clamp 双界。签名不变。

- [ ] **Step 1: 写失败测试(非单调消除 + 满足度 need 不变)**

`execute_gdscript`(load_autoloads=true):

```gdscript
var C = preload("res://Character_Class.gd")
var cfg = {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2}
var jane = C.new(cfg)
var acts = jane.list_of_activities
var fail = []
jane.sleep=50.0; jane.food=50.0; jane.entertainment=50.0; jane.social=50.0; jane.health=50.0; jane.physical=50.0; jane.mental=50.0; jane.money=0.0
var eat0 = jane.calculate_utility(acts["eating_out"])
jane.money=60.0
var eat60 = jane.calculate_utility(acts["eating_out"])
if not (eat0 < eat60): fail.append("eating_out 非单调: m=0=%.1f >= m=60=%.1f" % [eat0, eat60])
jane.money=0.0
var home0 = jane.calculate_utility(acts["eating_at_home"])
if not (eat0 < home0): fail.append("m=0 eating_out=%.1f 未被免费 eating_at_home=%.1f 压制" % [eat0, home0])
jane.money=0.0
var work0 = jane.calculate_utility(acts["working_overtime"])
if not (work0 >= eat0): fail.append("m=0 work=%.1f < eating_out=%.1f 未优先" % [work0, eat0])
jane.money=50.0
var sleep_u = jane.calculate_utility(acts["sleeping"])
if abs(sleep_u - 33.0) > 1.0: fail.append("sleeping=%.1f 偏离~33(满足度need应变)" % sleep_u)
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
```

- [ ] **Step 2: 跑测试,确认 FAIL(当前 v1 非单调)**

Expected: `FAIL ["eating_out 非单调: m=0=28.0 >= m=60=22.4", ...]`(v1 eating_out m=0=28 > m=60=22.4,U 形)

- [ ] **Step 3: 改 calculate_utility(方案 2)**

`Character_Class.gd` 的 `calculate_utility`,把 net_change 行:

```gdscript
		var net_change: float = clamp(current + (effect_ph - decay_ph) * duration, 0.0, mx) - current
```

改为:

```gdscript
		# money 是资源型 need:消费负 effect 不被下界 clamp 抹掉(消除非单调),其余 need 维持 clamp 净模型(阶段7)
		var raw_change: float = current + (effect_ph - decay_ph) * duration
		var net_change: float = (min(raw_change, mx) if need == "money" else clamp(raw_change, 0.0, mx)) - current
```

(其余行不变;tab 缩进)

- [ ] **Step 4: 跑测试,确认 PASS**

Expected: `PASS`(eat0≈14 < eat60≈22.4 单调;eat0<home0=26.5;work0=28>=eat0;sleep_u≈33)

- [ ] **Step 5: Commit(待用户确认)**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "fix(stage7): money utility no lower-clamp (eliminate nonmonotonic DEFECT)"
```

---

### Task 2: work 时机标定 + 集成测试(money_zero_run<6h)

**Files:**
- Modify(候选): `Main.gd`(`money_initial_decay`)或 `Character_Class.gd`(working_overtime money effect)
- Test: `execute_gdscript`(3 游戏天集成断言)

**Interfaces:**
- Consumes: Task 1 方案 2 的 calculate_utility
- Produces: money_zero_run<6h 的标定参数

- [ ] **Step 1: 写集成测试(全指标断言)**

`execute_gdscript`(load_autoloads=true):

```gdscript
var C = preload("res://Character_Class.gd")
var cfg = {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":2}
var jane = C.new(cfg)
var tm = TimeManager
tm.game_minutes=480.0; tm._last_consumed_game_minutes=480.0; tm.speed_scale=1.0; tm.paused=false
var SPEND=["eating_out","grocery_shopping","going_to_the_gym","socializing_at_cafe","watching_movie","going_to_doctor","playing_sports","going_to_a_concert","online_shopping","playing_video_games","going_to_a_museum","going_to_the_beach","visiting_a_spa","going_fishing","going_to_a_party"]
var work_count=0; var spend_kinds={}; var night_samples=0; var night_sleeping=0
var mz_run=0; var mz_max=0; var mf_run=0; var mf_max=0; var fz_run=0; var fz_max=0; var money_min=100.0; var money_max_seen=0.0
for i in range(72):
	var dp = tm.get_day_part()
	jane.tick(60.0, dp)
	tm.game_minutes += 60.0
	if jane.current_activity=="working_overtime": work_count+=1
	if jane.current_activity in SPEND: spend_kinds[jane.current_activity]=true
	if dp=="night":
		night_samples+=1
		if jane.is_busy and jane.current_activity=="sleeping": night_sleeping+=1
	if jane.money<=0.0: mz_run+=1; mz_max=max(mz_max,mz_run)
	else: mz_run=0
	if jane.money>=100.0: mf_run+=1; mf_max=max(mf_max,mf_run)
	else: mf_run=0
	if jane.money<money_min: money_min=jane.money
	if jane.money>money_max_seen: money_max_seen=jane.money
	if jane.food<=0.0: fz_run+=1; fz_max=max(fz_max,fz_run)
	else: fz_run=0
var fail=[]
var ratio = float(night_sleeping)/max(1,night_samples)
if mz_max >= 6: fail.append("money_zero_run=%dh>=6" % mz_max)
if ratio < 0.8: fail.append("night_sleeping=%.2f<0.8" % ratio)
if spend_kinds.size() < 2: fail.append("kinds=%d<2" % spend_kinds.size())
if fz_max >= 6: fail.append("food_zero_run=%dh>=6" % fz_max)
if money_min >= 50: fail.append("money_min=%.0f 未流动" % money_min)
if money_max_seen <= 50: fail.append("money_max=%.0f 未流动" % money_max_seen)
print("PASS mz=%dh night=%.2f kinds=%d food=%dh money[%.0f,%.0f] work=%d" % [mz_max, ratio, spend_kinds.size(), fz_max, money_min, money_max_seen, work_count]) if fail.is_empty() else print("FAIL "+str(fail)+" | mz=%dh night=%.2f kinds=%d food=%dh work=%d" % [mz_max, ratio, spend_kinds.size(), fz_max, work_count])
```

- [ ] **Step 2: Task1 方案2 已应用,跑集成测当前基线**

Expected(方案2 单独): `FAIL ["money_zero_run=6h>=6"]` —— 方案2 修了非单调但 money_zero_run 临界 6h(根因B 未修),其余指标 PASS(night≈0.92, kinds=3, food=3h)。记录 mz_max、work_count 作为标定基准。

- [ ] **Step 3: 候选1——money_decay 2→1.5**

改两处(保持一致):
- `Main.gd` 的 `jane_config_dict`:`"money_initial_decay": 2` → `"money_initial_decay": 1.5`
- Task2 Step1 测试脚本的 cfg:`"money_initial_decay":2` → `"money_initial_decay":1.5`

跑集成测试。

判定:
- 若 `PASS`(mz<6h 且全指标达标)→ 选定候选1,跳到 Step 6
- 若 `FAIL money_zero_run>=6` → 回退 decay=2,进 Step 4
- 若其他指标回归(night<0.8/kinds<2/food>=6) → 回退,进 Step 4

- [ ] **Step 4: 候选2——money_decay 2→1.0**

回退候选1(若改过)。改 decay → 1.0(同样两处:Main.gd + 测试 cfg)。跑集成测试。

判定同 Step 3:
- PASS → 选定候选2,Step 6
- FAIL(mz 或其他) → 回退,进 Step 5

- [ ] **Step 5: 候选3——机制兜底(仅当标定全失败)**

回退所有 decay 改动到 2。改 `Character_Class.gd` 的 `select_best_activity`,在 `if utility > highest_utility` 之前加缺钱 work 加成:

```gdscript
	for activity_name in activities.keys():
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		# 缺钱驱动:money 低于阈值时,赚钱活动(money effect>0)获加成,逼白天攒钱(阶段7 根因B 兜底)
		if money < 25.0 and activities[activity_name]["effects"].get("money", 0) > 0:
			utility += (25.0 - money) * 0.8
		if utility > highest_utility:
```

(decay 维持 2;tab 缩进)

跑集成测试。判定:
- PASS → 选定候选3,Step 6
- FAIL → 回退 select_best_activity 改动;回到 Phase 1 重新评估(spec §3 决策表里否决过的方案需重议——此时 STOP 找用户)

- [ ] **Step 6: 选定标定,确认最小达标改动 + 跑最终集成**

记录选定的候选(1/2/3)与参数。跑 Step1 集成测试确认 `PASS`。

- [ ] **Step 7: Commit(待用户确认)**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd Main.gd && git commit -m "fix(stage7): tune work timing so money_zero_run<6h (根因B)"
```

(只 add 实际改动的文件;候选3 只动 Character_Class.gd,候选1/2 只动 Main.gd)

---

### Task 3: 全回归 + run_and_verify + 收尾

**Files:**
- Modify: spec 状态、Obsidian 日志、任务看板
- Test: `run_and_verify`

**Interfaces:**
- Consumes: Task 1+2 完整修复

- [ ] **Step 1: 重新 import(刷新 .godot 缓存)**

```bash
"D:/godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "D:/GitHub/Character-Life-Simulator-in-Godot"
```

- [ ] **Step 2: run_and_verify 零错误**

`mcp__godot__validation`(action=run_and_verify, timeout=15)

Expected: `hasErrors=false`,`errors: []`,`warnings: []`(无 Character_Class/TimeManager/icon 错误)

- [ ] **Step 3: 重跑 Task1 单元 + Task2 集成,确认全 PASS**

(Task1 单元 + Task2 集成脚本各跑一次,确认方案2 + 选定标定下全绿)

- [ ] **Step 4: 更新 spec 状态**

`docs/superpowers/specs/2026-06-24-stage7-money-clamp-fix-design.md` 第 5 行状态:
`- 状态:设计中（designing 2026-06-24）` → `- 状态:已实现（implemented 2026-06-24；方案2 money 不 clamp 下界 + work时机[选定候选/参数]；money_zero_run [实测]h <6h，night/kinds/food 不回归）`

- [ ] **Step 5: 写 Obsidian 开发日志**

`D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-24 阶段7-money卡0根治.md`。frontmatter(date/project/systems/status)+ callouts 分区(`[!summary]`/`[!check]`/`[!bug]`+`[!tip]`/`[!todo]`)。内容:双根因(systematic-debugging)、方案2 矩阵证据、work时机选定、实测 money_zero_run、改的文件。

- [ ] **Step 6: 更新任务看板**

`D:\workspace\Obsidian\CharacterLifeSimulator\任务看板.md`:
- 待办② `money clamp 非单调根治(DEFECT money-utility-clamp-nonmonotonic)` → 移到已完成,标方案2
- 待办③ `money economy 调标定(work时机)` → 移到已完成,标选定参数(若 work_count 仍 8 则保留 economy 子项)
- 更新 frontmatter 计数(total/done/todo)

- [ ] **Step 7: Commit docs(待用户确认)**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add docs/superpowers/specs/2026-06-24-stage7-money-clamp-fix-design.md && git commit -m "docs(stage7): mark money-clamp-fix implemented + finalize stage 7"
```

---

## Self-Review 已完成

- **Spec 覆盖**:spec §2 双根因 → Task1(A 方案2)+ Task2(B work时机);§3 决策(方案2/标定优先/机制兜底)→ Task1 Step3 + Task2 Step3-5;§4 架构 → Task1 calculate_utility 改 + Task2 标定/机制;§6 测试(单元非单调+集成全指标)→ Task1 Step1 + Task2 Step1;§7 完成标准 → Task1+2+3。无遗漏。
- **Placeholder**:无 TBD/TODO。Task2 标定为候选枚举 + 判定逻辑(非占位,是明确实验流程),每个候选给具体代码改动与预期。
- **类型一致**:`calculate_utility(activity:Dictionary)->float` 签名 Task1 前后一致;`money_initial_decay` 在 Main.gd config 与测试 cfg 同步改;`select_best_activity` 兜底改动与现有 recency 逻辑衔接。
- **已知风险**:Task2 标定试错可能多轮,每轮改 config 需同步 Main.gd + 测试 cfg 两处(漏改致测试与运行不一致);候选3 机制兜底若启用,`money<25` 阈值与 `*0.8` 系数为 v1,集成验证定。
