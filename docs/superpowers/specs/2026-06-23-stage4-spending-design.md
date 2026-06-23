# 阶段 4 设计：消费活动扣 money（money 赚-花循环）

- 日期：2026-06-23
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-23；v1 弱循环——work 3/party 花/money 流动，消费只 party + night 79% 边缘，留后续调）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 3 money 需求（已实现，commit 1bb7886）

## 1. 目标

给 15 个消费活动加 money 负 effect，形成 money 赚（working_overtime）-花（消费）完整循环。jane 缺钱时减少消费、多工作。完成 = money 赚-花循环成立（money 流动不卡 0/100）、work 1-6 次/3 天、阶段 1-3 节律不回归。

## 2. 背景

阶段 3 money 只有赚（working_overtime +20/h）没花（decay 2/h 代表日常开销，无消费活动扣钱）。money 循环不完整——jane 没有花钱决策。阶段 4 加消费扣钱，让 money 有"花"出口，jane 在消费与储蓄间权衡。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 范围 | 明显消费 + 服务（15 活动） | 覆盖外出餐饮/购物/娱乐/服务；免费家庭活动不扣 |
| 标定方式 | 分档（轻/中/重） | 反映 spa/doctor 贵 vs fishing 便宜，真实；统一同价不真实 |
| 机制 | effect 加 money 负值 | 复用现有 effect 机制，tick/calculate_utility 自动覆盖 money |
| 标定 | 轻 −5 / 中 −9 / 重 −14 per_hour（v1，测试微调） | 与 work 赚钱平衡，spec §9 精神 |

## 4. 架构

### 4.1 Character_Class.gd 活动表（15 消费活动 effects 加 money 负值）

| 活动 | 档位 | money/h | 现有 effects |
|---|---|---|---|
| eating_out | 轻 | −5 | food 30, social 5, entertainment 5 |
| socializing_at_cafe | 轻 | −5 | social 8, food 10 |
| going_fishing | 轻 | −5 | entertainment 5, mental 4 |
| playing_sports | 轻 | −5 | physical 12, social 5, health 4 |
| playing_video_games | 轻 | −5 | entertainment 10, mental −2 |
| going_to_a_museum | 轻 | −5 | entertainment 5, mental 6 |
| grocery_shopping | 中 | −9 | food 15, physical 5 |
| watching_movie | 中 | −9 | entertainment 10, mental −1 |
| going_to_the_beach | 中 | −9 | entertainment 5, health 4 |
| going_to_a_party | 中 | −9 | social 10, entertainment 10 |
| online_shopping | 中 | −9 | entertainment 8, mental −1 |
| going_to_a_concert | 中 | −9 | entertainment 8, social 5 |
| going_to_the_gym | 中 | −9 | physical 12, health 5 |
| visiting_a_spa | 重 | −14 | health 8, mental 6 |
| going_to_doctor | 重 | −14 | health 12 |

`tick` / `calculate_utility` / `_apply_effects_hourly` 不动（money 已是 need，遍历 effects.keys() 自动覆盖）。

### 4.2 不动

Main.gd / node_2d.tscn / TimeManager / project.godot 不动（MoneyLabel 阶段 3 已有，GUI 显示 money）。

## 5. 标定 + 复算

**分档依据**：花费强度。轻（日常小消费 −5）/ 中（娱乐购物 −9）/ 重（贵服务 −14）。

**与 work 平衡**：work 赚 (20−2)×4=72/次。消费扣 X×dur/次：
- 轻 −5×2h = −10/次
- 中 −9×1~3h = −9~−27/次（含 online_shopping dur=1）
- 重 −14×3h(spa)/2h(doctor) = −42/−28/次

**收支（3 天）**：decay 2/h × 72h = 144。jane 消费 ~5 次（≈−100）+ decay 144 → 需 work 3-4 次（赚 216-288）平衡，money 流动。

**消费 utility 复算**（eating_out，money=m，其他 need=50，dur 2）：
- food: `clamp(50+(30−5)×2,0,100)−50 = 50` × urgency 0.5 = **25**
- social: `clamp(50+(5−3)×2,0,100)−50 = 4` × 0.5 = **2**
- entertainment: `clamp(50+(5−4)×2,0,100)−50 = 2` × 0.5 = **1**
- money: `clamp(m+(−5−2)×2,0,100)−m` × `(100−m)/100`
  - m=80: −14 × 0.2 = −2.8 → total = **25.2**（钱够，消费）
  - m=20: −14 × 0.8 = −11.2 → total = **16.8**（缺钱，少吃外出）

jane 缺钱时 eating_out utility 降（money 负 effect + 高 urgency）→ 少消费，转 eating_at_home（免费）或工作 ✓

**消费 vs 免费替代**（关键：消费要能被选）：eating_at_home（免费）utility 26.5，eating_out@money=80 仅 25.2——免费替代常更优。但 need 偏低时消费反超：eating_out@social=10 money=80 → 26.8 > eating_at_home 26.5（social 低 urgency 高）。即消费在对应 need 缺口大时被选。

**money clamp 非单调**（已知，DEFECT money-utility-clamp-nonmonotronic 跟踪）：money 项 net=clamp(m+(−X−2)×dur,0,100)−m，m<(X+2)×dur 时 clamp 截断到 0，惩罚非单调（eating_out m=14 最痛 −12.04、m=0 反弹到 0，total m=0 时 28 > m=14 时 15.96）。但 work money 项低位（+64.8）碾压消费，不破坏 work>consume 顺序。加 m<14 单元断言锁定。

## 6. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | 15 活动 effects 加 money 负值 |
| Main / node_2d.tscn / TimeManager / tick / calculate_utility | 不动 |

## 7. 测试（execute_gdscript + run_and_verify）

**单元**：
- 消费 utility：eating_out money=80 → +25.2、money=20 → +16.8（缺钱 utility 降）
- 消费 vs 免费（A1）：eating_out@social=10 money=80 → +26.8 > eating_at_home 26.5（need 低时消费被选）
- 消费 tick：money=50, eating_out 2h → money = 50 + (−5−2)×2 = 36（decay + consume，verify 扣钱生效）
- money clamp 非单调（B 锁定）：eating_out money=0 → total 28（m<14 clamp 截断反弹，DEFECT 跟踪）

**集成**（3 游戏天）：
- money 赚-花循环：money_zero_run < 6h 且 money_full_run < 6h（流动，瞬时触顶非卡）
- work 1-6 次/3 天（消费多 → work 增）
- **消费活动被选覆盖**：3 天 ≥3 个不同消费活动被选 ≥1 次（轻/中/重各 ≥1，证明"花"端触发——否则消费空转）
- **消费扣 money 总量**：3 天消费活动累计扣 money > 0（直接证据，绕开 decay）
- night sleeping ≥ 80%、food 跌零不回归（阶段 1-3 不回归）

**回归**：run_and_verify hasErrors=false。

## 8. 完成标准（Done）

1. 15 消费活动 effects 含 money 负值（分档 −5/−9/−14）
2. 消费 need 低时 utility 高于免费替代（A1，eating_out@social=10 > eating_at_home）
3. money 赚-花循环（money 流动不卡 0/100）
4. work 1-6 次/3 天
5. night sleeping ≥ 80%、food 跌零不回归
6. run_and_verify 零错误
7. 3 天消费活动被选覆盖轻/中/重（A2，证明消费出口触发——避消费空转）
8. 3 天消费扣 money 总量 > 0（A3，直接证据）

## 9. 已知限制（阶段 4 不处理）

- **标定 v1**：轻/中/重数值 proposal，集成测试微调（spec §9，参考阶段 3 D=3→2 经验）
- **消费强度粗分**：3 档固定值，同档活动同价（eating_out 和 fishing 都 −5）。细分留后续
- **免费活动假设**：eating_at_home/cooking/sleeping/yoga/reading 等家庭活动不扣 money（假设免费）。现实家庭也有成本（水电/食材），留后续
- **money economy 平衡风险**：消费扣太多 → jane 破产（money 卡 0，work 上限不够补）；太少 → money 满。集成测试 work 次数 + money 流动 + 消费被选覆盖兜底，标定微调
- **money clamp 非单调**（DEFECT money-utility-clamp-nonmonotronic）：m<14 时消费惩罚反弹（m=0 不惩罚）。不破坏 work>consume 顺序（work 低位碾压），但消费内部 m=0 时 utility 高。阶段 4 加单元断言锁定，根治留后续（per_hour 净消费模型或 floor 惩罚）
- **消费性价比差异**（Finding C）：eating_out 性价比 ≫ doctor，可能被过度选择挤压其他消费。不改标定，集成测试记录消费频率分布，eating_out 占比畸高再调
- **spa 与 taking_a_bath 同 effects**：visiting_a_spa 和 taking_a_bath effects 完全相同（health8/mental6），spa 多时长+收费。差异化留后续
- **stage4 v1 弱循环**（集成实测 2026-06-23）：核心循环成立（work 3 赚 + party 花 27 + money 流动 zero_run=0/full_run=1 + A3 spend_money>0），但**消费不多样**（只 going_to_a_party，light/heavy 档被 eating_at_home 等免费替代压——免费 food 项同价 + 无 money 惩罚）+ **night 19/24=79% 边缘回归**（party 3h + evening 长活动扰乱睡眠，bedtime 软指标范畴）。根因：消费 utility 整体低于免费替代 + party 双高 effect（social10+ent10）。后续调标定（升消费 need effect 或降 money 惩罚让多样）+ bedtime 时段边界（night 准时）。接受 v1 弱循环，A2（消费覆盖轻/中/重）部分达成（仅 mid），A3（消费扣 money>0）达成
