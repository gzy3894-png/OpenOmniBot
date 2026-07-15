# OmniBot 12bugs + B13 执行总方案（主线程调度）

> 日期：2026-07-15  
> 角色：**主线程只方案 / 调度 / 验收**；禁止主线程写产品业务码  
> 真源（禁止猜测，资料不足先搜）：  
> 1. `docs/results/PLAN-2026-07-15-user-12bugs-codex-handoff.md`（B1–B12 用户口径）  
> 2. `/root/workspace/codex-cli-core-implementation-logic.zh-CN.md`（Codex 协议/命令语义）  
> 3. `/tmp/codex-schema.PDR9ft/v2/*`（本机 app-server 类型）  
> 仓：`/root/workspace/omnibot-product` · 分支 `secondary/s1-baseline` · push **仅 mine**  
> 出包：GHA `baseline-standard-debug`  
> 时限：约 **30 分钟**内完成实现 + 静态验收 + 出包调度（真机回归可并行）  
> 并发：**不设上限**；按模块锁并行；效率优先、token 不限

---

## 0. 新 bug（B13）— 用户本轮补充

### B13 — 目标模式必须先发一句话才能用，否则提示「当前没有线程可以使用 goal」

- **现象**：打开目标模式后，若会话尚无 Codex thread，直接设目标 / 发 goal 会失败，提示类似「当前没有可设置 goal 的线程 / 当前没有线程」。
- **协议真源**（codex 文档 §6）：
  - Goal **挂在 thread 上**：`thread/goal/set|get|clear` 均需 `threadId`
  - `/goal <objective>` = `thread/goal/set` + **通常以 objective 启动首个 turn**
  - 无 thread 时不能 set；客户端必须先 `thread/start`（或 resume）再 set
- **代码现状（只读已证）**：
  - `chat_page_codex.dart` 约 1566：`'当前没有可设置 goal 的线程'`
  - `setThreadGoal` 走 `CodexAppServerService.setThreadGoal`，无 ensure-thread 前置
  - 存在 `startThread` / `startTurn`，但 goal 入口未统一 ensure
- **期望**：
  1. 开启 **目标模式** 或首次在目标模式下发送正文时：若无 `threadId` → **静默 `thread/start`**（带当前 model/effort/cwd/config）→ 再 `thread/goal/set`
  2. 设 goal 成功后：按官方语义可用 objective 启动工作 turn（与现有 setGoal 路径对齐）
  3. 用户文案：**目标模式**（中文）；错误 tip 友好且可行动（勿只甩英文 thread）
  4. 与 B1 联修：开 mode 清 `/` slash 草稿；goal 开启时正文 **不** 被当 slash
- **验收**：空会话 → 开目标模式 → **不**先随便发闲聊 → 直接输入目标并发送 → goal 设上 + 常显条有正文 + 模型能看见目标
- **锁**：L-Goal（与 B1/B2/B6 同锁）

---

## 1. Bug 全集与优先级（执行序）

| 级 | ID | 标题 | 锁 |
|----|-----|------|----|
| P0 | **B10** | DEBUG 外置文件日志 | L-Log |
| P0 | **B9** | 模型/思考真源（禁 hardcode） | L-Model |
| P0 | **B1** | 开目标模式残留 `/`，正文未成 goal | L-Goal |
| P0 | **B13** | 无 thread 不能用目标模式 → ensureThread | L-Goal |
| P0 | **B2** | complete 后 UI 零变化 | L-Goal |
| P1 | **B5** | 审查须能附言（禁止一点就跑） | L-Review |
| P1 | **B3** | @技能 actual 隐式 path | L-Skill |
| P1 | **B4** | tip 与 Goal bar 遮挡 | L-Layout |
| P1 | **B7** | **计划模式** 官方方案+审批 | L-Plan |
| P2 | **B8** | `/` 列表裁白+可滚 | L-Layout / slash catalog |
| P2 | **B11** | 显式 `@` 技能按钮 | L-Skill |
| P2 | **B12** | compact 真 RPC + 系统 tip | L-Compact |
| P2 | **B6** | 文案「目标模式」；空态不假锁底栏 | L-Goal |

命名铁律：用户可见 = **目标模式** / **计划模式**；协议层可 goal/plan。

---

## 2. 协议硬约束（摘自 codex 文档，实现不得偏离）

| 功能 | 公开语义 | App Server |
|------|----------|------------|
| 目标模式 `/goal` | set/get/clear；新目标通常启动工作 | `thread/goal/set\|get\|clear`；通知 `thread/goal/updated\|cleared` |
| Goal status | active/paused/blocked/usageLimited/budgetLimited/**complete** | agent 仅可 complete/blocked |
| 计划模式 `/plan` | collaborationMode=plan；可带 prompt 开 turn | `thread/settings/update` 或 `turn/start.collaborationMode` |
| 计划结构 | update_plan 工具 → 步骤状态 | `turn/plan/updated`、`item/plan/delta` |
| 审查 `/review` | 专用 review turn | `review/start(target, delivery)` |
| 技能 | 选择后结构化入 turn | `skills/list`；`UserInput.type=skill` |
| compact | 上下文压缩 | `thread/compact/start` |
| model | 列表与设置 | `model/list`；`thread/settings/update(model=…)` |

B7 最低可用：主区展示 plan 步骤 + 用户 **批准/拒绝**；拒绝不执行实施向；批准后才允许执行向（对齐官方 plan 协作，非仅 tip 开关）。

---

## 3. 模块锁（防踩踏）

| 锁 | 主要文件 | Bugs | 并行 |
|----|----------|------|------|
| **L-Log** | 新建 `ui/lib/services/debug_file_log.dart`（或等价）；Application/Kotlin sink 若需 | B10 | 与几乎所有并行 |
| **L-Model** | `chat_page_model_context.dart`、`chat_page_models.dart`、composer 选择器相关、`model_provider_config_service` 只读对齐 | B9 | 与 L-Goal 并行 |
| **L-Goal** | `chat_page_codex.dart` **goal 段**、`codex_mode_submit.dart`、`codex_goal_mode_bar.dart`、必要时 `chat_input_area*.dart` goal 前缀 | B1 B2 B6 B13 | **串行于本锁内** |
| **L-Review** | `chat_page_codex` review 段、`codex_slash_commands.dart` review 项 | B5 | 与 L-Goal 协调：slash 表小改可短锁 |
| **L-Skill** | `codex_skill_tokens.dart`、`codex_skill_panel.dart`、store、`@` 按钮 UI | B3 B11 | 与 L-Goal 并行 |
| **L-Layout** | `chat_page_ui.dart` inset/tip/slash 面板滚动 | B4 B8 | 与 L-Goal 协调 bar 高度 |
| **L-Plan** | plan 事件 reducer、审批卡、collaborationMode 切换 | B7 | 独立大刀 |
| **L-Compact** | compact handler + system tip | B12 | 与 L-Review 协调 tip 通道 |

`chat_page_codex.dart` 超大：按 **函数段** 认领，禁止整文件重写；冲突时后写方 rebase 再改。

---

## 4. 波次与并发（无上限）

### Wave 0 — 只读侦察（立即 8 并发）

每代理：只读搜代码 + 读协议；输出 `docs/results/reports/scout-<lock>.md`：根因、精确改点、测试点、**不改码**。

1. Scout-Log (B10)  
2. Scout-Model (B9)  
3. Scout-Goal (B1/B2/B6/B13)  
4. Scout-Review (B5)  
5. Scout-Skill (B3/B11)  
6. Scout-Layout (B4/B8)  
7. Scout-Plan (B7)  
8. Scout-Compact (B12)

### Wave 1 — P0 实现（Scout 完成后立即，可 4–5 并发）

- M-Log → B10  
- M-Model → B9  
- M-Goal → B1+B13+B2（同锁内顺序：B13 ensure → B1 发送 → B2 complete 同步 → B6 文案可顺带）  
- 报告：`docs/results/reports/b10-*.md` 等

### Wave 2 — P1（与 Wave1 尾部重叠启动）

- M-Review B5  
- M-Skill B3（B11 可同代理）  
- M-Layout B4  
- M-Plan B7（可拉长，但 30min 内至少：文案「计划模式」+ 主区 plan 卡 + 批准/拒绝最小环）

### Wave 3 — P2 + 集成

- B8 列表白名单 + scrollbar  
- B11 `@` 钮  
- B12 compact  
- M-Verify 静态 grep/验收表  
- M-Ship：commit（子代理）→ push mine → GHA → stage APK → 更新 `DELIVERY.md`

---

## 5. 交付与 GATE

出包后 `DELIVERY.md` 测点至少：

| # | 操作 | PASS |
|---|------|------|
| 1 | 空会话开目标模式直接设目标 | 无「没有线程」；goal 可见（B13+B1） |
| 2 | 开 mode 不手删 `/` 发正文 | 成为 goal，非 slash 脏串（B1） |
| 3 | 模型 complete | bar/mode 变化（B2） |
| 4 | @技能 | 气泡无 path；载荷有 path（B3） |
| 5 | tip+goal | 不互挡（B4） |
| 6 | 审查附言 | 能编辑再跑（B5） |
| 7 | 文案 | 「目标模式」「计划模式」（B6/B7） |
| 8 | 计划模式 | 主区方案+审批（B7） |
| 9 | `/` 列表 | 短、可滚、无死命令（B8） |
| 10 | model/effort | UI=真源（B9） |
| 11 | 复现后 Download 日志 | 有 actual/goal（B10） |
| 12 | `@` 按钮 | 可选技能（B11） |
| 13 | compact | tip+有效果（B12） |

GATE：静态验收全绿 + GHA success + APK staged；真机用户确认后最终 PASS。

---

## 6. 非目标

- 改 applicationId / 上架名  
- 砍 assists  
- push origin / omnimind-ai  
- 主线程写业务码  

---

## 7. 状态板

- [x] 总方案落盘  
- [ ] Wave0 scouts  
- [ ] Wave1 P0  
- [ ] Wave2 P1  
- [ ] Wave3 P2+ship  
- [ ] 静态 GATE  
- [ ] GHA APK  
