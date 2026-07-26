# EXEC · codex 实时上下文用度 + 卡顿优化 · 2026-07-26

> 来源：用户口头反馈（非既有 PLAN）
> 阶段：**IMPLEMENTED（未编译验证）** → 待 PC 端本机 analyze/test/build
> 约束：手机端**无编译额度**，本轮不触发 GHA；push 仅 mine
> 站规：push 仅 mine · tip ≠ PASS · 无 DEVICE_PASS 不标 READY

## 用户诉求

1. **Bug**：codex 模式「上下文设置的地方，不会显示实时的上下文用度」。
2. **性能**：整体使用体验卡顿，顺手找问题点优化。
3. **交接**：手机端编译额度耗尽，退回仓库，由 PC 端 cc 接力做本地编译。

---

## 一、Bug 根因

**codex 模式从来没有 token 用度链路。**

`latestPromptTokens` 的唯一生产者是 agent/normal 管线
（`AgentConversationHistoryRepository.updatePromptTokenUsage`）。
codex 走的是另一条完全独立的管线：

```
CodexAppServerManager → CodexAppServerChannel(EventChannel)
  → codex_event_reducer.dart → ChatConversationRuntimeCoordinator
```

这条链路**从头到尾没有碰过 token**。全仓检索 `token_count` /
`total_token_usage` / `model_context_window` —— **0 命中**。

`CodexContextBar` 的 `usedTokens` / `usageRatio` 入参、以及阈值面板的
「当前上下文」「占用比例」两格，都是早就接好的**死 UI**：读到的永远是 0。

溯源到 B30 设计稿 `PLAN-2026-07-17-b30-context-panel-model-perm.md:39`
明确挂起过这件事 —— *「若用 token 事件再绑 ratio，否则顶栏显示 conf 值即可」*。
这次是把当时挂起的那半条链补完。

### 修复（四层）

| 层 | 文件 | 动作 |
|----|------|------|
| 原生解析 | `CodexAppServerManager.kt` | 解析 codex `token_count` 的 `info.last_token_usage`（回退 `total_token_usage`）+ `model_context_window`，挂到 event 上 |
| 原生落库 | `CodexAppServerManager.kt` | 同步镜像写 conversation 行 |
| Flutter 应用 | `chat_conversation_runtime_coordinator.dart` | `_applyCodexTokenUsage` 从裸 event 取值，reducer 不认识该事件时也照样应用 |
| Flutter 重绘 | `chat_page.dart` / `chat_page_ui.dart` | chrome 签名纳入该值；阈值面板改 `ListenableBuilder` |

### 三个关键判断（别改回去）

1. **必须用 `last_token_usage`，不能用 `total_token_usage`。**
   后者是**跨轮累计**，拿来当上下文窗口占用会疯狂虚高。
   `last_token_usage` 才是「此刻窗口里躺着多少」。

2. **`turn/completed.usage` 只能当兜底。**
   它是**单轮内多次模型调用的聚合**，直接用会高报。
   已用 `tokenCountSeenThreads` 守卫：只有从不发 `token_count` 的
   thread 才回落到它。

3. **落库必须在 Kotlin 侧做，不能指望 Flutter 持久化路径。**
   `ConversationService._mergeLatestConversationMetadata`
   （`conversation_service.dart:163`）在 `preserveLatestMetadata: true`
   时会**显式从 DB 回读** `latestPromptTokens`。
   也就是说 Flutter 那条持久化路径永远写不进这个字段 —— 走它是死路。

### 顺带修掉的文案冲突

阈值面板副标题写「新的阈值会**立刻用于当前对话**」，
而 codex 的 toast 说「**新开对话后生效**」—— 自相矛盾。

根因：**一个面板被两个语义不同的调用点复用**。
normal 模式写 conversation 行、立即生效；
codex 模式写 `conf`、只对新会话生效。

改法是加 `appliesToCurrentConversation` 参数按调用点分流，
而不是二选一挑个字符串了事。

---

## 二、性能优化（5 项）

| # | 问题 | 改法 | 预期 |
|---|------|------|------|
| 1 | **流式期每 ~350ms 全量重写消息列表** | 中途快照节流到 5s | **最大头**。原本每个 debounce 窗口都整表序列化 + Room replace；终态事件仍无条件落库，只影响进程猝死时的丢失上限 |
| 2 | `resolveAgentToolActivitySnapshot` 每次布局重建都全量遍历消息 | 按 `lastMutationRevision` memo 化，并去掉多余的 `List.from()` 防御性拷贝（该函数只读） | 键盘弹收 / PageView 拖动 / 高度同步不再付 O(messages) |
| 3 | codex 本地 conf 读取失败后**每帧重试** | 失败后退避 10s | `readLocalConfig` 会 **fork 一个 Alpine shell**，且调用点在 build 路径上 |
| 4 | 输入柱高度同步一帧内被排多次 | 每帧去重 | Goal bar / 上下文顶栏 / composer 三处同帧各调一次，各自排一次 `findRenderObject` |
| 5 | **每个 codex 事件查一次 Room** 只为拿 conversationId | `CodexThreadBindingRepository` 内存 memo | 每条流式 delta 都会走到；失效面已核实——只有 `ensureBinding` / `rebindExistingThread` 会改映射 |

### #4 的取舍说明

原本想删掉「高度未变」早退分支里链式调用的 `_scheduleInputPillarHeightSync()`，
判断风险太高（可能破坏首次挂载时的同步），
改为在 `_scheduleInputPillarHeightSync` **内部**加每帧去重守卫 ——
同样的收益，零行为变更。

### #5 的失效面核实

读完 `CodexThreadBindingRepository.kt` 全文确认：
`updateTitle` / `setArchived` / `setConversationArchived` **不会**改
`conversationId`；只有 `ensureBinding` 和 `rebindExistingThread` 会。
因此把三处 `upsertCodexThreadBinding` 收口到私有 `upsertBinding`
（写库同时刷缓存），并在 `cleanupGeneratedEmptyConversation` 删会话时按值驱逐。

### 未做（已识别，留给下一轮）

- **native 事件批处理** —— 中风险，涉及事件顺序，需要单独设计。
- **chrome 签名字符串分配** —— 每次比较都 `join('|')` 造串。
- **`ChatToolActivityStrip` 的 `BackdropFilter` 缺 `RepaintBoundary`。**
- **`loadConversation` 用 `getAllConversations()` 取单个会话** ——
  外加 `publishMessagesReplaced` 的反向广播回环。

---

## 三、账本

| 字段 | 值 |
|------|-----|
| 分支 | `codex/b38-integration` |
| 源码 HEAD | `031ba548ccb68f8441f6b37d1a658abe1f30eefa` |
| 前一 commit | `c03df40`（补记 auto-review 移除的 APK_STAGED，与本轮无关） |
| GHA | **未触发**（用户编译额度耗尽） |
| APK | **无** |
| 真机 | **未验** |

### 改动文件

```
app/.../codex/CodexAppServerManager.kt          +126 -1
app/.../codex/CodexThreadBindingRepository.kt   + 31 -3
ui/.../chat/chat_page.dart                      +  3 -0
ui/.../chat/chat_page_ui.dart                   +173 -50
ui/.../chat/services/chat_conversation_runtime_coordinator.dart  +50 -1
```

---

## 四、⚠️ 验证状态（**必读**）

**本轮没有跑过任何编译器。** 手机端 Alpine 环境里
`flutter` / `dart` / JDK **均不存在**（已确认 `command -v` 全空），
不是「没跑」，是**跑不了**。

已做的替代核验（靠读，不靠编译器）：

- ✅ 全部引用符号存在：`setEquals` / `ListenableBuilder`（父库已 import
  `foundation.dart` + `material.dart`，本文件是 `part of`）、
  `lastMutationRevision`、`ChatPageMode`、
  `resolveAgentToolActivitySnapshot` 签名匹配
- ✅ Kotlin 侧：`Conversation.latestPromptTokens` /
  `latestPromptTokensUpdatedAt` 字段存在；
  `DatabaseHelper.getConversationById` / `updateConversation` 存在；
  `scope` / `TAG` / `ConcurrentHashMap` 均在作用域内
- ✅ `localConversationId` 在 event 构造点确实在作用域内
- ✅ 括号配平：Dart 三个文件全平；Kotlin manager 显示 `-2` 偏移，
  **已与 HEAD 对比确认是脚本剥离字符串的假阳性，非本轮引入**
- ✅ 数据通路逐跳读通：
  Kotlin 解析 → event 字段 → coordinator 应用 → chrome 签名 → 顶栏重绘
- ❌ **`flutter analyze` 未跑**
- ❌ **`flutter test` 未跑**
- ❌ **Kotlin 未编译**

**结论：静态门禁一个都没过，PC 端必须从头跑。**

---

## 五、PC 端接力清单

```bash
cd ui && flutter pub get && flutter analyze && flutter test
cd .. && ./gradlew assembleDevelopDebug
```

### 重点复查（按可疑度排序）

1. **`ListenableBuilder` 的 `builder` 签名** ——
   写的是 `(context, _)`；若 analyzer 报 unused/类型不符，改 `(context, child)`。
2. **Kotlin `extractCodexTokenUsage` 的 `Map<*, *>` 实参协变** ——
   传进去的是 `Map<String, Any?>`，理论上没问题，但 Kotlin 泛型偶有意外。
3. **`conversationIdByThreadId.values.remove(conversationId)`** ——
   `ConcurrentHashMap.values()` 的 `remove` 只删一个匹配项。
   这里语义可接受（一个 conversation 正常只绑一个 thread），
   但若 analyzer/lint 有意见，换成显式 `entries.removeAll { ... }`。

### 真机验收（编译过后）

- **D1**：codex 模式发一轮对话，顶栏 token 数**随流式实时上涨**（不再恒 0）
- **D2**：对话进行中**打开阈值面板并保持打开**，「当前上下文」跟着涨
- **D3**：codex 阈值面板副标题显示「新开对话后生效」；
  normal 模式长按用量环打开的面板显示「立刻用于当前对话」
- **D4**：退出会话再进，顶栏显示上次的用度（不回落到 0）——
  验 Kotlin 侧落库
- **D5**：**长回复流式期观感**是否比之前顺（性能项 #1 的主观验收）

---

## 六、遗留风险

- 性能项 #1 把中途落库拉到 5s，**进程猝死时最多丢 5s 的中途快照**。
  终态事件仍无条件落库，正常退出无影响。这是刻意的取舍。
- `token_count` 事件的实际字段名基于 codex app-server 协议推断
  （`info.last_token_usage.{input,output,total}_tokens`）。
  **若真机 D1 顶栏仍为 0，第一个要查的就是这里** ——
  抓一条真实 `token_count` 事件的 payload 比对字段名。
  解析层已写成宽容形式（`total_tokens` 优先，缺失则 input+output 求和），
  但字段路径本身没在真机上验证过。

---
*claude · 2026-07-26 · 手机端无编译额度，静态门禁全部留给 PC 端*
