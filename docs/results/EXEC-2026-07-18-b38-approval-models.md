# EXEC · B38 · 2026-07-18

> 当前 hardening 候选：**APK_STAGED**。同一最终 HEAD 的远端九路门禁与 APK stage 证据已闭合；禁止提前写 `DEVICE_PARTIAL`、`DEVICE_PASS` 或 `READY`。
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

当前源码整合基线为 `dad70e8f2dd00238c7a85c68a3e25235d7885ba0`。下表中的 topic 已进入同一源码树并完成主线程静态审查；同一 HEAD 的远端九路门禁与 summary 已全部成功，APK 已 stage。本机没有运行 Flutter、Dart、Gradle 或 Android 编译/测试。

| 工作线 | 状态 | topic → integration | 源码级边界 |
|--------|------|---------------------|------------|
| Native 审批/会话所有权 | `IMPLEMENTED` | `10a169e` → `003c85b` | listener registry、session generation、pending request 归属、stale/no-reconnect |
| Native 会话消息排序 | `IMPLEMENTED` | `3b210b6` → `e2eee67` | 完整消息 barrier、会话切换顺序、持久单调 generation、原子 session snapshot |
| Native 初始化就绪门禁 | `IMPLEMENTED` | `d8d9dd6` → `41bfbfc` | transport running 不再等同 initialized-ready；RPC 只使用 READY session |
| Native pending request replay | `IMPLEMENTED` | `7df2770` → `3239c7b` | listener 空窗内新 pending request 可向后续 stream replay；投递前复核仍为 PENDING |
| Approval UI/幂等生命周期 | `IMPLEMENTED` | `3ceaba0` → `8f6e775` | schema/generation/requestId、resolved/invalidated、双 Engine first-wins、断连重试 |
| Approval UI 终态竞态 | `IMPLEMENTED` | `5760d52` → `50f3bcb` | resolved/invalidated 先于 MethodChannel 返回时，不被 `response_sent` 或 `handled_elsewhere` 降级 |
| Approval 卡 dispose 持久化 | `IMPLEMENTED` | `a853cb7` → `249d519` | MethodChannel 成功或异常返回先检查 `mounted`；卡已 dispose 后不再派生 `response_sent` / `handled_elsewhere` 非终态写 |
| Flutter 启动期 request replay FIFO | `IMPLEMENTED` | `a853cb7` → `249d519` | 按 request identity 延后路由；同请求 pending→terminal FIFO，不同请求互不阻塞，conversation target 就绪后 drain |
| Models/UI catalog 隔离 | `IMPLEMENTED` | `86cec55` → `5194d9b` | latest-wins、authoritative empty/ghost、effort clamp/omit、原子 model+effort、Overlay refresh |
| Models 空目录去重 | `IMPLEMENTED` | `97d1a18` → `f30508b` | authoritative empty/no-effort 也完成 catalog generation，避免重复拉取 |
| 八路远端质量门禁 | `IMPLEMENTED` | `6e56dd9` → `4bf025c` | 4 Flutter test shard + analyze + Android unit/lint/APK；最终 run `#29656072103` 为 8/8 SUCCESS |
| 第九路 source-policy | `IMPLEMENTED` | `522c346` → `1ec0353` | commit/source/evidence、applicationId 与品牌不变量；同一 run / HEAD 为 1/1 SUCCESS |
| Android SDK license 假失败修复 | `IMPLEMENTED` | `99b5dbc` → `27d8051` | 避免 `yes` 在 `pipefail` 下因 SIGPIPE=141 把 license 接受误判失败 |
| 文档与证据治理 | `IMPLEMENTED` | `43ec7a7` → `bf67855` | 状态机、ignore、审计报告与 AGENTS 真源校准 |

### 当前候选交付字段

| 字段 | 当前值 |
|------|--------|
| 当前源码整合 HEAD（本次文档基线） | `dad70e8f2dd00238c7a85c68a3e25235d7885ba0` |
| topic → integration 映射 | **已回填；见上表** |
| 最终远端触发 HEAD | `dad70e8f2dd00238c7a85c68a3e25235d7885ba0` |
| 九路 GHA run ID / URL | `29656072103` · [Baseline Standard Debug #29656072103](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29656072103) |
| 九路 GHA 结果 | **SUCCESS** · 9/9 gates + summary success |
| APK artifact / stage path | `omnibot-standard-debug-apk` · artifact id `8433013672`<br>stable：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`<br>immutable：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-dad70e8-364b70d9.apk` |
| APK SHA-256 / cert SHA-256 | `364b70d9e8859f21200a907dbd02fa708164d62192f5afcf935b16f005c9432b`<br>`6D79D352E68FC7E1956FE14C41B6AFFAD2A1403EB22AF9E76B4E213FA10244C6` |
| AP1–AP7 / M1–M3 / F1 / A1 / R1 | **APK 已 stage；真机验证待执行** |

Post-`249d519` hardening trail：`3624e23` → `55152e7` → `d9e6774` → `57ece40` → `e54378d` → `2a8f6a0` → `85094ea` → `628e7b5` → `dad70e8`

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

## 6. 当前 hardening 候选真机验收表（APK 已 stage，设备待测）

依据 PLAN §6。当前候选已达到 `APK_STAGED`，但尚未执行设备验收，所以下表统一为待测；**tip 单独 ≠ PASS**。

### AP · Codex 原生审批环（优先）

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **AP1** | default：触发 shell/写盘越界 → **Codex 审批卡** + 日志 `requestApproval` / `approval_prompt` | 待测 | APK 已 stage；设备待测 |
| **AP2** | 卡上批准 → `respondToServerRequest` ok、动作续；拒绝 → 中止 | 待测 | APK 已 stage；设备待测 |
| **AP3** | autoReview：日志 `approvalsReviewer=auto_review` + `on-request`；自动决策可观测（非仅 UI 标签） | 待测 | APK 已 stage；设备待测 |
| **AP4** | fullAccess：`never` + `dangerFullAccess`；同任务 **不**弹人工审批卡 | 待测 | APK 已 stage；设备待测 |
| **AP5** | 切三档：live thread 时 `permission_set settingsRpc=ok`；失败 **不得**假 tip 成功 | 待测 | APK 已 stage；设备待测 |
| **AP6** | 双 Engine 竞争同一请求：单终态；另一端 `ALREADY_RESPONDED` → `handled_elsewhere` | 待测 | APK 已 stage；设备待测 |
| **AP7** | 断连/重连或 generation 更新：旧卡失效；retryable 请求有界恢复 | 待测 | APK 已 stage；设备待测 |

### M · 模型真源

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **M1** | 菜单 id 集合 = `GET {baseUrl}/models` 的 `data[].id` | 待测 | APK 已 stage；设备待测 |
| **M2** | 日志 `model_list source=http_v1 count=…` 与菜单一致 | 待测 | APK 已 stage；设备待测 |
| **M3** | 切模型成功；无 `select_failed` | 待测 | APK 已 stage；设备待测 |

### F / A / R · 回归

| # | 操作 / 期望 | 结果 | 备注 / 日志摘录 |
|---|-------------|------|-----------------|
| **F1** | Fast 开/关稳定 | 待测 | APK 已 stage；设备待测 |
| **A1** | 自动压缩卡与 slash 一致 | 待测 | APK 已 stage；设备待测 |
| **R1** | 约 10 min 无成片 `thread not found`；MissingPlugin 不拖死开关 | 待测 | APK 已 stage；设备待测 |

## 7. 残余风险（主线程验收）

1. 十四条工作线条目（十三组唯一 topic→integration 映射）已汇入最终源码整合基线 `dad70e8`；同一 HEAD 的远端九路门禁与 summary 已全部成功，但设备运行时联调尚未执行。
2. **P2 · Nonterminal DB upsert in-flight**：卡仍 mounted 时若已经发出非终态 conversation-history DB upsert，而 dispose 发生在该 await 期间，Flutter 无法取消底层在途写。当前门禁会阻止随后继续写 response cache 或在 RPC 返回后新发非终态持久化，但不能回滚已经开始的 DB upsert。
3. **P2 · Terminal tombstone replay residual**：若 `serverRequest/resolved` 或 `serverRequest/invalidated` 恰在 EventChannel 完全无 listener 的窗口到达，Native 当前不会保存 terminal tombstone，后续新 stream 因而无法 replay 该终态。已实现的 pending replay 会在投递前复核 PENDING，终态后不会重投同一 pending；残余是既有 UI/历史卡可能无法自动收敛终态，而不是同请求被重新创建为可操作卡。
4. 按本轮约束，Flutter/Dart/Gradle/Android 编译与测试均未在本机运行。
5. 同一最终 HEAD 的九路门禁、签名证书、APK SHA 与 stage 路径证据已经闭合；设备侧 AP1–AP7 / M1–M3 / F1 / A1 / R1 尚未执行。
6. 当前候选已有 staged APK，但尚无本轮设备验收日志；所有 AP/M/F/A/R 项保持待测。
7. 任何远端失败都保持 `IMPLEMENTED`；任何设备失败或未完成项最多到 `DEVICE_PARTIAL`。

## 8. READY 门禁

仅当同一最终 HEAD 已依次取得 `REMOTE_VERIFIED`、`APK_STAGED` 和完整 `DEVICE_PASS` 证据，且本账本所有待回填字段闭合，才可写 `READY`。本 EXEC 当前只声明 `APK_STAGED`。
