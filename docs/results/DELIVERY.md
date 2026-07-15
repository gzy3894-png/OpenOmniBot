# 当前交付单

> 更新：2026-07-15 · Stage **Codex 产品包 READY（Fast + slash + config + 图片）**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**

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
| 副本 | `/storage/emulated/0/Download/OpenOmniBot-s1-c388f54-standard-debug.apk` |
| 状态 | **READY** |
| sha256 | `2278ba38b4e4489bd19e6b3ff7d8a0b011c2349f84ac28e4382766bcb2b46af7` |
| 大小 | ~350 MB |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| versionName | `0.5.6.4`（versionCode 1） |
| commit | `c388f54` · `feat(codex): Fast serviceTier, expanded slash, goal config, image staging` |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` |
| GHA | [Baseline Standard Debug #29386637049](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29386637049) · success |
| 签名策略 | `stableDebug` + secrets `AWB_DEBUG_*`（与 AWB 内测 jks 同源） |
| 期望证书 SHA256 | `6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6` |

**本包相对 S1 基线新增：**

- Composer **Fast** 开关（备注「降延迟」）→ `serviceTier=fast`
- Codex 设置页：**Fast** + **默认 Goal**
- `/` 根列表：`/review /init /plan /compact /status /diff /stop /new /resume /goal`（**无** model / permission）
- 图片：用户侧预览；模型侧 workspace 路径（不再 `codex-preview path`）
- model·effort 芯片与权限按钮保持独立控件

---

## 3. 本包测点

| # | 测什么 | 期望 |
|---|--------|------|
| 1 | 启动 + 进 Codex | 不崩，可连接 |
| 2 | Composer | 有 **model·effort** 芯片、**Fast**、**权限** 三个独立控件 |
| 3 | Fast 开/关各发一轮 | 开时走 serviceTier=fast；关后行为正常 |
| 4 | Codex 设置 | Fast 开关 + 默认 Goal 能保存 |
| 5 | `/` 列表 | 见 compact/status/diff/stop/new/resume/goal 等；**没有** model/permission 项 |
| 6 | 发图 | 用户侧是图；模型侧是路径，不应再出现 `codex-preview path` |
| 7 | `/stop` / `/status` | 中断可用；status 有可读摘要 |

残余（已知，非阻塞）：

- `/resume` 偏轻量（绑 threadId，历史 UI 可能不全）
- `/diff` 只展示聊天里已有 diff 卡片，不主动拉 git
- 配置页 defaultGoal 写入 toml；不会每次 turn 自动 setThreadGoal

---

## 4. 通过标准

| 判定 | 含义 | 下一步 |
|------|------|--------|
| **GATE-PASS** | 启动 + Codex + 上述关键测点大体可用 | 可继续下一小步精简/功能 |
| **GATE-FAIL** | 闪退 / 无法进壳 / Fast 或 slash 明显坏 | 只修，不扩 scope |
| **PASS-B** | 壳稳但部分 slash 半实现 | 可接受已知残余 |

---

## 5. 主线程状态

- [x] 模块地图 + 逐步精简路线  
- [x] 交付区 + 冒烟/仓内 Codex 报告模板  
- [x] 固定 debug 签名 + 重出包 + stage  
- [x] Codex Fast + slash + config + 图片包（`c388f54`）GHA success + Download stage  
- [ ] 等你的冒烟结果  
- [ ] 通过后才下一阶段  

---

## 6. 变更日志

| 时间 | 事件 |
|------|------|
| 2026-07-15 | 交付区建立 |
| 2026-07-15 | GHA 29379975277 success；临时签 APK staged（已废弃深测） |
| 2026-07-15 | 接入 `stableDebug` + `AWB_DEBUG_*` |
| 2026-07-15 | `c388f54` Fast/slash/config/image 推 fork；GHA 29386637049 success；sha256 `2278ba38…` staged Download |
