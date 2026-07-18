# 当前交付单

> 更新：2026-07-18 · 当前 hardening 候选 **IMPLEMENTED · REMOTE TEST PENDING**
> 旧 B38 APK/日志证据集：**DEVICE_PARTIAL**；不得拿旧 GHA/APK 给当前候选提级
> **B38 真源：** `docs/results/PLAN-2026-07-18-b38-models-api-and-regressions.md`  
> **唯一实时账本：** `docs/results/EXEC-2026-07-18-b38-approval-models.md`
> **旧交接：** `docs/results/HANDOFF-2026-07-18-b38-approval-models.md`（**SUPERSEDED**）
> **B37 真源：** `PLAN-2026-07-17-b37-stale-thread-settings.md` · EXEC `EXEC-2026-07-17-b37-stale-thread.md`  
> **主线程只调度/验收** · ≥8 并发工作线 · push **仅 mine** · 最终九路远端门禁 · 禁本机编译测试
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

---

## 0. 当前波 · B38 hardening（IMPLEMENTED · REMOTE TEST PENDING）

| 工作线 | 状态 | commit / 备注 |
|--------|------|---------------|
| Native 审批/会话所有权 | `IMPLEMENTED` | `10a169e029f248f4b9734cddcae327d48280e72a` |
| Models/UI catalog 一致性 | `IMPLEMENTED` | `86cec55a85db446394ddbf1ebd306ee326dee960` |
| Approval UI/幂等回归 | `IMPLEMENTED` | `3ceaba07290273a303b9398769666fb2de57442c` |
| 八→九路远端质量门禁 | `IMPLEMENTED` | `6e56dd943319328148df965b251dfd215670fb1a` + `522c346e8a10dc37a1532e09bba56a4f3d30b2c2` |
| 文档/证据治理 | `IMPLEMENTED` | 本提交后回填 |

当前没有可交付的新 APK。以下字段全部待最终整合后按顺序回填：

| 字段 | 状态 |
|------|------|
| integration HEAD | 待回填 |
| 九路 GHA run ID / URL / result | 待运行；不得预写 SUCCESS |
| APK artifact / stage path | 待 `REMOTE_VERIFIED` 后产出 |
| APK SHA-256 / cert SHA-256 | 待回填 |
| AP1–AP7 / M1–M3 / F1 / A1 / R1 | 待同一 APK 真机验证 |

门禁纪律：

- topic commit 与源码级静态自审只支持 `IMPLEMENTED`。
- 九路远端全绿才到 `REMOTE_VERIFIED`；同一 HEAD 的签名包落位后才到 `APK_STAGED`。
- 任一设备失败、未知或矩阵未完成都只能到 `DEVICE_PARTIAL`；完整通过才到 `DEVICE_PASS → READY`。
- 本轮不进入 S2，不改写旧 commit、run、APK、SHA 或日志历史。

## 1. 旧 B38 候选 `68c1b79`（DEVICE_PARTIAL）

用户裁定：

1. **T6（P0）**：审批只有 UI，**没有**走 Codex 自身 `requestApproval → 卡/auto_review → respondToServerRequest`。tip/setState **不算 PASS**。  
2. **T3（P0）**：模型列表真源 = `GET {baseUrl}/models`（实测 9 id），不是 app-server `model/list`。

| 读什么 | 路径 |
|--------|------|
| 完整方案 | `PLAN-2026-07-18-b38-models-api-and-regressions.md`（§0 官方审批 + AP1–AP5） |
| 交接 | `HANDOFF-2026-07-18-b38-approval-models.md` |
| EXEC 清单 | `EXEC-2026-07-18-b38-approval-models.md` |
| 对照 | `reports/scout-b20-perm.md` · `reports/impl-b25-perm.md` |

### 旧 B38 包状态（历史证据 · 勿当当前包）

| 项 | 值 |
|----|-----|
| 状态 | **DEVICE_PARTIAL** · 历史 GHA SUCCESS / APK STAGED，但设备矩阵不完整 |
| 文档 commit | `c1e4341`（PLAN+HANDOFF） |
| 功能 commit(s) | `68c1b79` |
| HEAD（实现后） | `68c1b79`（docs 最新 `92c0600`） |
| GHA run id | `29641064531` |
| GHA 结果 | **SUCCESS** [#29641064531](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29641064531) |
| APK path | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 版本副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-68c1b79-847c4aab.apk` |
| APK sha256 | `847c4aaba2b3e6c2251be1f098d8310858ab4909904a3eb0ef57d17604265bd8` |
| 分支 / fork | `secondary/s1-baseline` · `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| 计划 / EXEC | `PLAN-2026-07-18-b38-models-api-and-regressions.md` · `EXEC-2026-07-18-b38-approval-models.md` |

**已落地（代码，非真机）：** `startThread` triad；settings stale→ensure→re-apply；HTTP `/models` 主路径；`approval_prompt`/`approval_decision`；MissingPlugin 有限加固。  
**站规：** 该包只作历史证据；tip 不算 PASS，且不得证明当前 hardening 候选。

### 历史测点（矩阵未闭合）

| # | PASS 摘要 | 结果 |
|---|-----------|------|
| AP1–AP5 | Codex 审批环（卡 + requestApproval + respond；三档映射） | |
| M1–M3 | HTTP `/models` 与菜单一致；可切换 | |
| F1 / A1 / R1 | Fast、auto-compact、10min 无成片 stale | |

该历史包没有闭合完整矩阵，因此统一归类 `DEVICE_PARTIAL`。当前候选的待测表只在 EXEC 维护。

---

## 2. 历史装机指令（SUPERSEDED）

以下路径只保留证据追溯，**不是当前装机动作**。当前 hardening 候选尚未远端验证、尚未出包。

- 历史 stage：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`
- 历史副本：`…-68c1b79-847c4aab.apk`
- 历史 SHA-256：`847c4aaba2b3e6c2251be1f098d8310858ab4909904a3eb0ef57d17604265bd8`

---

## 3. B34–B36 包状态（归档 · DEVICE_PARTIAL / 真机 FAIL）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（已被 B37 覆盖） |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-7896a6c-standard-debug.apk` |
| 状态 | **DEVICE_PARTIAL / 真机 FAIL**（设置 RPC stale thread） |
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

### 根因摘要（→ B37 → B38）

1. Soft conf 写假阳性 hard/bootstrap（toml 读空）→ session kill → stale threadId  
2. Flutter 死线程 settings RPC：无 clear / 无本地 apply  
3. 模型 UI 仅 wire（次要）→ B38 改 HTTP `/models`  
4. **T6**：triad 未稳定进 thread → 无 requestApproval 环（B38 P0）

---

## 4. 前序 · B37（DEVICE_PARTIAL · 非 B38）

| 项 | 值 |
|----|-----|
| 状态 | **DEVICE_PARTIAL** · APK staged，但 device retest 未完成 |
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

### B37 已实现（不含 T6/T3）

| ID | 修复 |
|----|------|
| **B37** | Manager `writeLocalConfig` 硬化；Flutter stale clear + model/perm/fast 本地 apply；displayName map；auto-compact slash → `_setCodexAutoCompactionEnabled` |

**保留不回滚：** B34 Fast≠compact · B35 权限按钮 · B36 soft 意图 · B32 wire slug  
**B37 未做 → B38：** requestApproval 闭环、HTTP `/models`、MissingPlugin 根治

---

## 5. 测点（B37 · PLAN §7 · 归档）

| # | 操作 | PASS 标准 |
|---|------|-----------|
| 1 | Fast 连拨 ×5 | 无 `thread not found`；session 不无故 kill |
| 2 | 权限三级各一次 | 无 `permission_set fail: thread not found` |
| 3 | 模型选另一 slug | 无 `select_failed`；有 displayName 则展示，value=slug |
| 4 | 自动压缩 / `/auto-compact` | conf↔UI 同步；不 compact RPC |
| 5 | soft 写后立刻 perm/model/fast | session 仍活；无连环 fail |
| 6 | 回归 B34 | Fast ≠ 压缩 |
| 7 | 回归 B35 | 权限按钮可见可点 |
| 8 | model_list | wire ids 仍加载（B38 将改为 HTTP 真源） |
| 9 | 使用 5–10 min | reconnect 不误杀；MissingPlugin 偶发可记日志 |

---

## 6. 状态勾选

- [x] B34–B36 实现 + GHA SUCCESS + APK stage  
- [x] 真机复测 → **FAIL**（stale thread settings）  
- [x] B37 PLAN / EXEC 文档  
- [x] B37 实现 · `1220a4d` + `898dc26`  
- [x] push mine · GHA #29594207043 SUCCESS  
- [x] APK stage · sha256 `9c560e73…` / shortsha `898dc26`  
- [ ] 真机 B37 §5 完整 PASS（当前仅 `DEVICE_PARTIAL`）
- [x] B38 PLAN + HANDOFF 落盘 · `c1e4341`  
- [x] B38 EXEC + 调度 A1–A7 实现  
- [x] B38 功能实现 · `68c1b79`  
- [x] B38 push mine · GHA `#29641064531` **SUCCESS**  
- [x] B38 APK stage · sha256 `847c4aab…` / shortsha `68c1b79`  
- [x] 旧 B38 `68c1b79` 证据重分类为 `DEVICE_PARTIAL`
- [x] 当前 hardening topic 实现完成，状态仅 `IMPLEMENTED`
- [ ] 最终 integration HEAD + 九路 `REMOTE_VERIFIED`
- [ ] 当前候选 `APK_STAGED` + SHA/cert 回填
- [ ] 当前候选 AP1–AP7 / M1–R1 达 `DEVICE_PASS`

---

## 7. 未改 / 残余

- Remote 2s poll、每 event `debugPrint`：仍未改  
- hard 字段（baseUrl / model / apiKey）变更仍应 reconnect  
- topic commits 尚未汇成并验证同一 integration HEAD；Native/Flutter 联调未知
- **当前 hardening 完成前**：审批 tip ≠ Codex 审批 PASS；远端和设备证据均待回填
