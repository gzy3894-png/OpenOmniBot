# 05 — baselib / uikit

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 范围：`:baselib`、`:uikit`  
> 纪律：只读地图；**禁止改业务代码 / 改包名 / 出产品 APK**

---

## 1. 一页结论

| 问题 | 答案 |
|------|------|
| baselib 标签 | **CORE必留** |
| uikit 标签 | 全量 Omni **CORE**；Codex-only 视角 **可选**（悬浮任务 UI） |
| baselib 体量 | `src/main/java` 约 **87** 源文件；模块树约 **108** 文件（含 res/aidl/test 等，约 ~116 量级） |
| 数据库 | Room **v14**，`DatabaseHelper` + `AppDatabase`，文件名保留 `omnibot_cache_databaseoss` |
| Codex 硬依赖 baselib 什么 | `Conversation`、`CodexThreadBinding`、`DatabaseHelper`、OmniLog/配置体系 |
| Codex 是否依赖 uikit | **否**直接依赖；uikit 服务自动化悬浮/半屏 |
| 依赖方向 | baselib 在底；uikit → baselib + assists + accessibility + omniintelligence；**只有 `:app` 依赖 uikit** |
| 逆向/耦合风险 | `OkHttpManager` 反射读 `cn.com.omnimind.bot.BuildConfig.BASE_URL`（库依赖 app 包名） |

---

## 2. `:baselib` — 底座库

### 2.1 职责

Android Library（`cn.com.omnimind.baselib`），提供全 App 共享的：

1. **Application 基类** `BaseApplication`
2. **Room 本地库**（会话、Agent 条目、Codex thread 绑定、执行/收藏/学习记录等）
3. **网络** OkHttp 单例 + 拦截器
4. **LLM 配置面** provider / scene / 官方目录 / 本地 MNN 状态桥
5. **特权执行** Shizuku / Privileged shell
6. **日志与 KV** OmniLog、MMKV、RuntimeLog
7. **OCR / 权限 / 设备信息 / i18n** 等横切工具

### 2.2 入口

| 入口 | 说明 |
|------|------|
| `BaseApplication` | `baselib/src/main/java/BaseApplication.kt`；`onCreate` 挂 `instance`；app 的 `App` 继承它 |
| `DatabaseHelper` | 对象式门面，懒建 Room + Migration 1→14 |
| `OkHttpManager` | 对象式 HTTP 客户端 |
| `MMKV` | 在 `app/.../App.kt` 中 `MMKV.initialize(this)`，baselib 通过 `MMKVUtil` / 各 Store 使用 |
| AIDL | `baselib` 开 `buildFeatures.aidl`，服务 Shizuku 特权侧 |

### 2.3 实现要点（关键目录/类）

```
baselib/src/main/java/
├── BaseApplication.kt
└── cn/com/omnimind/baselib/
    ├── Constants.kt
    ├── config/          # RemoteConfigLoader, ModelSceneConfigCache
    ├── database/        # AppDatabase v14, DatabaseHelper, entities/DAOs
    ├── http/            # OkHttpManager, interceptors, bean
    ├── i18n/            # AppLocaleManager
    ├── llm/             # Provider/Scene/LocalModel bridge（核心配置面）
    ├── ocr/             # OcrUtil（ML Kit 中文）
    ├── permission/      # PermissionRequest, ServiceRequest
    ├── service/         # DeviceInfoService
    ├── shizuku/         # Capability + Privileged shell/session
    └── util/            # OmniLog, MMKVUtil, Image*, APPPackageUtil...
```

#### Room v14（`AppDatabase`）

实体（`version = 14`）：

| Entity | 用途（二次开发相关） |
|--------|----------------------|
| `Conversation` | 聊天会话壳；Codex 与 Agent 共用 |
| `AgentConversationEntry` | 会话条目（含 thread 维度） |
| `CodexThreadBinding` | **Codex threadId ↔ conversationId** 绑定（Codex CORE） |
| `Message` | 历史消息形态 |
| `TokenUsageRecord` | Token 用量 |
| `ExecutionRecord` / `FavoriteRecord` / `StudyRecord` / `CacheSuggestion` / `AppIcons` | 自动化/陪伴产品侧 |

`DatabaseHelper`：

- 库文件名：`AppDatabase.DATABASE_NAME + "oss"` → 避免升级丢本地数据
- 集中 Migration `1_2` … 直至 v14
- 对外 API：会话 CRUD、Codex binding upsert、Agent entry 统计删除等  
  （Codex 经 `CodexThreadBindingRepository` 调用）

#### 网络

- `OkHttpManager`：`api(okhttp)` + SSE + logging interceptor
- **风险点（BuildConfig 反射）**：

```kotlin
// OkHttpManager.getDefaultBaseUrl()
Class.forName("cn.com.omnimind.bot.BuildConfig")
  .getField("BASE_URL").get(null) as String
```

含义：

- baselib **硬编码依赖 app 命名空间** `cn.com.omnimind.bot`
- 改 `applicationId` / 包名 / 模块拆分时，若未同步，会静默得到空 `BASE_URL`（开源模式后端关闭）
- 同类反射还有 `StatusBarUtil` 读 `com.android.internal.R$dimen`（系统 UI，非包名风险）

#### LLM provider / scene

| 类簇 | 作用 |
|------|------|
| `ModelProviderConfigStore` / `ModelProviderModels` | 用户/内置 provider 配置 |
| `OfficialProviderRegistry` / `UrlMatcher` | 官方供应商识别 |
| `ModelSceneRegistry` + `SceneModel*Store` | 场景（chat/VLM/voice 等）绑定模型 |
| `*Provider.kt`（DeepSeek/Bailian/Moonshot/…） | 各厂适配 |
| `OpenAiWireApi` / ChatCompletion & Responses models | 线协议模型 |
| `LocalModelProviderBridge` + `MnnLocalProviderStateStore` | 本地模型开关桥；真正实现由 app flavor 注入 Delegate |
| `AiRequestLogStore` | 请求日志 |

Codex **不直接**走 baselib 的 chat completion 发 turn（走 Alpine `codex app-server`），但 **设置页/场景模型/用量** 仍落 baselib 存储。

#### Shizuku / 特权

- `ShizukuCapabilityManager`、`PrivilegedCommandExecutor`、`PrivilegedShellSessionManager`
- `OmnibotPrivilegedUserService` + AIDL
- 与自动化提权、部分系统操作相关；Codex proot 路径 **不依赖** 此栈

#### OmniLog / MMKV

- `OmniLog`：统一日志门面（全仓广泛引用）
- `MMKVUtil` + 各 Store 直用 `MMKV.defaultMMKV()`
- 初始化在 app：`MMKV.initialize(this)`

### 2.4 依赖

| 方向 | 内容 |
|------|------|
| baselib 依赖 | AndroidX、Room、OkHttp(api)、MMKV(api)、Gson(api)、Glide(api)、Kotlinx serialization、Shizuku API、ML Kit text-recognition-chinese；**无** project 模块依赖 |
| 被谁依赖 | `:accessibility`（api）、`:assists`、`:omniintelligence`、`:uikit`、`:app`；几乎所有原生业务 |

### 2.5 与 Codex / 终端 / 聊天壳

| 关系 | 说明 |
|------|------|
| Codex | **硬依赖** Room：`CodexThreadBinding` + `Conversation`；Manager 用 `DatabaseHelper`；日志 OmniLog；**无** assists/uikit import |
| 交互终端 / ReTerminal | **无** baselib 边（core 模块独立） |
| Flutter 聊天壳 | 经 app Channel 读写 baselib 会话/provider/scene/token/log |

### 2.6 标签与拆装风险

| 标签 | **CORE必留** |
|------|----------------|
| 可后置 | 垂直拆分（db / llm / privileged / util）——**后置**，非 P0 |
| 移除会炸 | 全 App 编译；Codex 会话绑定；聊天历史；模型配置；日志与 KV |
| Codex-only 注意 | 可弱化 OCR/部分陪伴表，但 **不可** 砍 DatabaseHelper / Conversation / CodexThreadBinding / OmniLog 初始化链 |

---

## 3. `:uikit` — 悬浮与任务 UI

### 3.1 职责

Android Library（`cn.com.omnimind.uikit`），把 **无障碍任务态** 可视化为：

- 悬浮球 / 猫猫对话框（Cat）
- 半屏（HalfScreen）
- 遮罩、菜单、通知、执行/陪伴 UI 事件实现

本质是 **Assists 事件 → 系统悬浮窗 UI** 的适配层。

### 3.2 入口

`UIKit.init(context, halfScreenApi)`：

1. 装配 `CatApi` / `MenuApi` / `UI*Event` 实现
2. 构造 `AssistsEventApi`（Companion / Execution / Comment / Screenshot 回调）
3. 调用 `AssistsCore.initCoreWithEvent(context, assetsEventApi, screenshotImageUIImpl)`

即：**UIKit 启动时注入 AssistsCore 事件实现**。

### 3.3 实现要点

```
uikit/.../uikit/
├── UIKit.kt                 # 唯一 init 门面
├── api/
│   ├── callback(+impl)      # Cat/HalfScreen/Menu API
│   ├── eventimpl            # Comment/Companion/Execution/Screenshot UI
│   └── uievent(+impl)       # UIBase/Chat/Task
├── loader/                  # Overlay、HalfScreen、DraggableBall、Mask
├── util/                    # Notification + receiver
└── view/                    # layout/mask/overlay/indicator/data
```

关键能力：

- `DraggableBallLoader` / `DraggableBallInstance`：悬浮球
- `FloatingHalfScreenLoader` / `HalfScreenView`：半屏
- `ScreenMaskLoader` / `BlockUserTouchMask`：任务中遮罩
- `NotificationUtil`：任务完成等通知

### 3.4 依赖

`uikit/build.gradle.kts`：

```text
implementation(:omniintelligence)
implementation(:baselib)
implementation(:assists)
implementation(:accessibility)
```

| 方向 | 内容 |
|------|------|
| uikit 依赖 | baselib + assists + accessibility + omniintelligence + AndroidX/Material/Glide |
| 被谁依赖 | **仅 `:app`**（`implementation(project(":uikit"))`） |
| 不依赖 | Flutter、ReTerminal、codex 包 |

### 3.5 与 Codex / 终端 / 聊天壳

| 关系 | 说明 |
|------|------|
| Codex | **无** import / 无调用边 |
| 自动化全量 Omni | **CORE**：任务悬浮、半屏、事件回灌 Assists |
| Codex-only 瘦身 | **可选**：可不 init UIKit，或保留模块但空事件；不挡 `codex app-server` |
| 聊天壳 | Flutter 主聊天不经 uikit；uikit 是 **原生 Overlay** 产品面 |

### 3.6 标签与拆装风险

| 场景 | 标签 |
|------|------|
| 完整 Omni（陪伴/VLM 任务 UI） | **CORE必留**（产品体验） |
| Codex chat + shell 最小闭环 | **可选** |
| 裸删 | 会炸 `App` 初始化若仍调用 `UIKit.init`；assists 事件无 UI 实现（任务可跑但无悬浮反馈） |

建议（**只建议不执行**）：Codex-first 阶段用能力开关跳过悬浮初始化，而不是先删 Gradle 模块。

---

## 4. 依赖与耦合小结

```
                    ┌─────────────┐
                    │    :app     │  唯一依赖 uikit
                    └──────┬──────┘
           ┌───────────────┼────────────────┐
           ▼               ▼                ▼
       :uikit          :assists         :baselib ◀── 底座
           │               │                ▲
           │               ▼                │
           │         :accessibility ────────┘
           │               │
           └───────────────┼──► :omniintelligence (DTO)
```

| 耦合点 | 强度 | 说明 |
|--------|------|------|
| Codex ↔ baselib DB | **极高** | ThreadBinding / Conversation |
| App ↔ baselib LLM stores | **高** | 设置页与 Agent 配置 |
| OkHttpManager ↔ app.BuildConfig | **中（脆）** | 反射包名 |
| UIKit ↔ AssistsCore | **高** | init 注入事件 |
| UIKit ↔ Codex | **无** | — |
| baselib ↔ ReTerminal | **无** | — |

---

## 5. 二次开发检查清单（只读）

- [x] baselib = CORE；Room v14 + CodexThreadBinding 已确认
- [x] OmniLog / MMKV / OkHttp / LLM scene 路径已定位
- [x] BuildConfig 反射风险已记录（改包名必碰）
- [x] uikit 仅 app 依赖；服务自动化 UI
- [x] Codex 不 import uikit/assists
- [ ] （阶段 1 后）验证不 init UIKit 时 Codex 仍可 connect——**未在本阶段执行**

---

## 6. 相关路径

| 路径 | 说明 |
|------|------|
| `/root/workspace/omnibot-product/baselib/` | 底座模块 |
| `/root/workspace/omnibot-product/uikit/` | 悬浮 UI 模块 |
| `/root/workspace/omnibot-product/baselib/src/main/java/cn/com/omnimind/baselib/database/AppDatabase.kt` | Room v14 |
| `/root/workspace/omnibot-product/baselib/src/main/java/cn/com/omnimind/baselib/database/DatabaseHelper.kt` | DB 门面 |
| `/root/workspace/omnibot-product/baselib/src/main/java/cn/com/omnimind/baselib/http/OkHttpManager.kt` | BuildConfig 反射 |
| `/root/workspace/omnibot-product/uikit/src/main/java/cn/com/omnimind/uikit/UIKit.kt` | UIKit.init |
| `/root/workspace/omnibot-product/docs/module-map/09-coupling-matrix.md` | 总矩阵 |
