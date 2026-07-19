# EXEC · Codex 供应商独立化 · 2026-07-19

> 真源：`PLAN-2026-07-19-codex-supplier-isolation.md`  
> 阶段：**`APK_STAGED`**（九路 SUCCESS · 包已 stage · 真机 S1–S8 未跑）  
> 基线 HEAD 开工：`451b1be7c80bec976a478886c9224baf5bd46943`  
> 最终 HEAD：`ef757a0aa91ffaa1f60458a0530fb58a65638537`  
> 站规：主线程调度/验收 · push 仅 mine · GHA only · 禁本机 assemble  
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

## 0. 实时账本

| 字段 | 当前值 |
|------|--------|
| 用户批准 | 2026-07-19 已确认「执行」 |
| 工作线 | W1–W6 源码 ✅ · `67a9c44` · 语法修 `d9dc42d` · widget 测修 `c540b5f` + `ef757a0` |
| 源码整合 HEAD | `ef757a0aa91ffaa1f60458a0530fb58a65638537` |
| 九路 GHA | **SUCCESS** `#29684114544` on `ef757a0` · [Baseline Standard Debug](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29684114544) |
| APK artifact | `omnibot-standard-debug-apk` · id `8441631420` |
| APK stage | stable + immutable 已落 Download |
| 设备矩阵 S1–S8 | （未 · 待真机） |

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

1. 语义与 UI 行为已由 GHA 单测/widget 覆盖；**真机 S1–S8 未验证**。
2. `codex_supplier_store` ↔ `codex_app_server_service` 循环 import（Dart 通常可接受）。
3. 迁移会 **一次性复制** 密钥进 Codex 库；之后不与 Agent 双写。
4. 数百模型未虚拟列表（搜索过滤先上）。
5. remote runtime 仍可走 app-server 列表（W6 刻意保留）。

## 3. 约束回执（C1–C7）

- C1 只认 responses · C2 只填 API+Key · C3 默认全选 · C4 可搜索
- C5 与 Agent 隔离 · C6 omnimind 固定 · C7 每供应商模型+effort

## 4. 交付字段

| 字段 | 值 |
|------|-----|
| final HEAD | `ef757a0aa91ffaa1f60458a0530fb58a65638537` |
| GHA run | `#29684114544` SUCCESS · 9/9 |
| APK artifact | `omnibot-standard-debug-apk` · `8441631420` |
| APK sha256 | `cf0d0a5ec75264bc90b50b1b4d36f8730f864ad4073403e6fd2704e6f7ad99ad` |
| cert sha256 | `6d79d352e68fc7e1956fe14c41b6affad2a1403eb22af9e76b4e213fa10244c6` |
| stable path | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| immutable path | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-ef757a0-cf0d0a5e.apk` |

## 5. 远端验证证据

| 门禁 | 结论 |
|------|------|
| Source policy | success |
| Flutter analyze | success |
| Flutter tests 0–3/4 | success |
| Android unit | success |
| Android lint | success |
| Android apk | success |
| Nine-way gate summary | success |

修测过程（历史）：

- `67a9c44` 功能落地 → compile 红（named param 语法）
- `d9dc42d` 语法修 → widget 红
- `c540b5f` ListView 可见性 + key 断言修 → locale/filter 仍红
- `ef757a0` 去掉非法 zh locale pin；select-visible 用 `ap` 过滤 → **九路全绿**

## 6. 设备矩阵 S1–S8（待真机）

| ID | 场景 | 状态 |
|----|------|------|
| S1 | 管理入口只进 Codex 供应商页，不进 Agent | 待测 |
| S2 | 改 Agent 供应商不影响 Codex；反之亦然 | 待测 |
| S3 | 只填 API/Key；无协议选择；conf `wire_api = "responses"` | 待测 |
| S4 | 拉取 N 模型后默认全选，可取消部分 | 待测 |
| S5 | ≥100 模型搜索 + 可见集全选 | 待测 |
| S6 | 供应商 A/B 模型与 effort 不串；失败可回滚 | 待测 |
| S7 | Responses 供应商完整 turn；日志无 Key | 待测 |
| S8 | 非 Responses 源失败明示，不静默、不改 wire | 待测 |

## 7. 下一步

1. 真机安装 immutable / stable 包（同一 sha256）。
2. 按 S1–S8 验收；只在有证据时写 `DEVICE_PARTIAL` / `DEVICE_PASS` / `READY`。
3. tip 单独 ≠ PASS。

---

*claude 主线程 · 2026-07-19 · APK_STAGED*
