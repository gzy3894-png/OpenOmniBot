# PLAN · B38 · 模型真源 `/v1/models` + **Codex 原生审批流水线** + 真机回归 · 2026-07-18

> 计划状态：**PLANNED · SCOPE FROZEN**。本文件只冻结范围，不承担实时进度；实时状态唯一真源是 `EXEC-2026-07-18-b38-approval-models.md`。
> 输入：真机 FAIL 日志 `omnibot-debug-20260717.log` + `GET {base_url}/models` 实测 + Codex 对照文档（`scout-b20-perm` / `impl-b25-perm` / PLAN B20）+ upstream TUI `permissions_menu.rs` + protocol `ApprovalsReviewer`  
> 前序：B37（`898dc26`）治 stale-thread / soft conf；**未** HTTP models；**未**保证 requestApproval 闭环进 live thread  
> 规则：主线程只调度/验收 · ≥8 并发工作线 · push **仅 mine** · 远端 `baseline-standard-debug` 最终九路门禁 · 禁本机编译测试
> **禁止**把 tip/toast / 本地 setState 当成审批 PASS

---

## 状态协议与冻结边界

所有 B38 文档只使用以下交付状态，按证据单向推进：

`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

| 状态 | 必须已有的证据 |
|------|----------------|
| `PLANNED` | 范围、非目标和验收条件冻结 |
| `IMPLEMENTED` | 候选改动已形成聚焦 commit 并完成源码级静态自审；不代表编译或运行成功 |
| `REMOTE_VERIFIED` | 最终整合 HEAD 的远端九路门禁全绿，并记录 run URL/ID |
| `APK_STAGED` | 同一 verified HEAD 的固定签名 APK 已 stage，记录路径、SHA-256 和证书指纹 |
| `DEVICE_PARTIAL` | 有同一 APK 的设备证据，但必测矩阵未完成或仍有失败/未知项 |
| `DEVICE_PASS` | 冻结的 AP/M/F/A/R 关键矩阵有设备日志和结果支撑 |
| `READY` | 上述证据闭环，DELIVERY 与 EXEC 字段完整且无更高优先级阻塞 |

### 本轮 hardening 冻结范围

1. **Native 审批/会话所有权**：多 Engine listener registry、session generation、pending server request 归属，以及 stale/no-reconnect 防护；审批只能由当前 generation 响应。
2. **Approval UI/幂等生命周期**：三类真实 approval schema；generation + typed requestId + method 生命周期；resolved/invalidated；`ALREADY_RESPONDED` 中性 `handled_elsewhere`；可重试写入/断连；EventChannel 监听与有界退避。
3. **模型/UI 一致性**：local/remote catalog 真源隔离、provider/runtime/session generation latest-wins、authoritative empty/ghost 防护、per-model effort 合法化、model+effort 原子切换和 Overlay live refresh。
4. **远端质量门禁**：首版八路并行升级为最终九路；四个 Flutter test shard、analyze、Android unit/lint/APK、source-policy 必须来自同一 commit，summary 全绿才可进入 `REMOTE_VERIFIED`。
5. **证据治理**：只纳入经审查的 `scout-b20-perm.md`、`impl-b25-perm.md`；统一状态机并保留旧包/日志的 `DEVICE_PARTIAL` 事实。

### 明确排除

- **不进入 S2**，不做模块物理删除、包名/品牌/签名迁移或产品线扩张。
- 不改写 B34–B37 及旧 B38 commit、GHA、APK、SHA 和日志事实；旧证据只能重新归类，不能拔高为 PASS。
- 本地不运行 Flutter、Dart、Gradle、Android 构建或测试；实现候选只能先记 `IMPLEMENTED`。

## 1. 真机测出的问题（用户原话 → 证据）

| # | 用户现象 | 日志证据 | 根因归类 |
|---|----------|----------|----------|
| **T6** | **审批只有 UI，绝对没有走 Codex 自身审批** | `permission_set fail:autoReview/fullAccess … thread not found`；整日志 **无** `requestApproval` / approval_prompt 决策线 | **P0 真 bug**：policy/reviewer 未稳定写入 Codex thread；escalation 不发 `requestApproval`；用户看不到/回不了 Codex 审批环 |
| T1 | 审批模式没反应 | 同 T6 的 settings fail | T6 的表象之一（settings 失败 → 像没点） |
| T2 | 模型切换不了 | `select_failed model=gpt-5.4-mini` | 死 thread settings |
| T3 | 模型名 ≠ API 上游 | `model_list count=7` 含 `gpt-5.2` | 列表源 = app-server `model/list` 非 HTTP `/models` |
| T4 | 各种开关报错 | fast/compact `thread not found` | 死 thread + soft conf 误杀 |
| T5 | 间歇连不上 | `MissingPluginException connect` | channel 生命周期放大 T1–T6 |

---

## 2. 真源实测（本机已打通，非臆测）

```
GET https://api.ablill-ai.com/v1/models
Authorization: Bearer <OmniBot/Codex 同源 key>
→ 200
```

**上游 9 个 id（当前真源）：**

```
gpt-5.4
gpt-5.4-mini
gpt-image-2
gpt-5.5
gpt-5.3-codex-spark
codex-auto-review
gpt-5.6-sol
gpt-5.6-terra
gpt-5.6-luna
```

**OmniBot 真机 7 个（错误源 `model/list`）：**

```
gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna, gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-5.2
```

| 差集 | 模型 |
|------|------|
| 上游有、App 无 | `gpt-image-2`, `gpt-5.3-codex-spark`, `codex-auto-review` |
| App 有、上游无 | `gpt-5.2` |

说明：**不能**再拿沙盒 codex catalog / app-server 目录当真源；真源 = **provider `base_url` + `/models`**（OpenAI 兼容 `data[].id`）。

注意：`base_url` 已含 `/v1` 时路径是 `{base_url}/models`，**不是** `{host}/api/v1/models`（实测 520）。

---

## 3. B37 已做 / 未做

| 项 | 状态 | 说明 |
|----|------|------|
| soft conf 读空不当 hard/bootstrap | ✅ B37 | 减 session 误杀 |
| stale thread clear + model/perm/fast 本地继续 | ✅ B37 | 缓解 T1/T2/T4；**待真机确认** |
| displayName 映射 | ⚠️ 半成品 | 上游 `/v1/models` **无 displayName**，map 多半等于 id |
| 列表源改为 HTTP `/models` | ❌ 未做 | **T3 主修复** |
| MissingPlugin channel 生命周期 | ❌ 未做 | T5 |
| 同一 conversation 多 threadId 不同步 | ❌ 未做 / 部分 | 日志 goal/composer/turn id 分叉 |
| 审批「无线程时仅本地、下轮生效」可感知 | ⚠️ 弱 | 需 toast + **下轮 startThread/startTurn 必带 triad** |
| **Codex 原生 requestApproval 闭环** | ❌ 未验收 | 见 §0 / T6；tip 不算 PASS |

---

## 0. Codex 官方审批怎么走（对照文档 + 上游，非臆测）

**已读对照/实现文档（Codex 侧产物，非猜）：**

| 文档 | 结论 |
|------|------|
| `docs/results/reports/scout-b20-perm.md` | 历史：`_setCodexPermissionMode` **仅 setState+tip**；autoReview 曾错映 `guardian_subagent`；policy=`never` 不弹窗 |
| `docs/results/reports/impl-b25-perm.md` | 空 `writableRoots:[]` 覆盖 native cwd → **无 exec / 无审批弹窗**；映射钉死 + Kotlin sandbox kebab |
| `docs/results/PLAN-2026-07-16-next-fast-perm-slash.md` §B20 | 验收：切换即 RPC；default 弹窗可批；auto_review schema 名；full=never+dangerFullAccess |
| upstream `codex-rs/tui/.../permissions_menu.rs` | TUI 三档：Default=OnRequest+**User**+workspace；Auto review=OnRequest+**AutoReview**；Full Access=Never+User+danger-full-access |
| upstream `protocol` `ApprovalsReviewer` | `"user" \| "auto_review" \| "guardian_subagent"`；`auto_review` = 子代理风险评审后批/拒；`guardian_subagent` 仅为 legacy alias |

### 0.1 官方两轴 + 沙箱

1. **`approvalPolicy`（AskForApproval）**  
   - `on-request`：需升级的动作由 server 发 **`requestApproval`**，等 host 决策  
   - `never`：**不**向用户发审批请求（full access 语义）
2. **`approvalsReviewer`**  
   - `user`：人批（卡 + `respondToServerRequest`）  
   - `auto_review`：**仍是 on-request 通道**，但由 carefully prompted **子代理** 收集上下文并批/拒（TUI 文案 “Approve for me”），不是「关审批」
3. **`sandbox` / `sandboxPolicy`**  
   - `workspace-write` + **非空** writableRoots：工作区可写，越界/敏感动作才 escalation  
   - `danger-full-access`：宽沙箱，常配 `never`

### 0.2 官方运行时环（必须完整才叫「走了 Codex 审批」）

```
UI 选 mode → thread/settings/update 或 turn/start|thread/start 写入 triad
    → agent 触发需授权动作
    → app-server 发出 server request: requestApproval
    → host 建卡 (CodexRequestCard) 
    → 用户/auto_review 决策
    → respondToServerRequest(requestId, accept|deny)
    → Codex 继续/中止该动作
```

**auto_review 不是「不审批」**：policy 仍是 `on-request`，reviewer 换成 `auto_review` 子代理；用户侧可能看不到人工卡，但 **server 侧仍走 approval 通道**（可有 guardian lifecycle 事件）。

### 0.3 OmniBot 三档映射（代码现状，B20/B25/B35）

| UI `CodexPermissionMode` | approvalPolicy | approvalsReviewer | sandbox |
|--------------------------|----------------|-------------------|---------|
| `defaultMode` | `on-request` | `user` | `workspaceWrite` + 非空 roots |
| `autoReview` | `on-request` | `auto_review` | 同上 |
| `fullAccess` | `never` | `user` | `dangerFullAccess` |

映射表本身与 TUI/schema **对齐**。用户说的 bug 不是「映射字符串写错」，而是 **这条 triad 没有稳定进入 live Codex，且 requestApproval 环未在真机闭合**。

### 0.4 为何仍像「只有 UI」（代码+日志硬证据）

| 缺口 | 证据 | 后果 |
|------|------|------|
| settings 写不进 live thread | 日志 `permission_set fail:* thread not found` | UI/tip 与 Codex policy 脱节 |
| Dart `startThread` **不传** approval/reviewer/sandbox | `CodexAppServerService.startThread` 无这些参数 | 新 thread 只吃 Kotlin 默认 `on-request` + sandbox，**不带当前 UI mode 的 reviewer/fullAccess** |
| Kotlin start 有默认但不读 UI mode | `approvalPolicy ?: "on-request"`；reviewer 仅当 args 有才写 | fullAccess / autoReview 若只改 UI 未 settings/turn，**线程仍是默认** |
| turn 带 triad，但依赖活跃 thread | `startTurn` 传 policy/reviewer/sandboxPolicy | 若 thread 死/分叉，仍 fail |
| 真机无 requestApproval 线 | 20260717 日志无 approval 决策埋点 | 无法证明进了 Codex 审批环 |
| 卡+respond 代码在 | `codex_event_reducer` → `CodexRequestCard` → `respondToApproval` | **路径存在 ≠ 触发**；policy=never 或未写入 on-request 则永不触发 |

B37 只治了「死 thread 报错」的表层；**不能**把 stale_cleared + tip 当 T6 PASS。

---

## 4. 改正清单（按优先级）

### P0 — Codex 原生审批流水线（T6，用户定义真 bug）

1. **验收定义改写**：PASS = 日志可见完整环  
   - `permission_set` → `settingsRpc=ok`（或 clear 后 **ensure thread + re-apply ok**）  
   - `turn_start` / `thread_start` 字段含当前 `approvalPolicy` + `approvalsReviewer` + `sandbox`  
   - default 下触发需授权动作 → **`requestApproval` 事件** + 审批卡  
   - 点批准/拒绝 → `respondToServerRequest` 成功 + 动作继续/中止  
   - autoReview → reviewer=`auto_review` 且 **不要求**人工卡，但应有 auto_review/guardian 相关事件或可观测决策  
   - fullAccess → policy=`never`，**不**弹人工审批卡  
   - **tip/setState 单独不算 PASS**
2. **`startThread` 必带当前 triad**（Dart 扩参 + Kotlin 已支持 args）：与 `_codexPermissionMode` 一致；禁止只靠 Kotlin 静默默认。  
3. **settings 失败恢复**：stale → clear → **ensure/rebind live thread** → 再 `updateThreadSettings`；仍失败则 error，**禁止**假成功 tip。  
4. **切 mode 后强制 re-assert**：同 mode re-tap 也应对 live thread 重推 triad（B35 意图保留并测通）。  
5. **埋点**：`approval_prompt`（收到 requestApproval）、`approval_decision`（accept/deny + requestId）；无则视为未进环。  
6. **writableRoots**：保持 B25 非空；空 roots 禁止下发 on-request workspace。  
7. **默认档**：产品当前 `defaultMode`（非 fullAccess）；确认冷启动/新会话不会 sticky 到 conf 里的 never。

### P0 — 模型列表真源（T3）

1. **新增** OmniBot 侧拉取：`GET {localConfig.baseUrl}/models`（或规范化：`baseUrl` 去尾 `/` + `/models`）。  
   - baseUrl 来自 `config/local/read`（与写 conf 同源），**禁止**写死 host。  
   - 鉴权：`Authorization: Bearer {apiKey}`（同源 auth.json / localConfig）。  
2. **解析**：OpenAI 形 `{ data: [ { id, object, owned_by, created } ] }` → 选项 id = `data[].id`，保序。  
3. **UI `_loadCodexModelOptions`**：默认/主路径用上述 HTTP 结果；  
   - **不要**再把 app-server `model/list` 当唯一真源。  
   - app-server `model/list` 可保留作：effort catalog / 兼容 fallback（仅当 HTTP 失败且需降级时，并打日志 `source=app_server_fallback`）。  
4. **过滤策略（产品默认建议）**：  
   - 列表 = 上游全量 id（9 个），与 curl 一致；  
   - 可选：过滤明显非 chat 的 id（如 `gpt-image-2`）——**需产品确认**，默认先全量对齐。  
5. **日志**：`model_list source=http_v1 count=N models=...`；失败写 `error` + HTTP code，不静默空列表。  
6. **禁止**：用本机沙盒 `~/.codex/model_catalog.json`、手写 slug 表、display_name 臆造当列表源。

### P0 — 真机 T1/T2/T4 收口（B37 复测 + 补洞）

7. 装 `898dc26` 包复测：审批切换、模型切换、Fast 开关在 **goal clear 后 / 热启动后** 不报 `thread not found` 红错（允许「会话失效，下轮生效」软提示）。  
8. 若仍 fail：补 **settings 路径** 在 native 对 `thread not found` 的 recover（对齐 turn/start 的 `shouldRecoverMissingThread`），或 Flutter 在 clear 后 **强制 ensure thread 再 apply**（model/perm 需要立刻进 live thread 时）。  
9. 模型选中：成功路径必须 `setState` + pref；失败仅非-stale 错误才 toast error。

### P1 — 开关稳定性（T4）

10. Fast：settings stale 不 rollback（B37）→ 复测 conf 写成功且 UI 不抖。  
11. auto-compact：slash 与卡同一路径（B37）→ 复测一致。  
12. soft conf 写后禁止无故 disconnect（B37）→ 日志 `restart=skipped reason=soft`。

### P1 — Channel / 会话（T5 + 分叉 threadId）

13. `MissingPluginException connect`：Engine 重建时 channel 注册时序；goal.get 前 ensure connect。  
14. 同一 conversation 下 goal/composer/turn `threadId` 统一绑定源；clear 同步。

### P2 — 观测与验收工具

15. DebugFileLog：`model_list` 加 `source`/`httpStatus`；`approval_*` 埋点见 P0-T6。  
16. 可选：设置页强制刷新 models。  
17. DELIVERY：真源 endpoint + 审批环测点表。

---

## 5. 明确不做

- 不拿沙盒 Codex CLI catalog 对账模型。  
- 不本机 Gradle assemble；只 GHA + stage Download。  
- 不把 displayName 当 wire id。  
- 不默认错误双前缀 `/api/v1/models`。  
- **不把 tip / setState / stale_cleared 软提示当成审批闭环 PASS。**  
- 不把 plan-mode 批准（B7）与 exec `requestApproval` 混为一谈（相关但不同环）。

---

## 6. 验收标准（真机）

| 测点 | PASS |
|------|------|
| **AP1** | **default**：发一条会触发 shell/写盘越界的任务 → 出现 **Codex 审批卡**；日志有 `requestApproval` / `approval_prompt` |
| **AP2** | 卡上批准 → `respondToServerRequest` ok，动作继续；拒绝 → 中止 |
| **AP3** | **autoReview**：settings/turn 日志 `approvalsReviewer=auto_review` + `on-request`；自动决策可观测（或明确 guardian/auto 事件），非仅 UI 标签 |
| **AP4** | **fullAccess**：`never` + `dangerFullAccess`；同任务 **不**弹人工审批卡 |
| **AP5** | 切三档：live thread 时 `permission_set settingsRpc=ok`；失败不得假 tip 成功 |
| **AP6** | 双 Engine 竞争同一请求：只允许一个终态；另一端 `ALREADY_RESPONDED` 记 `handled_elsewhere`，不得显示伪失败 |
| **AP7** | 断连/重连或 generation 更新：旧卡失效且不能响应新 session；retryable 请求按有界策略恢复 |
| M1 | 模型菜单 id 集合 = `GET {baseUrl}/models` 的 `data[].id` |
| M2 | 日志 `model_list source=http_v1 count=…` 与菜单一致 |
| M3 | 切模型成功；无 `select_failed` |
| F1 | Fast 开/关稳定 |
| A1 | 自动压缩卡与 slash 一致 |
| R1 | 10 分钟无成片 `thread not found`；MissingPlugin 不拖死开关 |

---

## 7. 建议实现切片（并发工作线，≥8）

| 代理 | 任务 |
|------|------|
| A1 | 只读：对照 §0 与当前 `_setCodexPermissionMode` / startThread/startTurn / reducer / card 全路径 diff |
| A2 | Dart `startThread` 扩参 + 所有调用点注入 triad；Kotlin 透传验收 |
| A3 | settings stale → ensure thread → re-apply；禁止假成功 tip |
| A4 | `approval_prompt` / `approval_decision` 埋点 + 事件进 reducer 不丢 |
| A5 | HTTP `GET baseUrl/models` + `_loadCodexModelOptions` 换真源 |
| A6 | thread 分叉 / MissingPlugin 加固 |
| A7 | 文档 EXEC/DELIVERY + 真机 AP1–AP7 / M1–R1 表 |
| A8 | 远端九路质量门禁、source-policy 与最终整合验收 |

---

## 8. 交付物

- 聚焦功能/CI/文档 commits；整合前均只到 `IMPLEMENTED`。
- 最终整合 HEAD 的远端九路 SUCCESS 后，EXEC 回填 run/commit 并升 `REMOTE_VERIFIED`。
- 同一 HEAD 的固定签名 APK 回填 path/SHA/cert 后升 `APK_STAGED`。
- 用户复测 **AP1–AP7 优先**，再 M1–R1；部分证据只到 `DEVICE_PARTIAL`，完整通过后才到 `DEVICE_PASS` / `READY`。

---

## 9. 一句话

**审批的真 bug 不是 tip 没弹出，而是 Codex 的 `requestApproval → 卡 → respondToServerRequest` 环没闭合；映射表虽对齐 TUI，但 startThread 不带 triad + settings 写死 thread = 仍只有 UI。B38 先修这条环，再修 `/v1/models` 列表真源与 stale 开关。**
