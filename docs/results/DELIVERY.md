# 当前交付单

> 更新：2026-07-15 · Stage **Codex modes/skills 包（目标模式 / Fast 提示 / 技能 /@）**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**

---

## 1. 现在请你做

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）  
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）  
3. 可配置 GPT（本包为 **stableDebug 固定签**，后续同签可升级安装）  
4. 按下方 **§3 本包测点** 点测；回：`PASS` / `FAIL` + 卡在哪；或填 [`_TEMPLATE-smoke-report.md`](./_TEMPLATE-smoke-report.md)

**你不需要改代码、管构建、决定砍模块。**

---

## 2. 当前包（SHIPPING → 填 GHA 后 READY）

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-<commit>-standard-debug.apk` |
| 状态 | **SHIPPING**（commit 后由 M7 填 READY + sha256） |
| sha256 | _pending GHA_ |
| 大小 | _pending_ |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| versionName | `0.5.6.4`（versionCode 1） |
| commit | _pending_ · `feat(codex): goal mode bar, session Fast hint, @skills panel mapped to /skill` |
| 基线 | 基于 `c388f54` 的 modes/skills 包 |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` |
| GHA | _pending_ `baseline-standard-debug` |
| 签名策略 | `stableDebug` + secrets `AWB_DEBUG_*`（与 AWB 内测 jks 同源） |
| 期望证书 SHA256 | `6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6` |

**本包相对 `c388f54` 新增：**

- Slash 根列表重构为工作模式：目标模式开关 / Fast 开关 / 技能入口 / 审查等动作  
- 目标模式：Composer「目标:」前缀 + 常显 `CodexGoalModeBar`；发送 → setGoal；关 → clearGoal  
- Fast 开启时会话内插入可读效果提示（`codexFastModeHint`）  
- 技能：面板与 `@` 同源；选中插入 `@技能名`；发送映射 `/skill`  
- model / permission 仍为独立控件，不塞回根 slash  
- ＋ 附件语义不变  

---

## 3. 本包测点（方案 §4）

| # | 操作 | PASS |
|---|------|------|
| 1 | 点 `chat-input-trigger-slash-button` | 新列表含目标开关 / Fast / 技能 / 审查类 |
| 2 | 开目标模式 | 出现「目标:」前缀态 + 常显目标区 |
| 3 | 输入目标并发送 | 底层 setGoal / `/goal`；UI 显示目标正文 |
| 4 | 关目标模式 | `/goal clear`；UI 清除 |
| 5 | 开 Fast | 会话内**可见一句**效果说明；后续 turn fast |
| 6 | `@` 或面板技能 | 列表；选中后 `@技能名`；发送≈`/skill` |
| 7 | review | 点一下可跑 |
| 8 | ＋ 附件 | 行为与改前一致 |
| 9 | model / permission | 仍独立按钮，不在根 slash 塞回 |

残余（已知，非阻塞）：

- `/resume` 偏轻量（绑 threadId，历史 UI 可能不全）  
- `/diff` 只展示聊天里已有 diff 卡片，不主动拉 git  
- 配置页 defaultGoal 写入 toml；不会每次 turn 自动 setThreadGoal  
- 技能依赖 `AgentSkillStoreService` 列表；空库时为空态  

---

## 4. 通过标准

| 判定 | 含义 | 下一步 |
|------|------|--------|
| **GATE-PASS** | 启动 + Codex + 上述关键测点大体可用 | 可继续下一小步 |
| **GATE-FAIL** | 闪退 / 无法进壳 / 目标·Fast·技能明显坏 | 只修，不扩 scope |
| **PASS-B** | 壳稳但部分 slash/skill 半实现 | 可接受已知残余 |

---

## 5. 主线程状态

- [x] 模块地图 + 逐步精简路线  
- [x] 交付区 + 冒烟/仓内 Codex 报告模板  
- [x] 固定 debug 签名 + 重出包 + stage  
- [x] Codex Fast + slash + config + 图片包（`c388f54`）  
- [x] modes/skills 实现静态核对（`reports/m7-static-verify.md`）  
- [ ] modes/skills GHA 出包 + Download stage  
- [ ] 等你的冒烟结果  

---

## 6. 变更日志

| 时间 | 事件 |
|------|------|
| 2026-07-15 | 交付区建立 |
| 2026-07-15 | GHA 29379975277 success；临时签 APK staged（已废弃深测） |
| 2026-07-15 | 接入 `stableDebug` + `AWB_DEBUG_*` |
| 2026-07-15 | `c388f54` Fast/slash/config/image 推 fork；GHA 29386637049 success；sha256 `2278ba38…` staged Download |
| 2026-07-15 | modes/skills 静态 PASS；测点改方案 §4；出包中 |
