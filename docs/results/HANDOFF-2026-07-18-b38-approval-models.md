# HANDOFF · B38 · Codex 原生审批 + `/v1/models` · 2026-07-18

> **给下一手（新对话）**：只信本文件 + 下列真源路径；不要靠会话摘要臆测。  
> **状态**：方案已落盘，**实现未开工**。  
> **用户裁定**：审批「只有 UI、没走 Codex 自身审批」= **真 bug（T6）**，优先级 ≥ 模型列表。

---

## 0. 一句话

B37（`898dc26`）只治死 thread 报错；**tip/setState 不算审批 PASS**。下一刀必须让 **Codex 环**闭合：

`triad 写入 thread/turn → requestApproval → 卡/auto_review → respondToServerRequest`

同时模型列表真源改为 **`GET {baseUrl}/models`**，不是 app-server `model/list`。

---

## 1. 站规（不可破）

| 规则 | 说明 |
|------|------|
| 主线程 | **只**方案 / 调度 / 验收；**≥6 并发子代理**写实现 |
| 推送 | **仅** `mine` → `gzy3894-png/OpenOmniBot`；**禁止** push origin/upstream |
| 出包 | **仅** GHA `baseline-standard-debug`；**禁本机 Gradle assemble** |
| 密钥 | 不写 memory/docs/logs；baseUrl 可写 host，key 用 conf 同源读 |
| 验收 | tip/toast/setState **单独不算**权限 PASS |

**仓库路径**：`/root/workspace/omnibot-product`  
**分支**：`secondary/s1-baseline`（以 `git branch --show-current` 为准）  
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
| 前序 READY | B37 APK `898dc26` sha `9c560e73…` Download 已 stage | 可作基线装机，**未**修 T6/T3 |

**upstream 路径说明**：若本机无 `codex-upstream-remote-test`，以 PLAN §0 摘要 + protocol 注释为准，勿拿沙盒 `~/.codex` 和 OmniBot 对账。

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

## 5. 实现切片（调度用，≥6 子代理）

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

1. `asm context` / 读本 HANDOFF + **PLAN-2026-07-18-b38…** 全文  
2. 用户确认「开工」后：主线程 **只调度** ≥6 agent 按 §5  
3. **不要**先做 tip 文案；**不要**本机 assemble；**不要**对照沙盒 Codex catalog  
4. 交付时更新 `docs/results/DELIVERY.md` + 本 HANDOFF 状态行 → READY  

---

## 9. 明确不做

- tip-only 假修复  
- 沙盒 `~/.codex` 与 OmniBot 模型对账  
- plan-mode 批准（B7）冒充 exec `requestApproval`  
- push origin；本机 Gradle  

---

*落盘：claude · 2026-07-18 · 用户要求开新对话前完整交接*
