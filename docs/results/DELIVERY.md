# 当前交付单

> 更新：2026-07-17 · Stage **B30–B33 READY（真机 FAIL 点 → B34–B36 待修）**  
> **下一波真源：** `docs/results/PLAN-2026-07-17-b34-fast-perm-leak.md`  
> **主线程：方案/调度/验收**（不写业务码）· 子代理 ≥6 并发 · push **仅 mine**

---

## 1. 现在请你做

### 若仍测 5542b47 包（旧 READY）

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`  
2. 已知问题（**不必再当新功能回归主路径**）：  
   - Fast 可能被当成压缩 / 出现压缩失败类提示  
   - **权限审批按钮缺失**（B33 误伤，用户要求恢复）  
   - 使用中发热（待查泄漏）

### 若开新对话修 B34–B36

复制 `PLAN-2026-07-17-b34-fast-perm-leak.md` §10 启动句；修完再装新 APK。

**你不需要改代码、管构建**（修 bug 的对话除外）。

---

## 2. 当前包（B30–B33 READY · 含已知 FAIL）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-5542b47-standard-debug.apk` |
| 状态 | **READY 已装测 · 真机反馈 FAIL → 待 B34–B36** |
| sha256 | `418267c98ac40a82780c3646cec5e284be8e735dbb7486765be30f90d18af17c` |
| 功能 commit | `1162b66` + `5542b47` |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29550628790](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29550628790) · success |
| 下一波清单 | **`PLAN-2026-07-17-b34-fast-perm-leak.md`** |

**本包相对 cb7ce48 已含：** B30 顶栏上下文 · B31 /@ 互斥 · B32 纯 model/list · B33（含 **错误隐藏权限按钮**）

---

## 3. 真机已报问题 → B34–B36

| ID | 现象 | 目标 |
|----|------|------|
| **B34** | Fast 被识别成压缩对话 / 压缩失败类提示 | Fast 只改 serviceTier；不串 compact |
| **B35** | 权限审批按钮不见了（用户未要求删除） | 恢复按钮；稳定 on-request（参考 plan） |
| **B36** | 手机很烫，疑似泄漏 | 扫描监听/写 conf/setState；有证据再修 |

静态要点（详见 PLAN）：

- Fast 卡 handler 本身调 `_setCodexFastEnabled`，**未**直接调 compact  
- `/` 列表 Fast 与「自动压缩」相邻，`toolTypeLabel: 压缩` 易混  
- 权限：`composer` 硬编码 `_shouldShowCodexPermissionSelector => false` + UI props 传 null  

---

## 4. 状态

- [x] B30–B33 实现 + GHA + APK  
- [x] 真机反馈收集  
- [x] **B34–B36 落地清单**（本对话停修，仅文档）  
- [ ] B34–B36 实现 / GHA / 新 APK  
- [ ] 真机复测 PASS  
