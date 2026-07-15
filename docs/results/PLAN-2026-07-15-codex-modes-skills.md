# 可执行方案：Codex 工作模式面板（真控件名 + 并发模块）

> 日期：2026-07-15  
> 基线：`c388f54` GATE-FAIL  
> **主线程**：只 **方案 / 调度 / 验收**；**禁止**主线程改产品业务代码  
> **执行**：≤**8** 并发子代理；按下方 **文件所有权** 并行，禁止跨权改文件  
> 出包：GHA `baseline-standard-debug` only；本机不 Gradle  
> 用户：装测回报 PASS/FAIL  

真源路径：`/root/workspace/omnibot-product`

---

## 0. 口语 → 真实控件（方案禁止再用 ＋/# 描述）

| 用户口语 | 真实符号 | 文件 |
|----------|----------|------|
| 发图按钮 | `_buildLargeAddButton()` → `onPickAttachment` | `ui/lib/features/home/pages/command_overlay/widgets/chat_input_area_composer.dart` |
| 命令按钮 | `_buildSlashTriggerButton()` · `ValueKey('chat-input-trigger-slash-button')` · `onTriggerSlashCommand` | 同上 |
| 点命令钮 | `_triggerSlashCommandPanel()` | `ui/lib/features/home/pages/chat/chat_page_openclaw.dart` |
| 手输 `/` | `_handleSlashCommandInput()` → `_showSlashCommandPanel` | 同上 |
| 面板 UI | `_buildSlashCommandPanel()` / `_buildSlashCommandDrawerSurface()` | `ui/lib/features/home/pages/chat/chat_page_ui.dart` |
| Codex 根列表数据 | `_buildCodexRootCommandCards()` · cardId `slash-command-codex-*` | 同上 |
| 点选卡片 | `_handleSlashCommandCardSelected` → `_handleCodexSlashCommandCardSelected` | `chat_page_ui.dart` / `chat_page_codex.dart` |
| 发送解析 `/` | `resolveCodexSlashSubmitIntent` → `_tryHandleCodexSlashCommand` | `utils/codex_slash_commands.dart` / `chat_page_codex.dart` |
| 现有 Fast 钮 | `_buildCodexFastToggleButton` · `codexFastEnabled` / `onCodexFastEnabledChanged` | `chat_input_area_composer.dart` |
| Goal RPC | `CodexAppServerService` `thread/goal/get|set|clear` | `ui/lib/services/codex_app_server_service.dart` |
| 技能列表源 | `AgentSkillStoreService.listSkills()` | `ui/lib/services/agent_skill_store_service.dart` |

**本刀改动主入口**：`_buildSlashTriggerButton` + `/` 触发的面板内容与发送映射。  
**不改语义**：`_buildLargeAddButton` / `onPickAttachment` 仍只负责附件。

---

## 1. 产品契约（验收口径）

### 1.1 面板（`_buildCodexRootCommandCards` 重构）

点 `_buildSlashTriggerButton` 或输入以 `/` 开头 → 同一 `_buildSlashCommandPanel`，**新工作模式列表**（不再以「冷命令说明书」为主）：

| 面板项（建议 cardId） | 交互类型 | 行为 |
|----------------------|----------|------|
| `slash-command-codex-goal-mode` | **开关** | 开：进入目标模式；关：发底层 `/goal clear` 并清 UI |
| `slash-command-codex-fast-mode` | **开关** | 开：会话 Fast + **会话内明确提示一句效果**；关：关 Fast |
| `slash-command-codex-skills` | **入口** | 打开技能子列表（与输入 `@` 同一数据源） |
| `slash-command-codex-review` 等 | **动作** | 点一下执行（review 等既有 handler） |
| plan/stop/new/status/… | 保留有用动作 | 次要；不挡主路径 |

### 1.2 目标模式

- **开**（面板开关）：
  - Composer 输入呈现 **目标前缀态**（UI 文案「目标:」；实现可用 prefix chip / 模式条，**禁止**只改 placeholder 却无发送映射）。
  - **常显控件**展示当前目标正文（优先输入框上方新组件；允许其它固定位置，但不能丢）。
  - 用户输入目标内容后点发送 → **底层等价** `/goal <用户文本>`（走 `setGoal` / `CodexSlashSubmitKind.setGoal`，不要只插聊天假消息）。
- **关**：底层 `/goal clear`（`clearGoal`）；去掉前缀态 + 清常显目标 UI。
- 目标进行中：常显 UI 与线程 goal 单源同步（`thread/goal/get` 刷新）。

### 1.3 Fast 模式

- 面板开关（可与现有 `_setCodexFastEnabled` / `serviceTier=fast` 复用）。
- **开启时必须**在会话 transcript 插入一条**可读系统/本地提示**（说明降延迟/Fast 效果）；静默开关 = FAIL。
- 设置页 Fast = 默认；会话开关 = 覆盖（保持已有优先级思路）。

### 1.4 技能（`@` + 面板同源）

- 面板点「技能」或输入 **`@`** → 技能列表（`AgentSkillStoreService.listSkills()`；过滤 enabled 优先）。
- 点选 → 输入框出现 **`@技能名`**（可见 token）。
- 用户再写内容发送 → **底层等同 Codex `/skill`**（实现为提交文本映射/调用 skill 命令路径；需在 `resolveCodexSlashSubmitIntent` 或发送前规范化）。
- **隔离**：现有 model mention（`_showModelMentionPanel` / `_parseActiveModelMentionToken`）不得与 skill `@` 冲突；Codex 模式下 `@` 优先技能（写进方案与测试）。

### 1.5 审查等

- `slash-command-codex-review`：点选即 `startReview`（已有），同类动作保持「点一下就跑」。

### 1.6 明确不做

- 不改 `_buildLargeAddButton` 附件语义  
- 不把 model/permission 塞回 slash 根列表  
- 不改 applicationId / 签名策略  
- 主线程不写业务代码  
- `/resume` 次级页：**本刀 P1 不阻塞**；可 P2 另开（文件空闲时再做）

---

## 2. 模块分割与文件所有权（并发锁）

> 规则：子代理 **只改自己锁内文件**；跨模块只通过约定 API / 新文件；冲突时停手上报主线程。

| 模块 | 职责 | **独占可写文件** | 只读依赖 | 产出 |
|------|------|------------------|----------|------|
| **M0-Scout** | 只读确认 `/skill` 宿主是否存在、goal/fast 调用链 | 无 | 全仓 | `docs/results/reports/scout-skill-goal-fast.md` |
| **M1-Utils** | 纯逻辑：goal 模式态、发送规范化、`/skill` 解析、@skill token | `ui/lib/features/home/pages/chat/utils/codex_slash_commands.dart` **+ 仅新增** `ui/lib/features/home/pages/chat/utils/codex_mode_*.dart`、`codex_skill_*.dart` | service 接口 | 单测或纯 dart 可解析函数 |
| **M2-GoalChrome** | 目标常显 UI + composer 前缀态 props | **仅新增** `ui/lib/features/home/pages/chat/widgets/codex_goal_mode_bar.dart`；`chat_input_area.dart`；`chat_input_area_composer.dart`；`chat_widgets.dart`（只加 props 透传） | M1 API | Goal 条 + prefix 可开关 |
| **M3-PanelCatalog** | 重构根面板卡片：goal 开关 / fast 开关 / skills 入口 / review… | **仅** `chat_page_ui.dart` 中卡片构建与 panel 展示相关段（`_buildCodexRootCommandCards` 等） | M1 card schema 约定 | 新 cardId 列表 |
| **M4-Handlers** | 卡片点选、发送拦截、goal/fast/skill 闭环、会话 Fast 提示句 | **仅** `chat_page_codex.dart`；必要时 `chat_page_openclaw.dart` 的 `@` 分支（**最小 diff**） | M1/M2/M3 约定 | 行为闭环 |
| **M5-SkillPanel** | 技能列表 route（panel 二级）数据装配 | 优先 **新文件** `ui/lib/features/home/pages/chat/utils/codex_skill_panel.dart`；列表 UI 若必须改 `chat_page_ui.dart` → **等 M3 合入后** 串行补丁 | `AgentSkillStoreService` | skills route 卡片 |
| **M6-Wire** | `chat_page_ui.dart` 把 Goal bar 挂到输入区上方；props 接到 ChatInput | 在 M2/M3/M4 之后改 `chat_page_ui.dart` 布局挂载点 | 全部 | 可见联通 |
| **M7-VerifyShip** | 静态核对、DELIVERY 测点、commit 说明、GHA、stage APK | `docs/results/*`；version 仅 ship 时 | 代码 | 可装包 |

### 2.1 并发波次（≤8）

**Wave A（同时 ≤5，文件不重叠）**
1. M0-Scout（只读）  
2. M1-Utils  
3. M2-GoalChrome  
4. M3-PanelCatalog  
5. M5-SkillPanel（尽量只新文件）

**Wave B（M1/M2/M3/M5 完成后，≤2）**
6. M4-Handlers  
7. M6-Wire（若 M3 已改 `chat_page_ui`，M6 与 M3 **禁止并行**；M3 先合再 M6）

**Wave C（串行 1）**
8. M7-VerifyShip → GHA → Download stage → 主线程验收清单

### 2.2 模块接口约定（防打架）

```text
// 会话态（落在 ChatPage state，M4 维护）
bool _codexGoalModeEnabled
String? _codexActiveGoalText
bool _activeCodexFastEnabled  // 已有

// 发送前规范化（M1 提供，M4 调用）
CodexComposerSubmit planCodexComposerSubmit({
  required String rawText,
  required bool goalModeEnabled,
  required List<String> skillMentions, // from @tokens
})
// goalMode + 普通文本 → effective "/goal $text" 或 setGoal intent
// 含 @Skill → effective "/skill ..." 映射
// clear goal mode off → "/goal clear"

// 面板 card 约定字段（M3 产出，M4 消费）
cardId, toolTitle, controlType: toggle|action|nav,
toggleValue?, nav: 'skills'|null
```

---

## 3. 实现要点（给子代理，非主线程执行）

### M1
- 扩展 `CodexSlashSubmitKind` 仅当必要（skill / goalMode）；避免破坏现有 enum 用法。  
- `@Name` token 解析与 model mention 规则分离。  
- `/skill`：先 scout 宿主真实 method；若无 RPC，则提交规范化字符串让 Codex 终端侧识别（在 scout 报告写死策略）。

### M2
- 新组件例如 `CodexGoalModeBar`：显示 objective、清除按钮（回调 clear）。  
- Composer：goalMode 时显示「目标:」前缀 UI；**不**在 M2 里调 RPC。

### M3
- 重排 `_buildCodexRootCommandCards`：goal-mode / fast-mode / skills 置顶；review 等动作随后。  
- goal/fast 用既有 `isToggle` / `toggleValue` 卡片能力（plan 卡可参考）。

### M4
- `_handleCodexSlashCommandCardSelected`：goal-mode toggle、fast toggle、skills nav、review 执行。  
- 发送路径：goalMode 下非 slash 文本 → setGoal；关 goal → clearGoal。  
- Fast on → 本地 transcript 固定文案一条（中英文跟 `LegacyTextLocalizer`）。  
- `@`：Codex 下进 skills 列表（改 `_handleSlashCommandInput` 时最小改动）。

### M5
- `listSkills` → panel cards；空态文案。

### M6
- 在输入区上方插入 `CodexGoalModeBar`（`chat_page_ui` 输入柱布局）。  
- 透传 `codexGoalModeEnabled` 等 props 到 `ChatInputArea`。

### M7
- 更新 `docs/results/DELIVERY.md` 测点；GHA；stage APK；sha256。

---

## 4. 验收清单（主线程用）

| # | 操作 | PASS |
|---|------|------|
| 1 | 点 `chat-input-trigger-slash-button` | 新列表含目标开关/Fast/技能/审查类 |
| 2 | 开目标模式 | 出现「目标:」前缀态 + 常显目标区 |
| 3 | 输入目标并发送 | **会话用户气泡 `/goal …` 且模型有回复**（不能仅 toast）；UI 同步目标正文 |
| 4 | 关目标模式 | `/goal clear`；UI 清除 |
| 5 | 开/关 Fast | **开**提示含优先通道/约1.5×/约2× credits；**关也有提示**；后续 turn 跟随 serviceTier |
| 6 | `@` 或面板技能 | 列表；选中后 `@技能名`；发送≈`/skill` |
| 7 | review | 点一下可跑 |
| 8 | ＋ 附件 | 行为与改前一致 |
| 9 | model/permission | 仍独立按钮，不在根 slash 塞回 |

---

## 5. 主线程调度状态

- [x] 方案（真控件名 + 模块锁 + 波次）  
- [x] Wave A 派发 M0/M1/M2/M3/M5  
- [x] Wave B M4/M6  
- [x] Wave C M7 出包（modes/skills `4a285f7`）  
- [x] 修复出包：goal 可见 turn + Fast 开/关提示（`6b09bf2` / GHA 29400076462）  
- [ ] 用户真机重新验收（重点 #3 / #5）  

**当前命令**：修复包 READY → **主线程等待用户重验**。
