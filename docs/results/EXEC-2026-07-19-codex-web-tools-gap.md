# EXEC · Codex Web/Fetch 工具缺口 P0+P1 · 2026-07-19

> 真源：`PLAN-2026-07-19-codex-web-tools-gap.md`  
> 阶段：**IMPLEMENTED**（待 push / GHA）  
> 范围：**P0 文案 + P1 conf/设置** · **P2 不做** · 默认 **S-Default-A（Cached）**  
> 基线 HEAD：`ef757a0` / tip `def3096`  
> 站规：主线程调度 · push 仅 mine · GHA only · 禁本机 assemble · 无 Key

## 0. 锁定决策

| 项 | 值 |
|----|-----|
| 用户批准 | 2026-07-19「执行吧」 |
| 默认 | S-Default-A：未设置时不写键，Codex 上游默认 Cached |
| P2 MCP 桥 | **本波不做** |
| 授权模式 | **不纳入**（另 PLAN） |
| 供应商独立化 | 不改 store；本波叠在同一 branch 之上 |

## 1. 工作线

| 线 | 内容 | 状态 |
|----|------|------|
| N1 | Kotlin：read/write/`buildCodexConfigToml` 支持 `web_search` | **done** |
| N2 | Flutter：`CodexLocalConfig` + `writeLocalConfig` | **done** |
| N3 | 设置页：网络搜索三段 + P0 说明 | **done** |
| N4 | 单测 Kotlin + Dart | **done**（本机未跑；等 GHA） |
| N5 | EXEC/relay + push mine + GHA + stage | 进行中 |

## 2. 行为规格

### conf

- top-level `web_search = "cached" | "live" | "disabled"`（可选 `"indexed"` 规范化到 live 或保留）
- 写入：调用方提供非空 mode 时强制写；`null` 时保留 existing，两者皆无则 **省略键**（S-Default-A）
- `web_search` 列入 managed top-level，避免 preserve 双写
- soft write：改 mode **不** kill session（同 auto_compaction）

### UI

- 设置页「网络搜索」：关闭 / 缓存(cached) / 实时(live)
- 说明：无内置 `fetch`；hosted 依赖后端；第三方可能无效，可用 shell curl
- 非 OpenAI base_url 时弱提示「hosted 搜索可能无效」

### 读回

- conf 有键 → 回传
- 无键 → `webSearchMode: null`，UI 显示为「缓存（默认）」选中

## 3. 实时账本

| 字段 | 值 |
|------|-----|
| 源码 HEAD | `525fb0d` feat(codex): expose web_search mode… |
| 远端 | mine `secondary/s1-b38-hardening`（def3096..525fb0d） |
| GHA Baseline | run `29687511510` in_progress |
| GHA Sync CNB | run `29687511486` in_progress（历史常 failure，非九路） |
| APK | 待 GHA SUCCESS 后 stage |
| 真机 | **未测** · tip ≠ PASS |

## 4. 改动摘要

- **Native**：`normalizeCodexWebSearchMode`；`buildCodexConfigToml(webSearchMode)`；managed key `web_search`；read/write/migrate resolve requested?:existing；soft restart 含 web_search  
- **Flutter**：`CodexLocalConfig.webSearchMode` / `effectiveWebSearchMode`；`writeLocalConfig` 仅非 null 传参；设置页三段 Chip + P0 说明 + 非 OpenAI base_url 弱提示  
- **测试**：Kotlin 4；Dart fromMap/write omit  

## 5. 下一步

1. 等 Baseline `29687511510` SUCCESS  
2. stage APK → 真机：改设置看 conf.toml `web_search`；第三方不回归  
3. P2 / 授权模式 PLAN 仍不纳入  

---

*claude 主线程 · 2026-07-19*
