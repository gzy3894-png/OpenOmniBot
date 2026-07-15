# 当前交付单

> 更新：2026-07-15 · Stage **12bugs+B13 修复包 BUILDING**  
> **你只做：等装包 → 测 → 交报告**  
> **主线程：方案/调度/验收**（本轮已并发修 B1–B13）

---

## 1. 现在请你做

1. 等本单变为 **READY** 后安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`
2. 若签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装
3. 按 **§3 测点（B1–B13）** 点测；回 `PASS` / `FAIL` + 卡点

---

## 2. 当前包（BUILDING）

| 项 | 值 |
|----|-----|
| 状态 | **BUILDING**（push 后 GHA Baseline Standard Debug） |
| 分支 | `secondary/s1-baseline` · fork only `mine` |
| applicationId | `cn.com.omnimind.bot.debug` |
| 方案 | `PLAN-2026-07-15-user-12bugs-codex-handoff.md` + `PLAN-2026-07-15-12bugs-b13-exec.md` + codex 协议文档 |
| 基线 | 上一 READY `d739f18` GATE-FAIL（用户 12 点） |

**本包相对 d739f18 修复（静态已验）：**

| ID | 修复摘要 |
|----|----------|
| B13 | 空会话 `startThread` ensure 后再 `setThreadGoal` |
| B1 | 开目标模式清裸 `/` + 关 slash；goal 下正文 setGoal |
| B2 | `status=complete` / `goal/updated|cleared` 关 mode+清 bar |
| B6 | 文案「目标模式」；`showWhenEmpty: false` |
| B9 | `thread/settings/update`；去硬默认 gpt-5.5/xhigh 静默 |
| B10 | `DebugFileLog` → Download/OmniBotLogs |
| B5 | 审查预填 `/review `；附言 → custom.instructions |
| B3 | actual 含 `skill_path:`；气泡无 path |
| B11 | 输入栏 `@` 按钮 |
| B4 | overlay 锚点用输入柱 pillar |
| B8 | slash 白名单 7 项 + Scrollbar |
| B7 | 计划模式主区方案卡 + 批准/拒绝 |
| B12 | compact 成败 tip + compacted 通知 |

---

## 3. 本包测点

| # | 操作 | PASS |
|---|------|------|
| 1 | **空会话**开目标模式 → 直接设目标（不先闲聊） | 无「没有线程」；goal 可见（B13+B1） |
| 2 | 开 mode 不手删 `/` 发正文 | 成为 goal（B1） |
| 3 | 模型 complete goal | bar/mode 变化（B2） |
| 4 | @技能 附言 | 气泡无 path；模型侧有 path（B3） |
| 5 | tip+goal | 不互挡（B4） |
| 6 | 点审查 | 预填可附言再发（B5） |
| 7 | 文案 | 「目标模式」「计划模式」（B6/B7） |
| 8 | 计划模式 | 主区方案 + 批准/拒绝（B7） |
| 9 | `/` 列表 | 短、可滚、无 init/resume 死项（B8） |
| 10 | 改 model/effort | UI=真源（B9） |
| 11 | 复现后 Download 日志 | 有 actual/goal（B10） |
| 12 | `@` 按钮 | 可选技能（B11） |
| 13 | compact | tip+有效果（B12） |

---

## 4. 非目标

- push origin / 上游 omnimind-ai  
- 改 applicationId  
- 主线程写业务码（本轮由子代理实现）

---

## 5. 状态

- [x] 方案 + 8 模块 scout  
- [x] B1–B13 实现（静态 grep 命中）  
- [ ] GHA success + APK staged  
- [ ] 真机回归  
