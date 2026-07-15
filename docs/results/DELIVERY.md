# 当前交付单

> 更新：2026-07-15 · Stage **12bugs+B13 修复包 READY**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**  
> **主线程：方案/调度/验收**（不写业务码）

---

## 1. 现在请你做

1. 安装：（覆盖旧同名文件）  
2. 若系统提示签名冲突：先卸载  再装（**仅此一次**；之后同证书可覆盖升级）  
3. 按 **§3 测点（B1–B13）** 点测；回： /  + 卡在哪  

**你不需要改代码、管构建。**

---

## 2. 当前包（READY）

| 项 | 值 |
|----|-----|
| 文件 |  |
| 副本 |  |
| 状态 | **READY** |
| sha256 |  |
| 大小 | ~349 MB（366226250 bytes） |
| 变体 |  ·  |
| applicationId |  |
| 功能 commit | （含 12bugs+B13 + plan card import hotfix） |
| CI/ship |  · D8 heap 8g + max-workers=2 |
| 分支 |  |
| fork |  · push **仅 mine** |
| GHA | [Baseline Standard Debug #29438529208](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29438529208) · **success** |
| 签名 |  +  |
| 真源 |  +  +  |

**本包相对上一 READY（）修复：**

| ID | 修复 |
|----|------|
| **B13** | 空会话  ensure 后再 （目标模式无需先闲聊） |
| **B1** | 开目标模式清裸  + 关 slash；goal 下正文 setGoal |
| **B2** |  /  关 mode+清 bar |
| **B6** | 文案「目标模式」；空 bar 不占位 |
| **B9** | ；去硬默认 gpt-5.5/xhigh 静默 |
| **B10** |  →  |
| **B5** | 审查预填 ；附言 →  |
| **B3** | actual 含 ；气泡无 path |
| **B11** | 输入栏  技能按钮 |
| **B4** | overlay 锚点用输入柱 pillar |
| **B8** | slash 白名单 7 项 + Scrollbar |
| **B7** | **计划模式** 主区方案卡 + 批准/拒绝 |
| **B12** | compact 成败 tip +  |

---

## 3. 本包测点（B1–B13）

| # | 操作 | PASS |
|---|------|------|
| 1 | **空会话**开目标模式 → 直接设目标（不先闲聊） | 无「没有线程」；goal 可见（**B13+B1**） |
| 2 | 开 mode 不手删  发正文 | 成为 goal（B1） |
| 3 | 模型 complete goal | bar/mode 变化（B2） |
| 4 | @技能 附言 | 气泡无 path；模型侧有 path（B3） |
| 5 | tip+goal | 不互挡（B4） |
| 6 | 点审查 | 预填可附言再发（B5） |
| 7 | 文案 | 「目标模式」「计划模式」（B6/B7） |
| 8 | 计划模式 | 主区方案 + 批准/拒绝（B7） |
| 9 |  列表 | 短、可滚、无 init/resume 死项（B8） |
| 10 | 改 model/effort | UI=真源（B9） |
| 11 | 复现后 Download 日志 | 有 actual/goal（B10） |
| 12 |  按钮 | 可选技能（B11） |
| 13 | compact | tip+有效果（B12） |

---

## 4. 非目标 / 残余

- 未 push origin / 上游 omnimind-ai  
- 本机无 Flutter SDK：单元测试未在 CI 外执行  
- B3 为 text 注入 （bridge 尚未 structured ）  
- B7 MVP：无「清空上下文再实施」完整三选一  
- B9 冷启动依赖 config/list；远程 list 失败时的降级 tip 仍可加强  

---

## 5. 状态

- [x] 方案 + 8 模块 scout  
- [x] B1–B13 实现  
- [x] GHA success + APK staged  
- [ ] 真机回归（等你）  
