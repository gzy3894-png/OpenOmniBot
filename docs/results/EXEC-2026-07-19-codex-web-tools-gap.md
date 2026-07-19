# EXEC · Codex Web/Fetch 工具缺口 P0+P1 · 2026-07-19

> 真源：`PLAN-2026-07-19-codex-web-tools-gap.md`  
> 阶段：**`APK_STAGED`**（九路 SUCCESS · 包已 stage · **真机未跑** · tip ≠ PASS · ≠ READY）  
> 范围：**P0 文案 + P1 conf/设置** · **P2 不做** · 默认 **S-Default-A（Cached）**  
> 最终 HEAD：`210fc98c185087f301bd21b8211c429f2826495f`  
> 功能提交：`525fb0d` · 测修：`210fc98`  
> 站规：主线程调度 · push 仅 mine · GHA only · 禁本机 assemble · 无 Key  
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_* → READY`

## 0. 锁定决策

| 项 | 值 |
|----|-----|
| 用户批准 | 2026-07-19「执行吧」 |
| 默认 | S-Default-A：未设置时不写键，Codex 上游默认 Cached |
| P2 MCP 桥 | **本波不做** |
| 授权模式 | **不纳入**（另 PLAN） |
| 供应商独立化 | 不改 store；叠在 `secondary/s1-b38-hardening` |

## 1. 工作线

| 线 | 内容 | 状态 |
|----|------|------|
| N1 | Kotlin：read/write/`buildCodexConfigToml` 支持 `web_search` | ✅ |
| N2 | Flutter：`CodexLocalConfig` + `writeLocalConfig` | ✅ |
| N3 | 设置页：网络搜索三段 + P0 说明 | ✅ |
| N4 | 单测 Kotlin + Dart | ✅（GHA 绿；首轮测修方法名 `config/local/write`） |
| N5 | EXEC + push mine + GHA + stage | ✅ APK_STAGED |

## 2. 行为规格（实现对照）

### conf

- top-level `web_search = "cached" | "live" | "disabled"`（`indexed` 透传）
- 写入：`requested ?: existing`；两者皆无则 **省略键**（S-Default-A）
- `web_search` ∈ `CODEX_MANAGED_TOP_LEVEL_KEYS`
- soft write：改 mode **不** kill session（同 auto_compaction；进程是否热加载 conf 真机未验）

### UI

- 设置页「网络搜索」：关闭 / 缓存(cached) / 实时(live)
- P0 说明：无内置 fetch；hosted 依赖后端；第三方常无效
- 非 `api.openai.com` base_url 弱提示

### 读回

- conf 有键 → `webSearchMode`
- 无键 → null，UI `effectiveWebSearchMode == cached`

## 3. 实时账本

| 字段 | 值 |
|------|-----|
| 源码 HEAD | `210fc98c185087f301bd21b8211c429f2826495f` |
| 远端 | mine `secondary/s1-b38-hardening` |
| 九路 GHA | **SUCCESS** run [`29687603822`](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29687603822) on `210fc98` |
| 九路明细 | Source policy / Flutter analyze / Flutter 0–3 / Android unit / Android lint / Android apk / Nine-way gate → 全 success |
| APK artifact | `omnibot-standard-debug-apk` · id **`8442673167`** |
| APK SHA-256 | `0dec743b927eb37e8bb0209345212e78a2ee4aeeaf0e9b6e808616d741979edc` |
| CERT SHA-256 | `6d79d352e68fc7e1956fe14c41b6affad2a1403eb22af9e76b4e213fa10244c6`（BUILD-MANIFEST） |
| stage stable | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| stage immutable | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-210fc98-0dec743b.apk` |
| Sync CNB | failure（历史常态，不挡九路） |
| 真机 | **未测** |

## 4. 静态审查（主线程）

### 通过

- 链路闭合：settings → signature/save → `writeLocalConfig` omit-null → native resolve → TOML `web_search` → payload 回读
- managed key 防双写；migrate 不强制 web_search
- soft identity 不含 web_search（不因改搜索杀 session）
- 无密钥进 diff

### 已修

- Dart 单测误 expect `writeLocalConfig` → 应为 `config/local/write`（`210fc98`）

### 残余风险（真机前）

1. soft write 后 Codex 进程是否立即按新 `web_search` 出 hosted tool — **未验**
2. `indexed` 无独立 Chip，UI 会显示成缓存标签
3. 无设置页 widget 测试
4. 第三方供应商 hosted 仍常无效（P0 文案已声明；P2 未做）

## 5. 下一步（设备）

1. 安装 immutable/stable APK  
2. Codex 设置 → 改「网络搜索」→ 查 conf.toml 是否出现 `web_search = "..."`  
3. null 默认不写键；点「缓存」应显式写入 `cached`  
4. 第三方体感：不指望 hosted 突然可用；确认不回归  
5. **未 DEVICE_PASS 前禁止 READY**

---

*claude 主线程 · 2026-07-19 · APK_STAGED · 真机未跑*
