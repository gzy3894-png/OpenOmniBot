# 当前交付单

> 更新：2026-07-17 · Stage **B30–B33 READY**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**  
> **主线程：方案/调度/验收**（不写业务码）

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）
3. 按 **§3 测点（B30–B33）** 点测；回：`PASS` / `FAIL` + 卡在哪  
   - **优先 B30 顶栏上下文**、**B31 / 与 @ 互斥**、**B32 模型纯 list**、**B33 无三级权限**

**你不需要改代码、管构建。**

---

## 2. 当前包（READY）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-5542b47-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `418267c98ac40a82780c3646cec5e284be8e735dbb7486765be30f90d18af17c` |
| 大小 | ~349 MB（366320662 bytes） |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| 功能 commit | `1162b66`（B30–B33）+ `5542b47`（跨 mixin 字段编译修复） |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29550628790](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29550628790) · **success** |
| 签名 | `stableDebug` + `AWB_DEBUG_*` |
| 真源 | `PLAN-2026-07-17-b30-context-panel-model-perm.md` + `EXEC-2026-07-17-b30-b33.md` |

**本包相对上一 READY（`cb7ce48` / B22–B29）新增：**

| ID | 修复 |
|----|------|
| **B30** | Codex 输入柱顶半透明 **上下文条**；阈值写 conf `omnimind_context_token_threshold`；toast「新开对话后生效」 |
| **B31** | `/` 与 `@` 列表互斥：开 slash 清 skills flag；slash 前缀优先 root 路由 |
| **B32** | 模型下拉 **纯 model/list**；禁止 merge 注入 list 外 id；composer 菜单不 inject current |
| **B33** | 去掉 composer 三级权限按钮；`/` 管 goal / fast / **自动压缩**（`/auto-compact`→`features.auto_compaction`）；fast 默认关；权限固定 defaultMode 载荷 |

---

## 3. 本包测点（B30–B33）

| # | 操作 | PASS |
|---|------|------|
| 1 | 进 Codex 对话 | 输入区**上方**见半透明「上下文 …」条（可与 Goal bar 叠） |
| 2 | 点上下文条调阈值并保存 | toast 含「新开对话后生效」；杀进程重进阈值仍在 |
| 3 | 当前会话是否立刻用新阈值 | **可不立刻变**（设计如此）；新开对话生效 |
| 4 | 开 `/` 再开 `@` | 只见技能列表 |
| 5 | 开 `@` 再开 `/` | 只见 slash 根列表（goal/fast/…） |
| 6 | 模型菜单条数 | 与当次 `model/list` 一致；旧 conf 模型不在 list 时不出现在下拉 |
| 7 | 输入区 | **无** 盾牌/三级权限按钮 |
| 8 | `/` 列表 | 有 goal、fast（默认关）、**自动压缩**；切换自动压缩写 conf |
| 9 | 发需审批工具 | 仍可弹审批（默认 on-request + workspaceWrite） |
| 10 | 回归 B26 effort | 按模型 supported efforts，不回滚 max/ultra |

日志：`/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-YYYYMMDD.log`

---

## 4. 非目标 / 残余

- 未 push origin / 上游 omnimind-ai  
- 本机无 Flutter SDK 全量 analyze  
- conf 阈值键为 app 侧 `omnimind_context_token_threshold`（stock Codex 可忽略）  
- typed `/auto-compact` 与 slash 卡共用写 conf；卡路径会刷新 UI 镜像  
- 底栏上下文环仍仅 **normal** 模式（Codex 以顶栏为准）

---

## 5. 状态

- [x] 方案 + Wave0 scout（≥6 并发）  
- [x] B30–B33 六锁并行实现  
- [x] 编译修复 `5542b47`  
- [x] GHA success + APK staged  
- [ ] 真机回归（等你，**优先 B30 / B31 / B32 / B33**）
