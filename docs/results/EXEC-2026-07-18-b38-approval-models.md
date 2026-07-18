# EXEC · B38 · 2026-07-18

> 状态：**CODE LANDED · AWAITING GHA** · 功能 diff 已提交待 push · **无**真机 PASS · tip 不算审批 PASS  
> 真源：`PLAN-2026-07-18-b38-models-api-and-regressions.md`  
> 交接：`HANDOFF-2026-07-18-b38-approval-models.md`  
> 基线：B37 `898dc26` / sha256 `9c560e73…` · staged（**未**修 T6/T3）  
> 文档波：`c1e4341`（PLAN+HANDOFF）  
> 主线程：方案/调度/验收 · ≥6 子代理 · push **仅 mine** · GHA `baseline-standard-debug` · 禁本机 assemble  
> **禁止**：tip / setState / toast 单独算审批 PASS

## 触发

用户裁定 + 真机 `omnibot-debug-20260717.log`：

1. **T6（P0）**：审批只有 UI，**没有**走 Codex `requestApproval → 卡/auto_review → respondToServerRequest`
2. **T3（P0）**：模型列表真源 = `GET {baseUrl}/models`（实测 9 id），不是 app-server `model/list`（7 id）

硬缺口（方案已钉）：Dart `startThread` 不传 triad；settings 曾 stale；日志无 requestApproval 线。

## 范围（实现落地 · 待 GHA/真机）

| 块 | 状态 | 说明 |
|----|------|------|
| Dart `startThread` 扩参 + 调用点注入 triad | **已落地** | A2：service + ensure-thread + sessions defaultMode |
| Kotlin `startThread` 透传 | **既有 OK** | 已支持 args；本批未改 startThread 体 |
| settings stale → ensure thread → re-apply | **已落地** | A3：`reapply_ok` / fail 不假 tip |
| approval_prompt / approval_decision 埋点 | **已落地** | A4：reducer + request card |
| HTTP `GET baseUrl/models` 换列表真源 | **已落地** | A5：HTTP 主路径 + app_server_fallback |
| thread 分叉 / MissingPlugin 加固 | **已落地（有限）** | A6：retry + channel rebind + rebind-before-start |
| push mine · GHA · stage APK | **进行中** | push 后自动触发 baseline-standard-debug |
| 真机 AP1–AP5 / M1–R1 | **未开始** | 用户设备复测 |

## 代理分工

| 代理 | 锁建议 | 任务 | 状态 |
|------|--------|------|------|
| A1 | 只读 | §0 vs set/startThread/startTurn/reducer/card diff | ✅ 报告完成 |
| A2 | L-StartThread | Dart 扩参 + 调用点 triad | ✅ |
| A3 | L-Perm | settings stale ensure + re-apply | ✅ |
| A4 | L-Log | approval_prompt / approval_decision | ✅ |
| A5 | L-Models | HTTP `/models` + `_loadCodexModelOptions` | ✅ |
| A6 | L-Session | MissingPlugin + threadId rebind | ✅ 有限 |
| A7 | 文档 | EXEC / DELIVERY | ✅ |

## 改动文件

- [x] `ui/lib/services/codex_app_server_service.dart` — startThread triad + HTTP models + MissingPlugin retry
- [x] `ui/lib/features/home/pages/chat/chat_page_codex.dart` — load models HTTP-first；perm re-apply；ensure triad；bind helpers
- [x] `ui/lib/features/home/pages/codex/codex_sessions_page.dart` — remote start defaultMode triad
- [x] `ui/lib/services/codex_event_reducer.dart` — approval_prompt
- [x] `ui/lib/features/home/pages/command_overlay/widgets/cards/codex_request_card.dart` — approval_decision
- [x] `ui/lib/services/debug_file_log.dart` — logThreadStart / logApproval
- [x] `ui/test/services/codex_app_server_service_test.dart` — triad unit
- [x] `app/.../CodexAppServerManager.kt` — soft restart log
- [x] `app/.../CodexAppServerChannel.kt` — setChannel tear-down before rebind
- [x] 本 EXEC / DELIVERY
- [x] push mine（`68c1b79`）· GHA run `29641064531` in progress · stage APK 待 SUCCESS
- [ ] 真机 AP1–AP5 / M1–R1

## 交付字段（GHA 后回填）

| 项 | 值 |
|----|-----|
| 功能 commit(s) | `68c1b79` |
| 编译/热修 commit（如有） | `_TBD_` |
| HEAD | `68c1b791614e3447cd9faeeb5bd1a66ed922c6a7` |
| GHA run id | `29641064531` |
| GHA 结果 | **in progress** run `29641064531` |
| APK path（stage） | `_TBD_` |
| 版本副本 path | `_TBD_` |
| APK sha256 | `_TBD_` |
| 分支 / fork | `secondary/s1-baseline` · `gzy3894-png/OpenOmniBot` · push **仅 mine** |

## 真机验收表（用户填 · 默认空白）

依据 PLAN §6。**tip 单独 ≠ PASS。**

### AP · Codex 原生审批环（优先）

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **AP1** | default：触发 shell/写盘越界 → **Codex 审批卡** + 日志 `requestApproval` / `approval_prompt` | | |
| **AP2** | 卡上批准 → `respondToServerRequest` ok、动作续；拒绝 → 中止 | | |
| **AP3** | autoReview：日志 `approvalsReviewer=auto_review` + `on-request`；自动决策可观测（非仅 UI 标签） | | |
| **AP4** | fullAccess：`never` + `dangerFullAccess`；同任务 **不**弹人工审批卡 | | |
| **AP5** | 切三档：live thread 时 `permission_set settingsRpc=ok`；失败 **不得**假 tip 成功 | | |

### M · 模型真源

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **M1** | 菜单 id 集合 = `GET {baseUrl}/models` 的 `data[].id` | | |
| **M2** | 日志 `model_list source=http_v1 count=…` 与菜单一致 | | |
| **M3** | 切模型成功；无 `select_failed` | | |

### F / A / R · 回归

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **F1** | Fast 开/关稳定 | | |
| **A1** | 自动压缩卡与 slash 一致 | | |
| **R1** | 约 10 min 无成片 `thread not found`；MissingPlugin 不拖死开关 | | |

## 残余风险（主线程验收）

1. 本机无 flutter/dart PATH → **未**跑 analyze/test；靠 GHA 编译兜底。
2. A6 仅为有限加固：半屏双 engine 未全量重构；部分 `_activeCodexThreadId=` 仍直接赋值。
3. 无 live thread 时切 mode 仍可能 `settingsRpc=skipped` + 本地 tip；依赖下次 `startThread` 带 triad（A2 已补）。
4. **真机未测** → 不得写 READY/PASS。

## READY 门禁

仅当：GHA SUCCESS + APK stage + 用户 AP1–AP5 至少关键项有证据 → 另写 READY。本 EXEC **不**宣称 PASS。
