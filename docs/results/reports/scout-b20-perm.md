# Scout B20 · 权限只 setState / 默认 fullAccess / autoReview 错映射

> 证据属性：**历史快照，不代表当前代码状态**。2026-07-18 从本地遗留报告定向纳入；原文件 SHA-256：`e4c85266dab97779c7c9a5b12362aef780123d283931c2bb5a485bdafd583003`。
> 治理审查：未发现 token、密钥、认证头、个人信息或需脱敏值；路径均为仓库相对路径。当前实施与交付状态只认 `docs/results/EXEC-2026-07-18-b38-approval-models.md`。

**结论**：切换权限 **仅本地 setState+tip**，无 settings RPC；默认 **fullAccess=`never`** 不弹授权；autoReview 映成 `guardian_subagent` 而非 schema `auto_review`。

## 证据

| 点 | 位置 | 行为 |
|----|------|------|
| 只 setState | `chat_page_codex.dart:649-663` `_setCodexPermissionMode` | 改 `_codexPermissionMode` + tip；**无** `updateThreadSettings` / pref |
| 默认 fullAccess | `chat_page.dart:453` | `_codexPermissionMode = CodexPermissionMode.fullAccess` |
| 映射 approval | `chat_page_codex.dart:6740-6745` | full→`never`；default/autoReview→`on-request` |
| 映射 reviewer | `:6748-6752` | **autoReview→`guardian_subagent`**（错）；应用 `auto_review` |
| sandbox | `:6756-6762` | full→`dangerFullAccess`；default/autoReview→**null**（吃服务端默认） |
| turn 携带 | `:2798-2800` startTurn；`:2397-2399` startReview | 用当前 mode 的三件套，但 mode 切换本身未 RPC 固化到 thread settings |
| 审批链路存在 | `:4161+` requestApproval 规约；`codex_event_reducer.dart:487` | 卡片/事件路径在；**policy=never 时不会走到用户弹窗** |

## 用户现象对齐

- 默认档「完全访问」= never → 需授权动作直接按策略走，**无弹窗**。
- 切到「默认/自动审查」只改 UI 标签，thread 可能仍 sticky 旧 policy。
- 自动审查因 reviewer 错名，行为偏离官方 auto_review。

## 修法（L-Perm）

1. `_setCodexPermissionMode`：活跃 thread 调 `updateThreadSettings(approvalPolicy, approvalsReviewer, sandboxPolicy)`。
2. autoReview → `approvalsReviewer: 'auto_review'`。
3. default：`on-request` + `user` + 合理 sandbox（非 null 吃错默认时需钉死）。
4. full：`never` + `dangerFullAccess`（保持）但**不要**作为「可执行需授权动作却无提示」的静默默认若产品要安全默认——与产品确认默认档。
5. 埋点 `DebugFileLog.logPermissionSet` + approval prompt/decision。

## 锁

L-Perm：`chat_page_codex.dart` permission 段 + `codex_app_server_service.dart` settings/startTurn
