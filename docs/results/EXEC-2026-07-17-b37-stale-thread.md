# EXEC · B37 · 2026-07-17

> 状态：**READY-for-push** · 代码已落 · **commit / GHA run id / APK sha 待填**（不编造）  
> 真源：`PLAN-2026-07-17-b37-stale-thread-settings.md`  
> 基线：B34–B36 READY 包 `7896a6c` / sha256 `aa34e473…e6d9a8` · **真机 FAIL**  
> 主线程：方案/调度/验收 · ≥6 子代理 · push **仅 mine** · GHA `baseline-standard-debug` · 禁本机 assemble

## 触发

B34–B36 真机复测 FAIL（`omnibot-debug-20260717.log`）：

- `permission_set fail: thread not found`
- `model select_failed: thread not found`
- `fast_set settingsRpc fail: thread not found`
- `MissingPluginException connect` intermittent
- `model_list` 7 wire ids **OK**（list 与 write 路径分离）

## 根因（计划钉死）

1. Soft conf 写：toml 读空 → 假阳性 hard/bootstrap → session kill → **stale threadId**
2. Flutter 死线程 settings RPC：无 clear / 无本地 setState 回滚或乐观应用
3. 模型 UI 仅 wire（次要）→ displayName map

## 范围

| 块 | 状态 | 说明 |
|----|------|------|
| Manager `writeLocalConfig` 硬化 | **完成** | `existingTomlKnown` / `existingAuthKnown` / `firstLocalBootstrap`：无 live session 才 bootstrap；读空不假阳性 hard kill |
| Flutter stale clear + local apply（model/perm/fast） | **完成** | 统一 helper + 三路径接入 |
| model displayName UI map | **完成** | cards + composer；value 仍 slug |
| auto-compact slash/卡 UI 同步 | **完成** | slash → `_setCodexAutoCompactionEnabled`；不走 compact RPC |
| push mine · GHA · stage APK | **待做** | 落地后填 run / sha |
| 真机 §7 | 未开始 | |

## 代理分工（目标 ≥6）

| 代理 | 锁 | 任务 | 状态 |
|------|-----|------|------|
| A1 | 只读 | R1 writeLocalConfig / kill 调用图 | 完成 |
| A2 | 只读 | R2 settingsRpc 错误处理 | 完成 |
| A3 | L-Manager | conf 硬化 | 完成 |
| A4 | L-CodexCore | stale clear + 三路径 | 完成 |
| A5 | L-ChatUI | 乐观 apply + auto-compact UI | 完成 |
| A6 | L-ModelUI | displayName map | 完成 |

## 改动文件（已落地勾选）

- [x] `app/.../CodexAppServerManager.kt`（及 conf 读写邻接）— writeLocalConfig 硬化
- [x] `ui/.../chat_page_codex.dart` — stale clear helpers + model/perm/fast 路径
- [x] `ui/.../chat_page_ui.dart` — displayName 卡片/展示
- [x] `ui/.../codex_slash_commands.dart` — auto-compact slash → `_setCodexAutoCompactionEnabled`
- [x] 相关 composer / model UI（displayName map）
- [x] 本 EXEC / PLAN / `DELIVERY.md`（文档对齐 READY-for-push）
- [ ] push mine · GHA · stage APK · 回填 commit/run/sha

## 验收

见 PLAN §7 测点 1–9；PASS 标准含：**无** 上述三类 `thread not found`；soft 写不杀 session；B34/B35 回归不回退。

## 交付字段（push/GHA 后填，当前留空）

| 项 | 值 |
|----|-----|
| 功能 commit | _TBD_ |
| HEAD | _TBD_ |
| GHA run | _TBD_ |
| APK sha256 | _TBD_ |
| stage 路径 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
