# PLAN · Codex 供应商独立化 · 2026-07-19

> 阶段：`PLANNED`（待用户批准后执行）  
> 演示对齐：`/storage/emulated/0/Download/codex-supplier-demo-v2.html`（用户确认「对味」）  
> 基线 APK 参考：`451b1be` · sha `e20040f7…`（本刀不复用旧包背书）  
> 仓库：`/root/workspace/omnibot-product` · 分支惯例 `secondary/s1-b38-hardening` / 整合 `codex/b38-integration`  
> 站规：主线程只方案/调度/验收 · push **仅 mine** · **GHA only** 出包 · 禁本机 Flutter/Gradle assemble  
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

---

## 0. 一句话目标

把 Codex 模式的供应商管理从 Agent 的 `ModelProviderConfigService` + `/home/model_provider_setting` **连根拔出**，建成 **Codex 私有库 + 私有管理页**；用户只填 **API Base + API Key**（备注可选），拉取模型后 **勾选启用（默认全选）且可搜索**；运行时固定内部 `omnimind` + **`wire_api = "responses"`（无 UI 选择、不认 chat_completions）**；每个供应商独享已启用模型列表与思考等级（默认四档）。

---

## 1. 用户冻结约束（做偏 = 失败）

| # | 约束 | 说明 |
|---|------|------|
| C1 | **只认 Responses** | 系统写死 `wire_api = "responses"`。UI **禁止**出现 chat_completions / 协议下拉。 |
| C2 | **用户只填 API + Key** | 表单字段：API Base URL、API Key；备注名可选且仅展示。无协议、无 Agent 共用开关。 |
| C3 | **模型勾选 · 默认全选** | `GET {base}/models` 成功后写入本供应商库，**全部默认 enabled**；用户可取消不需要的。 |
| C4 | **列表可搜索** | 远端可能数百模型；搜索过滤 + 「全选/清空/反选可见集」。 |
| C5 | **与 Agent 不互通** | 物理隔离存储；管理入口 **禁止** push `/home/model_provider_setting`。可 copy 交互样式，不可共享指针。 |
| C6 | **内部 profile 固定** | 始终 `model_provider = "omnimind"` / `[model_providers.omnimind]`；备注名永不进 TOML 表名。 |
| C7 | **每供应商独享模型 + 思考** | 已启用模型集、当前模型、当前 effort 按供应商隔离；默认思考四档 `low/medium/high/xhigh`。 |

### 明确非目标

- 不改 Agent 供应商页业务逻辑（除互不影响的路由隔离）。
- 不引入 chat_completions 兼容层「让 DeepSeek 也能用」——用户裁定 Codex **只认 resp**；不支持 Responses 的供应商应明确失败提示，而不是偷偷改 wire。
- 不为每个用户供应商创建多个 `model_providers.xxx`。
- 不本机编译测试；不用 tip 代替设备验收。
- 日志/文档/记忆不写 API Key。

---

## 2. 现状根因（451b1be + 2026-07-19 日志）

| 现象 | 根因 |
|------|------|
| 「管理供应商」进 Agent 页 | `codex_setting_page._manageProviders` → `GoRouterManager.pushForResult('/home/model_provider_setting')` |
| 与 Agent 互通 | 真源 `ModelProviderConfigService.listProfiles` / 模型缓存 / manual ids |
| DeepSeek `FormatException` → `provider_library_cache count=1` | HTTP `/models` 解析过严 + 失败回落 **Agent** 缓存；再叠加写死 responses 与第三方能力错位 |
| 模型/思考串味 | 无 Codex 私有 per-supplier catalog；effort 元数据依赖 app-server |

> 注：用户最终裁定 **不开放 chat_completions**。第三方若只提供 completions，应在连通/拉模型阶段失败并提示「Codex 仅支持 Responses API」，而不是提供协议切换。

---

## 3. 目标数据模型

### 3.1 `CodexSupplierRecord`（Codex 独立库）

```text
id                 稳定 UUID（主键，非备注名）
memoName           可选展示名
baseUrl            API Base（normalize：去尾 /，保留 /v1）
apiKey             密钥（安全存储，日志不打印）
models[]           见下
activeModelId      必须 ∈ enabled models
activeEffort       low|medium|high|xhigh（可扩展但不默认塞 max/ultra）
updatedAt
```

### 3.2 `CodexSupplierModelEntry`

```text
id                 模型 id（= slug）
enabled            bool · 拉取时默认 true
displayName        可选，默认 = id
defaultEffort      默认 medium
supportedEfforts   默认 [low, medium, high, xhigh]
```

对齐官方 `model_catalog` 语义（应用层）：

```json
{
  "slug": "<id>",
  "display_name": "<id>",
  "default_reasoning_level": "medium",
  "supported_reasoning_levels": [
    {"effort": "low", "description": "..."},
    {"effort": "medium", "description": "..."},
    {"effort": "high", "description": "..."},
    {"effort": "xhigh", "description": "..."}
  ]
}
```

### 3.3 全局 Codex 状态

```text
activeSupplierId
revision           供 UI 监听，替代对 Agent codexProviderStateRevision 的依赖
```

### 3.4 存储

- 新键：`codex_suppliers_v1`（或分键 records + active），**不**读写 Agent profile 表。
- 迁移一次：`codex_provider_state_v1` + 曾绑定的 Agent profile → **复制**为 Codex 记录后打迁移标记；之后 Agent 改删不影响 Codex。
- 密钥：沿用现有安全存储惯例；禁止明文进 docs/memory。

---

## 4. 运行时写盘（Native）

`config/local/write` 生成（字段来自 **当前 Codex 供应商**）：

```toml
model_provider = "omnimind"
model = "<activeModelId>"
model_reasoning_effort = "<activeEffort>"

[model_providers.omnimind]
name = "omnimind"
base_url = "<baseUrl>"
wire_api = "responses"          # 常量，禁止从用户字段改写为 chat_completions
requires_openai_auth = true     # 保持与现网 omnimind 一致，除非另有证据需 false
```

切换事务（保留现有原子/回滚精神，数据源换 Codex 库）：

1. 校验 baseUrl / key / 至少一个 enabled model / activeModel ∈ enabled。  
2. 写 conf + auth（0600）→ 成功后 commit `activeSupplierId` 与 UI 态。  
3. catalog generation 递增，旧请求不得闪回。  
4. 任一步失败整单回滚；UI 显示真失败。

---

## 5. UI / 路由

| 界面 | 行为 |
|------|------|
| Codex 设置 · 供应商区块 | 下拉选供应商；当前模型仅 **enabled**；思考四档；**管理供应商** → 新路由 |
| **新** `CodexSupplierSettingPage` | 列表 / 新增 / 编辑 / 删除；表单仅备注+API+Key；拉 `/models`；搜索+勾选；手填模型 id（默认 enabled） |
| 路由 | 例如 `/home/codex/supplier_setting` |
| 删除 | 对 `/home/model_provider_setting` 的 Codex 入口跳转 |

交互细节（对齐 demo v2）：

- 搜索框过滤 id（大小写不敏感）。
- 工具条：全选可见 / 清空可见 / 反选可见。
- 统计：启用数 / 可见数 / 总数。
- 设置页模型下拉 = enabled only；若清空启用集，禁止「应用切换」并提示。

---

## 6. 模型列表加载

`CodexModelCatalogLoader`（本地 runtime）：

1. 真源 = 当前 Codex 供应商的 **enabled** models（设置菜单 / 聊天模型菜单一致）。  
2. 后台可刷新 `GET {base}/models`：  
   - 成功：合并进该供应商 `models[]`；**新 id 默认 enabled=true**；已有 id 保留用户勾选态。  
   - 失败：保留本库；日志 `httpErrorType` + host；**禁止**回落 Agent `provider_library_cache`。  
3. 解析：以 OpenAI `{data:[{id}]}` 为主；可兼容合理变体，但 **不**因此改 wire_api。  
4. app-server `model/list` 仅可选 enrich effort 元数据，**不得**把外来 model id 灌进当前供应商库。

---

## 7. 影响文件（预计）

| 区域 | 文件 |
|------|------|
| 新 Store | `ui/lib/services/codex_supplier_store.dart`（名可微调） |
| 目录加载 | `ui/lib/services/codex_model_catalog_loader.dart` |
| 服务 | `ui/lib/services/codex_app_server_service.dart`（switch 数据源；去掉对 Agent profile 的运行时依赖） |
| 设置页 | `ui/lib/features/home/pages/codex/codex_setting_page.dart` |
| 选择器 | `ui/lib/features/home/pages/codex/widgets/codex_provider_selector.dart` |
| **新管理页** | `ui/lib/features/home/pages/codex/codex_supplier_setting_page.dart` + 路由注册 |
| 聊天 | `ui/lib/features/home/pages/chat/chat_page_codex.dart`（监听 Codex revision；模型/effort 来源） |
| Native | `app/.../codex/CodexAppServerManager.kt`（wire 常量确认；write 字段来自 Codex 当前供应商） |
| 测试 | store 隔离 / 迁移 / 默认全选 / 搜索可见集 / switch 回滚 / loader 不读 Agent 缓存 |
| 文档 | 本 PLAN · 后续 EXEC · DELIVERY 状态 |

**禁止再作为 Codex 真源：** `ModelProviderConfigService.listProfiles` 运行时路径（迁移复制除外）。

---

## 8. 实施切片（建议 ≥4 并行工作线，主线程调度）

| 线 | 内容 | 完成标准 |
|----|------|----------|
| W1 Store + 迁移 | `CodexSupplierStore`、状态、一次性迁移、revision | 单测：Agent 库变更不碰 Codex；迁移只跑一次 |
| W2 管理页 + 路由 | 独立页、表单仅 API/Key、勾选/搜索/手填、去掉 Agent 跳转 | Widget/路由测试；无 `model_provider_setting` 引用（Codex 入口） |
| W3 Loader + 菜单 | catalog 只读 Codex 库；刷新默认全选新 id；失败不回落 Agent | 单测 FormatException 路径 + 数百条过滤 |
| W4 Switch + Native | 原子切换 omnimind；wire 固定 responses；effort/model 写入 | 单测回滚；Kotlin/协议测试若有则补 |
| W5 聊天接线 | 顶栏模型/effort 跟当前供应商 enabled 集；切供应商恢复选中态 | 现有 generation/latest-wins 不回归 |
| W6 文档 + 门禁 | EXEC 账本、DELIVERY 状态、远端九路、stage APK | 同 HEAD SUCCESS + Download 路径/SHA |

---

## 9. 验证

### 9.1 自动（远端 GHA）

- 相关 Dart 单测 + 现有 baseline-standard-debug 九路。  
- 本机不跑 assemble。

### 9.2 真机矩阵（同 staged APK）

| ID | 用例 | PASS 标准 |
|----|------|-----------|
| S1 | 管理入口 | 只进 Codex 供应商页，不进 Agent |
| S2 | 隔离 | 改 Agent 供应商不影响 Codex；反之亦然 |
| S3 | 只填 API/Key | 无协议选择；conf 中 `wire_api = "responses"` |
| S4 | 默认全选 | 拉取 N 个模型后 enabled=N，可取消部分 |
| S5 | 搜索 | 灌/拉 ≥100 模型时搜索与「可见集全选」正确 |
| S6 | 切换 | 供应商 A/B 模型与 effort 不串；失败可回滚 |
| S7 | 运行 | Responses 可用的供应商可完整 turn；日志无 Key，含 host/source/supplierId |
| S8 | 非 Responses 源 | 若 `/models` 或 turn 失败，明示错误，不静默假成功、不改 wire |

---

## 10. 风险与假设

| 风险 | 处理 |
|------|------|
| 用户曾用 DeepSeek chat 期望 Codex 也能聊 | 产品约束为 **仅 Responses**；UI/错误文案写清，不提供 comp 开关 |
| 数百模型 UI 卡顿 | 搜索过滤渲染；必要时后续再虚拟列表（本刀先过滤足够） |
| 迁移把 Agent 密钥复制进 Codex 库 | 一次性复制必要字段；不双写长期同步 |
| 旧 `codex_provider_state_v1` 残留 | 迁移后读路径只认新库 |

---

## 11. 交付物

1. 本 PLAN（已落盘）。  
2. 代码按 W1–W5 合并至整合分支 → push **mine**。  
3. GHA SUCCESS → stage：  
   - stable：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`  
   - immutable：`…-standard-debug-<commit>-<sha8>.apk`  
4. EXEC 回填 run id / artifact / SHA / 设备矩阵。  
5. 演示页 v2 保持为产品对照，不随 APK 打包（可选后续进 docs）。

---

## 12. 演示与技能附件

| 附件 | 路径 |
|------|------|
| 交互演示 v2（用户确认对味） | `/storage/emulated/0/Download/codex-supplier-demo-v2.html` |
| 演示备份 | `/root/workspace/deliveries/codex-supplier-demo-v2.html` |
| Claude 工作流技能（从 Codex copy） | `/root/.claude/skills/workflow/` |
| 技能 ASM 私有镜像 | `/root/agent-shared/skills/private-claude/workflow/` |

---

## 13. 批准门

请确认是否按本清单执行（W1–W6）。批准后进入实现调度；批准前 **不改业务代码**。

确认后请回复例如：`按此计划执行` 或指出要改的边界（仍保持 C1–C7）。
