# 03 — Codex 栈

> 真源：app `codex/*` + `CodexAppServerChannel` + Flutter `codex_*`  
> 范围：完整 Local/Remote 路径、事件还原、线程绑定、标签与拆装风险  
> 纪律：只读地图；**不**把 Codex 绑到 SessionService PTY

---

## 1. 职责

在 OmniBot 内提供 **Codex app-server** 会话：连接、线程生命周期、turn 流式事件、工具/命令执行卡片、本地 Alpine 进程或远程 bridge。

对外能力：

- Flutter 聊天 Codex 模式
- JSON-RPC/JSONL 风格 app-server 协议桥
- Local：proot/Alpine 内 `codex app-server` 长进程
- Remote：PC/ bridge WebSocket（可选）
- Room 级 `CodexThreadBinding`（conversationId ↔ threadId）

---

## 2. 入口

| 层 | 入口 |
|----|------|
| UI | `ChatPageMode.codex` / `ConversationMode.codex` → `chat_page_codex.dart` |
| Flutter API | `ui/lib/services/codex_app_server_service.dart` |
| Channel | Method `cn.com.omnimind.bot/CodexAppServer` + Event `.../CodexAppServerEvents` |
| 原生门面 | `CodexAppServerChannel` → `CodexAppServerManager` |
| 会话 | `CodexAppServerSession` |
| 连接 | `LocalCodexAppServerConnection` **或** `RemoteCodexBridgeConnection` |
| 进程 | `TerminalManager.startLongLivedAlpineProcess(..., executorKey="codex-app-server")` → shell 内 `exec codex app-server` |

---

## 3. 实现要点：完整路径

### 3.1 生命线（Local CORE）

```
Flutter ChatPage (codex)
  → CodexAppServerService (MethodChannel invoke + EventChannel listen)
  → CodexAppServerChannel
  → CodexAppServerManager
  → CodexAppServerSession
  → LocalCodexAppServerConnection
  → TerminalManager.startLongLivedAlpineProcess
       command ≈ 启动 alpine 环境并 exec codex app-server
       executorKey = "codex-app-server"
  → init-host.sh → proot → Alpine rootfs
  → stdout JSONL 事件上行
  → Session/Manager 解析
  → EventChannel → Flutter
  → CodexEventReducer + CodexToolCallParser
  → commandExecution / 审批 / diff 等 tool cards
  → chat_page_codex 渲染 + CodexRequestCard
```

### 3.2 远程旁路（可选）

```
Manager 按配置选择 RemoteCodexBridgeConnection
  → CodexRemoteBridgeConfigStore / CodexRemoteBridgeUrls
  → WebSocket/HTTP bridge（tools/codex-bridge 在 PC 侧）
  → 可代理 raw app-server JSON
  → 同一套 Session 事件面回流 Flutter
UI 辅助：
  codex_bridge_qr_scanner_page / codex_remote_workspace_browser /
  codex_remote_directory_picker / codex_remote_file_preview_page
```

### 3.3 原生关键类

目录：`/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/`

| 文件 | 职责 | 标签 |
|------|------|------|
| `CodexAppServerManager.kt` | 连接生命周期、线程 API、配置/auth probe、事件分发；体量大（~65KB） | **CORE** |
| `CodexAppServerSession.kt` | 单连接会话：initialize、request/response、断开清理；含 `exec codex app-server` 命令拼装 | **CORE** |
| `CodexAppServerConnection.kt` | 连接抽象 | **CORE** |
| `LocalCodexAppServerConnection.kt` | 本地 Process：stdin 写、stdout 读；默认 `defaultLocalProcessStarter` → TerminalManager | **CORE** |
| `RemoteCodexBridgeConnection.kt` | 远程 bridge | **可选** |
| `CodexThreadBindingRepository.kt` | conversation ↔ thread 绑定仓储 | **CORE** |
| `CodexRemoteBridgeConfigStore.kt` | 远程配置持久化 | **可选** |
| `CodexRemoteBridgeUrls.kt` | URL 规范化 | **可选** |

Channel：

- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/ui/channel/CodexAppServerChannel.kt`

进程工厂（非 codex 包，但生命线）：

- `/root/workspace/omnibot-product/app/src/main/java/com/ai/assistance/operit/terminal/TerminalManager.kt`
  - `startLongLivedAlpineProcess`
  - `executeHiddenCommand`（Manager 用于 config/auth/probe）

工作区 cwd：

- Agent workspace / `/workspace` 类路径由 Manager 与 `AgentWorkspaceManager` 协作（高耦合边，见 09 矩阵）

### 3.4 baselib 绑定

| 符号 | 路径 | 角色 |
|------|------|------|
| `CodexThreadBinding` | `baselib/.../database/CodexThreadBinding.kt` | 实体 |
| `CodexThreadBindingDao` | `.../CodexThreadBindingDao.kt` | DAO |
| `DatabaseHelper` upsert/get/delete | `.../DatabaseHelper.kt` | 门面 |
| `AppDatabase` | 注册 entity + dao | Room |

绑定用途：App 会话 ID 与 Codex `threadId` 映射，支持 resume/list/rebind。

### 3.5 Flutter 关键类

| 文件 | 职责 | 标签 |
|------|------|------|
| `ui/lib/services/codex_app_server_service.dart` | Channel 封装 | **CORE** |
| `ui/lib/services/codex_event_reducer.dart` | 事件 → 消息/工具 UI 状态（极大） | **CORE** |
| `ui/lib/services/codex_tool_call_parser.dart` | tool 调用/ commandExecution 解析 | **CORE** |
| `ui/lib/services/codex_diff_parser.dart` | diff | **CORE** 体验 |
| `ui/lib/features/home/pages/chat/chat_page_codex.dart` | 模式逻辑、订阅、apply 事件、新建线程 | **CORE** |
| `.../cards/codex_request_card.dart` | 权限/审批卡 | **CORE** |
| `.../cards/codex_diff_viewer.dart` | diff 卡 | **CORE** 弱 |
| `.../codex/codex_setting_page.dart` | 设置 | **CORE** 弱 |
| `.../codex/codex_sessions_page.dart` | 会话列表 | **CORE** 弱 |
| `.../codex/codex_bridge_qr_scanner_page.dart` 等 remote UI | 远程 | **可选** |
| `chat/.../utils/codex_slash_commands.dart` | slash | **CORE** 弱 |

### 3.6 事件与 tool cards

典型回流形态（概念）：

1. app-server stdout 行 → 原生解析为 Map/JSON
2. EventChannel 推送 Flutter
3. `CodexEventReducer` 归约：assistant delta、reasoning、tool call、turn 完成/失败
4. `CodexToolCallParser` 识别 `commandExecution` 等 → 命令卡
5. 需审批时 `CodexRequestCard` / permission mode（含 autoReview 等映射）
6. 用户批准/拒绝 → MethodChannel 回 Manager → stdin 写回 app-server

**注意**：是否出现 `commandExecution` 还取决于模型是否发起 tool；Manager 侧无单独「强制 enableTools」开关。成功路径是整链完整，不是单点参数。

### 3.7 与「交互终端」边界

| | Codex Local | 交互终端 UI |
|--|-------------|-------------|
| 进程模型 | 长生命周期 Process，无 PTY 交互目标 | PTY + terminal-view |
| API | `startLongLivedAlpineProcess` / hidden command | `SessionService` / PlatformView |
| UI | 聊天卡片 | `TerminalActivity` / embedded_terminal_view |
| 标签 | **CORE** | **可选** |

二者共享 Alpine/proot **运行时资产**，但 **不是同一调用栈**。

---

## 4. 依赖

```
Flutter codex UI
  → Codex Channel
  → CodexAppServerManager/Session/Local
  → TerminalManager + EmbeddedRuntime/proot/alpine assets
  → baselib CodexThreadBinding + Conversation
  → (可选) Remote bridge + tools/codex-bridge
```

反向：

- assists / accessibility / omniinfer：**无** Codex import 硬边（旁路产品）
- terminal-view / SessionService：**无** Codex 主路径依赖

---

## 5. 耦合

| 边 | 强度 |
|----|------|
| Flutter service ↔ Channel 字符串/方法表 | **极高** |
| Manager ↔ LocalConnection ↔ TerminalManager | **极高** |
| TerminalManager ↔ init-host/proot/alpine | **极高** |
| Manager ↔ CodexThreadBindingRepository ↔ Room | **高** |
| Manager ↔ executeHiddenCommand（配置探测） | **高** |
| Manager ↔ workspace cwd | **高** |
| EventReducer ↔ app-server 事件语义 | **高**（版本漂移敏感） |
| Remote bridge | **中**（可关） |
| 设置页 / slash / diff 体验 | **中低** |

---

## 6. 标签

### CORE必留

1. `chat_page_codex` + Codex 模式枚举路径
2. `codex_app_server_service` / `codex_event_reducer` / `codex_tool_call_parser` / request card
3. `CodexAppServerChannel`
4. `CodexAppServerManager` / `Session` / `LocalCodexAppServerConnection` / Connection 接口
5. `CodexThreadBinding*` + baselib DB API
6. `TerminalManager.startLongLivedAlpineProcess` + hidden command
7. Embedded runtime：init-host、proot、alpine、codex 二进制/安装路径（见 04）
8. standard flavor 能连上的模型配置面（baselib ModelProvider/Scene）

### 可选

- `RemoteCodexBridgeConnection` + ConfigStore/Urls
- `tools/codex-bridge`（仓内工具，非 APK 模块）
- 扫码/远程 FS UI 页
- account/login ChatGPT 流增强、review/start 花活
- diff viewer 高级展示

### 可砍P0（相对 Codex 主链）

- 与 Codex **无边** 的 assists/a11y/omniinfer（整产品瘦身时）
- 交互终端 UI（保留进程工厂）

### 后置

- 把 `app/.../codex/` 抽独立 Gradle 模块
- Manager 上帝对象拆分
- 事件契约版本化 / 兼容测试

### 构建专用

- CI 里 standard debug 验证路径
- runtime 资产打包任务（`prepareEmbeddedTerminalRuntime` 等，见 04/构建脚本）

---

## 7. 拆装风险

| 动作 | 后果 |
|------|------|
| 删 Local 只留 Remote | 无 bridge 时 Codex 不可用 |
| 把 Codex 接到 SessionService PTY | 架构错误；协议面不匹配 |
| 动 Channel 方法名/事件 shape | UI 静默坏或 reducer 丢事件 |
| 砍 baselib binding 表 | resume/多会话错乱 |
| 动 `executorKey` / 长进程 API | 多实例互踩或无法保活 |
| 不装 alpine/codex 只测 UI | connect 失败；易误判为 Flutter bug |
| 假设 Manager 有 enableTools 开关 | 不存在；工具可见性靠模型 + 完整上下文 |
| 并行改 AWB 软补思路 | 用户已弃 AWB；以本栈整链为准 |

---

## 8. 与聊天壳 / 终端关系（一句话）

聊天壳是 Codex 的 **唯一一等 UI**；终端进程工厂是 Codex 的 **唯一一等 Local 运行时**；交互终端页是 **可选二号入口**，不承担 app-server 协议。

---

## 9. 关键绝对路径

### Android

- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerManager.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerSession.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/LocalCodexAppServerConnection.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/RemoteCodexBridgeConnection.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/CodexThreadBindingRepository.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/ui/channel/CodexAppServerChannel.kt`
- `/root/workspace/omnibot-product/app/src/main/java/com/ai/assistance/operit/terminal/TerminalManager.kt`

### baselib

- `/root/workspace/omnibot-product/baselib/src/main/java/cn/com/omnimind/baselib/database/CodexThreadBinding.kt`
- `/root/workspace/omnibot-product/baselib/src/main/java/cn/com/omnimind/baselib/database/CodexThreadBindingDao.kt`

### Flutter

- `/root/workspace/omnibot-product/ui/lib/services/codex_app_server_service.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_event_reducer.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_tool_call_parser.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_diff_parser.dart`
- `/root/workspace/omnibot-product/ui/lib/features/home/pages/chat/chat_page_codex.dart`
- `/root/workspace/omnibot-product/ui/lib/features/home/pages/command_overlay/widgets/cards/codex_request_card.dart`
- `/root/workspace/omnibot-product/ui/lib/features/home/pages/codex/`

### 远程工具（仓内，非 APK）

- `/root/workspace/omnibot-product/tools/codex-bridge`（若存在；可选运维面）
