# EXEC · B38 · 2026-07-18

> 当前 hardening 候选：**IMPLEMENTED · REMOTE TEST PENDING**。禁止提前写 `REMOTE_VERIFIED`、`APK_STAGED`、`DEVICE_PASS` 或 `READY`。
> 旧 B38 APK/日志证据集：**DEVICE_PARTIAL**；旧 GHA/APK 字段保留，但不能证明当前候选。
> 真源：`PLAN-2026-07-18-b38-models-api-and-regressions.md`  
> 本文件是 B38 **唯一实时账本**；`HANDOFF-2026-07-18-b38-approval-models.md` 已 superseded。
> 基线：B37 `898dc26` / sha256 `9c560e73…` · staged（**未**修 T6/T3）  
> 文档波：`c1e4341`（PLAN+HANDOFF）  
> 主线程：只调度/验收 · ≥8 并发工作线 · push **仅 mine** · 最终九路远端门禁 · 禁本机编译测试
> **禁止**：tip / setState / toast 单独算审批 PASS

## 0. 实时状态账本

状态机：

`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

定义与冻结范围见 PLAN「状态协议与冻结边界」。状态只能按同一整合 HEAD 的证据推进；历史 run、APK 或日志不能给新候选提级。

### 当前 hardening 候选

| 工作线 | 状态 | topic commit / 证据 | 边界 |
|--------|------|---------------------|------|
| Native 审批/会话所有权 | `IMPLEMENTED` | `10a169e029f248f4b9734cddcae327d48280e72a` | listener registry、session generation、pending request 归属、stale/no-reconnect；仅源码级自审 |
| Models/UI catalog 一致性 | `IMPLEMENTED` | `86cec55a85db446394ddbf1ebd306ee326dee960` | latest-wins、authoritative empty/ghost、effort clamp/omit、原子 model+effort、Overlay refresh；仅源码级自审 |
| Approval UI/幂等回归 | `IMPLEMENTED` | `3ceaba07290273a303b9398769666fb2de57442c` | schema/generation/requestId 生命周期、resolved/invalidated、`ALREADY_RESPONDED` 中性处理、断连重试与 EventChannel；仅源码级自审 |
| 远端质量门禁 | `IMPLEMENTED` | `6e56dd943319328148df965b251dfd215670fb1a` + `522c346e8a10dc37a1532e09bba56a4f3d30b2c2` | 八路升级九路 + lint/source-policy；未在最终整合 HEAD 运行 |
| 文档与证据治理 | `IMPLEMENTED` | **本提交后回填** | 状态机、ignore、两份审计报告、AGENTS 真源校准 |

### 当前候选待回填字段

| 字段 | 当前值 |
|------|--------|
| 最终整合 HEAD | **待回填** |
| topic → integration 映射 | **待回填** |
| 九路 GHA run ID / URL | **待回填；未运行** |
| 九路 GHA 结果 | **待回填；不得预写 SUCCESS** |
| APK artifact / stage path | **待回填；当前候选未出包** |
| APK SHA-256 / cert SHA-256 | **待回填** |
| AP1–AP7 / M1–M3 / F1 / A1 / R1 | **待同一候选 APK 真机验证** |

### 历史证据集

| 候选 | 状态 | 可复用事实 | 不可外推 |
|------|------|------------|----------|
| B38 `68c1b79` | `DEVICE_PARTIAL` | GHA `#29641064531` SUCCESS；APK 已 stage；SHA-256 `847c4aab…bd8`；有旧日志/部分设备观察 | 不能证明本轮 listener、generation、catalog、approval 幂等或九路门禁 |
| B37 `898dc26` | `DEVICE_PARTIAL` | GHA SUCCESS；APK staged；SHA-256 `9c560e73…fd68` | device retest 未完成，不能叫 READY |
| B34–B36 `7896a6c` | `DEVICE_PARTIAL` | GHA SUCCESS + 真机 FAIL 日志 | 明确存在 stale/MissingPlugin/审批环问题 |

## 1. 历史触发与原 B38 范围

用户裁定 + 真机 `omnibot-debug-20260717.log`：

1. **T6（P0）**：审批只有 UI，**没有**走 Codex `requestApproval → 卡/auto_review → respondToServerRequest`
2. **T3（P0）**：模型列表真源 = `GET {baseUrl}/models`（实测 9 id），不是 app-server `model/list`（7 id）

硬缺口（方案已钉）：Dart `startThread` 不传 triad；settings 曾 stale；日志无 requestApproval 线。

## 2. 旧候选 `68c1b79`（DEVICE_PARTIAL）

| 块 | 状态 | 说明 |
|----|------|------|
| Dart `startThread` 扩参 + 调用点注入 triad | **已落地** | A2：service + ensure-thread + sessions defaultMode |
| Kotlin `startThread` 透传 | **既有 OK** | 已支持 args；本批未改 startThread 体 |
| settings stale → ensure thread → re-apply | **已落地** | A3：`reapply_ok` / fail 不假 tip |
| approval_prompt / approval_decision 埋点 | **已落地** | A4：reducer + request card |
| HTTP `GET baseUrl/models` 换列表真源 | **已落地** | A5：HTTP 主路径 + app_server_fallback |
| thread 分叉 / MissingPlugin 加固 | **已落地（有限）** | A6：retry + channel rebind + rebind-before-start |
| push mine · GHA · stage APK | **历史完成** | GHA `#29641064531` SUCCESS · staged |
| 真机 AP1–AP5 / M1–R1 | **部分/不完整** | 统一归类 `DEVICE_PARTIAL`，不得升 PASS |

## 3. 原 B38 代理分工（历史）

| 代理 | 锁建议 | 任务 | 状态 |
|------|--------|------|------|
| A1 | 只读 | §0 vs set/startThread/startTurn/reducer/card diff | ✅ 报告完成 |
| A2 | L-StartThread | Dart 扩参 + 调用点 triad | ✅ |
| A3 | L-Perm | settings stale ensure + re-apply | ✅ |
| A4 | L-Log | approval_prompt / approval_decision | ✅ |
| A5 | L-Models | HTTP `/models` + `_loadCodexModelOptions` | ✅ |
| A6 | L-Session | MissingPlugin + threadId rebind | ✅ 有限 |
| A7 | 文档 | EXEC / DELIVERY | ✅ |

## 4. 旧候选 `68c1b79` 改动文件（历史）

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
- [x] push mine（`68c1b79`）· GHA `#29641064531` SUCCESS · stage APK + sha256 已回填
- [ ] 真机 AP1–AP5 / M1–R1

## 5. 旧候选 `68c1b79` 交付字段（历史）

| 项 | 值 |
|----|-----|
| 功能 commit(s) | `68c1b79` |
| 编译/热修 commit（如有） | 无 |
| HEAD（功能） | `68c1b791614e3447cd9faeeb5bd1a66ed922c6a7` |
| 文档回填 HEAD | 见 `docs(results): B38 GHA SUCCESS…` 提交 |
| GHA run id | `29641064531` |
| GHA 结果 | **SUCCESS** · [Baseline Standard Debug #29641064531](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29641064531) |
| APK path（stage） | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 版本副本 path | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-68c1b79-847c4aab.apk` |
| APK sha256 | `847c4aaba2b3e6c2251be1f098d8310858ab4909904a3eb0ef57d17604265bd8` |
| 分支 / fork | `secondary/s1-baseline` · `gzy3894-png/OpenOmniBot` · push **仅 mine** |

## 6. 当前 hardening 候选真机验收表（远端出包后填写）

依据 PLAN §6。当前候选尚未 `REMOTE_VERIFIED` / `APK_STAGED`，所以下表统一为待测；**tip 单独 ≠ PASS**。

### AP · Codex 原生审批环（优先）

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **AP1** | default：触发 shell/写盘越界 → **Codex 审批卡** + 日志 `requestApproval` / `approval_prompt` | 待测 | 当前候选未出包 |
| **AP2** | 卡上批准 → `respondToServerRequest` ok、动作续；拒绝 → 中止 | 待测 | 当前候选未出包 |
| **AP3** | autoReview：日志 `approvalsReviewer=auto_review` + `on-request`；自动决策可观测（非仅 UI 标签） | 待测 | 当前候选未出包 |
| **AP4** | fullAccess：`never` + `dangerFullAccess`；同任务 **不**弹人工审批卡 | 待测 | 当前候选未出包 |
| **AP5** | 切三档：live thread 时 `permission_set settingsRpc=ok`；失败 **不得**假 tip 成功 | 待测 | 当前候选未出包 |
| **AP6** | 双 Engine 竞争同一请求：单终态；另一端 `ALREADY_RESPONDED` → `handled_elsewhere` | 待测 | 当前候选未出包 |
| **AP7** | 断连/重连或 generation 更新：旧卡失效；retryable 请求有界恢复 | 待测 | 当前候选未出包 |

### M · 模型真源

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **M1** | 菜单 id 集合 = `GET {baseUrl}/models` 的 `data[].id` | 待测 | 当前候选未出包 |
| **M2** | 日志 `model_list source=http_v1 count=…` 与菜单一致 | 待测 | 当前候选未出包 |
| **M3** | 切模型成功；无 `select_failed` | 待测 | 当前候选未出包 |

### F / A / R · 回归

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **F1** | Fast 开/关稳定 | 待测 | 当前候选未出包 |
| **A1** | 自动压缩卡与 slash 一致 | 待测 | 当前候选未出包 |
| **R1** | 约 10 min 无成片 `thread not found`；MissingPlugin 不拖死开关 | 待测 | 当前候选未出包 |

## 7. 残余风险（主线程验收）

1. topic commits 尚待汇入同一 integration HEAD；跨 Native/Flutter/CI 的冲突与接口联调未验证。
2. 按本轮约束只做源码级静态自审；Flutter/Dart/Gradle/Android 测试均未在本机运行。
3. 最终九路门禁尚未运行，签名证书、lint、分片测试与 source-policy 尚无同一 HEAD 的远端证据。
4. 当前候选无 APK、SHA 或设备日志；所有 AP/M/F/A/R 项均未知。
5. 任何远端失败都保持 `IMPLEMENTED`；任何设备失败或未完成项最多到 `DEVICE_PARTIAL`。

## 8. READY 门禁

仅当同一最终 HEAD 已依次取得 `REMOTE_VERIFIED`、`APK_STAGED` 和完整 `DEVICE_PASS` 证据，且本账本所有待回填字段闭合，才可写 `READY`。本 EXEC 当前只声明 `IMPLEMENTED`。
