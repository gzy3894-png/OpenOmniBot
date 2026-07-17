# 当前交付单

> 更新：2026-07-17 · Stage **B37 READY-for-push**（代码已落 · commit/GHA 待做）  
> **真源：** `docs/results/PLAN-2026-07-17-b37-stale-thread-settings.md` · EXEC `docs/results/EXEC-2026-07-17-b37-stale-thread.md`  
> 上一包：B34–B36 · `7896a6c` · GHA #29565426990 · sha256 `aa34e473…e6d9a8` · **真机 FAIL**  
> **主线程：方案/调度/验收** · push **仅 mine** · 禁本机 assemble  
> 状态：**READY-for-push** · **不编** 新 commit / GHA run id（待 push 后回填）

---

## 1. 现在请你做

**开发侧：**

1. push **mine only** → 等 GHA `baseline-standard-debug` → stage APK。  
2. 回填 EXEC/本单：commit · GHA run · sha256 → 标 **READY**。  
3. **禁止本机 assemble**。

**真机侧：**

- B34–B36（`7896a6c` / `aa34e473…`）**已 FAIL**，不必再测该包修设置类。  
- B37 出包并 READY 后再装新 APK，按 §4 复测。

---

## 2. B34–B36 包状态（归档 · 真机 FAIL）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
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

## 3. 当前波 · B37（READY-for-push）

| 项 | 值 |
|----|-----|
| 状态 | **READY-for-push**（代码已落 · 待 push/GHA） |
| 计划 | `PLAN-2026-07-17-b37-stale-thread-settings.md` |
| EXEC | `EXEC-2026-07-17-b37-stale-thread.md` |
| 功能 commit | _TBD_ |
| HEAD | _TBD_ |
| GHA | _TBD_ · workflow `baseline-standard-debug` |
| APK sha256 | _TBD_ |
| stage | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` + `…-<shortsha>-…` |

### 本波已实现（待 push）

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

---

## 5. 状态勾选

- [x] B34–B36 实现 + GHA SUCCESS + APK stage  
- [x] 真机复测 → **FAIL**（stale thread settings）  
- [x] B37 PLAN / EXEC 文档  
- [x] B37 实现（代码已落 · 待 push）  
- [ ] push mine · GHA SUCCESS  
- [ ] APK stage · 填 sha256 / shortsha  
- [ ] 真机 §4 PASS  

---

## 6. 未改 / 残余

- Remote 2s poll、每 event `debugPrint`：仍未改  
- MissingPlugin connect：B37 不优先全量修，除非阻断设置且有新证据  
- hard 字段（baseUrl / model / apiKey）变更仍应 reconnect  
