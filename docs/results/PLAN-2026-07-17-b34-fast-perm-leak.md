# PLAN-2026-07-17 · B34–B36 落地清单（新对话真源）

> **本文件只做定位与交付约束，不实现。**  
> 上一 READY：B30–B33 · commit `5542b47`（功能 `1162b66` + 编译修）· GHA `29550628790`  
> APK：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`  
> 副本：`…-5542b47-standard-debug.apk` · sha256 `418267c98ac40a82780c3646cec5e284be8e735dbb7486765be30f90d18af17c`  
> 分支：`secondary/s1-baseline` · push **仅 mine** `gzy3894-png/OpenOmniBot`  
> 工作区：`/root/workspace/omnibot-product` · **主线程只做方案/调度/验收** · 子代理实现 · **≥6 并发**  
> GHA：`baseline-standard-debug` → `assembleDevelopStandardDebug` / `lib/main_standard.dart` · **禁止本机 Gradle assemble**

---

## 0. 用户原话（绑定，勿再误读）

1. **忽略 goal-mode 测试文案**；**重点 bug 是 Fast**。  
2. Fast 模式被识别成了 **压缩对话**，报错类似「当前会话还没有可压缩的上下文 / 压缩失败」。  
3. **权限审批按钮不见了——用户并未要求删除它**；要的是能 **稳定实现请求授权**，参考 **plan 模式的授权方式**。  
4. 手机很烫，**可能存在内存泄漏**（需排查，可并行）。  
5. 新对话开工方式：按本清单 **多线程（≥6 子代理）** 修，不要单线程慢查。

**B33 计划原文**写过「去掉三级权限 UI」；**真机反馈否决「删按钮」**——产品意图改为：**保留权限入口**，载荷仍走 on-request + workspaceWrite（对齐 plan 审批），可改文案/减少迷惑，**不可整按钮消失**。

---

## 1. ID 映射（建议）

| ID | 要点 | 产品目标 |
|----|------|----------|
| **B34** | Fast 被当成压缩对话 | Fast 只改 `serviceTier=fast` / conf `features.fast_mode`；**绝不**走 manual/agent compact 或 `/compact` RPC；文案与卡片互不混淆 |
| **B35** | 权限审批按钮缺失 | **恢复** composer 权限选择器；`_setCodexPermissionMode` 可点；defaultMode=on-request 稳定弹审批（参考 plan 授权） |
| **B36** | 发热 / 疑似泄漏 | 查 Codex 监听、conf 写回、disconnect 循环、顶栏 height 回调、panel 状态；有证据再修，无证据写清「未复现/待真机 log」 |

可选后续（非本波必须）：B33 文案纠偏（「自动压缩」toolTypeLabel 勿与 Fast 混淆）；typed `/fast` 若需要可进 resolver（当前 **无** `/fast` kind，仅卡/composer 开关）。

---

## 2. 基线状态（已交付，勿回滚 B30–B32）

| 项 | 状态 |
|----|------|
| B30 顶栏上下文条 + conf 阈值 | 已进 `1162b66` |
| B31 `/` `@` 互斥 | 已进 |
| B32 模型纯 `model/list` | 已进 |
| B33 三级权限 UI 隐藏 + `/auto-compact` | **部分错误**：权限按钮被藏 → **B35 纠正**；auto-compact 卡可保留 |
| 编译修复跨 mixin | `5542b47`：auto-compact UI 字段只在 UiMixin 改 |
| 文档 READY | `3b856ce` · `docs/results/DELIVERY.md` 仍写 B30–B33 READY（**真机已报 FAIL 点，本清单覆盖**） |

**锁（可复用 EXEC 风格）：**  
`L-Composer` · `L-CodexCore` · `L-ChatUI` · `L-ConfAPI` · `L-PanelOpen` · `L-ContextBar` · 另可加 `L-LeakScan`（只读）

---

## 3. B34 · Fast ≠ 压缩 · 定位清单

### 3.1 已确认代码事实

| 事实 | 位置 | 含义 |
|------|------|------|
| Fast 卡 id | `chat_page_ui.dart` `_buildCodexRootCommandCards` · `slash-command-codex-fast-mode` · `toolTitle: '/fast'` | 展示「Fast 模式」 |
| Fast 卡 tap | `chat_page_codex.dart` `_handleCodexSlashCommandCardSelected` ~2029–2033 | **正确** → `_setCodexFastEnabled` |
| Fast 实现 | `chat_page_codex.dart` `_setCodexFastEnabled` ~995+ | 写 session `serviceTier` + conf `fastMode`；toast Fast 开关文案 |
| Fast toast 文案 | `codex_mode_submit.dart` `kCodexFastModeHint*` | 与「压缩」无关 |
| `/` 根列表顺序 | goal → **fast** → **自动压缩** → review → plan → **compact** | 相邻易误点 |
| 自动压缩卡 | `slash-command-codex-auto-compaction` · `toolTypeLabel: 压缩` | **易与「压缩对话」混淆** |
| 手动 compact 卡 | `command == '/compact'` → `_executeCodexCompactCommand` | Codex thread compact RPC |
| 解析器 | `codex_slash_commands.dart` `resolveCodexSlashSubmitIntent` | **有** `startCompact`（`/compact`）；**无** `/fast` kind |
| 提交规划 | `codex_mode_submit.dart` `planCodexComposerSubmit` | 无 `/` 前缀 → 普通消息；**不应**触发 compact |
| Codex compact 失败文案 | `_executeCodexCompactCommand` | 「当前没有可压缩的 Codex 线程」/「压缩失败：…」— **snack/tip**，非 agent marker |
| Agent 压缩 marker | `chat_conversation_runtime_coordinator.dart` `_contextCompactionLabel` | 「正在压缩 / 压缩失败 / 无需压缩 / 已压缩」· type `context_compaction_marker` |
| Normal 手动压缩 | `chat_page_openclaw.dart` `_executeManualContextCompactionCommand` | toast「当前暂无可压缩的上下文」；走 `AssistsMessageService.compactConversationContext` |

### 3.2 根因假设（新对话必须验证再改）

| # | 假设 | 如何验证 | 若成立改法 |
|---|------|----------|------------|
| H1 | 用户点了 **自动压缩/compact 卡**（紧挨 Fast），误以为是 Fast 副作用 | 复现：只点 Fast 卡 vs 点「自动压缩」/「/compact」；对照 tip「Fast 模式：已关闭」后是否出现 marker | 文案去歧义：toolTypeLabel 勿用裸「压缩」；Fast 卡与 compact 卡视觉分离；summary 明确「非压缩上下文」 |
| H2 | Codex 路径误入 **normal** `_executeManualContextCompactionCommand` | 日志/断点：`_supportsManualContextCompaction`、active mode、slash submit 在 Codex 是否仍 dispatch openclaw compact | Codex 禁止 manual agent compact；slash `/compact` 只走 `_executeCodexCompactCommand` |
| H3 | 发送「测试fast模式」或 tip 后二次路径触发 compact | 抓 `_tryHandleCodexSlashCommand` / openclaw slash 路由；plain 文本不应 compact | 修路由表；禁止 free text 命中 compact |
| H4 | conf `auto_compaction` 切换误触发一次压缩 | 点自动压缩开关是否 `beginContextCompaction` | 开关 **只写 conf**，不调 compact RPC（B33 意图） |
| H5 | UI 文案把 Fast toast 与历史 marker 叠在同一屏 | 截图时间线 | 纯展示/历史问题则文档说明 + 清噪 |

**静态结论（写清单时）：** Fast 卡 handler **本身未调用 compact**；用户现象更像 **误触 compact/auto-compact** 或 **跨 mode 走了 agent compaction marker 路径**。必须用 H1–H4 真机/代码路径钉死后再改，避免瞎改 Fast。

### 3.3 改动面（验证后）

| 优先级 | 文件 | 动作 |
|--------|------|------|
| P0 | `chat_page_codex.dart` | 保证 Fast / auto-compact / compact **三路互不串**；Fast 路径零 compact 调用 |
| P0 | `chat_page_ui.dart` 根卡 | 自动压缩：`toolTypeLabel`/`displayName` 与「压缩对话」区分；Fast summary 写清「加速/计费，不压缩上下文」 |
| P0 | 路由总闸（`chat_page.dart` / openclaw / codex） | Codex 模式下 `/compact` 与 manual compact 不交叉；mode gate |
| P1 | `codex_slash_commands.dart` | 可选：`/fast` → 专用 kind（toggle），避免 unknown→weird |
| P1 | 日志 | Fast toggle / compact start 打 `DebugFileLog` 统一字段，便于真机对照 |

### 3.4 验收

1. 只点 Fast 开/关 → 仅 Fast tip；**无** `context_compaction_marker`、无「无可压缩」toast。  
2. 只点「自动压缩」→ conf 切换 tip；**不** startCompact / 不 agent compact。  
3. 点 `/compact` → 仅 Codex thread compact 文案路径。  
4. 发送「测试fast模式」→ 普通 user turn，无压缩。

---

## 4. B35 · 恢复权限按钮 + 稳定请求授权

### 4.1 当前被关掉的点（B33 误伤）

| 文件 | 符号/行（约） | 现状 |
|------|----------------|------|
| `chat_input_area_composer.dart` | `_shouldShowCodexPermissionSelector => false` ~811 | **硬关**，即使 parent 接线也不显示 |
| `chat_page_ui.dart` | `codexPermissionMode: null` / `onCodexPermissionModeChanged: null` ~1937–1939 | 未接线 |
| 按钮本体 | `_buildCodexPermissionButton` ~1217+ | **仍在**，三级菜单 `CodexPermissionMode.values` 仍完整 |
| 模式枚举 | `chat_input_area.dart` `enum CodexPermissionMode { defaultMode, autoReview, fullAccess }` | 保留 |
| 写权限 | `chat_page_codex.dart` `_setCodexPermissionMode` ~908+ | 仍实现：thread/turn settings + approvalPolicy + sandbox |
| 默认 | `_codexPermissionMode = CodexPermissionMode.defaultMode` | on-request + user + workspaceWrite（B25 roots） |
| Plan 授权参考 | `_activateCodexPlanMode` / turn `turnUsesPlanMode` ~3344+ | **稳定审批**应对齐此路径的 approval handoff，不是删 UI |

### 4.2 改动清单

| 优先级 | 文件 | 动作 |
|--------|------|------|
| P0 | `chat_input_area_composer.dart` | **恢复** `_shouldShowCodexPermissionSelector` 为 null-check 门闸（`mode != null && onChanged != null`），删 `=> false` |
| P0 | `chat_page_ui.dart` | Codex 模式重新传入：`codexPermissionMode: _codexPermissionMode`，`onCodexPermissionModeChanged: (m) => unawaited(_setCodexPermissionMode(m))` |
| P0 | `chat_page_codex.dart` | 回归 `_setCodexPermissionMode`：defaultMode 必须稳定带 **on-request** + **writableRoots 非空**（B25）；对照 plan 审批弹窗是否仍出 |
| P1 | 文案 | 三级 label 可改「请求审批 / 自动审 / 全放行」等更直观中文；**不删入口** |
| 非目标 | 删 defaultMode 能力 | 禁止再「为简化 UX 整段隐藏」 |

### 4.3 验收

1. Codex 输入区可见权限按钮（盾牌/三级）。  
2. 切 defaultMode → 需工具时 **弹出请求授权**（与 plan 模式同类可批）。  
3. autoReview / fullAccess 行为与改前一致（或文档说明差异）。  
4. 杀进程重进权限模式仍正确（若原先有 persist 则保持）。

---

## 5. B36 · 发热 / 内存泄漏 · 排查清单

> 先 **只读扫描 + 日志点**，有硬证据再改。

| 优先级 | 嫌疑点 | 文件/方向 |
|--------|--------|-----------|
| P0 | Codex event / permission / config 监听未 dispose | `chat_page_codex.dart` bind/unbind、AppServer stream |
| P0 | conf 写成功后 reconnect 环 | `writeLocalConfig` → manager 重启是否循环 |
| P1 | 顶栏 `onHeightChanged` 触发 setState 风暴 | `codex_context_bar.dart` + `chat_page_ui` topBanner |
| P1 | slash/skills panel flag 抖动 | B31 互斥路径 |
| P1 | Fast/perm 连续 setState + toast | 热路径 |
| P2 | 真机 logcat / OmniBotLogs 看 GC、重复 connect | `/storage/emulated/0/Download/OmniBotLogs/` |

**交付：** 有修复则进同波 APK；无修复则 `docs/results/reports/` 写「扫描结论 + 未改原因」。

---

## 6. 并发执行建议（新对话第一波 ≥6）

| 代理 | 锁 | 任务 |
|------|-----|------|
| A1 | 只读 | B34 路径钉死：Fast/auto-compact/compact/manual 调用图 + 是否 H2 |
| A2 | L-ChatUI | 根卡文案去歧义（Fast vs 自动压缩 vs compact） |
| A3 | L-Composer | 恢复 `_shouldShowCodexPermissionSelector` 门闸 |
| A4 | L-ChatUI | 恢复 `chat_page_ui` 权限 props 接线 |
| A5 | L-CodexCore | `_setCodexPermissionMode` / turn 载荷与 plan 审批对齐；防 compact 串路 |
| A6 | L-LeakScan | 泄漏/热路径只读报告 |
| A7（可选） | 测试/文档 | 单测或手工测点表；更新 DELIVERY |

合并顺序建议：A1 结论 → A2/A5 串路修复 → A3+A4 并行 → A6 并行 → 统一 commit → push **mine** → 等 GHA → 拉 APK 到 Download → 改 DELIVERY。

---

## 7. 交付与 Git 约束（沿用）

- push **只** `mine`（`gzy3894-png/OpenOmniBot`），**禁止** push `origin`/上游。  
- APK 只走 GHA artifact `omnibot-standard-debug-apk`，stage 到  
  `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` + `…-<shortsha>-standard-debug.apk`。  
- 主线程不写业务实现码；验收对照 §3.4 / §4.3。  
- 记忆：`mem short` 记过程；长期用 `mem propose-long`；**不写密钥**。

---

## 8. 真机测点（修完后 DELIVERY 用）

| # | 操作 | PASS |
|---|------|------|
| 1 | 只拨 Fast 开→关→开 | 仅 Fast tip；无压缩 marker/toast |
| 2 | 发「测试fast模式」 | 正常对话，无压缩 |
| 3 | 点「自动压缩」 | conf tip；无 thread/agent compact |
| 4 | 点 `/compact` | 仅 Codex compact 文案 |
| 5 | 见权限按钮 | 存在且可点三级 |
| 6 | defaultMode 下触发需批工具 | 稳定弹出请求授权（类 plan） |
| 7 | 回归 B30–B32 | 顶栏 / 互斥 / 纯 model list 不回退 |
| 8 | 使用 5–10 min | 发热是否明显缓解（主观 + 日志） |

---

## 9. 相关文件速查

```
ui/lib/features/home/pages/chat/chat_page_ui.dart          # 根卡 + 权限 props + 顶栏
ui/lib/features/home/pages/chat/chat_page_codex.dart        # Fast / perm / compact / slash 卡
ui/lib/features/home/pages/chat/chat_page_openclaw.dart     # manual compact（agent）
ui/lib/features/home/pages/chat/utils/codex_slash_commands.dart
ui/lib/features/home/pages/chat/utils/codex_mode_submit.dart
ui/lib/features/home/pages/command_overlay/widgets/chat_input_area_composer.dart
ui/lib/features/home/pages/command_overlay/widgets/chat_input_area.dart  # CodexPermissionMode
ui/lib/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart
docs/results/PLAN-2026-07-17-b30-context-panel-model-perm.md  # 上一波（B33 误伤源）
docs/results/EXEC-2026-07-17-b30-b33.md
docs/results/DELIVERY.md
```

---

## 10. 新对话启动句（可复制）

```
按 docs/results/PLAN-2026-07-17-b34-fast-perm-leak.md 实现 B34–B36。
主线程只方案/调度/验收；≥6 并发子代理；push 仅 mine；GHA baseline-standard-debug；禁止本机 assemble。
用户否决「删除权限按钮」——必须恢复并稳定 on-request 授权（参考 plan）。
Fast 不得走压缩路径。发热/泄漏先扫描再改。
```
