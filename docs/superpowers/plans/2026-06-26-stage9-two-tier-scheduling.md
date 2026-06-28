# 阶段 9：双层调度（survival 强制 + 品质 deficit 轮换 + utility 三层 select）实施计划（事后归档）

> **For agentic workers:** 本 plan 为 **2026-06-28 事后归档**（stage9 已实现 commit `a282c5f`，探索性 TDD 未走事前 plan 流程）。记录实际实施步骤供复盘。checkbox 全 `[x]` 已完成；`[ ]` 为归档收尾项（进行中）。

**Goal:** 给 jane 的单步贪心 select 加双层调度：L1 survival 强制（food/money/sleep 刚需绕过 argmax）+ L2 品质 deficit 轮换（超阈 need 强制补给，打破 max-choose「永远的第二名」）+ L3 utility 兜底，在不回归 stage1-8 硬指标前提下提升 ent/phys。

**Architecture:** `select_best_activity` 改三层串联——L1 `_pick_survival_activity`（food<25 补 food / money<15 work / night+sleep<30 sleeping）→ L2 品质 deficit 轮换（找最大超阈 need、`last_forced_need` 轮换、food≥35/money≥20 守卫 + food_after≥15 预算过滤）→ L3 原 utility（recency 罚 + stage8 deficit 加成）。新增 `_commit_activity`/`_best_replenish` helper + `last_forced_need`/`FORCE_DEFICIT_THRESHOLD=15`。

**Tech Stack:** Godot 4.7 stable / GDScript（tab 缩进）/ 无 GUT（run_and_verify + 入树脚本；execute_gdscript 对 Node 非确定已弃，见 spec §9.2）

**Spec:** `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-26-stage9-two-tier-scheduling-design.md`

## Global Constraints（沿用 stage1-8）

- 项目路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- Godot 二进制：run_project/run_and_verify 用 4.7 stable
- GDScript 用 **tab 缩进**（项目惯例）
- 不引入 GUT 测试框架；测试用入树脚本（`test/*.tscn` + `*.gd` 挂 `extends Node`）+ `run_and_verify`（execute_gdscript 非确定已弃）
- jane config decay（Main.gd）：sleep=6/food=5/ent=4/social=3/health=1/physical=3/mental=2/money=1.5；所有 max=100
- 中节奏：1 现实秒 = 5 游戏分
- stage1 三铁律 + stage7（money 不 clamp 下界）+ stage8（deficit 加成 `WEIGHT=0.5`）仍有效，本阶段不动
- `calculate_utility` / 活动表 / TimeManager / Main / 场景 全不动（spec §4.5）
- 不主动 commit（项目全局规则）

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Character_Class.gd` | 三层 select | + `last_forced_need` + `FORCE_DEFICIT_THRESHOLD` + `_commit_activity` + `_best_replenish` + `_pick_survival_activity`；`select_best_activity` 改三层 |
| `Main.gd` | UI（附加） | 档位1：`NEEDS` 配置驱动 `update_gui` + `_need_color`；档位2：`character_rect`/`state_label` + `_activity_color` + `_any_need_low` |
| `node_2d.tscn` | UI 布局（附加） | 档位1：9 行 need（Label+ProgressBar）；档位2：HBox（左 need 面板 / 右 `CharacterStage`） |
| `test/exp.gd`+`.tscn` | 集成 runner | 72h 统计（night/food/mz/kinds/ent-phys） |
| `test/stage9_test.gd`+`.tscn` | 单元 runner | T1-T5（L1/L2/L3 各层） |
| spec/plan | 归档 | 本文件 + spec（事后补） |

不动：calculate_utility、活动表、TimeManager、stage7-8 处理。

---

### Task 1: 根因实证（systematic-debugging）

**Files:** 测试脚本（临时，复刻公式）

- [x] **Step 1:** 复刻 `calculate_utility` + recency + deficit 公式到测试脚本，对构造状态扫参数（food=20/50/80）看候选 utility 排名翻转 → 钉死「food 刚需垄断 #1」根因（spec §2）。结论：`eating_out` 随 food 从 57 跌到 21，仅 food≥~70 时 ent/phys（`playing_sports` 恒 36.2）才反超；jane food 长期 20~50 → ent/phys 永远 #2。

---

### Task 2: v1 单维硬触发（FAIL — food 崩）

- [x] **Step 1:** food<25 补 food / 最大 deficit need 强制补给（单维硬触发）。
- [x] **Step 2:** 集成实测 `food_zero=9` 崩 → **弃**。崩因：survival 守卫只看决策点（food≥25），长活动（party 3h）锁定期间 food 照 decay 跌穿；单维只补最大 deficit need，phys 永远轮不到。

---

### Task 3: v2 +轮换 + food 预算（FAIL — night 崩）

- [x] **Step 1:** 加 `last_forced_need` 轮换（最大 need == 上次则换第二个）+ food 预算过滤（food_after≥15）。
- [x] **Step 2:** 集成实测 night sleeping `15/24` 崩 → **弃**。崩因：轮换不区分时段，night 时 sleep 被「轮换」掉选了 gym/party，破坏 stage1-2 night 硬指标。
- [x] **Step 3:** systematic-debugging Phase 4.5 判定「治一处崩一处」（v1 food → v2 night）= 架构病信号 → 停止堆 fix，转双层架构。

---

### Task 4: 双层调度（PASS — 4/5 硬指标）

**Files:** `Character_Class.gd`

- [x] **Step 1:** 新增 `last_forced_need: String = ""` + `const FORCE_DEFICIT_THRESHOLD: float = 15.0`。
- [x] **Step 2:** 新增 `_commit_activity(act_name)` helper（统一 commit 尾部）+ `_best_replenish(need_name, day_part)` helper（survival 层补给选最高 utility）。
- [x] **Step 3:** 新增 `_pick_survival_activity`（L1：food<25→`_best_replenish("food")` / money<15→`working_overtime` / night+sleep<30→`sleeping`）。
- [x] **Step 4:** `select_best_activity` 改三层：L1 survival → return；L2 品质 deficit 轮换（最大超阈 need + `last_forced_need` 轮换 + food≥35/money≥20 守卫 + food_after≥15 过滤 → commit）；L3 utility 兜底（recency 罚 + deficit 加成）。
- [x] **Step 5:** 集成实测 PASS：night sleeping 22/24、food_zero=0、mz=2、kinds=3（4/5 硬指标达标）、phys avg 5.3→6.9。
- [x] **Step 6:** `run_and_verify` hasErrors=false。
- [x] **Step 7:** commit `a282c5f`。

---

### Task 5: UI 可视化（同会话附加，非双层调度核心）

**Files:** `Main.gd`、`node_2d.tscn`

- [x] **Step 1（档位1，`d8a4490`）：** need Label → ProgressBar + `_need_color`（<30 红/<60 黄/≥60 绿）+ `NEEDS` 配置数组驱动 `update_gui` 循环。
- [x] **Step 2（档位2，`a8efa29`）：** 改 HBox 左右布局（左 need 面板 / 右 `CharacterStage` Panel：JaneLabel + `CharacterRect` ColorRect 占位 + StateLabel）；`_activity_color`（sleep紫/eat绿/work蓝/运动橙/社交黄）+ `_any_need_low`（任 need<30→角色 modulate 灰）。
- [x] **Step 3:** `run_and_verify` 零错误，中文默认字体正常。

---

### Task 6: 归档收尾（进行中）

- [x] push 到 origin（`90f71f2..a8efa29`，3 commit 已上 origin/main）
- [x] Obsidian 开发日志（`2026-06-26 stage9-双层调度与架构天花板实证.md`）
- [ ] 补 stage9 spec/plan 归档（本文件 + spec）← 进行中（2026-06-28）
- [ ] 回写 stage8 spec §9.4：「deficit 弱效」→ 精确根因「max-choose 第二名陷阱」（指向 stage9 spec）
- [ ] （架构课题，超 stage9）ent/phys avg≥30 多步规划/全局优化 — 留作已知天花板，stage10+ 候选

---

## Self-Review 已完成

- **Spec 覆盖**：spec §3 决策（双层/L1 触发线/L2 阈值+轮换+守卫/流程偏离）→ Task4 Step1-4；§4 架构（4.1 状态/4.2 helper/4.3 三层/4.4 L1/4.5 不动）→ Task4 实现 + Global Constraints「不动」清单；§6 测试（单元 T1-T5 + 集成 72h + run_and_verify）→ Task4 Step5-6 + test/；§7 完成标准（实现/4-5 硬指标/phys 改善/零错/看板）→ Task4-6；§9.4 架构天花板 → Task6 最后一项。无遗漏。
- **事后归档诚实性**：Task2（v1 FAIL）、Task3（v2 FAIL）如实记录崩点与弃用，非「跳过失败路径」；§9.1 流程偏离（未走事前 plan）已声明。
- **类型/签名一致**：`_pick_survival_activity(day_part:String)->String`、`_best_replenish(need_name:String,day_part:String)->String`、`_commit_activity(act_name:String)->void`、`select_best_activity(day_part:String)->void` 签名与 spec §4 一致；`FORCE_DEFICIT_THRESHOLD=15.0` / `last_forced_need` 命名 spec-plan-code 三处一致；L2 守卫线 food≥35/money≥20、food_after≥15 与 spec §3 决策表一致。
- **已知风险**：① ent/phys avg≥30 是架构天花板（spec §9.4），本 plan 不假装解决，Task6 末项留作 stage10+ 候选。② L2 强制绕过 argmax 会偶尔选低 utility 活动（spec §8，设计 trade-off）。③ 测试依赖入树脚本而非 execute_gdscript（spec §9.2 非确定 bug）。
