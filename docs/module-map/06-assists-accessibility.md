# 06 — assists / accessibility

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 范围：`:accessibility`、`:assists`，以及 app 侧伪装服务 / Flutter `AssistCoreEvent` / `HttpController` 复用面  
> 纪律：只读地图；**禁止改业务代码**

---

## 1. 一页结论

| 问题 | 答案 |
|------|------|
| 产品定位 | **手机 UI 自动化**（无障碍手势 + 截图 + VLM/任务状态机） |
| Codex 直接 import assists/accessibility？ | **否**（`app/.../codex/*` 零匹配） |
| Codex-only 能否砍？ | 标签 **可砍P0**，但 **禁止裸删 `:assists`** |
| 不能裸删的原因 | `HttpController`（~**3752** 行）被 **Agent 聊天 / 模型请求** 复用，且 Flutter `AssistCoreEvent` 上帝通道挂在 app `AssistsCoreManager` |
| Flutter 通道 | `cn.com.omnimind.bot/AssistCoreEvent`；Channel 侧 **~110** method 分支；Manager **~7042** 行 / **~153** fun |
| 伪装 | `SelectToSpeakService` 继承 `AssistsService`，Manifest 声明为 Google SelectToSpeak |
| 与 Codex 生命线 | **旁路**：自动化高耦合栈 ≠ Codex Process 工厂 |

---

## 2. `:accessibility` — 无障碍与截图

### 2.1 职责

底层 **AccessibilityService + 手势/节点操作 + 截图/MediaProjection**。不负责任务编排，只提供「能点、能滑、能截」的宿主能力。

### 2.2 入口

| 入口 | 路径 | 说明 |
|------|------|------|
| `AssistsService` | `accessibility/.../service/AssistsService.kt` | `AccessibilityService` + LifecycleOwner；`instance` 单例 |
| 伪装服务 | `app/.../selecttospeak/SelectToSpeakService.kt` | `class SelectToSpeakService : AssistsService()` |
| Manifest | `app/src/main/AndroidManifest.xml` | 注册伪装服务；`service_config.xml` + `is_accessibility_tool` |
| `OmniAction` | `action/OmniAction.kt` | 点击/长按/滑动/输入/启动应用等 |
| 截图 | `OmniScreenshot` / `OmniScreenshotAction` / `OmniCaptureAction` / `ScreenCaptureManager` | 截图链路 |
| 前台 | `MediaProjectionForegroundService` | MediaProjection 保活 |

### 2.3 实现要点

```
accessibility/.../
├── action/
│   ├── OmniAction.kt              # 手势与节点操作核心
│   ├── OmniCaptureAction.kt
│   ├── OmniScreenshotAction.kt
│   ├── ScreenCaptureManager.kt
│   ├── ScreenStateReceiver.kt
│   └── *ScrollDirection / LaunchRequest
├── screenshot/OmniScreenshot.kt
├── service/
│   ├── AssistsService.kt
│   ├── AssistsServiceListener.kt
│   └── MediaProjectionForegroundService.kt
└── util/  ImageScreenshotUtils, ScreenStateUtil, XmlTreeUtils
```

要点：

- `OmniAction` 依赖 `AssistsService` + baselib（`APPPackageUtil` 隐私黑名单、`OmniLog`、厂商适配）
- 隐私：未授权包可抛 `PrivacyBlockedException`
- XML 树：`XmlTreeUtils` 供上层 detection / VLM 上下文

### 2.4 依赖

| 方向 | 内容 |
|------|------|
| accessibility → | `api(project(":baselib"))` |
| 被谁依赖 | `:assists`（`api`）、`:uikit`、`:app`（Manifest/服务） |

### 2.5 标签

| 场景 | 标签 |
|------|------|
| 全量自动化 Omni | **CORE** |
| Codex-only | **可砍P0**（与 SelectToSpeak + MediaProjection 一并） |
| 拆装风险 | 砍后陪伴/VLM/学习任务不可用；**不影响** Codex Local 长进程 |

---

## 3. `:assists` — 任务 SDK / VLM / HttpController

### 3.1 职责

无障碍之上的 **任务状态机 + VLM 操作环 + 视觉 detection + HTTP/LLM 客户端巨石**。

对外门面：`AssistsCore`（object）。

### 3.2 入口

| 入口 | 说明 |
|------|------|
| `AssistsCore.initCore` / `initCoreWithEvent` | 建 `StateMachine`，可选注入 UI 事件（uikit） |
| `AssistsCore.startTask` / cancel* / VLM 输入 | 任务生命周期 API |
| `TaskManager` | 任务实例管理（~401 行） |
| `StateMachine` | 状态机（~205 行） |
| `HttpController` | **巨石** LLM/VLM HTTP（~3752 行） |
| app `AssistsCoreManager` | Flutter 通道真正的上帝对象（在 **app** 模块，不在 assists 源码树） |
| app `AssistsCoreChannel` | MethodChannel 分发（~389 行，**~110** 分支） |

### 3.3 实现要点

```
assists/.../assists/
├── AssistsCore.kt              # 对外 SDK
├── StateMachine.kt
├── TaskManager.kt
├── api/                        # bean / enums / eventapi / interfaces
├── controller/
│   ├── accessibility/          # AccessibilityController, ScreenStableDetector
│   └── http/HttpController.kt  # ★ 巨石，Agent 复用
├── detection/                  # OpenCV 初始化 + popup/loading/icon/structure...
├── openclaw/                   # DeviceIdentity / TokenStore（旁路集成）
├── task/
│   ├── companion|learn|scheduled|ChatTask
│   └── vlmserver/              # VLMClient, ActionExecutor, OperationService...
└── util/
```

#### 任务类型

| 类型 | 类 | 说明 |
|------|-----|------|
| Companion | `CompanionTask` | 陪伴/建议 |
| Execution / VLM | `VLMOperationTask` + `vlmserver/*` | 视觉操作环 |
| Scheduled | `ScheduledTask` + WorkManager workers | 定时 VLM |
| Chat | `ChatTask` | 聊天任务形态（与 Flutter Agent 路径交织） |

#### VLM 环（摘要）

`VLMOperationService` → `VLMClient` / stream → `ActionExecutor` / `AndroidDeviceOperator` → `OmniAction` / 截图 → detection（loading/popup/stability）→ 循环。

#### `HttpController`（拆装关键）

- `object HttpController`，**~3752 行**
- 能力面（抽样）：
  - Chat Completions / Anthropic / Responses 转换与 listener wrap
  - `postLLMStreamRequest*` / `postChatCompletionsStreamRequest`
  - `postVLMRequest` / `postVLMStreamRequest*`
  - `postSceneChatCompletion*`
  - `checkVlmModelAvailability` / `checkProviderModelAvailability` / `fetchProviderModels`
  - OpenClaw chat completions 旁路
- **被 Agent 聊天与模型配置探测复用**，不必然经过无障碍手势
- 依赖 baselib：`OkHttpManager`、provider/scene stores、`LocalModelProviderBridge` 等

> **可砍P0 前置条件**：先把 `HttpController`（及必要的模型探测 API）**迁出**到 baselib 或独立 `:llm-http` 模块，再削 VLM/detection/companion。

#### Detection

OpenCV + 多 detector（关闭按钮、弹窗、白屏/骨架屏 loading、图标模板、页面结构、视觉/XML 稳定性）。体量大、仅服务自动化；Codex 无边。

### 3.4 依赖

`assists/build.gradle.kts`：

```text
api(project(":accessibility"))
implementation(project(":baselib"))
api(project(":omniintelligence"))
+ OpenCV, WorkManager, BouncyCastle, serialization...
```

| 方向 | 内容 |
|------|------|
| assists → | accessibility(api)、baselib、omniintelligence(api) |
| 被谁依赖 | `:uikit`、`:app`（直接 `implementation(:assists)`） |
| 不依赖 | ReTerminal、codex 包、omniinfer-server |

### 3.5 Flutter `AssistCoreEvent`（~110 methods）

| 层 | 位置 | 规模 |
|----|------|------|
| Dart 服务 | `ui/lib/services/assists_core_service.dart`（~1672 行） | 多服务复用同一 channel 名 |
| 其它 Dart 调用方 | conversation / token_usage / runtime_log / quick_log / ai_request_log / workspace_memory 等 | 聊天壳广泛依赖 **同一通道名** |
| Kotlin Channel | `app/.../AssistsCoreChannel.kt` | **~110** `->` 分支 |
| Kotlin Manager | `app/.../AssistsCoreManager.kt` | **~7042** 行，**~153** fun |

含义：

- 通道名是 **历史上帝通道**：不仅「无障碍任务」，还承载会话 CRUD、模型 provider、skill 安装、日志、剪贴板等
- Codex 有 **独立** Channel（`CodexAppServer*`），但 UI 设置/会话列表仍可能间接触碰 AssistCoreEvent 上的 **非 a11y** API
- 因此「砍 assists」必须同时规划 **Channel 拆分**，否则聊天壳编译/运行仍绑死

### 3.6 SelectToSpeak 伪装（app）

| 项 | 值 |
|----|-----|
| 类 | `com.google.android.accessibility.selecttospeak.SelectToSpeakService` |
| 继承 | `AssistsService` |
| 目的 | 注释写明：绕过微信等反无障碍检测 |
| Proguard | `-keep` 该类 |
| flavor | `is_accessibility_tool=true`（develop/production 均见） |

标签：自动化产品 **CORE 配套**；Codex-only **可砍P0**（Manifest + 引导一起下）。

---

## 4. 耦合矩阵（本切片）

图例：● 硬 / ◎ 软 / ○ 无 / ✂ Codex-only 可砍方向

| From \ To | baselib | accessibility | assists | uikit | omniintelligence | app Manager/Channel | Flutter 聊天壳 | Codex 包 |
|-----------|---------|---------------|---------|-------|------------------|---------------------|----------------|----------|
| accessibility | ● | — | ○ | ○ | ○ | ◎ 服务注册 | ○ | ○ |
| assists | ● | ● | — | ○（反向被 init） | ● DTO | ◎ 被 Manager 调 | ◎ 经 Channel | ○ |
| uikit | ● | ● | ● init | — | ● | ◎ App init | ○ | ○ |
| HttpController | ● | ○ | 所在模块 | ○ | ◎ | ● Agent 复用 | ● 模型/流式 | ○ |
| SelectToSpeak | ○ | ● 继承 | ○ | ○ | ○ | ● Manifest | ◎ 权限引导 | ○ |
| Codex `codex/*` | ● DB | ○ | ○ | ○ | ○ | ○ | ◎ 独立 Channel | — |

### 调用边（自动化生命线）

```
Flutter AssistCoreEvent
  → AssistsCoreChannel (~110)
  → AssistsCoreManager (~7k)
      ├─ 任务/VLM → AssistsCore → StateMachine → Task* → OmniAction / 截图
      ├─ LLM/VLM HTTP → HttpController → OkHttpManager / scene stores
      └─ 会话/配置/skill/log（大量非 a11y API）
UIKit.init → AssistsCore.initCoreWithEvent → 悬浮 UI 事件
```

### 与 Codex 对照

```
Flutter ChatPage(codex)
  → CodexAppServerChannel
  → CodexAppServerManager/Session/Local
  → TerminalManager 长进程
  → 无 assists import
```

---

## 5. 标签与拆装风险

| 组件 | 标签 | 风险 |
|------|------|------|
| `:accessibility` + SelectToSpeak + MediaProjection | **可砍P0**（Codex-only） | 自动化全灭；需改 Manifest/引导 |
| assists detection/VLM/companion/scheduled | **可砍P0** | 同上；OpenCV 包体 |
| `HttpController` 所在位置 | **CORE 能力，错放在 assists** | **不能随模块裸删** |
| `AssistsCoreManager` / Channel 上帝对象 | **CORE 聊天壳**（后置拆分） | 拆分前删除 assists 会连环炸 |
| omniintelligence DTO | **后置**（随 assists） | 见 `07` |

### 建议顺序（只建议，不执行）

1. **迁出** `HttpController` + 模型探测 API → baselib 或新模块  
2. **拆分** AssistCoreEvent：会话/配置 vs 任务/VLM  
3. 能力开关：无障碍改为可选，不阻断 Codex  
4. 空实现/剔除 VLM、detection、Companion、OpenCV  
5. 去 SelectToSpeak Manifest + MediaProjection  
6. 削 uikit 任务悬浮  
7. 编译面干净后再考虑 `settings` 去模块  

每步回归：**Codex connect + shell + 基础聊天**。

---

## 6. 相关路径

| 路径 | 说明 |
|------|------|
| `/root/workspace/omnibot-product/accessibility/` | 无障碍模块 |
| `/root/workspace/omnibot-product/assists/` | 任务/VLM/HttpController |
| `/root/workspace/omnibot-product/assists/.../http/HttpController.kt` | 巨石 HTTP |
| `/root/workspace/omnibot-product/app/.../AssistsCoreManager.kt` | 上帝 Manager |
| `/root/workspace/omnibot-product/app/.../AssistsCoreChannel.kt` | ~110 methods |
| `/root/workspace/omnibot-product/app/.../selecttospeak/SelectToSpeakService.kt` | 伪装服务 |
| `/root/workspace/omnibot-product/ui/lib/services/assists_core_service.dart` | Flutter 侧 |
| `/root/workspace/omnibot-product/docs/module-map/09-coupling-matrix.md` | 总矩阵阶段 4 |
