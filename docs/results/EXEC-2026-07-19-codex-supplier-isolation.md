# EXEC · Codex 供应商独立化 · 2026-07-19

> 真源：`PLAN-2026-07-19-codex-supplier-isolation.md`  
> 阶段：`IMPLEMENTED`（widget 测修 push 中 · 等九路绿）  
> 基线 HEAD 开工：`451b1be7c80bec976a478886c9224baf5bd46943`  
> 整合 HEAD：见下表（语法修 `d9dc42d` · 测修待 commit）  
> 站规：主线程调度/验收 · push 仅 mine · GHA only · 禁本机 assemble  
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

## 0. 实时账本

| 字段 | 当前值 |
|------|--------|
| 用户批准 | 2026-07-19 已确认「执行」 |
| 工作线 | W1–W6 源码 ✅ · `67a9c44` · 语法修 `d9dc42d` · widget 测修（ListView 可见性 + locale helper） |
| 源码整合 HEAD | 上一绿编译：`d9dc42d` · 下一 push：widget test fix |
| 九路 GHA | `#29683315510` on `d9dc42d`：analyze/unit ✅ · Flutter shard 2/3 FAIL（setting page ×4 + selector ×1）· 测修后重跑 |
| APK stage | （未 · 等九路 SUCCESS） |
| 设备矩阵 S1–S8 | （未） |

## 1. 工作线

| 线 | 内容 | 状态 |
|----|------|------|
| W1 | CodexSupplierStore + 迁移 + revision + 单测 | ✅ |
| W2 | 管理页 + 路由 `/home/codex/supplier_setting` | ✅ |
| W3 | Catalog 只读 Codex 库；失败不回落 Agent | ✅ |
| W4 | `switchLocalSupplier` + 测试；Native wire 已是常量未改 | ✅ |
| W5 | 设置页/选择器改 Codex 库；管理入口断 Agent | ✅ |
| W6 | 聊天 revision + EXEC/relay | ✅ |

报告：`docs/results/reports/impl-w1`…`impl-w6-*.md`

## 2. 静态审查（主线程 2026-07-19）

### 通过

- Codex 设置/选择器/管理页 **无** `model_provider_setting` 运行时跳转（管理 → `/home/codex/supplier_setting`）
- Catalog **无** `provider_library_cache` / `listProfiles` 运行时路径（仅注释提及旧名）
- 聊天监听 `CodexSupplierStore.revision`；gate identity 含 `supplier=` + `supplierRevision=`
- Switch 调用点均为 `switchLocalSupplier` + `CodexSupplierRecord`
- Store 对 `listProfiles` 的引用 **仅限 ensureMigrated 一次性复制**（符合 C5「迁移除外」）

### 已知残留 / 风险

1. **未本机跑 flutter test**（站规）；语义待 GHA。  
2. `codex_supplier_store` ↔ `codex_app_server_service` 循环 import（Dart 通常可接受）。  
3. 迁移会 **一次性复制** 密钥进 Codex 库；之后不与 Agent 双写。  
4. 数百模型未虚拟列表（搜索过滤先上）。  
5. remote runtime 仍可走 app-server 列表（W6 刻意保留）。

## 3. 约束回执（C1–C7）

- C1 只认 responses · C2 只填 API+Key · C3 默认全选 · C4 可搜索  
- C5 与 Agent 隔离 · C6 omnimind 固定 · C7 每供应商模型+effort

## 4. 交付字段（待回填）

| 字段 | 值 |
|------|-----|
| final HEAD | |
| GHA run | |
| APK sha256 | |
| stable path | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| immutable path | |

## 5. 下一步

1. 用户确认 → 主线程 commit + push **mine** `secondary/s1-b38-hardening`  
2. 触发/等待 `baseline-standard-debug` 九路  
3. stage APK → 真机 S1–S8  

---

*claude 主线程 · 2026-07-19*
