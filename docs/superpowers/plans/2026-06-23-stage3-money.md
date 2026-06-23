# 阶段 3：money 需求 + working_overtime 触发 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实施。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 加 money 第 8 个 need + working_overtime 加 money +20/h 正 effect，让 jane 缺钱时 working_overtime net utility 转正、被自主 AI 选中（3 天 1-6 次），money 赚-耗循环成立，阶段 1/2 节律不回归。

**Architecture:** money 复用现有 need 框架（max/decay/initial，utility/decay/clamp 自动覆盖）。Character_Class 加 money 变量 + _init + tick decay + working_overtime effect；Main 加 config + GUI money_label；场景加 MoneyLabel。calculate_utility/select_best_activity 不动。

**Tech Stack:** Godot 4.x（4.7 run / 4.6.2 import）/ GDScript / 无 GUT（execute_gdscript 断言 + run_and_verify）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage3-money-design.md`

## Global Constraints

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 执行前建分支：`git checkout -b stage3`（main 已含 stage1/2，HEAD c8a2d33）
- Godot 二进制：`D:\godot\Godot_v4.6.2-stable_win64.exe`（import）；run_project/run_and_verify 用 4.7
- GDScript tab 缩进
- 无 GUT；测试用 `mcp__godot__script` execute_gdscript（load_autoloads=true）+ `mcp__godot__validation` run_and_verify
- money 标定（v1 微调 D=2）：`money_max=100`、`money_initial=50`、`money_decay=2/h`、`working_overtime money effect=+20/h`（E≈10D 平衡律；原 D=3 集成卡 0/100，详见 spec §9 标定记录）
- 其他 decay（per_hour）：sleep 6 / food 5 / entertainment 4 / social 3 / health 1 / physical 3 / mental 2（阶段 1/2 已定）
- 各 need max=100，初始 round(max/2)=50
- 不主动 commit（项目规则，commit 由用户确认）
- DEFECT `DEFECT.project.character-life-simulator.working-overtime-never-selected`（`D:\workspace\review\.claude\knowledge\defects.md`，status=open）阶段 3 验证后改 fixed

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | money 变量 + _init + tick decay + working_overtime effect | 改（4 处） |
| `Main.gd` | jane_config 加 money + GUI money_label | 改 |
| `node_2d.tscn` | MoneyLabel | 加 |
| `docs/superpowers/specs/2026-06-23-stage3-money-design.md` | spec status | 改（implemented） |
| `D:\workspace\review\.claude\knowledge\defects.md` | DEFECT status | 改（open→fixed） |
| `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段3-money需求.md` | 开发日志 | 新建 |
| TimeManager / project.godot / calculate_utility / 其他 30 活动 | 不动 | — |

---

### Task 1: money need 机制 + working_overtime money effect + 单元测试

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Character_Class.gd`（变量声明区、_init、tick、working_overtime 活动条目）
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Main.gd`（jane_config_dict 加 money 字段，让运行时 jane 能创建）
- Test: `execute_gdscript`（load_autoloads=true）

**Interfaces:**
- Produces: `Character_Class` 新增 `money` / `money_max` / `money_decay` 字段；`_init` 读 `config["money_initial_max"]` / `config["money_initial_decay"]`；`tick` 对 money 做 decay；`working_overtime.effects` 含 `money: 20`。`calculate_utility` / `select_best_activity` 自动覆盖 money（无需改）

- [ ] **Step 1: 写失败测试**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":3})
var fail = []
# money 初始 round(100/2)=50
if abs(jane.money - 50.0) > 0.1: fail.append("money init got %s want 50" % str(jane.money))
# money decay: money=50, tick 1h → 50-3=47（tick 先 decay 再 select，select 不影响 money）
jane.money = 50.0
jane.is_busy = false
jane.tick(60.0, "morning")
if abs(jane.money - 47.0) > 0.1: fail.append("money decay got %s want 47" % str(jane.money))
# working_overtime utility money=20 → +10.4
jane.money = 20.0
jane.sleep = 50.0
jane.food = 50.0
jane.entertainment = 50.0
jane.social = 50.0
jane.health = 50.0
jane.physical = 50.0
jane.mental = 50.0
var u_low = jane.calculate_utility(jane.list_of_activities["working_overtime"])
if abs(u_low - 10.4) > 0.1: fail.append("working money=20 got %s want 10.4" % str(u_low))
# working_overtime utility money=50 → -19
jane.money = 50.0
var u_high = jane.calculate_utility(jane.list_of_activities["working_overtime"])
if abs(u_high - (-19.0)) > 0.1: fail.append("working money=50 got %s want -19" % str(u_high))
print("===STAGE3UNIT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("money_init=%s work_low=%.2f work_high=%.2f" % [str(jane.money), u_low, u_high])
```

- [ ] **Step 2: 跑测试确认 FAIL**

Expected: `FAIL`（`jane.money` 不存在 → 编译/运行错误，或 config 缺 money_initial_max key）

- [ ] **Step 3: 实现 money 机制（4 处 Edit）**

Edit `Character_Class.gd`（tab 缩进）：

3a. 变量声明区，`mental` 之后加 money 三件套（与现有 need 同构）：

```gdscript
var mental

# money（阶段3 新增，第 8 need）
var money_max
var money_decay
var money
```

3b. `_init` 函数，`mental_max = config["mental_initial_max"]` 之后加：

```gdscript
	money_max = config["money_initial_max"]
```

`mental_decay = config["mental_initial_decay"]` 之后加：

```gdscript
	money_decay = config["money_initial_decay"]
```

`mental = round(mental_max / 2)` 之后加：

```gdscript
	money = round(money_max / 2)
```

3c. `tick` 函数，`_decay_need("mental", hours)` 之后加：

```gdscript
	_decay_need("money", hours)
```

3d. `list_of_activities` 的 `working_overtime` 条目，effects 加 `money: 20`：

```gdscript
	"working_overtime": {"effects": {"mental": -3, "physical": -4, "food": -5, "money": 20}, "duration_hours": 4, "allowed_during": ["morning", "afternoon"]},
```

Edit `Main.gd`，`jane_config_dict` 的 `"mental_initial_decay": 2` 之后加：

```gdscript
	"money_initial_max": 100,
	"money_initial_decay": 3
```

- [ ] **Step 4: 跑测试确认 PASS**

Expected: `PASS`（money init 50、decay 后 47、working money=20 → +10.4、money=50 → −19）

- [ ] **Step 5: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Character_Class.gd Main.gd && git commit -m "feat(stage3): add money need + working_overtime wage effect"
```

---

### Task 2: GUI MoneyLabel（Main + 场景）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\Main.gd`（_ready + update_gui + money_label 变量）
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\node_2d.tscn`（加 MoneyLabel）
- Test: `run_and_verify`

**Interfaces:**
- Consumes: Task 1 的 `jane.money` 字段
- Produces: GUI 显示 money 值（MoneyLabel 节点，由 Main._ready 取节点引用、update_gui 赋值）

- [ ] **Step 1: Main.gd 加 money_label 变量**

`var speed_label` 之后加：

```gdscript
var money_label
```

- [ ] **Step 2: Main.gd _ready 取节点引用**

`speed_label = get_node("SpeedLabel")` 之后加：

```gdscript
	money_label = get_node("MoneyLabel")
```

- [ ] **Step 3: Main.gd update_gui 显示 money**

`mental_label.text = "Mental: " + str(int(jane.mental))` 之后加：

```gdscript
	money_label.text = "Money: " + str(int(jane.money))
```

- [ ] **Step 4: node_2d.tscn 加 MoneyLabel**

在 `SpeedLabel` 节点之后追加（offset_top 接在 SpeedLabel 312 之后，340 起）：

```
[node name="MoneyLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 4.0
offset_top = 314.0
offset_right = 300.0
offset_bottom = 340.0
text = "Money:"
```

- [ ] **Step 5: import 刷新 + run_and_verify**

```bash
"D:/godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "D:/GitHub/Character-Life-Simulator-in-Godot"
```

`mcp__godot__validation`（action=run_and_verify, timeout=15）。
Expected: `hasErrors: false`（MoneyLabel 节点存在、_ready 能 get_node、update_gui 不报错）。

- [ ] **Step 6: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add Main.gd node_2d.tscn && git commit -m "feat(stage3): add MoneyLabel GUI for money need"
```

---

### Task 3: 集成验证（working_overtime 1-6 次 + 节律不回归）

**Files:**
- Test only（不改代码，除非验证暴露标定问题）

**Interfaces:**
- Consumes: Task 1 money 机制 + Task 2 GUI

- [ ] **Step 1: 写集成测试（3 天采样）**

`mcp__godot__script`（action=execute_gdscript, load_autoloads=true）：

```gdscript
var C = preload("res://Character_Class.gd")
var jane = C.new({"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":3})
var tm = TimeManager
tm.game_minutes = 480.0
tm._last_consumed_game_minutes = 480.0
tm.paused = false
var night_samples = 0
var night_sleeping = 0
var food_zero_run = 0
var food_max_zero_run = 0
var work_count = 0
var money_min = 100.0
var money_max_seen = 0.0
for i in 72:
	var dp = tm.get_day_part()
	var was_idle = not jane.is_busy
	jane.tick(60.0, dp)
	if was_idle and jane.is_busy and jane.current_activity == "working_overtime":
		work_count += 1
	if dp == "night":
		night_samples += 1
		if jane.is_busy and jane.current_activity == "sleeping":
			night_sleeping += 1
	if jane.food <= 0.0:
		food_zero_run += 1
		food_max_zero_run = max(food_max_zero_run, food_zero_run)
	else:
		food_zero_run = 0
	money_min = min(money_min, jane.money)
	money_max_seen = max(money_max_seen, jane.money)
	tm.game_minutes += 60.0
var fail = []
var ratio = float(night_sleeping) / float(night_samples) if night_samples > 0 else 0.0
if work_count < 1 or work_count > 6: fail.append("working_overtime 次数 %d 不在 1-6" % work_count)
if ratio < 0.8: fail.append("night sleeping %.2f < 0.8" % ratio)
if food_max_zero_run >= 6: fail.append("food 连续 %d h 跌零 (>=6)" % food_max_zero_run)
if money_min <= 0.0 or money_max_seen >= 100.0: fail.append("money 卡边界 min=%s max=%s" % [str(money_min), str(money_max_seen)])
print("===STAGE3INT===")
print("PASS" if fail.is_empty() else "FAIL " + str(fail))
print("work=%d ratio=%.2f night=%d/%d food_zero=%d money[min=%.0f max=%.0f]" % [work_count, ratio, night_sleeping, night_samples, food_max_zero_run, money_min, money_max_seen])
```

- [ ] **Step 2: 跑测试确认 PASS**

Expected: `PASS`（work 1-6、ratio ≥ 0.80、food_zero < 6、money 流动不卡边界）

若 FAIL：
- work=0：money effect 不够，working_overtime net 始终 ≤ 其他活动 → 调高 money effect（如 20→25）或 money_decay（如 3→4），重测
- work>6：jane 过度工作，钱消耗太快或 effect 过强 → 调低 money_decay 或 effect
- ratio < 0.8 / food 跌零：阶段 1/2 回归，查 money 是否扰乱 select（不应，tick/decay 未动）
- money 卡边界：循环失衡，调 decay/effect

- [ ] **Step 3: run_and_verify 最终回归**

`run_and_verify`（timeout=15）。Expected: `hasErrors: false`。

- [ ] **Step 4: Commit（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "test(stage3): verify working_overtime 1-6x/3day + no rhythm regression"
```

---

### Task 4: 收尾（spec implemented + DEFECT fixed + 日志）

**Files:**
- Modify: `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-23-stage3-money-design.md`
- Modify: `D:\workspace\review\.claude\knowledge\defects.md`
- Create: `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段3-money需求.md`

- [ ] **Step 1: spec status → implemented**

Edit spec 第 5 行 `- 状态：已确认（待写实施计划）` → `- 状态：已实现（implemented 2026-06-23；working_overtime 3 天 N 次被选）`（N 填 Task 3 实测值）

- [ ] **Step 2: DEFECT working-overtime → fixed（重跑 detect 确认）**

重跑 detect：读 `Character_Class.gd` 的 `working_overtime` effects，确认含 `money: 20`（正 effect）；集成验证 3 天被选 ≥1 次。

Edit `D:\workspace\review\.claude\knowledge\defects.md`：
- `DEFECT.project.character-life-simulator.working-overtime-never-selected.status=open` → `=fixed`
- 加 `.fixed-in=<Task1/Task3 commit hash>`（执行时填）
- 改 `.note` 追加：`2026-06-23 复测(stage3)：working_overtime effects 含 money +20/h，money 低时 net utility 转正（+10.4）；集成验证 3 天被选 N 次（1-6 区间），money 赚-耗循环成立 → fixed`

- [ ] **Step 3: 写 Obsidian 开发日志**

Create `D:\workspace\Obsidian\CharacterLifeSimulator\开发日志\2026-06-23 阶段3-money需求.md`，frontmatter + callouts（summary/check/bug/tip/todo）：
- summary：阶段3 加 money 第 8 need + working_overtime 给钱，触发工作行为
- check：Character_Class.gd、Main.gd、node_2d.tscn、spec、defects.md
- bug：working_overtime 全负 utility（−44）永不被选（阶段 1/2 遗留）
- tip：money 复用 need 框架 + urgency 缺口权重，缺钱时工作 net 转正
- todo：阶段4 消费活动扣钱（money 赚-花完整循环）、bedtime 时段边界（软指标）

- [ ] **Step 4: Commit + push（待用户确认）**

```bash
cd "D:/GitHub/Character-Life-Simulator-in-Godot" && git add -A && git commit -m "docs(stage3): finalize money need + spec implemented"
git push origin stage3
```

---

## Self-Review 已完成

- **Spec 覆盖**：spec §4.1 架构（Character_Class）→ Task 1；§4.2（Main）→ Task 1 config + Task 2 GUI；§4.3（场景）→ Task 2；§5 标定（money_decay 3 / effect 20，复算 +10.4/−19）→ Task 1 单元断言；§7 单元（money 机制 + utility）→ Task 1 Step 1；§7 集成（work 1-6 + 节律不回归 + money 流动）→ Task 3 Step 1；§8 完成标准（work 1-6）→ Task 3；§9 限制（不修，标定微调）→ Task 3 FAIL 处理。无遗漏。
- **Placeholder**：无 TBD/TODO；所有代码/命令完整（Task 4 commit hash 标"执行时填"，是执行产物）。
- **类型一致**：`money`/`money_max`/`money_decay` 跨 Task 命名统一；`money_initial_max`/`money_initial_decay` config key 在 Character_Class._init 与 Main.jane_config_dict 一致；测试用 `float()`（避 ratio bug）。
- **已知风险**：Task 1 改 money 变量 + _init 读 config 后，运行时 jane = Character_Class.new(jane_config_dict) 需要 jane_config_dict 含 money key——Task 1 Step 3d 同步改 Main config，故 Task 1 后即可运行（中间态：money 存在但 GUI 不显示，Task 2 补 GUI）。Task 1 单元测试用独立 config（含 money），不依赖 Main。
