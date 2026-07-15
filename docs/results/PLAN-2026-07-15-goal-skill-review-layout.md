# 可执行方案：Goal 同步 / 底栏遮挡 / Fast 文案 / 技能附言 / 审查附言 / 灰块排版

> 日期：2026-07-15  
> 证据：截图 `1784118372353.6391` / `…4342.9573` / `…5698.5423` / `…7006.590`  
> **主线程**：只 **方案 / 调度 / 验收**；禁止主线程改产品业务代码  
> **执行**：≤8 并发子代理；文件锁并行  
> 出包：GHA `baseline-standard-debug` only  

真源：`/root/workspace/omnibot-product`

---

## 0. 对齐理解（先对齐再改）

| # | 用户现象（截图） | 根因理解 | 本刀是否修 |
|---|------------------|----------|------------|
| **G1** | 模型把 goal 清掉/标完成，常显条变「尚未设置目标」，但 **目标模式开关仍开**（Composer 仍有「目标:」前缀） | 线程 goal 正文被清/完成后只刷新了 `objective` 文本，**未**把 `_codexGoalModeEnabled` 置 false；面板 toggle 与「有无 goal 正文」不同步 | ✅ |
| **G2** | Goal 条 + 输入区 **挡住模型输出**；键盘抬起时更明显 | 消息列表 bottom inset 主要按输入框高度估，**未稳定计入** `CodexGoalModeBar` 高度；底栏叠在 transcript 上，像「没识别输入区占位」 | ✅ |
| **F1** | Fast 提示有歧义，易误解 | 现文案「1.5× 速度；计费约 1.5–2×」像「速度和计费是同一倍数」；用户要 **通顺、无歧义**（速度约 1.5×；计费升高到约 1.5–2× 标准） | ✅ |
| **S1** | `@技能 后面的附言被吞`（`@x 帮我用这个技能干…`） | 规划层 `parseCodexSkillTokens` + `buildCodexSkillCommand(..., prompt: plainText)` **设计上应保留**附言；需验证发送链 `displayText/actualText` 是否丢 `plainText`，以及展示气泡是否只剩附言/只剩 skill。截图 3 用户气泡无 `@`，也要区分「用户没带 @ 发送」vs「规范化吞掉」 | ✅ 验真 + 修发送链，保证 **skill 名 + 附言** 都到模型 |
| **R1** | 审查一点就跑，**不能**写「帮我审查 x 位置」 | `_startCodexReviewCommand` 写死 `addUserMessage('/review')` + `startReview(...)`，**无 prompt 参数**；面板是 one-tap，不进 Composer 附言 | ✅ 支持附言 |
| **L1** | 回复里灰色可点/像代码块的 `complete`、`/workspace`、目标 chip 把「状态:」挤乱 | 助手正文里的路径/状态词被 markdown **行内 code** 渲染成灰底 chip，和普通中文混排导致「状态:」飞到右侧；属于 **渲染/排版** 问题，不是用户要的「代码块」 | ✅ 收敛渲染，避免状态行被拆坏 |

**不在本刀（除非顺手且不扩 scope）**

- Goal 完成策略是否允许模型自动 complete（产品策略另议）  
- 远程 workspace 空路径文案  
- 技能目录为空  

---

## 1. 产品契约（验收口径）

### 1.1 Goal 模式与线程 goal 同步（G1）

- **有 active objective** → 可保持 goal 模式开 + 常显条显示正文  
- **线程 goal 为空 / cleared / completed 且无 active 正文** →  
  - `_codexActiveGoalText = null`  
  - **`_codexGoalModeEnabled = false`**（关模式：去掉「目标:」前缀）  
  - 常显条：**隐藏**或仅在 mode 开且无正文时显示「尚未设置」（二选一，推荐 **mode 关则隐藏 bar**，避免空 bar 占位挡字）  
- 刷新时机：`turn/completed`、set/clear 之后、线程切换；统一走 `_refreshCodexActiveGoalText`（或等价），根据 get 结果 **同时** 更新 mode 与 text  
- 用户手动开目标模式但尚未提交 → 允许 mode 开 + 空正文（「描述目标…」）；**仅当服务端已无 goal 且上次是「曾有 goal 被清掉」时** 自动关 mode，避免误关用户刚打开的空模式  

实现要点（给子代理）：

- 区分 `userExplicitlyEnabledMode` vs `serverHadGoal`；或：get 返回 empty **且** 本地 `_codexActiveGoalText` 曾非空 → 关 mode；get empty 且本地本来就空且用户刚 toggle 开 → 保持开  

### 1.2 底栏不挡消息（G2）

- transcript 底部 padding = **输入区实测高度 + Goal bar 高度（若可见）+ 安全边距**  
- Goal bar 属于输入柱（`topBanner`），高度变化必须触发 `_handleInputAreaHeightChanged` 或独立测量回调  
- 键盘弹起时，最后一条助手消息仍可滚到 bar **上方**，不被 bar/composer 遮住  
- PASS：键盘开 + goal 模式开，长回复最后一行不被挡  

### 1.3 Fast 文案通顺（F1）

禁止歧义并列。建议（可微调，需中英）：

| | ZH | EN |
|---|----|----|
| 开 | `已开启 Fast：响应更快（约 1.5×），计费约为标准的 1.5–2 倍。` | `Fast on: ~1.5× faster replies; billing ~1.5–2× Standard.` |
| 关 | `已关闭 Fast：已恢复标准速度与标准计费。` | `Fast off: standard speed and standard billing.` |

原则：**速度** 与 **计费** 分句说清，不写成「1.5× 速度；计费 1.5–2×」易被读成同一指标。

### 1.4 技能 = 名 + 附言（S1）

用户输入：`@find-install-skills 帮我安装 xxx`

| 层 | 要求 |
|----|------|
| 解析 | `skillNames` + `plainText`（附言）都保留 |
| 发给模型 | `actualText` 必须含 skill 与附言，例如 `/skill find-install-skills 帮我安装 xxx`（或 Codex 等价格式） |
| 用户气泡 | 建议显示原文 `@find-install-skills 帮我安装 xxx`（或等价可读），**禁止**只显示附言导致像没带技能 |
| 回归 | 无 `@` 的普通句不走 skill；多 `@a @b 附言` 附言仍在 |

子代理必须先写 **失败复现用例**（纯 Dart）：构造 plan → 断言 `normalizedText`/`plainText`；再查 M4 `startSkill` 是否用了错字段。

### 1.5 审查可带附言（R1）

- 面板「审查」：仍可 one-tap 默认全量 review（保持现状）  
- **新增**：Composer 支持  
  - `/review 帮我审查 app/src/...`  
  - 或审查模式/占位：选审查后进入输入，发送带 prompt  
- 最小可用方案（推荐）：  
  1. `resolveCodexSlashSubmitIntent`：`/review` 无参 → 现网 startReview；`/review <prompt>` → startReview **或** `startTurn` 文本 `/review <prompt>`（以 app-server 是否接受 prompt 为准；scout 先确认 `review/start` 有无 prompt 字段）  
  2. 若 RPC 无 prompt：改为 `_startCodexTurnCommand(displayText: raw, actualText: '/review ...')` 让模型侧 slash 吃附言  
  3. UI：面板点击可改为 **预填** `/review ` 到输入框（不立刻发送），用户补路径后再发——与「点一下就跑」可并存：无参卡 = 立即跑；有输入 = 带附言  

验收：用户能发出「审查某某路径/文件」且模型/审查流能看到该附言。

### 1.6 灰 chip / 代码块排版（L1）

截图问题：`/workspace`、`complete`、目标句被渲成灰底 chip，「状态:」错位。

| 策略 | 说明 |
|------|------|
| **优先 A** | 助手消息 markdown：对 **单行短 token**（如 `complete`、状态枚举）不要用大号 code chip；inline code 样式改为轻量等宽、不强制灰底大 padding，避免打断中文段落 |
| **优先 B** | 若 `complete`/`状态` 来自结构化 goal 卡片而非纯 markdown，则 goal 状态用 **独立一行/卡片组件**，不要把「状态:」和 chip 塞进同一行 Flex 无换行 |
| **C** | `/workspace` 路径 pill：保留可点，但独占一行或 inline 不挤占「状态」标签 |

PASS：目标完成那一段「目标内容 / 状态 / complete / 耗时」阅读顺序从左到右、从上到下清晰，无飞字。

---

## 2. 模块分割与文件锁

| 模块 | 独占可写 | 职责 |
|------|----------|------|
| **M0-Scout** | 无（只读） | `review/start` 是否支持 prompt；goal get 空/completed 字段形态；skill 发送链 actualText；L1 chip 来自 StreamingText 还是自定义 widget |
| **M1-Copy+SkillParse** | `codex_mode_submit.dart`；`codex_skill_tokens.dart`；对应 test | Fast 通顺文案；skill 附言单测；`/review <prompt>` 解析 kind（若放 utils） |
| **M4-GoalSync+Review+SkillSend** | `chat_page_codex.dart`；最小 `chat_page_ui.dart` | goal 刷新关 mode；skill startSkill 不丢 prompt；review 附言；turn complete 后 refresh goal |
| **M2-Layout** | `codex_goal_mode_bar.dart`；`chat_input_area*.dart` / `chat_page_ui.dart` 输入柱高度 | bar 高度上报；mode 关隐藏 bar；padding |
| **M-Render** | `message_bubble.dart` 和/或 `streaming_text.dart`（scout 定） | inline code / goal 状态行排版 |
| **M7-Ship** | `docs/results/*`；GHA；stage APK | 出包 |

### 波次

**Wave A（并行 ≤4）**  
1. M0-Scout（只读）  
2. M1-Copy+SkillParse  
3. M-Render（与 M1 文件不重叠）  
4. M2-Layout（避免与 M4 同时大改 `chat_page_ui`——若冲突则 M2 先做 bar/composer，M4 后接）

**Wave B（≤2）**  
5. M4-GoalSync+Review+SkillSend（依赖 M0/M1 结论）

**Wave C**  
6. M7-Ship  

---

## 3. 实现要点（给子代理）

### M0

- 读 `CodexAppServerService.startReview` / Kotlin 透传参数  
- 跟一条 skill 发送：`planCodexComposerSubmit('@foo 附言')` → handler actualText  
- 定位 `complete` chip 组件树（StreamingText code span vs 自定义）  

### M1

- Fast 文案替换 + 单测  
- skill：`@name 附言` → plainText==附言，command 含附言  
- 可选：`/review` vs `/review foo` intent  

### M4

- `_refreshCodexActiveGoalText`：empty → 清 text **并** 关 mode（带 1.1 防误关规则）  
- `turn/completed` 后 refresh goal  
- skill：`startSkill` 确保 `actualText`/`displayText` 含附言  
- review：支持附言路径（按 M0）  

### M2

- Goal bar 可见性绑定 mode；测量高度并入 input inset  
- 键盘 + bar 场景目测标准写入报告  

### M-Render

- 修状态行/inline code 样式或结构化 goal 状态 UI  

---

## 4. 验收清单（主线程）

| # | 操作 | PASS |
|---|------|------|
| 1 | 模型完成/清除 goal | 常显目标消失或「无目标」；**目标模式开关关闭**；无「目标:」前缀 |
| 2 | 开目标模式打字 + 键盘 | 助手长回复不被 bar/输入框挡住，可滚到末行 |
| 3 | Fast 开/关 | 文案通顺，速度与计费分句，无歧义 |
| 4 | 发 `@某技能 附言内容` | 气泡能看出技能+附言；模型回复体现附言（未吞） |
| 5 | `/review 审查某路径` 或预填后发送 | 附言到达审查/模型 |
| 6 | 含 complete / 状态 / workspace 的回复 | 排版不乱，「状态」不飞到行尾乱序 |
| 7 | 正文/用户气泡 | 正常聊天气泡字号与结构不被误伤 |

---

## 5. 调度状态

- [x] 对齐理解（本文件）  
- [x] 用户确认方案或修正  
- [x] Wave A 派发  
- [x] Wave B（M4 GoalSync+Review+SkillSend）  
- [x] Wave C（M7-Ship 出包中 / 完成后勾真机）  
- [ ] 真机验收  

**当前命令**：**Wave A/B 实现完成；Wave C M7-Ship BUILDING（push + GHA + stage）**。
