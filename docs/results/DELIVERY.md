# 当前交付单

> 更新：2026-07-17 · Stage **B22–B29 READY**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**  
> **主线程：方案/调度/验收**（不写业务码）

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）
3. 按 **§3 测点（B22–B29）** 点测；回：`PASS` / `FAIL` + 卡在哪  
   - **优先 B25 默认权限弹窗**、**B24 目标模式**、**B26 sol 的 max/ultra**

**你不需要改代码、管构建。**

---

## 2. 当前包（READY）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-cb7ce48-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `d7caffbe091705ec39b781dd745b4c80af814155fe44304a187186e776de1aa7` |
| 大小 | ~349 MB（366289442 bytes） |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| 功能 commit | `89f1755`（B22–B29）+ `cb7ce48`（lifecycle abstract 编译修复） |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29545742198](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29545742198) · **success** |
| 签名 | `stableDebug` + `AWB_DEBUG_*` |
| 真源 | `PLAN-2026-07-17-b22-b29.md` + `EXEC-2026-07-17-b22-b29.md` |

**本包相对上一 READY（`4902430` / B14–B21）新增：**

| ID | 修复 |
|----|------|
| **B22** | `@` 再按收起技能列表 |
| **B23** | `#` 再按收起 slash 列表（清裸 `/`） |
| **B24** | 目标模式：`goal:null` 不再误关；OFF 与 X 清目标分离；跨会话 refresh |
| **B25** | 默认权限 `writableRoots` 填 cwd；`thread/start` 用 `sandbox` 模式串 |
| **B26** | 思考等级按 `model/list` 每模型 `supportedReasoningEfforts`（**含 max/ultra 若模型有**）；本地 model→efforts 图 |
| **B27** | 上下文环可点开阈值；Codex 设置 `auto_compaction` 开关 |
| **B28** | 日志落盘确认（见 §3 测点 12） |
| **B29** | turn 完成 / 用户停 / 失败 → 通知栏 |

**B26 纠偏说明：** 不是去掉 max/ultra；sol 有 max+ultra 就显示；其它 5.6 有 max 就显示。

---

## 3. 本包测点（B22–B29）

| # | 操作 | PASS |
|---|------|------|
| 1 | `@` 开技能列表再按 `@` | 列表收起 |
| 2 | `#` 开 slash 再按 `#` | 列表收起 |
| 3 | 空会话开**目标模式** | 保持 ON（不会闪一下关） |
| 4 | 目标模式发一句目标 | 有 setGoal + 模型 turn 回复 |
| 5 | 点 X 清目标 | 目标清；可再开模式 |
| 6 | 权限 **默认** | 需授权动作时出现审批卡；模型能执行（cwd 可写） |
| 7 | 权限 **自动审查** / **完全访问** | 映射正确；full 无卡可跑 |
| 8 | 切 `gpt-5.6-sol` 看思考等级 | **有 max 与 ultra**（若 list 返回） |
| 9 | 切其它 5.6 模型 | 有 **max**（若 list 返回）；无则不硬造 |
| 10 | 普通模式输入区上下文环 | 可见；点开可调阈值 |
| 11 | Codex 设置 | 有「自动压缩 / Auto compaction」开关 |
| 12 | **日志落盘** | 路径：`/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-YYYYMMDD.log`（debug 包）；含 turn_start / permission_set / goal 等 |
| 13 | 模型做完 / 点停 | 通知栏有完成或停止通知（非当前前台同会话可被抑制） |

可选：B14 关 Fast 回归；冷启动 Codex 发 `pwd && ls`。

---

## 4. 日志（B28 直接回答）

| 项 | 值 |
|----|-----|
| **有没有落盘** | **有**（debug 包已写） |
| 主路径 | `/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-YYYYMMDD.log` |
| 设备现状 | 已存在 `omnibot-debug-20260716.log`、`omnibot-debug-20260717.log` |
| 条件 | `kDebugMode` 且未 force-disable |
| 回退 | app external files 下 `OmniBotLogs/` |

---

## 5. 非目标 / 残余

- 未 push origin / 上游 omnimind-ai  
- 本机无 Flutter SDK 全量 analyze  
- B25 真机以审批卡 + 工具执行为准  
- B26 依赖上游 `model/list` 是否带回 supported efforts  
- B29 依赖系统通知权限；同会话前台会抑制  

---

## 6. 状态

- [x] 方案 + Wave0 scout  
- [x] B22–B29 实现  
- [x] 编译修复 `cb7ce48`  
- [x] GHA success + APK staged  
- [ ] 真机回归（等你，**优先 B25 / B24 / B26**）
