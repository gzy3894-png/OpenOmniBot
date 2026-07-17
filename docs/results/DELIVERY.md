# 当前交付单

> 更新：2026-07-17 · Stage **B14–B21 READY**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**  
> **主线程：方案/调度/验收**（不写业务码）

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）
3. 按 **§3 测点（B14–B21）** 点测；回：`PASS` / `FAIL` + 卡在哪  
   - **优先 B14 关 Fast 计费**（费用相关）

**你不需要改代码、管构建。**

---

## 2. 当前包（READY）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-4902430-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `0817dadb1ab2f90a46cfbcef4be3be5be7cad8a7ae2466098c89575108a5af02` |
| 大小 | ~349 MB（366263698 bytes） |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| 功能 commit | `4902430`（B14–B21 + turn 日志；主体 `a2632d2`） |
| CI/ship | `4902430` · D8 heap 8g + max-workers=2 |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` · push **仅 mine** |
| GHA | [Baseline Standard Debug #29542819162](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29542819162) · **success** |
| 签名 | `stableDebug` + `AWB_DEBUG_*` |
| 真源 | `PLAN-2026-07-16-next-fast-perm-slash.md` + `EXEC-2026-07-16-b14-b21.md` |

**本包相对上一 READY（`ee07854` / 12bugs+B13）新增修复：**

| ID | 修复 |
|----|------|
| **B14** | 关 Fast 三写：settings null clear + config `fast_mode=false` + 偏好 off；失败回滚；`logFastSet` |
| **B20** | 权限切换 `updateThreadSettings`；default=on-request+user+workspaceWrite；autoReview→`auto_review`；默认 defaultMode |
| **B19** | effort 白名单；拒 max/ultra；非法不 RPC |
| **B15** | `/` 列表去掉 stop/skills |
| **B18** | 点 slash 收列表 + 保键盘 |
| **B17** | compact tip + snackbar + compact_* 日志 |
| **B16** | `@` 与 `/` 同色（accentPrimary） |
| **B21** | 日志矩阵 API + fast/perm/effort/compact/turn 埋点 |

---

## 3. 本包测点（B14–B21）

| # | 操作 | PASS |
|---|------|------|
| 1 | **关 Fast** 后立刻发 turn | UI 关；日志 `fast_set` settingsRpc=ok；config 含 `fast_mode = false`；`turn_start` serviceTier 非 fast；**后台不再 Fast 计费** |
| 2 | 杀进程重启 | Fast 仍关 |
| 3 | 开 Fast 再关 | 关失败有 error toast（非假关） |
| 4 | 权限 **默认** | `permission_set` 日志；需授权动作出现审批卡可批/拒 |
| 5 | 权限 **自动审查** | reviewer=`auto_review` |
| 6 | 权限 **完全访问** | never + dangerFullAccess |
| 7 | 思考等级 | 无 max/ultra（除非模型支持）；非法拒绝 tip |
| 8 | 输入 `/` | **无** stop、skills |
| 9 | 点 goal/fast/plan | 列表收；**键盘仍在** |
| 10 | `@` 与 `/` | 同色；`@` 仍可选技能 |
| 11 | `/compact` | 开始/成功/失败可感知 + 日志 |
| 12 | `Download/OmniBotLogs/` | 有 fast_set / permission_set / turn_start / effort_set / compact |

可选 S1 冒烟：冷启动 → Codex connect → 发 `pwd && ls` → 看工具卡是否稳定。

---

## 4. 非目标 / 残余

- 未 push origin / 上游 omnimind-ai
- 本机无 Flutter SDK：单测未在 CI 外执行
- MethodChannel→JSON null clear 以真机 `settingsRpc=ok` + 计费为准
- config 写回 merge features；复杂注释可能丢
- 上一包 B1–B13 应保持；回归 FAIL 请点名 ID

---

## 5. 状态

- [x] 方案 + Wave0 scout
- [x] B14–B21 实现
- [x] GHA success + APK staged
- [ ] 真机回归（等你，**优先 B14**）
