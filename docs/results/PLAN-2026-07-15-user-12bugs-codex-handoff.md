# 用户 12 点验收 FAIL 交接（给 Codex / 下一执行方）

> 日期：2026-07-15  
> 来源：用户真机截图 + 口述纠偏（**以用户定义为准**，覆盖主线程先前「5 点」解读）  
> 当前包：产品 `d739f18` · APK sha256 `7b7016df0bdf90718550b554798422dba00ceffea0a09eb36072ea6bd40f9886`  
> 分支：`secondary/s1-baseline` · fork only `mine` → `gzy3894-png/OpenOmniBot`  
> 应用：`cn.com.omnimind.bot.debug` · DEBUG 角标  
> **主线程**：只方案/调度/验收；禁止主线程写产品业务码  
> **执行方**：Codex 或 Claude 子代理；GHA `baseline-standard-debug` 出包；push 仅 `mine`

截图 FILE_ID（`codex-preview path <id>`）：

| # | id | 用户关联 |
|---|-----|----------|
| 1 | `1784124762370.2945` | 审查失败文案；`/goal` 清理；无活动目标 |
| 2 | `1784124766703.3002` | `@find-install-skills 这个技能呢` |
| 3 | `1784124771477.965` | bare `/review`；**空 goal 仍开模式+常显条** |
| 4 | `1784124777005.3166` | `/goal` 完成 → 弹出 **Codex plan** 卡 |
| 5 | `1784124779870.4635` | Plan tip 连闪；Fast 文案；`/init` |
| 6 | `1784124781611.5632` | `/` 列表 + goal-mode 开关；键盘 |
| 7 | `1784124783018.5995` | `/` 列表较长；compact/goal-mode |

---

## 0. 总判

| 项 | 结论 |
|----|------|
| 本包相对方案 G/F/S/R/L | **不能 GATE-PASS** |
| 用户认定 bug 数 | **12**（B1–B12） |
| 最高优先级 | **B9（模型/思考是否硬编码）**、**B1（goal 发送被 `/` 污染）**、**B2（完成 goal UI 不变）**、**B5（审查不能附言）**、**B7（Plan 官方审批流）**、**B10（外置日志）** |

**不要**再按主线程旧摘要「只有 3 个 P0」排期；以本文件 B1–B12 为真源。

---

## 0.1 主线程曾反读（必须先认，禁止再按反的修）

| # | 反的理解（错） | 用户正读（对） |
|---|----------------|----------------|
| 1 | 图1「没有活动目标」= **清 goal 后 mode 没关**（G1 完成侧） | **设 goal 就失败了**：goal 已开，输入框残留 `/`，正文发出去 **没变成 goal** → 模型当然看不到。因果在 **发送/前缀**，不在「完成后关 mode」 |
| 2 | 把「complete 后弹出 Plan 卡」当成 goal 主 bug | **B2 主诉**：模型已标记完成，**goal UI 零变化**。Plan 卡乱入是 **另一条（B7）**，不要拿 Plan 卡代替 B2 验收 |
| 3 | bare `/review` +「已开始审查」算 **R1 半通过** | 用户要的是 **能附言再审**；一点就跑 = **B5 FAIL**，不是可接受默认 |
| 4 | `@技能 附言` 气泡在、模型会聊 = **S1 PASS** | 用户要的是 **模型侧隐式 skill 路径**；聊得起来 ≠ B3 过 |
| 5 | 应去掉「目标模式/计划模式」、只留英文 goal/Plan | **反了**。用户要中文产品名：**目标模式**、**计划模式**（协议层仍可 goal/plan） |
| 6 | `/` 列表「要 **上滑** 才知道还有」 | 用户原话：**从下往上展开**，要 **下滑** 才看到更多；且 **无滚动条** 不知可滑 |
| 7 | Fast 文案通顺 ≈ 本包可过 | F1 文案改善 **不抵消** B1–B12；本包仍 **GATE-FAIL** |
| 8 | 优先「关空 mode / compact chip」当本轮主修 | 用户优先级：**B9 真源 > B1 发送 > B2 完成同步 > B10 可观测** 等，见 §2 |

**纪律**：截图只作证据；**因果与期望以用户口述为准**。主线程旧 PLAN 的 G1/S1/R1 验收句若与 B1–B12 冲突，**以本文件为准**。

---


### 命名铁律（2026-07-15 用户当场纠正）

| 概念 | 用户可见中文名 | 协议/代码可保留 |
|------|----------------|-----------------|
| goal | **目标模式** | goal / thread goal |
| plan | **计划模式** | plan / Codex plan |

主线程曾写成「叫 goal/Plan、不要叫目标模式/计划模式」→ **方向反了，已作废**。

## 1. Bug 清单（用户口径）

### B1 — Goal 已开，输入框残留 `/`，正文发出去 **没被识别成 goal**（设失败，不是清失败）
- **现象**：用户 **主动打开** goal 后，composer 里还留着 `/`（slash 草稿），再输入的文字发出去 **没有变成线程 goal** → 模型回「当前没有活动目标可清理」（图1）。
- **正读**：模型没看到目标，是因为 **目标根本没设上**；不是「设上了又被清掉 / mode 没关」。
- **反读禁止**：不要把本条修成「empty 后关 mode」——那是 **B2**；B1 是 **开 mode 后的发送链/残留 `/`**。
- **期望**：
  1. 进入 goal 时 **清掉** 未完成的 `/` slash 草稿，或 goal 与 `/` **互斥**（开 goal 退出 slash 面板并剥掉前导 `/`）。
  2. goal 开启时：用户只打正文 → 稳定 `setThreadGoal` / goal 契约 turn；**禁止**把正文解析成 `/…` slash。
  3. 若 UI 有 goal 前缀 chip，controller 与 actualText 必须是 goal 载荷，不能是 `/` + 正文脏串。
- **验收**：开 goal → **不**手删残留符 → 输入一句目标并发送 → `getThreadGoal`/常显条出现该正文 → 模型再被要求处理 goal 时 **能看见**。
- **嫌疑文件**：`chat_page_codex.dart`（composer submit / goalMode）、`codex_mode_submit.dart`、`chat_input_area*.dart`（controller 文本与 slash 状态）。

### B2 — 模型已「标记为完成」，目标 UI **完全没变**（完成侧；与 B1 分开）
- **现象**：模型回复「已标记为完成…」（图5 一带），用户侧 goal **仍在 / 无变化**（条、mode、前缀该关关、该刷新刷新——以真机为准：用户说 **没任何变化**）。
- **正读**：complete **已发生在模型话术里**，**UI/本地状态未跟随**。不要用「弹出了 Plan 卡」替代本条（Plan = B7）。
- **期望**：服务端 goal **completed/cleared/empty**（或官方 complete 事件）后：
  - 清 `_codexActiveGoalText`；
  - **关** goal chrome（无错误前缀）；
  - **隐藏**无 active 时的占位条；
  - 刷新含 `turn/completed`、goal 事件、本地 complete。
- **与 d739f18**：曾做 hadLocalGoal 关 mode，**真机仍 FAIL** → 查 status 未读、refresh 未跑、complete 与 clear 字段、UI 绑错。
- **验收**：先 **成功设上** goal（B1 PASS 前提）→ 模型 complete → UI 明确变化（条/mode/前缀按契约消失或完成态），**不是**零变化。

### B3 — @技能未把技能路径交给模型（隐式；用户侧不展示路径）
- **现象**：用户气泡可见 `@find-install-skills 这个技能呢`（图2），模型能聊技能，但用户要求：**模型侧应拿到技能文件/目录路径**，**UI 气泡不要暴露路径**。
- **期望**：
  - `displayText`：保留 `@name 附言`（用户可见，无绝对路径）。
  - `actualText` / skill 载荷：含 **隐式 skill path**（如 workspace 下 `…/skills/find-install-skills/SKILL.md` 或 store 解析出的 path），附言仍在。
  - 路径来源：`AgentSkillStoreService` / 技能索引，禁止写死错误盘符。
- **验收**：抓 actualText 或 app-server 入参含 path；气泡无 path；模型能 `read` 到 SKILL.md。
- **嫌疑**：`codex_skill_tokens.dart`、`codex_skill_panel.dart`、`chat_page_codex` skill 发送、`AgentSkillStoreService`。

### B4 — 失败/状态类 UI 与 Goal bar 抢同一底栏区域，互相遮挡
- **现象**：系统 tip、审查状态、「任务已取消」、工具结果条等贴在输入框上方，与 Goal 常显条 **叠层/抢高**，遮消息或互相挡（图3 审查 tip + 空 goal bar + 输入柱）。
- **期望**：
  - 统一 **输入柱高度测量**（tip 区 + goal bar + composer）写入 transcript `bottomOverlayInset`；
  - tip 与 goal bar **垂直堆叠规则**固定（谁上谁下），禁止同槽覆盖；
  - 长回复可滚到柱顶之上。
- **验收**：goal 开 + 出现「已开始审查」/失败 tip 时，末条助手消息不被挡；两栏不重叠像素。
- **嫌疑**：`chat_page_ui.dart` inset、`codex_goal_mode_bar.dart`、系统 tip 插入位置、message list padding。

### B5 — 审查仍然「一点就跑」，不能附言（一点就跑 = FAIL，不是半通过）
- **现象**：点审查或 `/review` → 立刻「已开始审查」（图3），**不能**先写「帮我审查 xx」。
- **反读禁止**：不要把「能启动审查」写成 R1 PASS；用户要的是 **附言能力**，当前 **直接弹出执行** 就是 bug。
- **期望（产品）**：
  - 默认交互改为：**预填** `/review `（或审查占位）→ 用户补路径/说明 → 再发送；或等价「先编辑后跑」。
  - `/review <附言>` 附言必须到模型/审查流（RPC 无 prompt 则 turn 文本，以 M0 为准）。
  - 若保留「无参立即全量 review」，必须是 **显式第二动作**，不能冒充唯一入口。
- **验收**：用户能带「审查某路径」发出且模型/日志见附言；不再只有「指哪打哪立刻跑」。

### B6 — 产品名要叫 **「目标模式」**（不要只显示英文 goal）；且不应错误锁定占位
- **现象**：界面/列表用英文 **goal** / goal-mode 等，**没有**按产品语言叫 **「目标模式」**；且该 chrome **锁死在底栏位置**，空也占位（图6–7）。
- **正读（用户纠正）**：要叫 **目标模式**，不是「只叫 goal、不要叫目标模式」。主线程曾把命名方向写反，**禁止再反**。
- **期望**：
  1. 对外文案统一：**目标模式**（中文产品名）；内部协议/RPC 仍可用 goal。
  2. slash 卡片、常显条、开关说明、settings：用户可见处优先「目标模式」，不要只甩一个裸 `goal`。
  3. **非**永久锁死底栏：无 active、用户未在编辑时不占位挡字。
- **验收**：用户可见文案为「目标模式」；空态不挡字、不假锁。

### B7 — 产品名要叫 **「计划模式」**；且 **官方流程未实现**
- **现象**：
  - 界面/tip 用 Plan / 英文，**没有**稳定叫 **「计划模式」**；
  - 只有 tip 开/关，甚至连闪（图5）；
  - 模型 plan 只出现在 **终端工具卡**（图4），**会话主区无方案、不能审批**；
  - 用户要：按 Codex 官方——模型给出方案 → **用户审批** → 再执行。
- **正读（用户纠正）**：要叫 **计划模式**，不是「只叫 Plan、不要叫计划模式」。命名方向曾被主线程写反。
- **反读禁止**：只改 tip 英文/去抖 **不等于** B7 完成；缺主区方案 + 审批 = 未实现。
- **期望**：
  1. 用户可见名称：**计划模式**（中文产品名）；协议层可仍用 plan。
  2. 主区展示方案；**批准 / 拒绝（或修订）**；批准后才执行向。
  3. 禁止只在 tool 终端卡「成功」而用户侧零交互。
- **验收**：文案见「计划模式」；主区见方案 → 审批可用 → 拒绝不执行 / 批准才继续。

### B8 — `/` 列表过长、含无用项；自下向上展开；无滚动条；要 **下滑** 才看到更多
- **现象**：resume/new/stop/diff/status/compact/goal…（图6–7）；`init` 等未实现仍在；面板 **从下往上** 展开；**无滚动条**，用户不知道可滑；用户原话要 **下滑** 才看到更多（不要写成「上滑」）。
- **期望**：
  1. **裁白名单**：只留已实现有用项；未实现（`init`/`resume`/`new` 等以能力表为准）**下架或修到可用**。
  2. **可视滚动**（滚动条或强 hint）。
  3. 首屏优先常用项；展开/滚动方向与文案、手势提示一致（按真机：内容在上方时提示可 **下滑/上翻** 以用户手感为准，实现时对着真机，**禁止再写反方向**）。
- **验收**：无死命令；一屏内发现可滚；方向与提示不反。

### B9 — 【最严重】模型名与思考等级：硬编码 vs 读配置？
- **现象**：底栏显示 `gpt-5.5 · 超高`（图1–7）。用户质疑是否 **写死**，要求与 **当前环境 model 命令/配置读取方式** 一致。
- **期望**：
  1. Scout：模型列表、当前 model、effort/思考等级 的 **真源**（provider 配置、app-server、toml、远程 `/models` 等）——对齐本机 Claude/Codex wrapper 或 OmniBot 已有 `fetchModels` / profile 逻辑。
  2. UI 展示 = 真源当前值；切换写入真源；**禁止**仅 hardcode `gpt-5.5`/`超高` 而与后端 session 不一致。
  3. 若远程列表失败，明确降级策略与 tip，不静默假值。
- **验收**：改配置/拉模型列表后 UI 与实际 turn 的 model/effort 一致；日志可核对。
- **嫌疑**：`chat_page_model_context.dart`、`chat_page_models.dart`、composer 模型选择器、Kotlin/provider 配置。

### B10 — DEBUG 包无外置日志，修 bug 靠猜
- **现象**：debug 应用 **没有** 稳定输出到用户可取路径（如 `/storage/emulated/0/Download/…`）。
- **期望**（最小可用）：
  - DEBUG/develop 包：会话级或滚动 **文件日志** → 例如  
    `Download/OmniBotLogs/omnibot-debug-YYYYMMDD.log`（或 app 外可读目录）；
  - 含：composer submit 的 display/actual、slash resolve、goal get/set/clear、review start、model/effort、关键错误；
  - 可选：设置页「导出日志 / 打开日志目录」。
  - **禁止**日志写入密钥全文。
- **验收**：复现 B1 后 Download 下能看到 actualText 含脏 `/` 或 goal payload；无需 logcat 权限也能取。

### B11 — `#` 旁应有 `@` 技能入口，勿只靠手打 `@`
- **现象**：输入栏有 `+`、（技能/井号类）控件，用户要 **显式 `@` 按钮** 打开技能列表（与 `/`、附件并列）。
- **期望**：`#`（或现有技能钮）旁增加 **`@` 控件** → 打开技能列表 → 插入 `@name `（路径仍按 B3 隐式给模型）。
- **验收**：只点 `@` 不敲键盘可完成选技能。

### B12 — compact（压缩）不可用：有提示无结果，未走新系统通知
- **现象**：列表有 compact；执行后可能只有旧提示/无结果，**没走** 31c4f35 后的系统 tip 样式/通道。
- **期望**：compact 调通真实压缩/摘要 RPC 或明确 disabled；成功/失败都走 **统一系统 tip**（小字号+分割线）；有结果展示（摘要长度/状态）。
- **验收**：点 compact → tip「已压缩/失败原因」；会话上下文确实变短或官方等价效果。

---

## 2. 建议优先级与波次（给 Codex）

| 波次 | Bugs | 说明 |
|------|------|------|
| **P0** | B9, B1, B2, B10 | 真源错误 / goal 主路径 / 可观测性 |
| **P1** | B5, B7, B3, B4 | 审查附言、Plan 官方流、技能 path、遮挡 |
| **P2** | B8, B11, B12, B6 | 列表 UX、@ 钮、compact、文案 |

推荐顺序：

1. **B10 日志**（先可观测，后续不靠猜）  
2. **B9 模型/思考真源**  
3. **B1+B2 goal 发送与完成同步**（可同一 M4）  
4. **B5 审查附言 UX**  
5. **B3 隐式 skill path**  
6. **B4 底栏堆叠**  
7. **B7 Plan 官方审批**（独立大刀，需协议 scout）  
8. **B8/B11/B12/B6** 收尾

---

## 3. 模块锁建议（防并行踩踏）

| 锁 | 文件倾向 | Bugs |
|----|----------|------|
| L-Log | 新建 `…/debug_file_log.dart` + Application/Kotlin 文件 sink | B10 |
| L-Model | `chat_page_model_context.dart` / models / provider | B9 |
| L-Goal | `chat_page_codex.dart` goal 段、`codex_mode_submit.dart`、`codex_goal_mode_bar.dart` | B1 B2 B6 |
| L-Review | `chat_page_codex` review、`codex_slash_commands` | B5 |
| L-Skill | skill tokens/panel/store + `@` 按钮 UI | B3 B11 |
| L-Layout | `chat_page_ui` inset、tip 容器、slash 面板滚动 | B4 B8 |
| L-Plan | plan 事件、审批卡片、tip 去抖 | B7 |
| L-Compact | compact handler + system tip | B12 |

并行上限仍 **≤8**；P0 建议 3–4 并发。

---

## 4. 明确非目标（本交接默认不扩）

- 改 applicationId / 上架包名  
- 砍 assists 等大模块  
- 远程空 workspace 产品文案（除非挡 B5）  
- push `origin`/上游 omnimind-ai  

---

## 5. 交付与回归

出包后更新 `docs/results/DELIVERY.md`，测点至少覆盖：

| # | 操作 | PASS |
|---|------|------|
| 1 | goal 模式无残留 `/` 设目标 | 模型能看到 goal |
| 2 | 模型 complete goal | bar 关、mode 关 |
| 3 | @技能 | 气泡无 path；模型有 path |
| 4 | tip+goal 同时 | 不互挡 |
| 5 | `/review 路径` | 附言到达 |
| 6 | 文案 goal / Plan | 无错误「目标模式/计划模式」产品名 |
| 7 | Plan | 主区方案 + 审批 |
| 8 | `/` 列表 | 短、可滚、无死命令 |
| 9 | 改 model/effort | UI=真源 |
| 10 | 复现后 | Download 有日志 |
| 11 | `@` 按钮 | 能插入技能 |
| 12 | compact | tip+有效果 |

---

## 6. 给 Codex 的启动指令（可复制）

```text
真源：/root/workspace/omnibot-product
分支：secondary/s1-baseline
只 push mine（gzy3894-png/OpenOmniBot），禁止 origin
读：docs/results/PLAN-2026-07-15-user-12bugs-codex-handoff.md
先做 P0：B10 外置日志 → B9 模型/思考真源 → B1/B2 goal 发送与完成同步
主线程不写业务码；出包 GHA baseline-standard-debug
每 bug 报告写入 docs/results/reports/bNN-*.md
```

---

## 7. 状态

- [x] 用户 12 点口径落盘  
- [x] 交接文件就绪  
- [ ] Codex/子代理认领 P0  
- [ ] 真机回归  

**当前命令**：主线程已交接；**等待 Codex（或用户指定执行方）按 B1–B12 实施**。
