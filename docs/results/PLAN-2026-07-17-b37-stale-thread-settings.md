# PLAN-2026-07-17 · B37 stale thread / settings RPC（新对话真源）

> **本文件只做定位与交付约束，不实现。**  
> 上一 READY：B34–B36 · 功能 `d7abe18` + 编译修 `7896a6c` · GHA `baseline-standard-debug` SUCCESS · APK sha256 `aa34e473…e6d9a8`  
> **真机复测：FAIL**（见 §0 / §2）  
> 分支：`secondary/s1-baseline` · push **仅 mine** `gzy3894-png/OpenOmniBot`  
> 工作区：`/root/workspace/omnibot-product` · **主线程只做方案/调度/验收** · 子代理实现 · **≥6 并发**  
> GHA：`baseline-standard-debug` → `assembleDevelopStandardDebug` / `lib/main_standard.dart` · **禁止本机 Gradle assemble**  
> 状态：**READY** · HEAD `898dc26` · GHA #29594207043 SUCCESS · APK staged · **pending device retest**

---

## 0. 真机 FAIL 证据（B34–B36 复测）

日志：`omnibot-debug-20260717.log`（及同日 OmniBotLogs）

| 现象 | 证据要点 |
|------|----------|
| 权限切换失败 | `permission_set fail: thread not found` |
| 模型选择失败 | `model select_failed: thread not found` |
| Fast 开关失败 | `fast_set settingsRpc fail: thread not found` |
| 通道偶发 | `MissingPluginException connect` intermittent |
| 模型列表本身 | `model_list` 加载 **7 个 wire id** 正常（列表 OK，RPC 写设置挂） |

**结论：** B34 三路互斥 / B35 权限按钮 / B32 residual 列表 slug **未完全否定**；主 FAIL 是 **settings RPC 打到已死 / 陈旧 `threadId`**，导致 perm / model / fast 写设置全挂。`model_list` 能出 7 项说明 list 路径与 stale write 路径分离。

---

## 1. ID 映射

| ID | 要点 | 产品目标 |
|----|------|----------|
| **B37** | soft conf / bootstrap 误杀 session → stale threadId；Flutter 对死线程 RPC 无清场；模型 UI 仅 wire | Manager 写 conf 硬化；Flutter stale 清 thread + 本地乐观应用；displayName 映射；auto-compact slash UI 同步 |

本波 **不回滚** B34–B36 已合逻辑（Fast≠compact、权限按钮、soft 名单意图）；在其上修 **false-positive hard change** 与 **死线程 RPC**。

---

## 2. 根因（钉死后再改）

| # | 根因 | 机制 | 与 FAIL 的对应 |
|---|------|------|----------------|
| **R1** | Soft conf 写 **假阳性 hard change / bootstrap** | `writeLocalConfig` 读 toml **空**（时序/缓存/路径）→  diff 判为硬字段变更或 bootstrap → **session kill / reconnect** → 旧 `threadId` 作废 | 拨 Fast / 改 auto-compact 等 soft 字段后，后续 perm/model/fast 全部 `thread not found` |
| **R2** | Flutter settings RPC 打在 **死线程** | `_setCodexPermissionMode` / model select / `_setCodexFastEnabled` 仍用内存 threadId；失败后 **无 clear stale**、**无 setState 回滚/本地应用** | 日志 `*_fail: thread not found`；UI 状态与真实 session 脱节 |
| **R3** | 模型 UI **只显示 wire id**（次要） | list 有 slug；展示未 map `displayName` | 列表 7 项可用但难读；非主 FAIL |

附带：`MissingPluginException connect` 偶发 → 加重 reconnect 窗口内 stale id 竞态，B37 以 **清 stale + 本地 apply + 写 conf 不误杀** 为主，不扩大为插件通道大修，除非证据强制。

---

## 3. 修复范围（B37）

### 3.1 Manager · `writeLocalConfig` 硬化（R1）

| 优先级 | 动作 |
|--------|------|
| P0 | toml **读空** 不得默认等价「硬字段全变」；缺读 → 保守 **不 kill session**（或重试读一次再判） |
| P0 | soft 字段集合保持/收紧：`fast_mode` / `auto_compaction` / `service_tier` / threshold 等 **永不** 触发 disconnect |
| P0 | hard 字段（baseUrl / model / apiKey 等）变更才允许 restart；日志打清：`soft_skip_disconnect` vs `hard_reconnect` + 读空标志 |
| P1 | bootstrap 路径与 soft 写回分离；避免 conf 热写走 bootstrap 全量 |

**锁建议：** `L-Manager` / `L-ConfAPI`  
**文件锚点（实现时再精确定位）：**  
`app/.../CodexAppServerManager.kt`（B36 soft 入口）、conf 读写与 session lifecycle 相邻逻辑。

### 3.2 Flutter · stale thread 清场 + 本地 apply（R2）

| 优先级 | 动作 |
|--------|------|
| P0 | settings RPC 返回 `thread not found`（及等价）→ **clear 内存 threadId / 会话绑定**；禁止继续用死 id |
| P0 | **model / perm / fast**：RPC 失败时 **本地 setState 仍应用用户意图**（乐观 UI + conf 侧已成功则保留）；成功路径保持现逻辑 |
| P0 | 失败 tip 可区分：`线程已失效，已本地应用，请重开对话后再 RPC` vs 真 conf 失败 |
| P1 | reconnect / 新 thread 就绪后可选 reconcile；本波不强制全量 resync |
| P1 | 统一 helper：`isStaleThreadError` + `clearStaleThreadBinding`，三处共用，避免只修 Fast |

**锁建议：** `L-CodexCore` · `L-ChatUI`  
**文件锚点：**  
`ui/.../chat_page_codex.dart`（`_setCodexFastEnabled` / `_setCodexPermissionMode` / model select / settingsRpc）  
相关 mixin 仅声明、实现放对文件（避免再踩跨 mixin 编译坑）。

### 3.3 模型 displayName 映射（R3 · 次要）

| 优先级 | 动作 |
|--------|------|
| P1 | UI 展示：`displayName`（有则）+ 保留 wire id 作 value；**wire id 仍与 model/list slug 一致**（不回退 B32） |
| P1 | 无 displayName 时回退 wire，不编造 |

### 3.4 auto-compact slash UI 同步

| 优先级 | 动作 |
|--------|------|
| P0/P1 | `/auto-compact` 与卡开关 **同一状态源**；toggle 后卡片/ tip / conf 一致 |
| P1 | 若 soft 写 conf 成功但 thread RPC 无意义（auto-compact 本就不该 thread compact），UI 只反映 conf，不打 thread settings |

---

## 4. 非目标（本波不做）

- 不删 B35 权限按钮；不把 Fast 再接到 compact。  
- 不本机 `assemble*`；不 push `origin`/上游。  
- 不编造 commit SHA / GHA run id；READY 字段仅填已验证值。  
- 不扩大修 Remote 2s poll / 全量 MissingPlugin 根治（除非 R1 修后仍必现且有新证据）。  
- 不回滚 B34 三路互斥与 B36 soft 意图；只修 **假阳性 kill** 与 **死线程 RPC**。

---

## 5. 并发执行（主线程调度 · ≥6 代理）

| 代理 | 锁 | 任务 |
|------|-----|------|
| A1 | 只读 | 钉 R1：`writeLocalConfig` 空 toml / hard 判定 / disconnect 调用图 + 对照 debug 日志时间线 |
| A2 | 只读 | 钉 R2：perm/model/fast settingsRpc 错误处理；是否 rollback / setState |
| A3 | L-Manager | writeLocalConfig 硬化：读空保守、soft 永不 kill、日志字段 |
| A4 | L-CodexCore | stale clear helper + fast/perm/model 三路径接入 |
| A5 | L-ChatUI | 乐观本地 apply + tip 文案；auto-compact 卡/slash UI 同步 |
| A6 | L-ModelUI | displayName map（value=wire slug） |
| A7（可选） | 文档/测试 | EXEC 勾选、测点表、单测若有 conf soft 判定 |

合并顺序：A1+A2 结论 → A3 与 A4 并行 → A5/A6 并行 → 统一 commit → push **mine** → 等 GHA → stage APK → DELIVERY READY。

---

## 6. 交付与 Git 约束（沿用）

- push **只** `mine`（`gzy3894-png/OpenOmniBot`），**禁止** push `origin`/上游。  
- APK 只走 GHA artifact `omnibot-standard-debug-apk`，stage 到  
  `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` + `…-<shortsha>-…`。  
- 主线程不写业务实现码；验收对照 §7。  
- 记忆：`mem short` 记过程；长期 `mem propose-long`；**不写密钥**。

### 本波交付（已填）

| 项 | 值 |
|----|-----|
| 功能 commit | `1220a4d` |
| 编译修 | `898dc26`（cross-mixin private → base abstract） |
| HEAD | `898dc26` |
| GHA | #29594207043 SUCCESS（首包 #29593369757 FAILED 后修） |
| APK sha256 | `9c560e73b461cee69ac0a9b2ceb93fa8551fd7b8e0b43bbc2b5473257164fd68` |
| stage | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 版本副本 | `…-898dc26-9c560e73.apk` |

---

## 7. 真机测点（修完后 DELIVERY 用）

| # | 操作 | PASS |
|---|------|------|
| 1 | 冷启动后只拨 Fast 开→关→开 ×5 | 无 `thread not found`；无 session 无故 kill；tip 与 UI 一致 |
| 2 | 切权限三级各一次 | 无 `permission_set fail: thread not found`；按钮与策略一致 |
| 3 | 模型列表选另一 slug | 无 `select_failed: thread not found`；展示 displayName（若有），value 仍为 slug |
| 4 | 点「自动压缩」/ `/auto-compact` | conf 与卡状态同步；**不** compact RPC；无 stale 风暴 |
| 5 | soft 写 conf 后立刻 perm/model/fast | session 仍活；若曾 stale 则 clear 后可恢复，不连环 fail |
| 6 | 回归 B34 | Fast ≠ 压缩；三路互斥 |
| 7 | 回归 B35 | 权限按钮可见可点 |
| 8 | `model_list` | 仍能加载 wire ids（≥ 本机 catalog）；展示可读 |
| 9 | 使用 5–10 min | 关注 reconnect 是否仍误触发；MissingPlugin 若仍偶发记日志不挡本波 PASS（除非阻断设置） |

**复测优先清单（设备）：** permission mode · model switch · model labels · Fast/auto-compact toggles after goal clear / resume。

---

## 8. 相关文件速查

```
app/.../CodexAppServerManager.kt          # writeLocalConfig / soft vs hard / disconnect
ui/.../chat_page_codex.dart               # fast / perm / model settingsRpc
ui/.../chat_page_ui.dart                  # 卡 / 权限 props / 模型展示
ui/.../codex_slash_commands.dart          # /auto-compact · /fast · resolve
ui/.../chat_input_area_composer.dart      # 权限按钮（B35，勿再关）
docs/results/PLAN-2026-07-17-b34-fast-perm-leak.md
docs/results/EXEC-2026-07-17-b34-b36.md
docs/results/DELIVERY.md
日志：omnibot-debug-20260717.log
```

---

## 9. 状态机（文档）

| 阶段 | 状态 |
|------|------|
| 本文档 / 定位 | **完成** |
| 代码实现（Manager 硬化 · stale clear · displayName · auto-compact UI） | **完成** · `1220a4d` + `898dc26` |
| push + GHA + APK stage | **完成** · GHA #29594207043 · sha256 `9c560e73…` |
| 真机 §7 | **pending device retest** · 用户 PASS/FAIL |
