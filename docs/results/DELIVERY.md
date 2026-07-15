# 当前交付单

> 更新：2026-07-15 · Stage **S1 基线（固定签名重出包中）**  
> **你只做：装包 → 测 → 交报告（或只回 PASS/FAIL）**

---

## 1. 现在请你做

**先别深配 GPT。** 上一包（sha `34d08d8e…`）是 GHA 临时 debug 签名，**不能**保证后续升级安装；配好账号后若换签名会被迫重装丢数据。

等本单 **§2 固定签名包** 就绪后：

1. 安装：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`（覆盖旧同名文件）  
2. 若系统提示签名冲突：先卸载 `cn.com.omnimind.bot.debug` 再装（**仅此一次**；之后同证书可覆盖升级）  
3. 按 [`../smoke-codex.md`](../smoke-codex.md) 点测  
4. 回：`PASS` / `FAIL` + 卡在第几步；或填 [`_TEMPLATE-smoke-report.md`](./_TEMPLATE-smoke-report.md)

**你不需要改代码、管构建、决定砍模块。**

---

## 2. 基线包（S1）— 固定签名重出中

| 项 | 值 |
|----|-----|
| 文件 | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| 状态 | **BUILDING** — 接入 AWB 固定 debug 证书后重打 |
| 旧包（勿深配） | sha256 `34d08d8e12a529661cefe38beb1d46e48f4611450b06abf83065592b20a30da2` · 临时 GHA debug 签 |
| 变体 | `developStandardDebug` · `-Ptarget=lib/main_standard.dart` |
| applicationId | `cn.com.omnimind.bot.debug` |
| 上游 tip | `b157e16` (0.5.6.4) |
| 分支 | `secondary/s1-baseline` |
| fork | `gzy3894-png/OpenOmniBot` |
| 签名策略 | `stableDebug` + secrets `AWB_DEBUG_*`（与 AWB 内测 jks 同源） |
| 期望证书 SHA256 | `6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6` |

就绪后本节会补：新 sha256、GHA run 链接、证书核验结果、**可安全配置 GPT**。

---

## 3. 通过标准（S1 GATE）

| 判定 | 含义 | 下一步 |
|------|------|--------|
| **GATE-PASS** | 启动 + Codex 入口 + connect 不崩；工具 A 或仅文本 B | 开 **S2.1**（无障碍不强制，单小步） |
| **GATE-FAIL** | 闪退 / 无法进壳 / connect 崩 | 只修，不进 S2 |
| **PASS-B** | 壳稳但不调 shell | 可行为降级；**不可**删模块 |

---

## 4. 主线程状态

- [x] 模块地图 + 逐步精简路线  
- [x] 交付区 + 冒烟/仓内 Codex 报告模板  
- [x] 首包 GHA 成功（临时签，已废弃作深测用途）  
- [ ] **固定 debug 签名 + 重出包 + stage**  
- [ ] 等你的冒烟结果  
- [ ] 通过后才 S2.1  

---

## 5. 变更日志

| 时间 | 事件 |
|------|------|
| 2026-07-15 | 交付区建立 |
| 2026-07-15 | GHA 29379975277 success；临时签 APK staged |
| 2026-07-15 | 接入 `stableDebug` + `AWB_DEBUG_*`；禁止对临时签包深配 GPT |
