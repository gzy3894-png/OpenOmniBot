# 02 — Flutter UI 模块

> 真源：`/root/workspace/omnibot-product/ui`  
> 范围：Flutter module 入口、bootstrap、GoRouter、features、会话模式、Channel 全表、PlatformView、标签与耦合  
> 纪律：只读地图；不改 `ui/` 业务代码

---

## 1. 职责

跨端 UI 壳：Riverpod + GoRouter 的产品界面，经 Method/Event Channel 调用 Android 宿主能力（聊天、Codex、权限、自动化、终端嵌入、本地模型等）。

对外能力：

- 多入口 `main_*`（standard / omniinfer / web）
- 主引擎 + `subEngineMain` 次引擎 bootstrap
- 首页/任务/记忆/我的/欢迎/本地模型等 feature 路由
- 会话模式与聊天页（含 Codex part）
- 与原生 Channel / PlatformView 的全部契约面

---

## 2. 入口

| 入口文件 | 用途 | 标签 |
|----------|------|------|
| `ui/lib/main_standard.dart` | 标准版：关本地模型 feature，调 `bootstrapMain` / `subEngineMain` | **CORE**（Codex-first） |
| `ui/lib/main_omniinfer.dart` | 本地推理版：开 local_model + 额外路由 | **可砍P0** |
| `ui/lib/main.dart` | 默认/兼容入口（薄封装） | 构建时注意 target |
| `ui/lib/web_main.dart` | Flutter web → 打进 APK `flutter_web/`（webchat） | **可选/构建强制** |
| `ui/lib/app_bootstrap.dart` | 统一初始化：Flutter 绑定、Riverpod、GoRouter、字体/主题、终端 init overlay 等 | **CORE** |

Gradle 侧 slim 指定：

```bash
-Ptarget=lib/main_standard.dart
```

模块类型：Flutter **module**（`project_type: module`）；嵌入依赖 `ui/.android`（`flutter pub get` 生成）。

---

## 3. 实现要点

### 3.1 Bootstrap

`app_bootstrap.dart` 关键步骤（概念序）：

1. 绑定 WidgetsFlutterBinding / 系统 UI
2. 解析初始 route（宿主可注入）
3. `GoRouterManager.setInitialRoute` / sub-engine 标记
4. 创建 `ProviderScope` + `GoRouter`
5. 主界面挂载；可选 embedded terminal 首次 init overlay
6. `subEngineMain`：半屏/次引擎场景，路由与主引擎隔离策略

### 3.2 GoRouter

| 文件 | 角色 |
|------|------|
| `ui/lib/core/router/go_router_manager.dart` | 创建 Router、go/push/pop、onboarding 重定向、RouteObserver |
| `ui/lib/features/home/router_config.dart` | 首页树 |
| `ui/lib/features/*/router_config.dart` 或 `local_model_router_config.dart` | feature 路由片段 |
| `AppRouterConfig.configure(extraHomeRoutes/extraWelcomeRoutes)` | omniinfer 注入本地模型路由 |

导航纪律：

- 未完成 onboarding → 强制 welcome
- 已完成 → welcome 重定向 home
- 次引擎可限制路由集合（半屏/悬浮场景）

### 3.3 Features 目录

```
ui/lib/features/
  home/          # 聊天主战场、Codex 页、设置、命令卡片
  task/          # 任务/自动化相关 UI
  memory/        # 记忆
  my/            # 我的/设置聚合
  welcome/       # 引导/onboarding
  local_model/   # 本地模型（standard stub / omniinfer full）
  load/          # 加载态
```

Home 内与 Codex/聊天强相关：

```
features/home/pages/chat/
  chat_page.dart              # 主聊天 Stateful，mode 分发
  chat_page_codex.dart        # part：Codex 模式全逻辑
  chat_page_openclaw.dart     # OpenClaw
  ...
features/home/pages/codex/
  codex_setting_page.dart
  codex_sessions_page.dart
  codex_bridge_qr_scanner_page.dart
  codex_remote_*              # 远程桥文件/目录
features/home/pages/command_overlay/widgets/cards/
  codex_request_card.dart
  codex_diff_viewer.dart
```

### 3.4 会话模式

两套枚举，勿混：

**A. 持久化会话模式** — `ui/lib/models/conversation_model.dart`

```dart
enum ConversationMode {
  normal('normal'),
  chatOnly('chat_only'),
  openclaw('openclaw'),
  subagent('subagent'),
  codex('codex'),
}
```

| 值 | 存储键 | UI 文案倾向 | 标签 |
|----|--------|-------------|------|
| `normal` | `normal` | 普通（Agent 工具循环） | **CORE**（产品默认之一） |
| `chatOnly` | `chat_only` | 纯聊天 | **可选** |
| `openclaw` | `openclaw` | OpenClaw | **可选** |
| `subagent` | `subagent` | SubAgent | **可选** |
| `codex` | `codex` | Codex | **CORE**（Codex-first） |

**B. 聊天页运行时 mode** — `chat_page.dart`

```dart
enum ChatPageMode { normal, openclaw, codex }
```

- 页内按 mode 隔离草稿、附件、消息列表 navigator、island 层
- Codex 细节在 `chat_page_codex.dart` part
- `ConversationMode` ↔ `ChatPageMode` 在切换会话/新建线程时映射

### 3.5 Channel 全表（宿主注册 ↔ Flutter 使用）

宿主注册中枢：`app/.../ui/channel/ChannelManager.kt`  
Flutter 侧多在 `ui/lib/services/*`。

| Channel 名（Android） | 宿主类 | Flutter 主要消费 | 用途 | 标签 |
|----------------------|--------|------------------|------|------|
| `cn.com.omnimind.bot/AssistCoreEvent` | `AssistsCoreChannel` | `assists_core_service.dart` | 自动化/任务/VLM 事件与方法 | **可砍P0*** |
| `cn.com.omnimind.bot/CodexAppServer` + `.../CodexAppServerEvents` | `CodexAppServerChannel` | `codex_app_server_service.dart` | Codex 连接/线程/turn/事件流 | **CORE** |
| `cn.com.omnimind.bot/SpecialPermissionEvent` + `.../SpecialPermissionEvents` | `SpecialPermissionChannel` | `special_permission.dart` / `permission_service.dart` | 特殊权限申请与状态流 | **CORE**（权限壳）/ 部分自动化权限可砍 |
| `cn.com.omnimind.bot/CacheDataEvent` | `CacheChannel` | `cache_service.dart` / `cache.dart` | 缓存读写 | **CORE** |
| `cn.com.omnimind.bot/network` | `HttpChannel` | `http_handler` / 模型请求 | 原生 HTTP 栈 | **CORE***（实现落在 assists，禁裸删） |
| `cn.com.omnimind.bot/overlay` | `OverlayChannel` | `overlay_service.dart` | 悬浮宠/遮罩 | **可选** |
| `cn.com.omnimind.bot/AgentBrowserSession` | `BrowserSessionChannel` | `agent_browser_session_service.dart` | Agent 浏览器会话 | **可选**（Agent） |
| `cn.com.omnimind.bot/app_state` | `AppStateChannel` | `app_state_service.dart` | 前后台/应用状态 | **CORE** |
| `cn.com.omnimind.bot/app_update` | `AppUpdateChannel` | `app_update_service.dart` | OTA 检查 | **可选** |
| `cn.com.omnimind.bot/file_save` | `FileSaveChannel` | 导出/保存 | 文件保存 SAF | **可选/弱 CORE** |
| `cn.com.omnimind.bot/pdf_preview` | `PdfPreviewChannel` | `pdf_preview_service.dart` | PDF 预览 | **可选** |
| `cn.com.omnimind.bot/StorageUsage` | `StorageUsageChannel` | `storage_usage_service.dart` | 存储占用 | **可选** |
| `cn.com.omnimind.bot/McpServer` | `McpServerChannel` | `mcp_server_service.dart` | 本地 MCP | **可选** |
| `cn.com.omnimind.bot/RemoteMcpConfig` | `RemoteMcpConfigChannel` | `remote_mcp_config_service.dart` | 远程 MCP 配置 | **可选** |
| `cn.com.omnimind.bot/ImChannel` | `ImChannel` | `im_channel_service.dart` | IM 通道 | **可选** |
| `cn.com.omnimind.bot/ScreenDialogEvent` | `ScreenDialogChannel` | `screen_dialog_service.dart` | 屏上对话框 | **可选** |
| `cn.com.omnimind.bot/VoicePlayback` + Events | `VoicePlaybackChannel` | 语音播放 | **可选** |
| `device_info` | `DeviceInfoChannel` | `device_service.dart` | 设备信息 | **CORE** 弱 |
| `ui_router_channel` | `UIRouterChannel` | 路由桥 | 原生→Flutter 跳转 | **CORE** 弱 |
| `hide_from_recents` | `HideFromRecentsChannel` | `hide_from_recents_service.dart` | 最近任务隐藏 | **可选** |
| `LocalModelFeature.setChannel` / Mnn | flavor 侧 `MnnLocalModelsChannel` 等 | `mnn_local_models_service.dart` | 本地模型 | **可砍P0** |

\* `HttpController` 位于 assists，被网络 channel 复用——Codex-only 砍 assists 前必须先迁出。

### 3.6 PlatformViews

| viewType | Factory | Flutter | 标签 |
|----------|---------|---------|------|
| `cn.com.omnimind.bot/agent_browser_view` | `AgentBrowserPlatformViewFactory` | `agent_browser_session_service.dart` / chat browser overlay | **可选**（Agent 浏览） |
| `cn.com.omnimind.bot/embedded_terminal_view` | `EmbeddedTerminalPlatformViewFactory` | embedded terminal widgets | **可选**（交互终端 UI） |

注册点：`MainActivity` configureFlutterEngine。  
**注意**：Codex shell **不**依赖 embedded_terminal PlatformView；它走 Process 工厂（见 03/04）。

### 3.7 Codex 相关 Flutter 服务（高信号）

| 文件 | 角色 | 标签 |
|------|------|------|
| `ui/lib/services/codex_app_server_service.dart` | Method/Event 封装，connect/thread/turn/API | **CORE** |
| `ui/lib/services/codex_event_reducer.dart` | app-server 事件 → UI 状态（大体量） | **CORE** |
| `ui/lib/services/codex_tool_call_parser.dart` | tool 调用解析 / commandExecution 卡片数据 | **CORE** |
| `ui/lib/services/codex_diff_parser.dart` | diff 展示 | **CORE** 弱 / 体验 |
| `ui/lib/features/home/pages/chat/chat_page_codex.dart` | 聊天页 Codex 模式 | **CORE** |
| `.../command_overlay/.../codex_request_card.dart` | 审批/请求卡片 | **CORE** |

### 3.8 其它高频 services（按标签）

| 服务 | 标签 |
|------|------|
| `conversation_service` / `conversation_history_service` | **CORE** |
| `model_provider_config_service` / `scene_model_config_service` | **CORE**（配置） |
| `permission_*` / `special_permission` | **CORE** 壳；自动化权限项可砍 |
| `assists_core_service` | **可砍P0*** |
| `app_update_service` / `im_channel_service` / `mcp_*` / `overlay_service` | **可选** |
| `mnn_local_models_service` | **可砍P0** |
| `chat_terminal_environment_service` | 终端环境探测（与 runtime 弱耦）**CORE** 弱 |

---

## 4. 依赖

| 方向 | 内容 |
|------|------|
| UI → 宿主 | 几乎所有设备能力经 Channel / PlatformView |
| UI → 包 | Flutter SDK、Riverpod、GoRouter、自有 `features/services/models` |
| 被依赖 | `:app` `implementation(project(":flutter"))`；web 产物被 app preBuild 吸入 assets |
| 数据 | 会话/消息多经 baselib Channel/缓存，而非纯 Dart 本地 DB |

---

## 5. 耦合

| 耦合点 | 强度 | 说明 |
|--------|------|------|
| Channel 契约双端字符串 | **极高** | 改名必须双端同步；无 codegen 契约 |
| `chat_page` 巨石 + parts | **极高** | normal/openclaw/codex 状态机交织 |
| Codex reducer/parser 体量 | **高** | 事件语义与原生 Manager 输出强绑定 |
| Http/Assists | **高** | 聊天发模型请求不纯 Dart |
| GoRouter + 宿主 UIRouter | **中** | 原生可强行跳 Flutter 路由 |
| local_model 路由注入 | **中** | 仅 omniinfer；standard 应无路由 |
| PlatformView 生命周期 | **中** | 与 Activity/Engine 绑定；与 Codex 无硬依赖 |

**总评：对 app channels 高度耦合** —— Flutter 不是可独立发布的完整产品，而是宿主的 UI 进程面。

---

## 6. 标签（Codex-first）

### CORE必留

- `main_standard.dart` + `app_bootstrap` + GoRouter 主链
- `features/home` 聊天壳 + `ConversationMode.codex` 路径
- `codex_app_server_service` / `codex_event_reducer` / `codex_tool_call_parser` / `codex_request_card`
- 会话/模型配置/权限基础 channel 消费
- Cache / network（迁出后）/ app_state / device_info

### 可选

- openclaw / subagent / chat_only 产品模式
- IM、MCP UI、OTA、overlay 宠物、语音、PDF、远程 Codex UI 页
- embedded_terminal / agent_browser PlatformView
- web_main / webchat 资产（若证伪 MCP 静态依赖可后置摘强制 preBuild）

### 可砍P0

- local_model feature + `main_omniinfer` + Mnn channels
- assists 驱动的 task/VLM UI（保留聊天所需 HTTP 面）
- 强制无障碍引导文案/流程（改为可选）

### 后置

- 拆分 `chat_page` 巨石
- Channel 契约 codegen / 单测
- `main.dart` 默认改 standard

---

## 7. 拆装风险

| 动作 | 风险 |
|------|------|
| 只改 Flutter channel 名 | 原生静默 no-op / MissingPlugin |
| 删 `chat_page_codex` 却留入口 | 运行时 mode 崩溃 |
| 砍 assists 服务调用而不改 UI | 任务页/部分首页入口红屏 |
| 去掉 web_main 构建 | 现 preBuild 失败；或 webchat 空白 |
| standard 误用 omniinfer routes | 缺 channel 实现 |
| 以为砍 terminal PlatformView 等于砍 Codex | **错误**——两栈分离 |

---

## 8. 与 Codex / 终端 / 聊天壳

```
用户 ChatPageMode.codex
  → codex_app_server_service
  → CodexAppServer Channel
  → (原生，见 03)
  → EventChannel 回流
  → codex_event_reducer + tool cards
  → 聊天列表/审批卡

交互终端 PlatformView / TerminalActivity
  → 独立可选 UI（见 04）
  → 不参与 app-server JSONL 主路径
```

---

## 9. 关键绝对路径

- `/root/workspace/omnibot-product/ui/lib/main_standard.dart`
- `/root/workspace/omnibot-product/ui/lib/main_omniinfer.dart`
- `/root/workspace/omnibot-product/ui/lib/web_main.dart`
- `/root/workspace/omnibot-product/ui/lib/app_bootstrap.dart`
- `/root/workspace/omnibot-product/ui/lib/core/router/go_router_manager.dart`
- `/root/workspace/omnibot-product/ui/lib/models/conversation_model.dart`
- `/root/workspace/omnibot-product/ui/lib/features/home/pages/chat/chat_page.dart`
- `/root/workspace/omnibot-product/ui/lib/features/home/pages/chat/chat_page_codex.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_app_server_service.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_event_reducer.dart`
- `/root/workspace/omnibot-product/ui/lib/services/codex_tool_call_parser.dart`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/ui/channel/ChannelManager.kt`
