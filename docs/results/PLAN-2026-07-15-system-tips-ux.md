# 可执行方案：系统提示样式 + 覆盖面 + Fast 短文案

> 日期：2026-07-15  
> **主线程**：只 **方案 / 调度 / 验收**；禁止主线程改产品业务代码  
> **执行**：≤8 并发子代理；按文件所有权并行  
> 出包：GHA `baseline-standard-debug` only；本机不 Gradle  
> 用户：装测回报 PASS/FAIL  

真源：`/root/workspace/omnibot-product`  
详报：`docs/results/reports/fix-system-tips-ux-2026-07-15.md`

---

## 0. 用户原意（禁止再误读）

用户指出的是 **现状缺陷**，不是「禁止改样式」：

1. 系统提示 **字号** 与正文相同 → 应更小  
2. 系统提示 **无分割线** → 应有  
3. 颜色视情况可微调  
4. 模型切换 / 思考等级 / 技能 / 审查等 **多数没有** 会话内系统提示  
5. Fast 开启提示过长 → 短句：`1.5× 速度；计费约 1.5–2×`；关闭对应缩短  

左对齐即可；**不要求居中**。

---

## 1. 产品契约

### 1.1 系统提示视觉

| 项 | 要求 |
|----|------|
| 识别 | `user==3` + `content.localSystemTip==true`（或 `kind==local_system_tip`）；兼容 id 含 `codex-fast-tip` / `codex-system-tip` |
| 字号 | 小于正文（约 `_chatTextSize * 0.86`） |
| 分割线 | 上下细线 |
| 颜色 | secondary / 略灰 |
| 布局 | 左对齐；无用户气泡；无 markdown 流式；无 usage footer |

### 1.2 会话内系统提示覆盖

| 操作 | 要有 tip？ | 文案（ZH） |
|------|------------|------------|
| Fast 开 | 是 | `已开启 Fast：1.5× 速度；计费约 1.5–2×。` |
| Fast 关 | 是 | `已关闭 Fast：恢复标准速度与计费。` |
| 模型切换 | 是 | `已切换模型：{id}` |
| 思考等级 | 是 | `已切换思考等级：{effort}` |
| 审查开始 | 是 | `已开始审查`（可与 `/review` 用户气泡并存） |
| 技能插入 | 是 | `已插入技能：@{name}` |
| Plan 开/关 | 是 | `已开启 Plan` / `已关闭 Plan` |
| 权限切换 | 是 | `权限：{label}` |

写入 content 必须带 `localSystemTip: true`。

### 1.3 明确不做

- 不改 goal RPC 语义（另案）  
- 不改附件按钮  
- 主线程不写业务码  
- 不 push `origin`/omnimind-ai  

---

## 2. 模块与文件锁

| 模块 | 独占可写 | 职责 |
|------|----------|------|
| **M1-TipsCopy** | `ui/lib/.../utils/codex_mode_submit.dart`；`ui/test/.../codex_mode_submit_test.dart` | Fast 短文案 + model/effort/review/skill/plan/permission helper |
| **M-Bubble** | `ui/lib/.../command_overlay/widgets/message_bubble.dart` | localSystemTip 小字号 + 上下分割线 |
| **M4-Wire** | `chat_page_codex.dart`；**最小** `chat_page_ui.dart`（仅 permission 回调改调 codex 方法） | tip 标记 + 各开关 call site |
| **M7-Ship** | `docs/results/DELIVERY.md`；commit/push mine；GHA；stage APK | 出包验收材料 |

### 波次

**Wave A（并行 3）**：M1 + M-Bubble +（M4 可读 M1，若 M1 未完可用约定 API）  
**Wave B**：M4（若与 M1 抢 `codex_mode_submit` 则等 M1）  
**Wave C**：M7  

M1 与 M4 文件不重叠 → 可与 Bubble 三线并行；M4 只 **调用** M1 API，不改 M1 文件。

---

## 3. 验收清单（主线程）

| # | 操作 | PASS |
|---|------|------|
| 1 | Fast 开 | 短文案 + **小字号** + **分割线** |
| 2 | Fast 关 | 短文案 + 同上样式 |
| 3 | 切换模型 | 会话内系统提示 |
| 4 | 切换思考等级 | 会话内系统提示 |
| 5 | 点审查 | 系统提示「已开始审查」（或等价） |
| 6 | 插入技能 | 系统提示「已插入技能：@…」 |
| 7 | Plan / 权限 | 各有系统提示 |
| 8 | 普通用户/AI 正文 | 字号 **不变** |

---

## 4. 调度状态

- [x] 方案（纠正误读 + 模块锁）  
- [ ] Wave A：M1 + M-Bubble  
- [ ] Wave B：M4  
- [ ] Wave C：M7  
- [ ] 用户真机验收  

**当前命令**：立即 Wave A（M1 ∥ M-Bubble），同时派 M4（只写 codex/ui 回调，不写 M1/Bubble 文件）。  
