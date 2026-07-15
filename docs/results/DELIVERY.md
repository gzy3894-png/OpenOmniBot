# 当前交付单

> 更新：2026-07-15 · Stage **goal / skill / review / layout 包 READY**  
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
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-d739f18-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `7b7016df0bdf90718550b554798422dba00ceffea0a09eb36072ea6bd40f9886` |
| 大小 | ~349 MB（366162422 bytes） |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| versionName | `0.5.6.4`（versionCode 1） |
| commit | 产品 `d739f18` · `fix(codex): goal mode sync, review/skill prompts, layout inset, compact chips` |
| CI/ship tip | `596ae4f` · `ci(baseline): raise Gradle heap to 6g for D8 mergeExtDex`（同分支 HEAD；APK 按此 SHA 构建） |
| 基线 | 基于 system tips UX `31c4f35` / docs `ee65c7c`；方案 `PLAN-2026-07-15-goal-skill-review-layout` |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` |
| GHA | [Baseline Standard Debug #29418496475](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29418496475) · **success**（含 CI heap 修复） |
| 前次失败 | [run 29417034628](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29417034628) attempt1/2 · D8 `Java heap space` @ `mergeExtDexDevelopStandardDebug`（产品 `d739f18`/`e0ba90a`） |
| 签名策略 | `stableDebug` + secrets `AWB_DEBUG_*`（与 AWB 内测 jks 同源） |
| 期望证书 SHA256 | `6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6` |

**本包相对上一 READY（`31c4f35`）新增（方案 G1/G2/F1/S1/R1/L1）：**

- **G1** 线程 goal 空/清/完成后：刷新 `_codexActiveGoalText` 并在「本地曾有 goal」时 **关 goal mode**（去掉「目标:」前缀）；mode 关隐藏 Goal bar  
- **G2** transcript bottom inset 优先整柱实测（含 Goal bar）；回退 composer + bar 占用；mode 关 bar 高度 0  
- **F1** Fast 开/关 tip：速度与计费分句通顺文案（中英）  
- **S1** `/skill` 与 `@技能 附言` 发送链保留 skill 名 + 附言  
- **R1** bare `/review` → `startReview`；`/review <prompt>` → model turn 带全文  
- **L1** 助手 markdown 行内 code 收敛为紧凑样式，减轻灰 chip 拆坏「状态:」等中文行  
- **CI** Baseline workflow `GRADLE_OPTS=-Xmx6g`，缓解 D8 mergeExtDex OOM  

---

## 3. 本包测点（对齐方案 §4 验收 1–7）

| # | 操作 | PASS |
|---|------|------|
| 1 | 模型完成/清除 goal | 常显目标消失或「无目标」；**目标模式开关关闭**；无「目标:」前缀 |
| 2 | 开目标模式打字 + 键盘 | 助手长回复不被 bar/输入框挡住，可滚到末行 |
| 3 | Fast 开/关 | 文案通顺，速度与计费分句，无歧义 |
| 4 | 发 `@某技能 附言内容` | 气泡能看出技能+附言；模型回复体现附言（未吞） |
| 5 | `/review 审查某路径` 或预填后发送 | 附言到达审查/模型 |
| 6 | 含 complete / 状态 / workspace 的回复 | 排版不乱，「状态」不飞到行尾乱序 |
| 7 | 正文/用户气泡 | 正常聊天气泡字号与结构不被误伤 |

回归（不扩 scope，有空可点）：

| # | 操作 | PASS |
|---|------|------|
| R1 | bare 审查面板 | 仍 one-tap 启动 review（无附言） |
| R2 | 系统 tip 样式 | 小字号 + 上下分割线（`31c4f35`） |
| R3 | ＋ 附件 | 与改前一致 |

残余（已知，非阻塞）：

- `/resume` 偏轻量（绑 threadId，历史 UI 可能不全）  
- `/diff` 只展示聊天里已有 diff 卡片，不主动拉 git  
- 配置页 defaultGoal 写入 toml；不会每次 turn 自动 setThreadGoal  
- 技能依赖 `AgentSkillStoreService` 列表；空库时为空态  
- 目标发送时若 `_isAiResponding`，只保证 RPC+UI，不强制第二 turn  
- GHA 在 2g 堆曾连续 OOM；已用 6g `GRADLE_OPTS` 缓解，极端负载仍可能偶发  
- 本机无 Flutter test 执行；依赖 GHA 编译 + 真机验收  

---

## 4. 通过标准

| 判定 | 含义 | 下一步 |
|------|------|--------|
| **GATE-PASS** | 启动 + Codex + §3 #1–#7 大体可用 | 可继续下一小步 |
| **GATE-FAIL** | 闪退 / goal 清后模式仍开挡字 / 附言全吞 / 审查附言无效 | 只修，不扩 scope |
| **PASS-B** | 壳稳但个别排版或 tip 半实现 | 可接受已知残余 |

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
- [x] 方案 PLAN goal-skill-review-layout 用户确认 + Wave A/B 实现落盘  
- [x] **Wave C M7-Ship：GHA 出包 + stage + DELIVERY READY**（`d739f18` + CI `596ae4f` / run 29418496475）  
- [ ] **主线程等待你验收**（重点 §3 #1–#7）  

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
| 2026-07-15 | `31c4f35` system tip style + session tips；GHA 29407300883 attempt1 D8 OOM fail → attempt2 success；sha256 `542bf2de…` staged Download |
| 2026-07-15 | 产品 `d739f18` goal-skill-review-layout；GHA 29417034628 attempt1/2 D8 OOM fail |
| 2026-07-15 | CI `596ae4f` GRADLE_OPTS 6g；GHA 29418496475 success；sha256 `7b7016df…` staged Download；**READY** |
