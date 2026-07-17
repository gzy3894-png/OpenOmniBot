# 当前交付单

> 更新：2026-07-17 · Stage **B37 READY**（pending device retest）  
> **真源：** `docs/results/PLAN-2026-07-17-b37-stale-thread-settings.md` · EXEC `docs/results/EXEC-2026-07-17-b37-stale-thread.md`  
> 上一包：B34–B36 · `7896a6c` · GHA #29565426990 · sha256 `aa34e473…e6d9a8` · **真机 FAIL**  
> **主线程：方案/调度/验收** · push **仅 mine** · 禁本机 assemble  
> 状态：**READY** · HEAD `898dc26` · GHA #29594207043 SUCCESS · APK staged · **待真机复测**

---

## 1. 现在请你做

**真机侧（装本包后复测）：**

1. 安装 staged APK（见 §3）。  
2. 按 §4 全表 + **优先清单** 复测。  
3. 回传 PASS/FAIL 与关键日志（`omnibot-debug-*.log` / OmniBotLogs）。

**优先复测清单：**

- permission mode 切换  
- model switch  
- model labels（displayName / wire slug）  
- Fast / auto-compact toggles  
- 上述开关在 **goal clear / resume** 之后仍可用、无 `thread not found`

**开发侧：**

- 本波代码与 GHA 已完成；无本机 assemble。  
- 真机 FAIL 再开下一波 PLAN。

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
