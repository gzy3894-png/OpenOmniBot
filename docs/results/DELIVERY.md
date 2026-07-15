# 当前交付单

> 更新：2026-07-15 · Stage **系统提示样式 + 会话 tip 覆盖 包 READY**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**  
> **主线程等待验收**

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）  
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）  
3. 可配置 GPT（本包为 **stableDebug 固定签**，后续同签可升级安装）  
4. 按下方 **§3 本包测点** 点测；回：`PASS` / `FAIL` + 卡在哪；或填 [`_TEMPLATE-smoke-report.md`](./_TEMPLATE-smoke-report.md)

**你不需要改代码、管构建、决定砍模块。**

---

## 2. 当前包（READY）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-31c4f35-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `542bf2dea54771ef16c52e36130afe6fd4e629efb3f51b6ba0359496ca7c48ff` |
| 大小 | ~349 MB（366151386 bytes） |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| versionName | `0.5.6.4`（versionCode 1） |
| commit | `31c4f35` · `feat(codex): system tip style + session tips for model/effort/review/skills` |
| 基线 | 基于 goal/Fast 修复 `6b09bf2` / docs `1470e56` 的 system tips UX 包 |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` |
| GHA | [Baseline Standard Debug #29407300883](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29407300883) · success（attempt 2；attempt 1 为 D8 OOM 瞬时失败） |
| 签名策略 | `stableDebug` + secrets `AWB_DEBUG_*`（与 AWB 内测 jks 同源） |
| 期望证书 SHA256 | `6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6` |

**本包相对上一 READY（`6b09bf2`）新增：**

- 本地系统提示视觉：`MessageBubble` 识别 `content.localSystemTip` / `kind=local_system_tip`（兼容 id `codex-fast-tip` / `codex-system-tip`）  
  - **更小字号**（约正文 `×0.86`）  
  - **上下细分割线**  
  - secondary 色、左对齐；非用户气泡 / 非 AI 正文流  
- 会话 tip 覆盖（均为本地 transcript，不作为 model turn）：  
  - Fast 开/关（**短文案**：`1.5× 速度；计费约 1.5–2×` / 关闭恢复标准）  
  - 模型切换、思考等级、审查开始、技能插入、Plan 开/关、权限切换  
- content 写入带 `localSystemTip: true` + `kind: local_system_tip`  

---

## 3. 本包测点（system tips UX）

| # | 操作 | PASS |
|---|------|------|
| 1 | 开 Fast | 短文案 + **小字号** + **上下分割线** |
| 2 | 关 Fast | 短关闭文案 + 同上样式 |
| 3 | 切换模型 | 会话内系统提示（如「已切换模型：…」） |
| 4 | 切换思考等级 | 会话内系统提示 |
| 5 | 点审查 | 系统提示「已开始审查」（或等价） |
| 6 | 插入技能（@/面板） | 系统提示「已插入技能：@…」 |
| 7 | Plan / 权限 | 各有系统提示 |
| 8 | 普通用户/AI 正文 | 字号 **不变**（仅 tip 变小） |

回归（不扩 scope，有空可点）：

| # | 操作 | PASS |
|---|------|------|
| R1 | 目标模式发送 | 用户气泡 `/goal …` 且模型有回复（`6b09bf2`） |
| R2 | `@` 技能发送 | 约等于 `/skill` |
| R3 | ＋ 附件 | 与改前一致 |

残余（已知，非阻塞）：

- `/resume` 偏轻量（绑 threadId，历史 UI 可能不全）  
- `/diff` 只展示聊天里已有 diff 卡片，不主动拉 git  
- 配置页 defaultGoal 写入 toml；不会每次 turn 自动 setThreadGoal  
- 技能依赖 `AgentSkillStoreService` 列表；空库时为空态  
- 目标发送时若 `_isAiResponding`，只保证 RPC+UI，不强制第二 turn  
- GHA attempt 1 曾 D8 `Java heap space`（`mergeExtDex`）；attempt 2 成功；偶发 CI OOM 可能再出现  

---

## 4. 通过标准

| 判定 | 含义 | 下一步 |
|------|------|--------|
| **GATE-PASS** | 启动 + Codex + tip 样式/覆盖大体可用 | 可继续下一小步 |
| **GATE-FAIL** | 闪退 / tip 样式全无 / 关键开关无 tip | 只修，不扩 scope |
| **PASS-B** | 壳稳但个别 tip 文案或覆盖半实现 | 可接受已知残余 |

---

## 5. 主线程状态

- [x] 模块地图 + 逐步精简路线  
- [x] 交付区 + 冒烟/仓内 Codex 报告模板  
- [x] 固定 debug 签名 + 重出包 + stage  
- [x] Codex Fast + slash + config + 图片包（`c388f54`）  
- [x] modes/skills 实现静态核对（`reports/m7-static-verify.md`）  
- [x] modes/skills GHA 出包 + Download stage（`4a285f7` / run 29394732847）  
- [x] goal 可见 turn + Fast 开/关提示修复出包（`6b09bf2` / run 29400076462）  
- [x] system tips UX 出包（`31c4f35` / run 29407300883 attempt 2）  
- [ ] **主线程等待你验收**（重点 tip 字号/分割线 + 覆盖 #1–#7）  

---

## 6. 变更日志

| 时间 | 事件 |
|------|------|
| 2026-07-15 | 交付区建立 |
| 2026-07-15 | GHA 29379975277 success；临时签 APK staged（已废弃深测） |
| 2026-07-15 | 接入 `stableDebug` + `AWB_DEBUG_*` |
| 2026-07-15 | `c388f54` Fast/slash/config/image 推 fork；GHA 29386637049 success；sha256 `2278ba38…` staged Download |
| 2026-07-15 | modes/skills `0871898`；首轮 GHA 29394428147 fail（UI mixin 调私有 clearGoal） |
| 2026-07-15 | fix `4a285f7`；GHA 29394732847 success；sha256 `e82684ad…` staged Download |
| 2026-07-15 | fix `6b09bf2` model-visible `/goal` turn + Fast on/off priority-lane tips；GHA 29400076462 success；sha256 `14bbb431…` staged Download |
| 2026-07-15 | `31c4f35` system tip style + session tips；GHA 29407300883 attempt1 D8 OOM fail → attempt2 success；sha256 `542bf2de…` staged Download；主线程等待 tip UX 验收 |
