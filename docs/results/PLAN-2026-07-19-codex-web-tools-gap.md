# PLAN · Codex Web/Fetch 工具缺口 · 2026-07-19

> 状态：**PLANNED**（研究完成 · 等用户确认「执行」）  
> 关联：截图 path `1784462854732.2887` · 模型自称无 `web`/`fetch`  
> 基线：供应商独立化 APK_STAGED `ef757a0` · 本方案 **不** 改那条线  
> 站规：主线程调度/验收 · push 仅 mine · GHA only · 禁本机 assemble · 无 Key 入文档/记忆

## 0. 问题一句话

模型在第三方 Responses（如 deepseek-v4-flash）上 **看不到可用的 web/fetch 函数工具**，只能 `exec_command`+`curl`。  
根因是 **Codex 工具形态 + 供应商能力**，**不是** OmniBot 剥工具。

## 1. 研究结论（证据）

| 项 | 结论 | 证据 |
|----|------|------|
| `fetch` | **Codex 无此内置工具** | 上游 `core/src/tools` 无 `fetch` handler |
| hosted `web_search` | Codex **默认尝试**塞 `type:"web_search"`（Cached） | `config/mod.rs` `unwrap_or(WebSearchMode::Cached)`；`hosted_spec.rs` |
| 模型可见形态 | hosted 工具 **不是** function 名 `web_search` | `tools/src/tool_spec.rs` `ToolSpec::WebSearch` |
| `web.run` 扩展 | Feature `standalone_web_search` **默认关** / UnderDevelopment | `features/src/lib.rs` |
| OmniBot 剥工具 | **无** | `thread/start`/`turn/start` 不传 tools 白名单；parser 只渲染 |
| conf 关搜索 | **未写** `web_search=disabled` | `buildCodexConfigToml` 不管 web_search；runtime conf 亦无 |
| 第三方体感 | 中转常 **不实现** OpenAI hosted search → 等于不可用 | 产品实测 + 模型 introspection |

### 责任划分

| 责任方 | 范围 |
|--------|------|
| Codex 自身 | 无 `fetch`；hosted search 依赖后端；standalone 默认关 |
| 供应商 | 非 OpenAI Responses 常不执行 `web_search` |
| OmniBot | **未剥离**；展示层已支持事件；**缺** 产品开关与第三方兜底 |

## 2. 目标 / 非目标

### 目标

1. 用户能区分：**本机会画搜索卡** vs **模型实际能搜**。  
2. OpenAI 兼容且支持 hosted search 的供应商：可显式开 `cached`/`live`。  
3. 第三方供应商：有 **不依赖 OpenAI hosted** 的兜底（推荐 MCP / 本机 smart-search 桥）。  
4. 文档与设置文案不再让模型/用户误以为「有 web/fetch 函数」。

### 非目标

- 不伪造上游不存在的 `fetch` 工具名。  
- 不在本波改供应商独立化 HEAD / 真机 S1–S8 矩阵。  
- 不默认全局 `danger-full-access` 或静默开全网。  
- 不把 API Key 写入 conf 示例/日志/记忆。  
- **自动审模式移除 + 默认 untrusted** 是 **并行另一 PLAN**，本文件只交叉引用，不合并实施。

## 3. 方案比较

| 方案 | 做法 | 优点 | 缺点 | 推荐 |
|------|------|------|------|------|
| A. 只改文案/提示 | 系统提示说明用 curl；设置页说明 | 零风险 | 无真工具 | 必做底线 |
| B. conf 暴露 `web_search` 开关 | 设置写 `web_search = "cached"\|"live"\|"disabled"` | 对齐上游；OpenAI 有效 | 第三方仍可能无效 | **P1 推荐** |
| C. OmniBot Search MCP / 桥 | 注册 MCP 工具 `web_search`→`smart-search`/Jina | 第三方可用；可控 | 要适配权限与 UI | **P1/P2 推荐** |
| D. 开 `standalone_web_search` | 上游 `web.run` | 原生 | 实验/依赖 Codex 扩展链路 | 观望 |
| E. 强制模型 function 伪装 hosted | 自己造 function 名再转 curl | 体验统一 | 与上游协议分叉、难维护 | 不推荐 |

**推荐组合：A + B + C（分阶段）**。

## 4. 分阶段实施

### P0 · 认知对齐（小改 · 可当日）

| ID | 内容 | 文件区 |
|----|------|--------|
| P0.1 | 设置/帮助：说明「无 fetch；web_search 为服务端 hosted；第三方请用 shell 或 MCP」 | `codex_setting_page` 文案 / FAQ |
| P0.2 | 开发者 tip（可选）：模型侧 system 备注不写假工具名 | 提示组装处 |
| P0.3 | EXEC 记证据链（本 PLAN §1） | `docs/results/EXEC-…` |

**验收**：文案可见；无 conf/行为回归。

### P1 · 配置面 + 状态可见（中改）

| ID | 内容 | 要点 |
|----|------|------|
| P1.1 | 设置项「网络搜索」：关闭 / 缓存(cached) / 实时(live) | 写 top-level `web_search`；**默认保持 Codex Cached** 或显式 `disabled`（产品二选一，实施前锁） |
| P1.2 | `buildCodexConfigToml` 写入/保留 `web_search` | 与 features 合并策略一致；不冲掉用户其它 top-level |
| P1.3 | 供应商能力徽标（弱） | 非 OpenAI base_url 显示「hosted 搜索可能无效」 |
| P1.4 | 单测：toml 含 `web_search = "live"` / `"disabled"`；features 不丢 | Android unit + 可选 widget |

**验收**：

- 改设置 → conf 可见对应键。  
- 重启 thread 后行为随 conf（OpenAI 源用 mock/日志看 tools 数组更佳）。  
- GHA 九路绿；APK stage。

**默认值建议（待确认）**：

- **S-Default-A**：继续依赖上游默认 Cached（现状），设置仅暴露覆盖。  
- **S-Default-B**：产品默认 `disabled`，避免第三方无效请求；用户手动开。  

推荐实施前用户选一个；未选则用 **S-Default-A**（最小行为变化）。

### P2 · 第三方兜底工具（较大）

| ID | 内容 | 要点 |
|----|------|------|
| P2.1 | 内置或可选 MCP：`web_search` / `web_fetch` | 后端走 `smart-search` 与 Jina/直连策略（与本机 gateway 一致） |
| P2.2 | 权限：只读网络；结果摘要进聊天卡 | 复用现有 tool card / webSearch 渲染路径 |
| P2.3 | 与 hosted 互斥策略 | hosted 已启用且供应商支持时可不注册桥，避免双工具混淆 |
| P2.4 | 设备矩阵 | 第三方模型能调用桥工具；OpenAI 路径不回归 |

**验收**：deepseek 类模型 function 列表出现桥工具并能返回结果；无 Key 泄漏。

### P3 · 观望上游

- `features.standalone_web_search` 稳定后再评估原生 `web.run`。  
- 不在 P1/P2 强依赖。

## 5. 与授权模式 PLAN 的关系

用户另提：去掉「自动审」+ 默认审批更底层（`untrusted`）。  
见会话计划草案；**单独 PLAN/EXEC**，本方案不绑定。  
建议顺序：工具认知(P0) → 授权收紧 → web conf(P1) → MCP 兜底(P2)。

## 6. 风险

| 风险 | 缓解 |
|------|------|
| 开 live 增加外网与费用 | 默认不强制 live；设置明示 |
| MCP 桥被模型滥用扫站 | 限流、域名策略、审批策略挂钩 |
| conf 重写丢用户键 | 沿用 `extractPreservedTopLevelTomlLines` |
| 误以为 hosted 已在第三方可用 | P1.3 徽标 + 文案 |
| 与供应商独立化冲突 | 仅改 conf 构建与设置 UI；不动 supplier store |

## 7. 验证矩阵（实施后）

| ID | 场景 | 期望 |
|----|------|------|
| T1 | 默认 conf 无显式 web_search | 与现状一致（Cached 或选定默认） |
| T2 | 设 disabled | 请求 tools 无 hosted web_search（OpenAI mock） |
| T3 | 设 live + OpenAI 兼容 | 请求含 `type:web_search`；有结果或明确错误 |
| T4 | 第三方 + P2 桥 | 模型可见桥工具；返回摘要 |
| T5 | UI 事件 | 若有 begin/end，聊天卡正常（现有 reducer） |
| T6 | 回归 | 供应商切换、权限三态、九路 GHA |

## 8. 交付物清单

- [x] 本 PLAN  
- [ ] 用户确认「执行」及默认策略（S-Default-A/B）  
- [ ] EXEC + 代码 + GHA + APK_STAGED  
- [ ] 真机 T1–T6 证据  
- [ ] 演示页：`/root/workspace/deliveries/codex-web-tools-gap-demo.html`  
  - 同步：`/storage/emulated/0/Download/codex-web-tools-gap-demo.html`

## 9. 请确认

1. 是否按 **A+B+C** 分阶段（P0→P1→P2）？  
2. P1 默认选 **S-Default-A（Cached/现状）** 还是 **S-Default-B（disabled）**？  
3. P2 是否纳入本波，还是只先做 P0+P1？  
4. 授权模式（去 autoReview / untrusted）是否并行另开，还是先压后做？

**请确认是否按此计划执行（可附带默认策略选择）。**

---

*claude 主线程 · 2026-07-19 · PLANNED*
