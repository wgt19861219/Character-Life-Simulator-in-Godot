# 阶段 8：need 均衡机制（deficit 加成）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 给 jane 的单步贪心 utility AI 加 deficit（长期低位 need 累计亏欠）加成，select 时给"补该 need 的活动"utility 加成，使 3 游戏天集成测试 `ent/phys 不长期 0`（avg ≥ 30 或末态 ≥ 20），且不回归 stage1-7 任何指标。

**Architecture:** tick 里基于 need 当前值更新 7 个满足度 need 的 deficit（<30 累计 / >60 衰减；money 不参与）；select_best_activity 里给"对高 deficit need 有正 effect"的活动加 `deficit × WEIGHT` utility。deficit 是长期累计（捕获"长期忽视"），与 urgency 的瞬时缺口互补不震荡；加成放 select 不污染 calculate_utility 的瞬时净效用语义。

**Tech Stack:** Godot 4.7 stable / GDScript（tab 缩进）/ 无 GUT（用 godot MCP 的 `execute_gdscript` 断言 + `run_and_verify` 集成）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-24-stage8-need-deficit-balance-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import 用；run_project/run_and_verify 用 4.7 stable）
- GDScript 用 **tab 缩进**（项目惯例，不可用空格）
- 不引入 GUT 测试框架（YAGNI）；测试用 `mcp__godot__script` 的 `execute_gdscript`（load_autoloads=true）+ `mcp__godot__validation` 的 `run_and_verify`
- jane config 实际 decay（Main.gd，必须与测试 cfg 一致）：sleep=6/food=5/ent=4/social=3/health=1/physical=3/mental=2/money=1.5；所有 max=100
- 中节奏：1 现实秒 = 5 游戏分
- 阶段 1 三铁律 + stage7 方案2（money 不 clamp 下界）仍有效，本阶段不动
- calculate_utility / 活动表 / TimeManager / Main / 场景 全不动（spec §4.4）
- 每个 Task 的 commit 命令给出，但**是否 commit 由用户在执行 handoff 时确认**（项目全局规则：不主动 commit）
- 用户偏好 **inline 执行**（跳过 subagent，直接接手）

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | deficit 状态、tick 更新、select 加成 | + `need_deficit` var + 5 const + tick 里 deficit 更新 + select_best_activity 加成；Task3 调 `DEFICIT_WEIGHT` |
| `docs/superpowers/specs/2026-06-24-stage8-need-deficit-balance-design.md` | 设计 | 状态改 implemented |
| Obsidian 日志/看板 | 记录 | 新增日志 + 推进看板①/节律项 |

不动：calculate_utility、活动表、TimeManager、Main.gd、node_2d.tscn、stage7 money 处理。

---

### Task 1: deficit 状态 + const + tick 更新 + 单元测试（累计/衰减/money 不参与）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（+ var/const 约 41-42 行；tick 约 131 行后插 deficit 更新）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: `need_deficit: Dictionary`（public var，key=need 名 value=float，只含 7 满足度 need）；const `DEFICIT_LOW=30.0`/`DEFICIT_HIGH=60.0`/`DEFICIT_ACCRUE=0.5`/`DEFICIT_DECAY=0.8`/`DEFICIT_WEIGHT=1.0`；tick 每步更新 deficit（decay 循环 + recency decay 之后、`if is_busy` 之前）。Task 2 消费 `need_deficit` 与 `DEFICIT_WEIGHT`。

- [ ] **Step 1: 写失败测试（低位累计 / 高位衰减 / money 不参与）**

`execute_gdscript`（load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var cfg = {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":1.5}
var fail = []

# ① 低位累计：entertainment=20 持续 10h → deficit ≈ 0.5×10 = 5.0
var j1 = C.new(cfg)
j1.entertainment = 20.0
j1.current_activity = "sleeping"   # sleeping 不含 entertainment effect，且 night 允许；is_busy 避免 select 干扰
j1.is_busy = true
j1.remaining_hours = 100.0
for i in range(10):
	j1.tick(60.0, "night")   # 10 步 ×1h；entertainment decay 4/h 从 20→0，全程 <30，每步累计 0.5
var d_low = j1.need_deficit.get("entertainment", 0.0)
if abs(d_low - 5.0) > 0.5: fail.append("低位累计: deficit=%.2f 偏离 ~5.0" % d_low)

# ② 高位衰减：deficit=10、entertainment=70 持续 5h → deficit ≈ 10×0.8⁵ ≈ 3.28
var j2 = C.new(cfg)
j2.need_deficit["entertainment"] = 10.0
j2.entertainment = 70.0
j2.current_activity = "reading"    # reading: mental+12/ent+5，ent net +1/h 保持 >60
j2.is_busy = true
j2.remaining_hours = 100.0
for i in range(5):
	j2.tick(60.0, "afternoon")   # 5 步 ×1h；entertainment 70→75，全程 >60，每步 ×0.8
var d_high = j2.need_deficit.get("entertainment", 0.0)
if abs(d_high - 10.0 * pow(0.8, 5)) > 0.5: fail.append("高位衰减: deficit=%.2f 偏离 ~3.28" % d_high)

# ③ money 不参与：money=0 长期 10h → need_deficit 无 money key
var j3 = C.new(cfg)
j3.money = 0.0
j3.current_activity = "sleeping"
j3.is_busy = true
j3.remaining_hours = 100.0
for i in range(10):
	j3.tick(60.0, "night")
if j3.need_deficit.has("money"): fail.append("money 不参与: 却出现 money deficit=%.2f" % j3.need_deficit["money"])

print("PASS low=%.2f high=%.2f money_absent=%s" % [d_low, d_high, not j3.need_deficit.has("money")]) if fail.is_empty() else print("FAIL " + str(fail))
```

- [ ] **Step 2: 跑测试，确认 FAIL（deficit 机制未实现）**

Expected: `FAIL ["低位累计: deficit=0.00 偏离 ~5.0", ...]`（`need_deficit` 为空 / 不存在，deficit 全 0；若 `need_deficit` 未定义则报 Identifier 失败——二者皆属 FAIL）

- [ ] **Step 3: 加 var + const**

`Character_Class.gd`，在 `RECENCY_PENALTY` 那行（约 42 行）之后插入：

```gdscript
var activity_recency: Dictionary = {}
var RECENCY_PENALTY: float = 10.0

# need deficit（阶段8：长期低位 need 累计亏欠，select 时驱动均衡；money 不参与）
var need_deficit: Dictionary = {}
const DEFICIT_LOW: float = 30.0      # need < 此值开始累计 deficit
const DEFICIT_HIGH: float = 60.0     # need > 此值衰减 deficit
const DEFICIT_ACCRUE: float = 0.5    # 低位累计速率 /h
const DEFICIT_DECAY: float = 0.8     # 高位衰减系数（每游戏小时 ×此值）
const DEFICIT_WEIGHT: float = 1.0    # select 时 deficit 加成权重（Task3 集成调）
```

（`var activity_recency` / `RECENCY_PENALTY` 两行已存在，保留不动；只在它们后面追加 deficit 块。tab 缩进）

- [ ] **Step 4: tick 里加 deficit 更新**

`Character_Class.gd` 的 `tick`，在 recency decay 循环（`for k in activity_recency: ...`）之后、`if is_busy:` 之前插入：

```gdscript
	for k in activity_recency:
		activity_recency[k] = max(0.0, activity_recency[k] - 0.15 * hours)
	# need deficit 更新（阶段8：长期低位 need 累计亏欠，select 时驱动均衡；money 不参与）
	for need_name in ["sleep", "food", "entertainment", "social", "health", "physical", "mental"]:
		var cur_d: float = float(get(need_name))
		if cur_d < DEFICIT_LOW:
			need_deficit[need_name] = need_deficit.get(need_name, 0.0) + DEFICIT_ACCRUE * hours
		elif cur_d > DEFICIT_HIGH:
			need_deficit[need_name] = need_deficit.get(need_name, 0.0) * pow(DEFICIT_DECAY, hours)
	if is_busy:
```

（`for k in activity_recency` 与 `if is_busy:` 两行已存在，保留；只在两者之间插入 deficit 块。tab 缩进；变量名用 `cur_d` 避免与 calculate_utility 的 `current` 混淆）

- [ ] **Step 5: 跑测试，确认 PASS**

Expected: `PASS low=5.00 high=3.28 money_absent=true`（low 允许 ±0.5：entertainment decay 4/h 从 20 起每步仍 <30；high 允许 ±0.5）

- [ ] **Step 6: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage8): add need deficit accrual/decay in tick (money excluded)"
```

---

### Task 2: select_best_activity 加 deficit 加成 + 单元测试（加成驱动选择）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（select_best_activity 约 172-177 行）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Consumes: Task 1 的 `need_deficit` 与 `DEFICIT_WEIGHT`
- Produces: select_best_activity 在 recency 罚后、比大小前，给"对高 deficit need 有正 effect"的活动加 `deficit × WEIGHT` utility。签名不变。

- [ ] **Step 1: 写失败测试（高 deficit 驱动选 ent 活动）**

`execute_gdscript`（load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var cfg = {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":1.5}
var fail = []

# 场景：food=30（eating_at_home utility 强 ~36.5）、entertainment=0 + deficit=50（长期低位累计）
# 无加成时：eating_at_home(36.5) > reading(6) → 选 eating_at_home（非 ent）
# 有加成时：reading(6+50=56) > eating_at_home(36.5) → 选 ent 活动
var j = C.new(cfg)
j.sleep=50.0; j.food=30.0; j.entertainment=0.0; j.social=50.0; j.health=50.0; j.physical=50.0; j.mental=50.0; j.money=50.0
j.need_deficit["entertainment"] = 50.0   # 模拟长期低位累计的高 deficit
j.activity_recency = {}                   # 清零避免 recency 干扰
j.is_busy = false
j.remaining_hours = 0.0
j.select_best_activity("afternoon")       # afternoon 时段所有非 sleeping 活动可选
var chosen = j.current_activity
var ents = j.list_of_activities[chosen]["effects"].get("entertainment", 0) if chosen != "" else 0
if ents <= 0: fail.append("deficit 加成未驱动 ent 活动: 选了 %s(ent effect=%d)" % [chosen, ents])

# 对照：deficit=0 时同场景应选非 ent 活动（eating_at_home）——证明加成是关键
var j2 = C.new(cfg)
j2.sleep=50.0; j2.food=30.0; j2.entertainment=0.0; j2.social=50.0; j2.health=50.0; j2.physical=50.0; j2.mental=50.0; j2.money=50.0
j2.activity_recency = {}
j2.is_busy = false
j2.remaining_hours = 0.0
j2.select_best_activity("afternoon")
var chosen2 = j2.current_activity
var ents2 = j2.list_of_activities[chosen2]["effects"].get("entertainment", 0) if chosen2 != "" else 0
# 不强断 ents2<=0（food=30 时可能恰选边界 ent 活动）；仅打印对照供人工确认
print("PASS chosen=%s(ent=%d) baseline_chosen=%s(ent=%d)" % [chosen, ents, chosen2, ents2]) if fail.is_empty() else print("FAIL " + str(fail) + " | chosen=%s baseline=%s" % [chosen, chosen2])
```

- [ ] **Step 2: 跑测试，确认 FAIL（加成未加，选了 eating_at_home）**

Expected: `FAIL ["deficit 加成未驱动 ent 活动: 选了 eating_at_home(ent effect=0)"]`（无加成时 eating_at_home utility 36.5 最高）

- [ ] **Step 3: select_best_activity 加 deficit 加成**

`Character_Class.gd` 的 `select_best_activity`，把循环体：

```gdscript
	for activity_name in names:
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		if utility > highest_utility:
```

改为：

```gdscript
	for activity_name in names:
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		# deficit 加成：活动对该 need 有正 effect 时，按该 need 累计 deficit 加 utility（money 不参与；阶段8）
		var effects = activities[activity_name]["effects"]
		for need_name in effects:
			if effects[need_name] > 0 and need_name != "money":
				utility += need_deficit.get(need_name, 0.0) * DEFICIT_WEIGHT
		if utility > highest_utility:
```

（保留 `names.sort()` 与 `if utility > highest_utility:` 不变；只在两行之间插入加成块。tab 缩进）

- [ ] **Step 4: 跑测试，确认 PASS**

Expected: `PASS chosen=reading(ent=5) baseline_chosen=eating_at_home(ent=0)`（reading 含 entertainment 正 effect：reading utility = 6(raw) + 50(deficit) = 56 > eating_at_home 36.5；baseline 无加成选 eating_at_home）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "feat(stage8): apply deficit bonus in select_best_activity"
```

---

### Task 3: 集成测试（3 游戏天）+ DEFICIT_WEIGHT 调参

**Files:**
- Modify（仅调参时）: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（`DEFICIT_WEIGHT` const）
- Test: `execute_gdscript`（3 游戏天集成断言）

**Interfaces:**
- Consumes: Task 1 + Task 2 完整 deficit 机制
- Produces: 通过核心验收（ent/phys 不长期 0）+ 不回归的 `DEFICIT_WEIGHT` 终值

- [ ] **Step 1: 写集成测试（核心 ent/phys + 不回归全指标）**

`execute_gdscript`（load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var cfg = {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":1.5}
var jane = C.new(cfg)
var tm = TimeManager
tm.game_minutes=480.0; tm._last_consumed_game_minutes=480.0; tm.speed_scale=1.0; tm.paused=false
var SPEND=["eating_out","grocery_shopping","going_to_the_gym","socializing_at_cafe","watching_movie","going_to_doctor","playing_sports","going_to_a_concert","online_shopping","playing_video_games","going_to_a_museum","going_to_the_beach","visiting_a_spa","going_fishing","going_to_a_party"]
var ent_sum=0.0; var phys_sum=0.0; var night_samples=0; var night_sleeping=0
var mz_run=0; var mz_max=0; var fz_run=0; var fz_max=0; var spend_kinds={}
for i in range(72):
	var dp = tm.get_day_part()
	jane.tick(60.0, dp)
	tm.game_minutes += 60.0
	ent_sum += jane.entertainment
	phys_sum += jane.physical
	if jane.current_activity in SPEND: spend_kinds[jane.current_activity]=true
	if dp=="night":
		night_samples+=1
		if jane.is_busy and jane.current_activity=="sleeping": night_sleeping+=1
	if jane.money<=0.0: mz_run+=1; mz_max=max(mz_max,mz_run)
	else: mz_run=0
	if jane.food<=0.0: fz_run+=1; fz_max=max(fz_max,fz_run)
	else: fz_run=0
var ent_avg=ent_sum/72.0; var phys_avg=phys_sum/72.0
var ent_last=jane.entertainment; var phys_last=jane.physical
var ratio=float(night_sleeping)/max(1,night_samples)
var fail=[]
# 核心目标：ent/phys 不长期 0（avg ≥ 30 或末态 ≥ 20）
if ent_avg < 30.0 and ent_last < 20.0: fail.append("ent 长期低: avg=%.0f,last=%.0f" % [ent_avg,ent_last])
if phys_avg < 30.0 and phys_last < 20.0: fail.append("phys 长期低: avg=%.0f,last=%.0f" % [phys_avg,phys_last])
# 不回归 stage1-7
if mz_max >= 6: fail.append("money_zero_run=%dh>=6" % mz_max)
if fz_max >= 6: fail.append("food_zero_run=%dh>=6" % fz_max)
if ratio < 0.8: fail.append("night=%.2f<0.8" % ratio)
if spend_kinds.size() < 2: fail.append("kinds=%d<2" % spend_kinds.size())
print("PASS ent[avg=%.0f,last=%.0f] phys[avg=%.0f,last=%.0f] mz=%dh food=%dh night=%.2f kinds=%d" % [ent_avg,ent_last,phys_avg,phys_last,mz_max,fz_max,ratio,spend_kinds.size()]) if fail.is_empty() else print("FAIL "+str(fail)+" | ent[%.0f,%.0f] phys[%.0f,%.0f] mz=%dh food=%dh night=%.2f kinds=%d" % [ent_avg,ent_last,phys_avg,phys_last,mz_max,fz_max,ratio,spend_kinds.size()])
```

- [ ] **Step 2: Task1+2 已应用，跑集成测当前 WEIGHT=1.0 基线**

Expected（WEIGHT=1.0）：观察输出。判定分支：
- `PASS`（ent/phys 达标 + 不回归）→ WEIGHT=1.0 选定，跳到 Step 6
- `FAIL ent/phys 长期低` → deficit 加成不够强，进 Step 3 升 WEIGHT
- `FAIL money_zero_run / food_zero_run` → deficit 加成过强挤压 food/money，进 Step 4 降 WEIGHT
- `FAIL` 同时含 ent/phys 低 **和** mz/fz 崩 → 进 Step 5（可能需调 ACCRUE/阈值，或 STOP）

- [ ] **Step 3: 候选升档——DEFICIT_WEIGHT 1.0 → 1.5**

改 `Character_Class.gd` 的 const：`const DEFICIT_WEIGHT: float = 1.0` → `const DEFICIT_WEIGHT: float = 1.5`。跑集成测试。

判定：
- `PASS` → 选定 1.5，Step 6
- `FAIL ent/phys` 仍低 → 再升 2.0（同法），再跑；2.0 仍 FAIL 则进 Step 5
- `FAIL mz/fz`（升档致崩）→ 回退 1.0，进 Step 5

- [ ] **Step 4: 候选降档——DEFICIT_WEIGHT 1.0 → 0.7**

改 `const DEFICIT_WEIGHT: float = 0.7`。跑集成测试。

判定：
- `PASS`（mz/fz 回稳且 ent/phys 仍达标）→ 选定 0.7，Step 6
- `FAIL mz/fz` 仍崩 → 再降 0.5，再跑；0.5 仍崩则进 Step 5
- `FAIL ent/phys`（降档后不达标）→ 回退 1.0，进 Step 5

- [ ] **Step 5: 升降档均不可兼得 → STOP 找用户**

若 WEIGHT ∈ {0.5, 1.0, 1.5, 2.0} 均无法同时满足"ent/phys 达标 + mz/fz 不崩"（spec §8 已知限制），**STOP**：
- 回退 `DEFICIT_WEIGHT` 到 1.0
- 向用户报告：列各档实测 ent/phys 与 mz/fz 数值，说明 ent/phys 改善与 food/money 稳定不可兼得；提议调 `DEFICIT_ACCRUE`/`DEFICIT_LOW` 或重议机制（spec §3 决策表）。等用户裁决，不擅自改机制。

- [ ] **Step 6: 选定 WEIGHT，跑最终集成确认 PASS**

记录选定的 WEIGHT 值与实测数据（ent/phys avg+last、mz/fz、night、kinds）。跑 Step 1 集成测试确认 `PASS`。

- [ ] **Step 7: Commit（待用户确认；仅当 WEIGHT ≠ 1.0 才需）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd && git commit -m "fix(stage8): tune DEFICIT_WEIGHT=<选定值> for ent/phys balance without regression"
```

（若选定 1.0 则跳过此 commit，WEIGHT 未改）

---

### Task 4: 全回归 run_and_verify + spec/日志/看板 收尾

**Files:**
- Modify: spec 状态、Obsidian 日志、任务看板
- Test: `run_and_verify`

**Interfaces:**
- Consumes: Task 1+2+3 完整 deficit 机制 + 选定 WEIGHT

- [ ] **Step 1: 重新 import（刷新 .godot 缓存）**

```bash
"D:/godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "D:/GitHub/Character-Life-Simulator-in-Godot"
```

- [ ] **Step 2: run_and_verify 零错误**

`mcp__godot__validation`（action=run_and_verify, timeout=15）

Expected: `hasErrors=false`，`errors: []`，`warnings: []`（无 Character_Class/TimeManager 错误）

- [ ] **Step 3: 重跑 Task1 单元 + Task2 单元 + Task3 集成，确认全 PASS**

（三个脚本各跑一次，确认 deficit 机制 + 选定 WEIGHT 下全绿）

- [ ] **Step 4: 更新 spec 状态**

`docs/superpowers/specs/2026-06-24-stage8-need-deficit-balance-design.md` 第 5 行状态：
`- 状态：设计中（designing 2026-06-24）` → `- 状态：已实现（implemented 2026-06-24；deficit 累计/衰减 + select 加成；WEIGHT=[选定值]；ent[avg/last 实测]/phys[avg/last 实测] 不长期 0，mz/fz/night/kinds 不回归）`

- [ ] **Step 5: 写 Obsidian 开发日志**

`D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-24 阶段8-need均衡deficit加成.md`。frontmatter（date: 2026-06-24 / project / systems: [[need-deficit机制]]/[[utility-AI]] / status: done）+ callouts 分区（`[!summary]` 今日工作 / `[!check]` 修改的文件 / `[!bug]` 遇到的问题 + `[!tip]` 解决方案 / `[!todo]` 下一步）。内容：架构判定（单步贪心难均衡 8 need）、deficit vs urgency 区别、5 const、WEIGHT 选定过程与实测、改的文件。日志写完按需更新 wiki/MOC + 系统状态。

- [ ] **Step 6: 更新任务看板**

`D:\workspace\Obsidian\CharacterLifeSimulator\任务看板.md`：
- 「进行中」`阶段8 need 均衡机制（deficit 加成）` → 移到「已完成」，标 WEIGHT 选定值 + 实测 ent/phys
- 看板①`消费多样仍不足时调标定`：若 stage8 实测消费 kinds 仍 < 3，保留并备注"stage8 deficit 顺带效果=[实测]"；若 ≥ 3 则关闭
- 更新 frontmatter 计数（total/done/doing/todo）

- [ ] **Step 7: Commit docs（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add docs/superpowers/specs/2026-06-24-stage8-need-deficit-balance-design.md docs/superpowers/plans/2026-06-24-stage8-need-deficit-balance.md && git commit -m "docs(stage8): mark need-deficit-balance implemented + finalize stage 8"
```

（spec + plan 一起 add；Obsidian 日志/看板在 vault 不入此 repo）

---

## Self-Review 已完成

- **Spec 覆盖**：spec §3 决策（deficit 机制/money 不参与/加成在 select/const v1/衰减触发）→ Task1 const+tick + Task2 加成；§4 架构（4.1 状态/4.2 tick 更新/4.3 select 加成/4.4 不动）→ Task1+2 实现 + Global Constraints「不动」清单；§6 测试（单元累计/衰减/money 不参与/加成驱动 + 集成全指标）→ Task1 Step1 + Task2 Step1 + Task3 Step1；§7 完成标准（实现/单元/集成核心/集成不回归/run_and_verify 零错误/看板）→ Task1-4 全覆盖；§8 已知限制（WEIGHT 调参权衡）→ Task3 Step5 STOP 分支。无遗漏。
- **Placeholder**：无 TBD/TODO。Task3 WEIGHT 调参为档位枚举 + 明确判定逻辑（非占位，是实验流程），每档给具体 const 改动与判定；STOP 分支给明确上报动作。
- **类型一致**：`need_deficit: Dictionary`、`DEFICIT_LOW/HIGH/ACCRUE/DECAY/WEIGHT` 命名 Task1 定义、Task2/Task3 消费一致；`select_best_activity(day_part:String)->void` 签名不变；tick 插入点（recency decay 后、is_busy 前）与 select 加成点（recency 罚后、比大小前）与 spec §4.2/4.3 一致；测试 cfg 的 decay 值与 Main.gd 实际 config（money=1.5）一致。
- **已知风险**：① Task3 WEIGHT 调参可能多轮，每轮改 const 后需重跑集成；若走到 Step5 STOP，ent/phys 与 food/money 不可兼得，须用户裁决不擅改机制。② Task1 单元测试 `low` 允许 ±0.5 容差（entertainment decay 4/h 从 20 起的边界），`high` 允许 ±0.5（0.8⁵ 浮点）。③ Task2 对照断言（baseline）仅打印不强断，因 food=30 边界可能波动。④ deficit 不持久化（spec §8），角色重建清零，session 内有效。
