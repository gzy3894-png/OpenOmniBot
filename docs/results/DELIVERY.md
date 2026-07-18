# 当前交付单

> 更新：2026-07-18 · **B37 基线 APK 仍可用** · **下一刀 B38 方案已落盘、实现未开工**  
> **B38 真源：** `docs/results/PLAN-2026-07-18-b38-models-api-and-regressions.md`  
> **B38 交接：** `docs/results/HANDOFF-2026-07-18-b38-approval-models.md`  
> **B37 真源：** `PLAN-2026-07-17-b37-stale-thread-settings.md` · EXEC `EXEC-2026-07-17-b37-stale-thread.md`  
> **主线程：方案/调度/验收** · push **仅 mine** · 禁本机 assemble  
> 状态：**B37 READY 包 staged** · HEAD 文档波待 push · **B38 等「开工」**

---

## 0. 下一刀 B38（新对话第一读）

用户裁定：

1. **T6（P0）**：审批只有 UI，**没有**走 Codex 自身 `requestApproval → 卡/auto_review → respondToServerRequest`。tip/setState **不算 PASS**。  
2. **T3（P0）**：模型列表真源 = `GET {baseUrl}/models`（实测 9 id），不是 app-server `model/list`。

| 读什么 | 路径 |
|--------|------|
| 完整方案 | `PLAN-2026-07-18-b38-models-api-and-regressions.md`（§0 官方审批 + AP1–AP5） |
| 交接 | `HANDOFF-2026-07-18-b38-approval-models.md` |
| 对照 | `reports/scout-b20-perm.md` · `reports/impl-b25-perm.md` |

**硬缺口：** Dart `startThread` 不传 triad；settings 曾 `thread not found`；真机日志无 requestApproval 线。  
**站规：** ≥6 子代理实现；push 仅 mine；GHA only。

---

## 1. 现在请你做

**若开新对话做 B38：** 读 §0 交接 → 说「开工」→ 主线程只调度。  

**若仍要装 B37 基线摸底：**

1. 安装 staged APK（见 §3）。  
2. 知悉：B37 **未**修 T6/T3；权限 tip 成功 ≠ Codex 审批环。  
3. 回传日志时重点搜：`permission_set` / `requestApproval` / `model_list`。

**开发侧：**

- B38 **实现未开工**；本波仅文档落盘。  
- 无本机 assemble。

---

## 2. B34–B36 包状态（归档 · 真机 FAIL）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（已被 B37 覆盖） |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-7896a6c-standard-debug.apk` |
| 状态 | **真机 FAIL**（设置 RPC stale thread） |
| sha256 | `aa34e473d781302247188bc925425893fe8e1b7a0ce9e3ad219a412437e6d9a8` |
| 功能 commit | `d7abe18` + `7896a6c` |
| HEAD（该波） | `7896a6c9342303d964f9908e2571a4471d619afd` |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29565426990](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29565426990) · SUCCESS · head `7896a6c` |
| 计划 / EXEC | `PLAN-2026-07-17-b34-fast-perm-leak.md` · `EXEC-2026-07-17-b34-b36.md` |

### FAIL 证据（`omnibot-debug-20260717.log`）

- `permission_set fail: thread not found`
- `model select_failed: thread not found`
- `fast_set settingsRpc fail: thread not found`
- `MissingPluginException connect` intermittent
- `model_list` 加载 7 wire ids **OK**

### 根因摘要（→ B37）

1. Soft conf 写假阳性 hard/bootstrap（toml 读空）→ session kill → stale threadId  
2. Flutter 死线程 settings RPC：无 clear / 无本地 apply  
3. 模型 UI 仅 wire（次要）

---

## 3. 当前波 · B37 READY（pending device retest）

| 项 | 值 |
|----|-----|
| 状态 | **READY** · **pending device retest** |
| 计划 | `PLAN-2026-07-17-b37-stale-thread-settings.md` |
| EXEC | `EXEC-2026-07-17-b37-stale-thread.md` |
| 功能 commit | `1220a4d`（stale-thread + soft conf harden + model display + auto-compact） |
| 编译修 | `898dc26`（base abstract for auto-compact compile fix） |
| HEAD | `898dc26` |
| 首包 GHA | [#29593369757](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29593369757) **FAILED**（cross-mixin private compile） |
| GHA | [Baseline Standard Debug #29594207043](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29594207043) · **SUCCESS** · head `898dc26` |
| APK sha256 | `9c560e73b461cee69ac0a9b2ceb93fa8551fd7b8e0b43bbc2b5473257164fd68` |
| stage | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 版本副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-898dc26-9c560e73.apk` |
| 分支 / fork | `secondary/s1-baseline` · `gzy3894-png/OpenOmniBot` · push **仅 mine** |

### 本波已实现

| ID | 修复 |
|----|------|
| **B37** | Manager `writeLocalConfig` 硬化（`existingTomlKnown` / `existingAuthKnown` / `firstLocalBootstrap` 仅无 live session）；Flutter stale clear + model/perm/fast 本地 apply；displayName map（cards/composer）；auto-compact slash → `_setCodexAutoCompactionEnabled` |

**保留不回滚：** B34 Fast≠compact · B35 权限按钮 · B36 soft 意图（修假阳性 kill）· B32 wire slug

---

## 4. 测点（B37 · PLAN §7）

| # | 操作 | PASS 标准 |
|---|------|-----------|
| 1 | Fast 连拨 ×5 | 无 `thread not found`；session 不无故 kill |
| 2 | 权限三级各一次 | 无 `permission_set fail: thread not found` |
| 3 | 模型选另一 slug | 无 `select_failed`；有 displayName 则展示，value=slug |
| 4 | 自动压缩 / `/auto-compact` | conf↔UI 同步；不 compact RPC |
| 5 | soft 写后立刻 perm/model/fast | session 仍活；无连环 fail |
| 6 | 回归 B34 | Fast ≠ 压缩 |
| 7 | 回归 B35 | 权限按钮可见可点 |
| 8 | model_list | wire ids 仍加载 |
| 9 | 使用 5–10 min | reconnect 不误杀；MissingPlugin 偶发可记日志 |

**设备优先复测：** permission mode · model switch · model labels · Fast/auto-compact toggles after goal clear / resume。

---

## 5. 状态勾选

- [x] B34–B36 实现 + GHA SUCCESS + APK stage  
- [x] 真机复测 → **FAIL**（stale thread settings）  
- [x] B37 PLAN / EXEC 文档  
- [x] B37 实现 · `1220a4d` + `898dc26`  
- [x] push mine · GHA #29594207043 SUCCESS  
- [x] APK stage · sha256 `9c560e73…` / shortsha `898dc26`  
- [ ] 真机 §4 PASS  

---

## 6. 未改 / 残余

- Remote 2s poll、每 event `debugPrint`：仍未改  
- MissingPlugin connect：B37 不优先全量修，除非阻断设置且有新证据  
- hard 字段（baseUrl / model / apiKey）变更仍应 reconnect  
