# 当前交付单

> 更新：2026-07-15 · Stage **S1 基线**  
> 你的动作：装包 → 测 → 交报告（或只回 PASS/FAIL）

---

## 1. 现在要你做的事

| 优先级 | 动作 | 交付物 |
|--------|------|--------|
| P0 | 等主线程给出 **APK 路径 + sha256**（本单 §2 填齐后） | 安装成功 |
| P0 | 按 [`../smoke-codex.md`](../smoke-codex.md) 测 | 复制 [`_TEMPLATE-smoke-report.md`](./_TEMPLATE-smoke-report.md) → `reports/2026-07-15-s1-smoke.md` |
| P1 | 若 Codex 已能调 shell：用 [`_TEMPLATE-codex-inapp-report.md`](./_TEMPLATE-codex-inapp-report.md) 提示词自测 | `reports/2026-07-15-s1-inapp-codex.md` |

**你不需要**：改代码、管 Gradle、决定砍哪个模块。

---

## 2. 基线包（S1）

| 项 | 状态 / 值 |
|----|-----------|
| 目标变体 | `developStandardDebug` · target `lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot`（debug 可能 `.debug`） |
| 上游 tip | `b157e16` (0.5.6.4) |
| 构建来源 | fork `gzy3894-png/OpenOmniBot` · GHA（进行中则下方为 pending） |
| APK 本地路径 | _pending — 构建完成后写入 `/storage/emulated/0/Download/…`_ |
| sha256 | _pending_ |
| GHA run | _pending_ |
| 分支 | `secondary/s1-baseline`（计划） |

### 安装注意
- 若已装商店/旧 OmniBot，签名不同需卸载或并列 debug id  
- **不要**用微信目录里 ~20KB 的 Xposed 小包当宿主

---

## 3. 通过标准（S1 GATE）

- 冒烟 1–3 PASS（启动、Codex 入口、connect 不崩）  
- 步骤 5：PASS-A 或 PASS-B 可接受；**崩溃 = FAIL**  
- 有 in-app 报告更佳，非必须

**GATE-PASS** → 主线程开 **S2.1**（无障碍不强制，单小 PR）  
**GATE-FAIL** → 只修/回滚，不进入 S2

---

## 4. 主线程并行在做什么

1. 文档与路线已落盘（module-map、slim-roadmap）  
2. 推 fork 跑 standard 构建出包  
3. 填齐本单 §2 后通知你  

---

## 5. 变更日志

| 时间 | 事件 |
|------|------|
| 2026-07-15 | 交付区建立；S1 包 pending CI |
