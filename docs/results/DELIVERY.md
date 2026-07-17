# 当前交付单

> 更新：2026-07-17 · Stage **B34–B36 READY（待真机复测）**  
> **真源：** `docs/results/PLAN-2026-07-17-b34-fast-perm-leak.md` · EXEC `docs/results/EXEC-2026-07-17-b34-b36.md`  
> **主线程：方案/调度/验收**（不写业务码）· 子代理 ≥6 并发 · push **仅 mine**

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`  
   （副本：`/storage/emulated/0/Download/OpenOmniBot-s1-7896a6c-standard-debug.apk`）
2. 按 §3 测点 1–8 真机复测；优先 B34 Fast≠压缩、B35 权限按钮、B36 Fast 拨开关无 `thread not found`。
3. 模型列表对照：wire id 须为 catalog **slug**（见下方 note），勿只认 display_name。

**你不需要改代码、管构建。** 反馈 PASS/FAIL 即可（FAIL 写现象 + 是否可复现）。

---

## 2. 当前包（B34–B36 READY · 待真机）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-7896a6c-standard-debug.apk` |
| 状态 | **READY · 待真机复测** |
| sha256 | `aa34e473d781302247188bc925425893fe8e1b7a0ce9e3ad219a412437e6d9a8` |
| 大小 | `366335306` bytes（~349 MB） |
| 功能 commit | `d7abe18`（B34–B36）+ `7896a6c`（跨 mixin：`_executeCodexCompactCommand` 声明在 base） |
| HEAD | `7896a6c9342303d964f9908e2571a4471d619afd` |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29565426990](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29565426990) · **SUCCESS** · head `7896a6c` |
| 计划 / EXEC | `PLAN-2026-07-17-b34-fast-perm-leak.md` · `EXEC-2026-07-17-b34-b36.md` |
| B36 报告 | `docs/results/reports/b36-heat-leak-scan-2026-07-17.md` |

**本包相对 5542b47 已含：** B34 Fast≠compact · B35 权限按钮恢复 · B36 soft conf 不杀 session · B32 residual 模型列表 wire id 优先 slug

**本机模型 note（对照测点 7 / B32）：**  
- conf `model` = `gpt-5.6-sol`  
- catalog slug：`claude-fable-5` · `claude-haiku-4-5-20251001` · `claude-opus-4-8` · `gpt-5.6-sol`  
- 列表 wire id **须与 `model/list` slug 一致**，勿用 display_name 当 id

---

## 3. 测点（B34–B36 · PLAN §8）

| # | 操作 | PASS 标准 |
|---|------|-----------|
| 1 | 只拨 Fast 开→关→开 | 仅 Fast tip；**无**压缩 marker / 「无可压缩」toast |
| 2 | 发「测试fast模式」 | 正常 user turn；无压缩 |
| 3 | 点「自动压缩」 | 仅 conf 开关 tip；**不** thread/agent compact |
| 4 | 点 `/compact` | 仅 Codex compact 文案路径 |
| 5 | 看输入区权限按钮 | 可见且可点三级（请求审批 / 自动审 / 全放行） |
| 6 | defaultMode 下触发需批工具 | 稳定弹出请求授权（类 plan） |
| 7 | 回归 B30–B32 + 模型列表 | 顶栏 / `/` `@` 互斥 / 列表 **slug** 与 `model/list` 一致 |
| 8 | 使用 5–10 min；Fast 连拨 5 次 | 发热主观对比；**无** `thread not found`；soft conf 不杀 session |

### 本波修复摘要

| ID | 修复 |
|----|------|
| **B34** | 卡标签去歧义；`/fast` · `/auto-compact` · `/compact` **三路互斥**；Fast **永不** compact RPC；Codex hard-gate 禁止 agent compact |
| **B35** | 权限按钮恢复（composer 门闸 + UI props）；defaultMode = on-request + writableRoots 再断言 |
| **B36** | soft conf（`fast_mode` / `auto_compaction` / `service_tier` / threshold 等）写回 **跳过** session disconnect；静态泄漏扫描见报告 |
| **B32 residual** | model/list wire id **优先 slug**，不用 display_name |

---

## 4. 状态

- [x] B34–B36 实现（`d7abe18`）
- [x] 跨 mixin 编译修（`7896a6c`）
- [x] push mine · GHA #29565426990 SUCCESS
- [x] APK stage → sha256 / size 已填
- [ ] 真机复测 PASS

---

## 5. 未改 / 残余（B36 报告）

- Remote 2s poll、每 event `debugPrint`：**未改**（待真机确认 remote 是否常开）
- 监听 bind/unbind、顶栏 height：无硬泄漏证据，**未改**
- 改 baseUrl / model / apiKey 仍应 reconnect（硬字段）
