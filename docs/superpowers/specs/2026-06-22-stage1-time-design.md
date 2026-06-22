# 阶段 1 设计：时间系统 + 活动持续行为

- 日期：2026-06-22
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已确认（待写实施计划）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`

## 1. 目标

让角色从「每 3 秒重选一次活动、瞬时应用」升级为「有昼夜节律的持续行为」：引入游戏时钟、活动持续锁定、按时段过滤活动。

完成 = 角色能自主过完整游戏天（夜间睡、白天工作/吃饭），玩家可调速/暂停。

## 2. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 交互模式 | 自主 + 可干预 | 角色按效用 AI 自主生活；玩家可下指令/暂停/调速；为阶段 6 玩家干预留接口 |
| 时间节奏 | 中节奏 1 现实秒 ≈ 5 游戏分（1 天 ≈ 4.8 现实分）+ 1x/2x/3x + 暂停 | 观察一天约 5 分钟，节奏舒服 |
| 架构 | 方案 A | TimeManager Autoload 单例 + Character 自治 tick + 活动表升级 + Main 撤 Timer |

## 3. 架构与组件

### 3.1 `TimeManager.gd`（注册为 Autoload 单例 `TimeManager`）

职责：持有并推进游戏时间、提供时段查询。不碰角色逻辑。

- `var game_minutes: float = 480.0` — 游戏内分钟，初始 480 = 08:00（morning，刚醒）
- `var speed_scale: float = 1.0` — ∈ {1, 2, 3}
- `var paused: bool = false` — 独立于 speed_scale
- `const BASE_MIN_PER_SEC: float = 5.0` — 中节奏基准
- `_process(delta)`：`if not paused: game_minutes += BASE_MIN_PER_SEC * speed_scale * delta`
- `func get_hour() -> int`：`int(floor(game_minutes / 60.0)) % 24`
- `func get_day_part() -> String`：
  ```gdscript
  var h = get_hour()
  if h >= 22 or h < 6: return "night"
  if h < 12: return "morning"
  if h < 18: return "afternoon"
  return "evening"
  ```
- `func get_clock_string() -> String` — "HH:MM" 格式
- `func set_speed(n)` / `func toggle_pause()`
- `func consume_delta() -> float` — 返回自上次调用以来的 game_minutes 增量（Main 用它取增量，避免与 TimeManager._process 的执行顺序耦合）；内部 `last_consumed_game_minutes` **初值必须 = 480**（= game_minutes 初值），否则首帧 delta=480 会给角色塞 8 小时衰减

**Autoload 注册**：`project.godot` 手写 `[autoload]` 段：
```
[autoload]
TimeManager="*res://TimeManager.gd"
```

### 3.2 `Character_Class.gd` 扩展

新增状态：
- `var current_activity: String = ""`
- `var remaining_hours: float = 0.0`
- `var is_busy: bool = false`

新增/改动方法：
- `func tick(delta_minutes: float, day_part: String)` — 角色自治主循环（见 §4）
- `func select_best_activity(day_part: String)` — 仅 `!is_busy` 时由 Main 调用；按 `day_part` 过滤候选；选中后写状态、锁定 `duration_hours`
- `calculate_utility(activity)` — 入参已是含 `effects/duration_hours/allowed_during` 的字典；内部 `var impact = activity.effects[need] * activity.duration_hours` 还原总效果再算缺口（与现状行为一致，闭环节 1 登记的 utility break）

### 3.3 活动表 `list_of_activities` 升级

每项结构：
```gdscript
"sleeping": {
    "effects": {"sleep": 15, "health": 2, "mental": 3},  # per_hour 毛值
    "duration_hours": 8,
    "allowed_during": ["night"]
}
```

- `effects` 存 **per_hour 毛速率**（不是总效果）—— tick 里直接 `per_hour × actual`，免每帧除法
- 未标 `duration_hours` 的吃默认 2h（在 select_best_activity 里 `.get("duration_hours", 2.0)`）
- 未标 `allowed_during` 的不限制（任意时段）
- 全表见 §6

### 3.4 `Main.gd` 改造

- 删除 `Timer` 节点及其 `_on_timer_timeout` 信号连接
- `_process(delta)`：
  ```gdscript
  var dm = TimeManager.consume_delta()
  jane.tick(dm, TimeManager.get_day_part())
  update_gui()
  ```
- GUI 增三行 Label：**时间**（HH:MM · 时段）、**状态**（正在做 X · 剩 Yh）、**速度档**（1x/⏸ 等）
- `_unhandled_input(event)`：`1/2/3` 切速度、`Space` 暂停（用 `_unhandled_input` 不抢 UI 焦点）

## 4. 数据流（修正版，含 actual 钳制）

```
TimeManager._process(delta):
  if not paused: game_minutes += 5 × speed × delta

Main._process(delta):
  dm = TimeManager.consume_delta()
  jane.tick(dm, TimeManager.get_day_part())
  update_gui()

Character.tick(delta_minutes, day_part):
  hours = delta_minutes / 60.0

  ① decay（完整 hours，所有需求）:
     for need: need = max(0, need - decay[need] × hours)

  ② if is_busy:
       actual = min(hours, remaining_hours)        # 钳到剩余，防结束帧超额
       for need in effects: need = clamp(need + effects[need] × actual, 0, max)
       remaining_hours -= hours                     # 扣完整 hours
       if remaining_hours <= 0: is_busy = false; current_activity = ""

  ③ else:
       select_best_activity(day_part) → 命中则 current/remaining/is_busy 写入
       （仅锁定，不立即给 effects；effects 从下一帧 tick ② 按 actual 给）
```

**三条铁律（审查抓出的硬伤修正，实现时不可退回）：**

1. **毛值叠加**：`effects` 存 per_hour 毛值，`decay` 也 per_hour；两者在 tick 里独立叠加（sleeping 时 food 照常 decay）。不存 net 值，因为负 effect（working_overtime 的 mental）会让"负 effect 时该不该叠 decay"拧成死结。
2. **actual 只钳 effects**：`actual = min(hours, remaining_hours)` 限活动收益到结束点；`decay` 用完整 hours —— 时间真流逝多久，decay 就付多久；活动收益只给到活动结束那刻。
3. **结束不 apply**：活动 `remaining ≤ 0` 时只解锁（`is_busy=false`），**不调 `apply_activity`** —— effects 已在 ② 持续给完。`apply_activity` 在阶段 1 后无调用方（Main 撤 Timer 后无人调），**直接删除**；阶段 6 若需“玩家立即生效指令”再加回。

## 5. 时段过滤

`get_activities(day_part, _name)`：`day_part ∈ item.allowed_during` 才入选（未标 `allowed_during` 的全入选）。**只在 select 那一刻判**，锁定后跨段不重判。

| day_part | 小时 | 时长 |
|---|---|---|
| night | 22:00–06:00（`h ≥ 22 or h < 6`，跨午夜） | 8h |
| morning | 06:00–12:00 | 6h |
| afternoon | 12:00–18:00 | 6h |
| evening | 18:00–22:00 | 4h |

限制型：`sleeping=["night"]`、`take_a_nap=["afternoon","evening"]`、`working_overtime=["morning","afternoon"]`；其余 28 项不限。

## 6. decay / effects 标定

**基准 decay/h**（让 1 游戏天合理耗尽）：

| 需求 | decay/h | 依据 |
|---|---|---|
| sleep | 6 | 醒 16h 耗 ~96，逼一次 8h 睡眠 |
| food | 8 | ~12h 耗尽，日食 2–3 顿 |
| entertainment | 4 | 慢衰 |
| social | 3 | 慢衰 |
| physical | 3 | |
| mental | 2 | |
| health | 1 | 长周期 |

**标定公式**：`per_hour（毛值） = decay + net_target / duration`，net_target 是该活动对该需求的期望净恢复。长活动（dur 大、自身 decay 大）必须按此反推；短活动 decay 占比小可宽松。

**全 31 项活动（per_hour 毛值 / duration / allowed_during）—— v1 初稿，集成验证后微调：**

| 活动 | dur(h) | allowed_during | effects/h（毛值） |
|---|---|---|---|
| sleeping | 8 | night | sleep 15, health 2, mental 3 |
| take_a_nap | 1 | afternoon, evening | sleep 12 |
| eating_at_home | 1 | — | food 55, health 4 |
| eating_out | 2 | — | food 30, social 5, entertainment 5 |
| grocery_shopping | 2 | — | food 15, physical 5 |
| going_to_the_gym | 2 | — | physical 12, health 5 |
| socializing_at_cafe | 2 | — | social 8, food 10 |
| watching_movie | 2 | — | entertainment 10, mental −1 |
| reading | 1 | — | mental 12, entertainment 5 |
| working_overtime | 4 | morning, afternoon | mental −3, physical −4, food −5 |
| going_to_doctor | 2 | — | health 12 |
| playing_sports | 2 | — | physical 12, social 5, health 4 |
| taking_a_bath | 1 | — | health 8, mental 6 |
| cooking | 1 | — | food 20, mental 4 |
| going_to_a_concert | 3 | — | entertainment 8, social 5 |
| visiting_family | 3 | — | social 8, mental 4 |
| doing_yoga | 1 | — | health 8, mental 8 |
| online_shopping | 1 | — | entertainment 8, mental −1 |
| playing_video_games | 2 | — | entertainment 10, mental −2 |
| going_to_a_museum | 3 | — | entertainment 5, mental 6 |
| gardening | 2 | — | mental 5, physical 5 |
| taking_a_walk | 1 | — | health 5, mental 5, physical 5 |
| going_to_the_beach | 3 | — | entertainment 5, health 4 |
| visiting_a_spa | 3 | — | health 8, mental 6 |
| going_fishing | 3 | — | entertainment 5, mental 4 |
| painting | 2 | — | mental 6, entertainment 5 |
| writing | 2 | — | mental 4 |
| going_to_a_party | 3 | — | social 10, entertainment 10 |
| volunteering | 3 | — | social 5, mental 5 |
| going_to_a_library | 2 | — | mental 8 |
| cleaning_the_house | 2 | — | health 4, mental −2 |

**验算（sleeping）**：sleep 初始 50；08:00→22:00 醒 14h，decay 6×14=84 → sleep=0；22:00 睡 8h，effects 15×8=120、decay 6×8=48，net +72 → 06:00 醒来 sleep ≈ 72 ✓（目标 ~70）。

## 7. 测试（不引入 GUT 框架，YAGNI）

**单元**（`execute_gdscript` 断言）：
- `get_day_part` 边界：h=0/5→night、6→morning、11→morning、12→afternoon、17→afternoon、18→evening、21→evening、22→night、23→night
- 时间推进：game_minutes=480（08:00），+300min → `get_hour()=13`
- `paused=true` 时 game_minutes 不增
- `get_activities("night")` 含 sleeping、不含 working_overtime
- **busy 叠加断言（最易出 bug）**：构造 `is_busy`、`remaining=0.5h`、delta 推 0.6h → 验证 effects 只按 `actual=0.5` 给、decay 按 0.6 给、结束帧 `remaining` 归零且 `is_busy=false`、need 未超 max 也未负

**集成**：`run_project` 长跑 3 游戏天，确认无崩溃 + 行为合理（见完成标准第 7 条）。

## 8. 完成标准（Done）

1. TimeManager 单例推进游戏时间，`get_day_part` / `get_clock_string` 正确（含跨午夜）
2. 活动有 duration，期间 `is_busy` 锁定，不再每帧重选
3. effects per_hour 持续 + decay per_hour，需求平滑（无跳变、无负值、无溢出 max）
4a. **行为可断言**：sleeping 的 night 时段过滤生效 —— night 候选含 sleeping、白天候选不含
4b. **数据正确性**：working_overtime 的 `allowed_during=["morning","afternoon"]` 字段静态正确（注：working_overtime 全负效用自主 AI 下不被选，见 §9，故只验字段不验行为）
5. `1/2/3` 切速、`Space` 暂停生效
6. GUI 三行：时间（HH:MM · 时段）、状态（正在做 X · 剩 Yh）、速度档
7. `run_project` 跑 3 游戏天零崩溃，且（headless 可断言）：
   - night 段 `is_busy==true 且 current_activity=="sleeping"` 的样本占比 ≥ 80%
   - food 不连续 ≥ 6 游戏小时停留在 0

## 9. 已知限制（阶段 1 不处理）

- `game_minutes` 单调递增、不归零；跨天靠 `hour % 24`。Godot 的 float 是 double，数月内精度安全；超长跑（年级）再考虑归零
- effects 标定为 v1 初稿，集成验证后按实际行为微调
- 无「第几天」概念，仅时段循环；多日进度留后续阶段
- 玩家「下指令」接口仅占位（is_busy 时被打断的机制留阶段 6）
- **working_overtime 不被选**：全负 effect 导致 utility 恒负，自主 AI 下永不被选（继承自上游现状）。阶段 1 只验 allowed_during 字段正确；待阶段 6 玩家指令或引入「赚钱」正需求后才会被触发
- **utility 对长活动系统性低估**：calculate_utility 用一次性总效果（per_hour × duration）估 wasted，但实际 tick 分帧按 actual 给、每帧 clamp，不会一次性溢出。导致长活动/高 per_hour 活动效用被低估、角色行动时机偏晚（如 sleeping 要 sleep 掉破 45 才考虑睡）。阶段 1 节律仍能跑通；阶段 2 改 per_hour 净效用模型时修正
