# HANDOFF · B38 · Codex 原生审批 + `/v1/models` · 2026-07-18

> 文档生命周期：**SUPERSEDED**。本文件仅保留 2026-07-18 开工前的历史上下文，**不得再作为执行清单或状态真源**。
> 当前状态只认 `EXEC-2026-07-18-b38-approval-models.md`：hardening 候选为 `IMPLEMENTED · REMOTE TEST PENDING`；旧 APK/日志为 `DEVICE_PARTIAL`。
> 当前源码整合基线：`249d519f50417385596d4d6624030028565b4ca9`；只完成源码级静态审查，本机未编译、未测试，九路远端门禁未运行。
> 统一状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`。
> **用户裁定**：审批「只有 UI、没走 Codex 自身审批」= **真 bug（T6）**，优先级 ≥ 模型列表。

---

## 0. 一句话

B37（`898dc26`）只治死 thread 报错；**tip/setState 不算审批 PASS**。以下是开工前冻结的原始目标，不是当前进度：

`triad 写入 thread/turn → requestApproval → 卡/auto_review → respondToServerRequest`

同时模型列表真源改为 **`GET {baseUrl}/models`**，不是 app-server `model/list`。

---

## 1. 站规（不可破）

| 规则 | 说明 |
|------|------|
| 主线程 | **只**方案 / 调度 / 验收；当前要求 **≥8 并发工作线** |
| 推送 | **仅** `mine` → `gzy3894-png/OpenOmniBot`；**禁止** push origin/upstream |
| 出包 | **仅**最终九路 GHA `baseline-standard-debug`；**禁本机编译测试** |
| 密钥 | 不写 memory/docs/logs；baseUrl 可写 host，key 用 conf 同源读 |
| 验收 | tip/toast/setState **单独不算**权限 PASS |

**仓库路径**：`/root/workspace/omnibot-product`  

**当前本地整合分支**：`codex/b38-integration`（源码基线 `249d519`）

**目标远端分支**：`secondary/s1-b38-hardening`

**远端**：`mine` = 自己的 fork

---

## 2. 真源文件（先读再动）

| 优先级 | 路径 | 用途 |
|--------|------|------|
| **P0 方案** | `docs/results/PLAN-2026-07-18-b38-models-api-and-regressions.md` | **完整改正清单 + §0 官方审批 + AP1–AP5** |
| 对照 | `docs/results/reports/scout-b20-perm.md` | 历史：只 setState；autoReview 错映 |
| 对照 | `docs/results/reports/impl-b25-perm.md` | 空 roots 杀审批；三档映射 + Kotlin |
| 对照 | `docs/results/PLAN-2026-07-16-next-fast-perm-slash.md` §B20 | 原验收：RPC + 弹窗可批 |
| 上游 TUI | `codex-upstream-remote-test/codex-rs/tui/src/chatwidget/permissions_menu.rs` | Default / AutoReview / Full Access |
| 上游协议 | `…/protocol/src/config_types.rs` → `ApprovalsReviewer` | `user` \| `auto_review` \| `guardian_subagent` |
| 映射代码 | `ui/lib/features/home/pages/chat/chat_page_codex.dart` → `_CodexPermissionModePayload` ~7874 | 三档 triad（字符串已对齐） |
| 设权限 | 同文件 `_setCodexPermissionMode` ~926 | updateThreadSettings + B37 stale |
| 缺口 | `ui/lib/services/codex_app_server_service.dart` → `startThread` ~321 | **不传** approval/reviewer/sandbox |
| Kotlin | `app/.../codex/CodexAppServerManager.kt` `startThread` ~178 | 默认 `on-request`；reviewer 仅 args 有才写 |
| 事件卡 | `codex_event_reducer.dart` + `codex_request_card.dart` | requestApproval → 卡 → `respondToApproval` |
| 真机日志 | `/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-20260717.log` | permission_set fail thread not found；**无** requestApproval 线 |
| 前序 `DEVICE_PARTIAL` | B37 APK `898dc26` sha `9c560e73…` Download 已 stage | device retest 未完成，**未**修 T6/T3 |

**upstream 路径说明**：若本机无 `codex-upstream-remote-test`，以 PLAN §0 摘要 + protocol 注释为准，勿拿沙盒 `~/.codex` 和 OmniBot 对账。

---

## 2.1 当前 hardening 源码快照（后补）

本节只用于把历史交接连接到当前实时账本，不改变本文件的 `SUPERSEDED` 生命周期。以下条目均为 `IMPLEMENTED`，不代表 GHA、APK 或设备 PASS。

| 工作线 | topic → integration | 源码状态 |
|--------|---------------------|----------|
| Native ownership | `10a169e` → `003c85b` | listener/session/request 隔离已入树 |
| Native ordering | `3b210b6` → `e2eee67` | barrier、持久 generation、session snapshot 已入树 |
| Native readiness | `d8d9dd6` → `41bfbfc` | initialized READY 门禁已入树 |
| Native pending replay | `7df2770` → `3239c7b` | listener 空窗 pending replay + 投递前 PENDING 复核已入树 |
| Approval lifecycle | `3ceaba0` → `8f6e775` | request 生命周期与 first-wins 已入树 |
| Approval terminal race | `5760d52` → `50f3bcb` | 先到终态不被 RPC 返回降级已入树 |
| Approval card dispose persistence | `a853cb7` → `249d519` | dispose 后 RPC 返回不再派生非终态 DB/cache 写 |
| Flutter startup request FIFO | `a853cb7` → `249d519` | request-owned pending→terminal FIFO 与延后路由已入树 |
| Models catalog isolation | `86cec55` → `5194d9b` | catalog generation/latest-wins 已入树 |
| Models empty reload | `97d1a18` → `f30508b` | empty/no-effort 去重已入树 |
| 八路质量门禁 | `6e56dd9` → `4bf025c` | 工作流源码已入树；未运行 |
| 第九路 source-policy | `522c346` → `1ec0353` | 工作流源码已入树；未运行 |
| SDK license pipefail | `99b5dbc` → `27d8051` | SIGPIPE 假失败修复已入树 |
| 文档/证据治理 | `43ec7a7` → `bf67855` | 状态与证据规则已入树 |

**P2 残余**：

- **Nonterminal DB upsert in-flight**：卡仍 mounted 时已经发出的非终态 conversation-history DB upsert，无法在 await 期间因 dispose 而取消；后续 response cache 写会被门禁阻止，但已开始的 DB 写不能回滚。
- **Terminal tombstone replay**：EventChannel 完全没有 listener 的窗口内若到达 `serverRequest/resolved` / `serverRequest/invalidated`，Native 尚不保存 terminal tombstone，之后新 stream 无法 replay 该终态。新 pending 在空窗内会被 replay，且每次投递前复核 PENDING，所以 terminal 后不会重投同一 pending；该残余不得误写成乱序 replay 会重建可操作卡。

---

## 3. Codex 审批（对照结论，勿再猜）

### 3.1 两轴 + 沙箱

1. **`approvalPolicy`**：`on-request` 才发 `requestApproval`；`never` 不弹人审。  
2. **`approvalsReviewer`**：  
   - `user` = 人批  
   - `auto_review` = **仍是 on-request**，子代理风险评审后批/拒（不是关审批）  
   - `guardian_subagent` = legacy 别名  
3. **`sandbox`**：`workspaceWrite` + **非空** `writableRoots` vs `dangerFullAccess`

### 3.2 OmniBot 三档（映射已对齐 TUI）

| UI | policy | reviewer | sandbox |
|----|--------|----------|---------|
| defaultMode | on-request | user | workspaceWrite + 非空 roots |
| autoReview | on-request | auto_review | 同上 |
| fullAccess | never | user | dangerFullAccess |

### 3.3 为何仍「只有 UI」（硬证据）

| 缺口 | 证据 |
|------|------|
| settings 写不进 | 日志 `permission_set fail:* thread not found` |
| 新 thread 不带 UI mode | Dart `startThread` 无 triad 参数 |
| 真机无审批环 | 日志无 `requestApproval` / decision |
| 路径存在≠触发 | reducer/card/respond 在；policy 未写入则永不发 |

**PASS 定义**：见 PLAN §6 **AP1–AP5**（必须有 requestApproval 日志/卡/respond，tip 不算）。

---

## 4. 模型列表真源（T3）

- **对**：`GET {localConfig.baseUrl}/models`（base 已含 `/v1` 时不要再拼 `/api/v1`）  
- **实测 9 id**：`gpt-5.4`, `gpt-5.4-mini`, `gpt-image-2`, `gpt-5.5`, `gpt-5.3-codex-spark`, `codex-auto-review`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`  
- **错源 7 id**（app-server `model/list`）：多 `gpt-5.2`，缺 image/spark/auto-review  
- **禁止**：沙盒 catalog、手写 slug 表当列表源  

鉴权：Bearer 与 conf/auth 同源；**勿**把 key 写入文档。

---

## 5. 原始实现切片（历史，已 superseded）

| ID | 任务 | 锁建议 |
|----|------|--------|
| A1 | 只读 diff：§0 vs 当前 set/startThread/startTurn/reducer/card | 只读 |
| A2 | Dart `startThread` 扩参 + 全部调用点注入 triad；Kotlin 透传验收 | L-StartThread |
| A3 | settings stale → ensure thread → re-apply；禁止假成功 tip | L-Perm |
| A4 | `approval_prompt` / `approval_decision` 埋点 | L-Log |
| A5 | HTTP `GET baseUrl/models` + `_loadCodexModelOptions` | L-Models |
| A6 | thread 分叉 / MissingPlugin 加固 | L-Session |
| A7 | EXEC/DELIVERY + 真机表 AP1–AP5 / M1–R1 | 文档 |

完整条目：PLAN §4 / §7。

---

## 6. 验收（真机，用户测）

优先 **AP1–AP5**，再 M1–R1（PLAN §6）：

- AP1 default → 有 **Codex 审批卡** + 日志 requestApproval  
- AP2 批/拒 → respond 成功、动作续/止  
- AP3 autoReview → 日志 `approvalsReviewer=auto_review`，自动决策可观测  
- AP4 fullAccess → never，不弹人审卡  
- AP5 切档 settingsRpc=ok，失败不假 tip  
- M1 菜单 id = HTTP `/models`  

装包：GHA SUCCESS 后 stage 到 Download；记录 run id + commit + sha256。

---

## 7. 当前基线（B37，非 B38）

| 项 | 值 |
|----|-----|
| 功能 tip | `1220a4d` + compile fix `898dc26` + docs `97e845c` |
| GHA | `#29594207043` SUCCESS（首包 `#29593369757` compile FAIL） |
| APK | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| sha256 | `9c560e73b461cee69ac0a9b2ceb93fa8551fd7b8e0b43bbc2b5473257164fd68` |
| 版本副本 | `…-898dc26-9c560e73.apk` |

B37 做了：soft conf harden、stale thread clear、本地 mode 继续、display map 半成品、auto-compact abstract。  
**未做**：T6 审批环、HTTP models、MissingPlugin 根治。

---

## 8. 下一手第一件事

1. **停止使用本 HANDOFF 做状态判断**；先读 EXEC §0 实时账本和 PLAN 冻结范围。
2. 十四条工作线条目（十三组唯一 topic→integration 映射）已汇入源码基线 `249d519`，当前仍只能标记 `IMPLEMENTED`；最终远端触发 HEAD 以主线程合入本次文档提交后的实际推送为准。
3. 只在同一最终 HEAD 的九路远端门禁全绿并回填 run/HEAD 后升 `REMOTE_VERIFIED`；随后才允许 stage 同一 HEAD 的 APK。
4. 设备证据不完整或有失败统一记 `DEVICE_PARTIAL`；完整 AP/M/F/A/R 通过后才可 `DEVICE_PASS → READY`。
5. 不进入 S2，不改历史 commit/run/APK/log，不本机编译测试。

---

## 9. 明确不做

- tip-only 假修复  
- 沙盒 `~/.codex` 与 OmniBot 模型对账  
- plan-mode 批准（B7）冒充 exec `requestApproval`  
- push origin；本机 Gradle  

---

*历史落盘：claude · 2026-07-18；2026-07-18 文档治理标记 SUPERSEDED，实时状态迁移至 EXEC。*
