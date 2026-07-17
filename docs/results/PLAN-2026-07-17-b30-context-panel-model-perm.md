# PLAN-2026-07-17 · B30–B33 定位清单（下一对话真源）

> **本文件只做定位，不实现。**  
> 基线：B22–B29 READY `cb7ce48` / APK sha256 `d7caffbe…`  
> 用户反馈：上下文环位置错；`/` 与 `@` 不互斥；模型列表仍硬编码污染；composer 三级权限看不懂→去掉，只保留 `/` 列表开关 goal/fast/自动压缩，**fast 默认关**。

## ID 映射

| ID | 用户原话要点 | 产品目标 |
|----|--------------|----------|
| **B30** | 找不到上下文/压缩阈值环；应半透明固定在**对话框顶部空白**；实时写 conf；提示**新开对话才生效** | Codex（及需要时 normal）顶栏上下文/阈值控件 + config 落盘 + toast |
| **B31** | `/` 列表与 `@` 列表不互斥 | 开其一必关另一；路由/flag 互斥 |
| **B32** | 模型列表与 `model/list` 不一致，仍有硬编码 | UI 仅展示 list 结果；禁止 merge 注入 list 外 id |
| **B33** | 三级权限设计看不懂→**去除**；默认支持 goal/fast/自动压缩；fast 默认关；用户在 **`/` 列表**开关 | 去掉 composer 权限按钮/菜单；权限走合理默认（无三级 UI）；`/` 根列表保留 goal/fast/compact（auto_compaction） |

---

## B30 · 上下文长度 / 压缩阈值 UI（错位）

### 现状（为何找不到）

| 点 | 位置 | 问题 |
|----|------|------|
| 环只挂在 **normal** 模式输入区右侧 | `chat_page_ui.dart:1581-1596` | **Codex 模式 `contextUsageRatio=null`，环不渲染** |
| 环在 **composer 底栏**，非对话框顶部 | `chat_input_area_composer.dart:200-210, 744-774` | 与用户期望「对话框顶部空白半透明」不符 |
| 阈值写 **会话 DB + SharedPrefs 手工 map**，不是 Codex conf | `chat_page_ui.dart` sheet ~3082+；`storage_service.dart` `manual_model_context_thresholds`；`AssistsCoreManager` promptTokenThreshold | 无「写 conf + 新对话生效」提示 |
| Codex `auto_compaction` 在 **设置页** | `codex_setting_page.dart` ~291+, 615+ | 用户要的是聊天顶栏可调，不是藏设置 |

### 定位清单（下一对话改这些）

| 优先级 | 文件 | 行/符号 | 动作 |
|--------|------|---------|------|
| P0 | `ui/.../chat/chat_page_ui.dart` | `:1581-1596` contextUsage* 仅 normal | Codex 也要展示或**独立顶栏控件**，勿 null |
| P0 | `ui/.../chat/chat_page_ui.dart` | `topBanner` `:1556-1575` 现仅 Goal bar | 扩展/并列：**半透明 Context 条**固定对话区顶（或消息区顶空白），非底栏 ring |
| P0 | `ui/.../chat/widgets/codex_goal_mode_bar.dart` 或新 `codex_context_bar.dart` | — | 新建半透明顶栏：显示窗口/阈值 + 点击调值 |
| P0 | `app/.../codex/CodexAppServerManager.kt` | config read/write `~475+`, `buildCodexFeaturesTomlSection` | 阈值/上下文相关键写入 **config.toml**（对齐上游字段；至少 `auto_compaction` + 若 schema 有 context 相关则同步） |
| P0 | `ui/.../services/codex_app_server_service.dart` | `writeLocalConfig` / `CodexLocalConfig` | 暴露写 conf API；保存后 **toast：新开对话后生效** |
| P1 | `ui/.../chat/chat_page_ui.dart` | `_ContextThresholdSheet` ~3082+ | 复用 sheet，但入口改顶栏；保存路径改 conf |
| P1 | `ui/models/conversation_model.dart` | `contextUsageRatio` | Codex 侧若用 token 事件再绑 ratio；否则顶栏显示 conf 值即可 |
| 非目标 | 底栏 `_ContextUsageRingButton` 对 Codex | composer | 可保留 normal；**Codex 不以底栏环为真源** |

### 验收

1. Codex 对话打开即见**顶部**半透明条（空消息区上方/对话 chrome 顶）  
2. 调阈值 → 立刻写 conf → toast「新开对话后生效」  
3. 杀进程重进 conf 仍在；**当前 thread 可仍旧值，新对话生效**

---

## B31 · `/` 与 `@` 列表不互斥

### 现状

| 点 | 位置 | 问题 |
|----|------|------|
| `@` 开 skills 时 **强制** `_showSlashCommandPanel=true` + `_codexSkillsPanelVisible=true` | `chat_page_codex.dart` `_openCodexSkillsPanel` `:1221-1236` | 与 `/` 共用同一 panel 壳 |
| 路由：skills 优先于 root | `chat_page.dart` `_resolveSlashCommandPanelRoute` `:1063-1066` | `if (_codexSkillsPanelVisible) return skills` |
| `#` 开 slash **不关** skills flag | `chat_page_openclaw.dart` `_triggerSlashCommandPanel` | 可能仍带 skills 路由 |
| `@` 开 **不关** 纯 slash root 语义 | `chat_page_ui.dart` `:1540-1550` | 二按只 toggle hide，不处理与 `/` 交叉 |

### 定位清单

| 优先级 | 文件 | 行/符号 | 动作 |
|--------|------|---------|------|
| P0 | `chat_page_codex.dart` | `_openCodexSkillsPanel` `:1221+` | 开 `@` 前：清 slash 文本态 / 确保 route=skills only；关 root 卡 |
| P0 | `chat_page_openclaw.dart` | `_triggerSlashCommandPanel` / `_handleSlashCommandInput` | 开 `/` 时：`_codexSkillsPanelVisible=false`；清 `@` mention 态 |
| P0 | `chat_page.dart` | `_resolveSlashCommandPanelRoute` `:1063+` | 显式互斥：skills **仅**当 skillsVisible **且**非强制 root；typed `/` 优先 root |
| P1 | `chat_page_ui.dart` | `@` / `#` wire `:1538-1550` | 开一侧前调用对方 close API |
| P1 | `chat_page_openclaw.dart` | `_hideSlashCommandPanel` | 已同时清双方 flag——确保所有入口用它 |

### 验收

1. 开 `/` 再开 `@` → 只见技能列表  
2. 开 `@` 再开 `/` → 只见 slash 根列表  
3. 不会两套卡叠在同一 panel

---

## B32 · 模型列表 ≠ model/list（硬编码污染）

### 现状

| 点 | 位置 | 问题 |
|----|------|------|
| `listModels` 真源 | `codex_app_server_service.dart:570+`；`_loadCodexModelOptions` `chat_page_codex.dart:366+` | 有拉取 |
| **`_mergeCodexOptionIds` 把 current/preferred 塞进列表** | `chat_page_codex.dart:6810-6830` | **list 外 id 仍出现在 UI**（硬编码/残留偏好污染） |
| load 时 preferred/active 注入 | `chat_page_codex.dart:387-449` | 同上 |
| select 后再 merge | `chat_page_codex.dart:1717+` | 继续放大 |
| 冷启动/默认 model 可能来自 config 字符串 | config `model` + prefs | 允许作 **选中值**，但 **不得伪造 option 行** |

### 定位清单

| 优先级 | 文件 | 行/符号 | 动作 |
|--------|------|---------|------|
| P0 | `chat_page_codex.dart` | `_mergeCodexOptionIds` `:6810+` | 改为 **仅 options**；current/preferred 只影响选中，不在 list 内则 clamp 到第一项或清空+提示 |
| P0 | `chat_page_codex.dart` | `_loadCodexModelOptions` `:366-460` | `modelOptions = extract only`；禁止 add preferred 进 options |
| P0 | `chat_page_codex.dart` | `_selectCodexModel` / rebind effort | 选中 id 必须 ∈ catalog |
| P1 | `chat_input_area_composer.dart` | run settings menu `:986+` | 无本地假模型 fallback 列表 |
| P1 | Kotlin | `listModels` pass-through | 确认无服务端假列表；若 config model 不在 list 不写入 options |
| P1 | DebugFileLog | model select | 打 log：list 条数、是否 clamp |

### 验收

1. UI 模型条数/id **等于** 当次 `model/list` 可解析集合  
2. conf 里旧模型不在 list → 不出现在下拉，提示切换  
3. sol / 5.6 等与上游一致；effort 仍 per-model（B26）

---

## B33 · 去除三级权限 UI；`/` 管 goal/fast/压缩；fast 默认关

### 用户意图（图片1 = composer 权限入口）

用户不理解「默认权限 / 自动审查 / 完全访问」三级设计 → **整段 UI 去掉**。  
保留能力：

- **goal**、**fast**、**自动压缩**：产品默认支持  
- **fast 默认关闭**（已有 `_activeCodexFastEnabled = false` @ `chat_page.dart:429`）  
- 用户在 **`/` 根列表** 自己开关（已有 goal/fast/compact 卡）

### 现状

| 点 | 位置 | 角色 |
|----|------|------|
| enum 三级 | `chat_input_area.dart:42` `CodexPermissionMode` | UI 数据源 |
| 权限按钮+玻璃菜单 | `chat_input_area_composer.dart:49-61, 219+, 790+, 810-812, 1204-1320, 1654+` | **用户看到的「看不懂设计」** |
| 接线 | `chat_page_ui.dart:1656-1659` `onCodexPermissionModeChanged` | 打开菜单 |
| 切换逻辑 | `chat_page_codex.dart` `_setCodexPermissionMode` `:870+`；payload `:7455+` | RPC 映射（可内化默认，不必删死代码立即） |
| `/` 列表已有 | `chat_page_ui.dart` `_buildCodexSlashCommandCards` `:360-496` | goal-mode / fast / review / plan / compact |
| auto_compaction 在设置页 | `codex_setting_page.dart` | 用户要 **`/` 列表** 开关 → 给 compact 或单独 auto_compaction 卡绑定 features 写 |

### 定位清单

| 优先级 | 文件 | 行/符号 | 动作 |
|--------|------|---------|------|
| P0 | `chat_input_area_composer.dart` | `_shouldShowCodexPermissionSelector` / `_buildCodexPermissionButton` / menu | **不再渲染**权限按钮与菜单 |
| P0 | `chat_page_ui.dart` | `codexPermissionMode` / `onCodexPermissionModeChanged` wire | 传 null / 去掉 |
| P0 | `chat_page.dart` | `_codexPermissionMode` 默认 | 固定合理默认（建议保持 defaultMode 载荷：on-request+user+workspaceWrite）；**无 UI 切换** |
| P1 | `chat_page_codex.dart` | `_setCodexPermissionMode` | 可保留内部 API 或仅 startTurn 注入默认 payload；去掉 slash/tip 切三档入口 |
| P0 | `chat_page_ui.dart` | `_buildCodexSlashCommandCards` `:389-496` | 确认 **goal / fast / compact**；fast 卡反映默认关；**自动压缩**可：compact 卡扩展 或 新增 `/auto-compact` 开关写 `features.auto_compaction` |
| P0 | fast 默认 | `chat_page.dart:429`；refresh `:293-321` | 确保 conf `fast_mode=false` 与 UI 一致；禁止 sticky-on |
| P1 | `codex_setting_page.dart` auto_compaction | 可保留设置页作次入口；**主入口改 `/` 列表** |
| P2 | review/plan 卡 | `:446-461` | 用户未点名删除；本轮可不砍，除非要极简只留 goal/fast/compact |

### 验收

1. 输入区 **无** 盾牌/三级权限按钮  
2. `/` 可见 goal、fast（默认关）、自动压缩/compact 类开关  
3. 新会话 fast 关；开 fast 仍走 B14 三写  
4. 工具仍可在默认策略下请求审批（无三级 UI，行为固定 default）

---

## 推荐锁（下一对话调度）

| Lock | 文件 | 覆盖 |
|------|------|------|
| **L-ContextTop** | 新 bar + `chat_page_ui` topBanner + Kotlin conf | B30 |
| **L-PanelMutex** | `chat_page_openclaw` / `chat_page_codex` open skills / `chat_page` route | B31 |
| **L-ModelCatalog** | `chat_page_codex` merge/load/select | B32 |
| **L-PermUI-Remove** | `chat_input_area_composer` + `chat_page_ui` wire + 默认 payload | B33 |
| **L-SlashCards** | `chat_page_ui` `_buildCodexSlashCommandCards` | B33 + B30 auto_compaction 入口 |

建议并行：B31 ‖ B32 ‖ B33-UI 拆除；B30 与 topBanner/Goal 串行。

---

## 非目标

- 不回滚 B14 Fast 三写 / B25 writableRoots（除非 B33 默认 payload 回归）  
- 不本机 Gradle 出包  
- 不 push origin  

## 下一对话开场建议（可复制）

```
按 docs/results/PLAN-2026-07-17-b30-context-panel-model-perm.md 修 B30–B33。
主线程只方案/调度/验收；≥6 并发；push 仅 mine；GHA baseline-standard-debug。
B33：去掉三级权限 UI；/ 列表管 goal/fast/自动压缩；fast 默认关。
B30：顶栏半透明上下文/阈值，写 conf，toast 新对话生效。
B31：/ 与 @ 互斥。
B32：模型列表纯 model/list，禁止 merge 注入 list 外 id。
```
