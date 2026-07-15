# 09 — 总耦合矩阵 + 建议拆装顺序

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 依据：`01`–`08` 只读分析合成  
> 纪律：拆装须走 [`docs/slim-roadmap.md`](../slim-roadmap.md) **逐步 Stage**；禁止一刀砍。
> 当前：S0 完成 · S1 基线；未授权不删模块 / 不改包名

---

## 1. 一页结论（二次开发用）

| 问题 | 答案 |
|------|------|
| **Codex chat + shell 最小闭环** | Flutter `ChatPageMode.codex` → `CodexAppServer` Channel → `CodexAppServerManager/Session` → `LocalCodexAppServerConnection` → `TerminalManager.startLongLivedAlpineProcess` → proot/Alpine `codex app-server` → events → `CodexEventReducer` + tool cards |
| **与「交互终端页」是否同一栈** | **否**。Codex 用 **Process 工厂**（无 PTY）；交互终端用 `SessionService`/`TerminalView`（可选） |
| **Gradle 模块边界 = 包边界？** | **否**。`app` 是巨石：`codex/` `agent/` `terminal/` `mcp/` `im/` 全在 `:app` |
| **Codex-only 可砍什么** | assists/accessibility 自动化、uikit 悬浮任务 UI、omniinfer 本地推理、Remote bridge、OTA Worker、IM/QuickLog/webchat |
| **绝对不能先砍** | proot/alpine + init-host、`TerminalManager` 长进程 API、Codex Manager/Session/Local、Channel 契约、baselib DB（Conversation + CodexThreadBinding）、Flutter 聊天壳 |
| **P0 出包路径（已存在）** | `assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart`（勿裸 `assemble`，会逼 omniinfer submodule） |

---

## 2. 模块 × 能力 矩阵

图例：● 硬依赖 / ◎ 软依赖 / ○ 无 / ✂ 可砍(Codex-only)

| 模块 / 切片 | Codex chat+shell | 交互终端 UI | 手机自动化 | 本地推理 | 聊天壳 | 标签(Codex-first) |
|-------------|------------------|-------------|------------|----------|--------|-------------------|
| `:app` 壳 + Application | ● | ◎ | ◎ | ◎ flavor | ● | **CORE** |
| `:flutter` / `ui/` 聊天壳 | ● | ◎ | ◎ | ◎ omniinfer | ● | **CORE** |
| `app/.../codex/*` LOCAL | ● | ○ | ○ | ○ | ◎ | **CORE** |
| `app/.../codex/*` REMOTE | 可选 | ○ | ○ | ○ | ◎ | **可选** |
| `TerminalManager` 长进程/hidden | ● | ◎ | ○ | ○ | ○ | **CORE** |
| `EmbeddedRuntime` proot/alpine | ● | ● | ○ | ○ | ○ | **CORE** |
| `terminal-view` / PlatformView / SessionService | ○ | ● | ○ | ○ | ◎ | **可选** |
| `:baselib` OmniLog/DB/LLM config | ● binding | ○ | ● | ◎ | ● | **CORE** |
| `:assists` VLM/任务/detection | ○ | ○ | ● | ○ | ◎* | **可砍P0*** |
| `:accessibility` + SelectToSpeak | ○ | ○ | ● | ○ | ◎ | **可砍P0** |
| `:uikit` 悬浮/半屏 | ○ | ○ | ● | ○ | ◎ | **可选** |
| `:omniintelligence` DTO | ○ | ○ | ● | ○ | ○ | **后置**(随 assists) |
| omniinfer / local_model | ○ | ○ | ○ | ● | ◎ | **可砍P0** |
| `tools/codex-bridge` | 可选 | ○ | ○ | ○ | ◎ | **可选** |
| `workers/` OTA | ○ | ○ | ○ | ○ | ◎ | **可选** |
| `builtin_skills` assets | ○ | ○ | ◎ Agent | ○ | ◎ | **CORE**(Agent) / Codex 弱 |
| CI `build-local-release` | 构建 | 构建 | 构建 | 构建 | 构建 | **构建专用** |

\* `assists` 内 `HttpController` 被 Agent 聊天复用——**不能裸删模块**，须先迁出。

---

## 3. 关键调用边（耦合强度）

```
[极高 / 生命线]
Flutter ChatPage(codex)
  → CodexAppServerChannel
  → CodexAppServerManager
  → CodexAppServerSession
  → LocalCodexAppServerConnection
  → TerminalManager.startLongLivedAlpineProcess
  → init-host.sh → proot → Alpine → codex app-server
  → stdout JSONL → EventChannel
  → CodexEventReducer / tool parser → commandExecution cards

[高 / 本地会话]
Manager ↔ CodexThreadBindingRepository ↔ baselib Room
Manager ↔ TerminalManager.executeHiddenCommand (config/auth/probe)
Manager ↔ AgentWorkspaceManager (/workspace cwd)

[高 / 自动化产品 — Codex 旁路]
Flutter AssistCoreEvent → AssistsCoreManager(~7k) → AssistsCore
  → accessibility OmniAction / VLM loop
uikit.UIKit.init → AssistsCore 事件注入

[中 / 可选远程]
RemoteCodexBridgeConnection → tools/codex-bridge (PC)

[低 / 无边]
Codex ↔ assists/accessibility  (无 import)
Codex ↔ omniinfer
Codex ↔ terminal-view / SessionService
ReTerminal core ↔ baselib
```

---

## 4. 标签总表（按拆装优先级）

### CORE必留（Codex chat + shell）

1. settings 模块图 + `:app` + Flutter embed + `ChannelManager`
2. `app/.../codex/`：Manager / Session / LocalConnection / Defaults / BindingRepository
3. `CodexAppServerChannel` + Flutter `codex_app_server_service` + `codex_event_reducer` + `codex_tool_call_parser`
4. `chat_page_codex` / lifecycle 订阅 / `applyCodexEvent` / `CodexRequestCard`
5. `TerminalManager` 长进程 + hidden + `EmbeddedRuntimeInstaller` + init-host/init + proot/alpine assets
6. `:baselib`：OmniLog、DatabaseHelper、Conversation、**CodexThreadBinding**、ModelProvider/Scene（配置）
7. product flavor **standard** + `main_standard.dart`

### 可选（产品取舍，不挡 Codex）

- Remote Codex + `tools/codex-bridge` + 扫码/远程 FS UI
- 交互终端 UI（terminal-view、PlatformView、TerminalActivity、rk Compose）
- SessionService / ReTerminalSessionBridge 头less PTY
- workers OTA + AppUpdateManager
- IM / QuickLog / MCP UI / skill store / webchat / 语音
- account/login ChatGPT 流、review/start 增强

### 可砍P0（Codex-only 瘦身）

- `:accessibility` + SelectToSpeak 伪装 + MediaProjection
- `:assists` 任务/VLM/detection/companion（**先迁 HttpController**）
- uikit 任务悬浮（或整模块 optional + 空 Assists 事件）
- omniinfer edition + submodule + Flutter local_model 路由
- `skills/wechat.json`、根 `fonts/` 大文件、codex-bot CI、CNB mirror

### 后置

- baselib 垂直拆分（db/llm/privileged）
- AssistsCoreManager 上帝对象拆分
- app 内 monorepo 包抽独立 Gradle 模块
- `main.dart` 默认改 standard
- split_assets 遗留脚本清理

### 构建专用

- `scripts/build-local-release.sh`、upload/mirror、GHA release/ci
- `prepareEmbeddedTerminalRuntime`、Flutter web preBuild（现状强制）

---

## 5. 建议拆装顺序（渐进，每步可回滚）

> 用户要求：先摸清 → **一点点拆/装**。下列为建议阶段，**未授权前不执行**。

### 阶段 0 — 冻结与地图（**完成**）→ 详见 slim-roadmap S0

- [x] 拉仓至 `omnibot-product`
- [x] ≤8 并行只读模块地图 `docs/module-map/01`–`09`
- [ ] 用户确认地图与拆装优先级
- **禁止**：改业务代码、改 applicationId、出 fork 产品 APK

### 阶段 1 — 构建可复现（**S1 进行中**）

1. `cd ui && flutter pub get` 生成 `.android`
2. 固定 slim：`assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart`
3. 文档钉死：勿裸 `assemble`；勿强制 init omniinfer submodule
4. 验收：debug APK 可装、主界面起来、Codex 设置页可进

### 阶段 2 — 能力开关（行为降级，不删模块）

1. 权限引导：无障碍改为**可选**，不阻断 Codex 入口
2. 默认会话模式偏 Codex（产品策略，需确认）
3. Remote / OTA / IM 配置默认关
4. 验收：不开无障碍也能 Codex connect + shell

### 阶段 3 — 可选面物理隔离（小步）

1. 文档/CI 去掉 omniinfer 默认路径；standard-only 脚本
2. 摘 webchat preBuild 强制（若确认无 MCP 静态依赖）— **需先证伪依赖**
3. 交互终端 UI 可隐藏入口（保留进程工厂）
4. 验收：包体/启动路径变短；Codex shell 回归

### 阶段 4 — 自动化栈解耦（高风险，最后动）

1. **先**把 `HttpController` + 模型/会话 channel API 迁出 assists  
2. 再空实现/剔除 VLM、Companion、detection、OpenCV  
3. 去 SelectToSpeak Manifest + MediaProjection  
4. 削 uikit 任务悬浮；Assists 空事件  
5. 最后 `settings` 去掉模块（若编译面干净）  
6. 每步回归：Codex shell + 基础聊天

### 阶段 5 — 二次开发增值（地图完成后另开方案）

- 包名/品牌/签名策略（**单独确认**）
- app 内 `codex/` 是否抽 Gradle 模块
- baselib 分层、AssistsCoreManager 拆分
- 自有 OTA / 默认模型策略

---

## 6. 明确「不做什么」（防再走反）

| 禁止 | 原因 |
|------|------|
| 上来改 AWB / 软补 tool.absent | 用户已判定整条路偏；AWB 产品线 ABANDONED |
| 未摸清就 hard-port / 改包名 / 发 fork APK | 同「路走反了」 |
| 裸删 `:assists` | HttpController/Channel 上帝对象会炸编译与聊天壳 |
| 把 Codex 绑到 SessionService PTY | 当前正确边界是 Process 工厂 |
| 把 WeiXin 目录 Xposed 小包当宿主烟测 | 不是 full host |
| 本机 Alpine 当发布 assemble | 无完整 SDK；Omni 出包另立 GHA 方案（阶段 1 后） |

---

## 7. 与历史 AWB 问题的对照（只读洞察）

| AWB 现象 | OmniBot 对照 |
|----------|----------------|
| connect OK、零 `commandExecution` | Omni 同样靠 **模型决策** 发 tool；Manager 无 enableTools 开关；差异在完整 chat 上下文/工具卡/审批/沙箱默认 |
| 交互终端 OK、聊天工具不行 | Omni 也是 **两栈**：PTY UI vs Process app-server——正常 |
| 软补 wire 无效 | Omni 成功路径是整段 Manager+Reducer+卡片+Local 长进程，不是单点参数 |

→ 二次开发应 **站在 Omni 完整闭环上裁剪**，而不是回 AWB 补丁线。

---

## 8. 文档索引

| 文件 | 内容 |
|------|------|
| [00-README](./00-README.md) | 目标与状态 |
| [01-gradle-app-shell](./01-gradle-app-shell.md) | settings/app 壳 |
| [02-flutter-ui](./02-flutter-ui.md) | Flutter UI / channels |
| [03-codex-stack](./03-codex-stack.md) | Codex 端到端 |
| [04-terminal-reterminal](./04-terminal-reterminal.md) | 终端/proot 两栈 |
| [05-baselib-uikit](./05-baselib-uikit.md) | baselib / uikit |
| [06-assists-accessibility](./06-assists-accessibility.md) | 无障碍自动化 |
| [07-omniintelligence-infer](./07-omniintelligence-infer.md) | 协议 DTO + 本地推理 |
| [08-workers-tools-bridge](./08-workers-tools-bridge.md) | workers/scripts/skills/CI |

---

## 9. 验收标准（本阶段）

- [x] 8 路模块分析覆盖 Gradle 全图 + 关键非模块目录  
- [x] 每模块具备：职责/入口/依赖/耦合/标签/风险  
- [x] 总矩阵给出 CORE / 可选 / 可砍 / 后置 / 构建  
- [x] 拆装顺序分阶段且标明不执行  
- [ ] **用户确认地图**后，才进入阶段 1（构建可复现）

---

*合成完毕。等待用户确认后再谈拆装执行。*
