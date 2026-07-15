# 01 — Gradle / App 壳

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 范围：settings 模块图、root build/props、`:app` Application/Activity、Manifest、依赖与瘦身构建路径  
> 纪律：只读地图；本阶段不改业务代码 / 不改包名 / 不出 fork 产品 APK

---

## 1. 职责

Android 宿主壳：把 Flutter UI、自动化、终端运行时、Codex、IM/MCP 等能力装配进单一 `applicationId` 的 APK。

对外能力：

- Gradle 多模块装配与 flavor 矩阵
- `Application` / 启动 Activity / FlutterEngineGroup
- Method/Event Channel 总线（`ChannelManager`）
- Manifest 组件与权限总表
- 标准瘦身 debug 出包路径（不依赖 omniinfer submodule）

---

## 2. 入口

| 层级 | 路径 / 标识 |
|------|-------------|
| Gradle 根工程名 | `OmnibotApp`（`settings.gradle.kts`） |
| Application | `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/App.kt` |
| 冷启动 | `LauncherActivity` → 首次终端环境准备 → 进入主界面 |
| 主 Flutter 壳 | `MainActivity`（注册 Channel + PlatformView） |
| Flutter 入口（slim） | `-Ptarget=lib/main_standard.dart` |
| Flutter 入口（本地模型） | `-Ptarget=lib/main_omniinfer.dart` |
| 版本 | `applicationId=cn.com.omnimind.bot`；`versionName=0.5.6.4`；`versionCode=1` |
| Debug 包名 | `cn.com.omnimind.bot.debug`（`applicationIdSuffix=.debug`） |

关键启动行为（`App.kt`）：

- `MMKV.initialize` / `DatabaseHelper.init` / `ModelSceneRegistry.init`
- `FlutterEngineGroup` + 主引擎缓存 + `subEngineMain` 次引擎
- 隐私同意后 SDK/后置初始化

---

## 3. 实现要点

### 3.1 `settings.gradle.kts` 模块图

固定 include：

| 模块 | 物理目录 | 标签 |
|------|----------|------|
| `:app` | `app/` | **CORE** |
| `:flutter` | `ui/` via `ui/.android/include_flutter.groovy` | **CORE** |
| `:baselib` | `baselib/` | **CORE** |
| `:uikit` | `uikit/` | **可选**（悬浮/半屏任务 UI） |
| `:assists` | `assists/` | **可砍P0***（先迁 HttpController） |
| `:accessibility` | `accessibility/` | **可砍P0** |
| `:omniintelligence` | `omniintelligence/` | **后置**（随 assists） |
| `:core:main` | `ReTerminal/core/main` | **CORE**（进程工厂/runtime） |
| `:core:components` | `ReTerminal/core/components` | **可选/UI** |
| `:core:resources` | `ReTerminal/core/resources` | **CORE/资源** |
| `:core:terminal-emulator` | `ReTerminal/core/terminal-emulator` | **可选**（PTY 栈） |
| `:core:terminal-view` | `ReTerminal/core/terminal-view` | **可选**（交互终端 UI） |

条件 include：

- `:omniinfer-server` ← `third_party/omniinfer/android/omniinfer-server`
- 仅当 marker `build.gradle.kts` 存在，**或**任务名含 `omniinfer` / 裸 `build`/`assemble`/`check`/`test` 时强制要求 submodule
- **standard 专用任务不会强制拉 omniinfer**

Flutter 嵌入门槛：

- `apply(from = ui/.android/include_flutter.groovy)`
- 工作树常缺 `ui/.android`，需 `cd ui && flutter pub get` 生成
- 缺文件时 settings 直接失败（不是 app 业务问题）

### 3.2 Root build / properties

| 文件 | 作用 |
|------|------|
| `/root/workspace/omnibot-product/build.gradle.kts` | 根插件/公共配置 |
| `/root/workspace/omnibot-product/gradle.properties` | JVM、AndroidX、`OMNIBOT_BASE_URL`、`OMNIBOT_UPDATE_WORKER_URL`、镜像/API 可选字段、omniinfer QNN 开关 |
| `/root/workspace/omnibot-product/split_assets.gradle` | **遗留未用**；拆装清理可后置，不影响当前 slim 构建 |

`gradle.properties` 要点：

- `OMNIBOT_BASE_URL=` 默认空（开源/自建）
- `OMNIBOT_UPDATE_WORKER_URL=https://omni.1775885.xyz`
- `OMNIBOT_IMAGE_*` 可选；密钥勿进 git
- `omniinfer.backend.executorch_qnn=true` 仅 omniinfer 相关

### 3.3 `:app` flavor 矩阵

维度：`version` × `edition`

| Flavor | Dimension | 关键 BuildConfig / 行为 |
|--------|-----------|------------------------|
| `develop` | version | `BASE_URL` / `APP_UPDATE_WORKER_URL`；accessibility tool |
| `production` | version | 同上；release 签名 |
| `standard` | edition | `LOCAL_MODEL_FEATURE_ENABLED=false`；`APP_EDITION=standard` |
| `omniinfer` | edition | `LOCAL_MODEL_FEATURE_ENABLED=true`；挂 `:omniinfer-server`；额外 assets/sourceSet |

其它工程约束：

- `minSdk=29` / `targetSdk=34` / `compileSdk=36`
- ABI：`arm64-v8a` only
- Release：V2+V3，关 V1；需 `OMNI_RELEASE_*`
- `preBuild` **强制依赖** Flutter web 产物：`flutter build web --target lib/web_main.dart --base-href /webchat/` → assets `flutter_web/`

### 3.4 Activity / 壳类

| 类 | 路径 | 角色 | 标签 |
|----|------|------|------|
| `App` | `app/.../bot/App.kt` | Application、EngineGroup、DB/SDK 初始化 | **CORE** |
| `LauncherActivity` | `app/.../activity/LauncherActivity.kt` | 启动分流、首次 embedded terminal 准备 | **CORE** |
| `MainActivity` | `app/.../activity/MainActivity.kt` | FlutterActivity、Channel/PlatformView 注册 | **CORE** |
| `TerminalActivity` | `app/.../activity/TerminalActivity.kt` | 交互终端页 | **可选** |
| `QuickLog*Activity` | `app/.../activity/` | 速记入口/Widget 桥 | **可选** |
| `McpFileReceiverActivity` | `app/.../activity/` | MCP/分享文件接收 | **可选** |
| `ClipboardHelperActivity` / `BrowserFileChooserRequestActivity` | 透明辅助 | **可选** |

PlatformView（在 `MainActivity` 注册）：

- `cn.com.omnimind.bot/agent_browser_view`
- `cn.com.omnimind.bot/embedded_terminal_view`

### 3.5 Manifest 组件分组

路径：`/root/workspace/omnibot-product/app/src/main/AndroidManifest.xml`

| 分组 | 代表组件 | 标签 |
|------|----------|------|
| Launcher | `LauncherActivity`、`MainActivity` | **CORE** |
| a11y 伪装 | `com.google.android.accessibility.selecttospeak.SelectToSpeakService`（绕过部分 App 反无障碍） | **可砍P0** |
| FGS | `OmniForegroundService`、`MediaProjectionForegroundService`、Agent 闹钟/音乐、`ImChannelForegroundService` | CORE 仅部分 / 多数 **可选** |
| IM | `ImChannelForegroundService` + Boot receiver | **可选** |
| QuickLog | Widget Provider/Service + 入口 Activity | **可选** |
| MCP | `McpFileReceiverActivity` + channel | **可选** |
| Terminal | `TerminalActivity` + runtime assets | 进程工厂 **CORE** / UI **可选** |
| Shizuku | `rikka.shizuku.ShizukuProvider` | **可选**（特权路径） |
| FileProvider | `${applicationId}.fileprovider` | **CORE**（安装/导出） |

权限侧重点：网络、通知、FGS、悬浮窗、QUERY_ALL_PACKAGES、忽略电池优化等。Codex shell 最小闭环不依赖无障碍/MediaProjection。

### 3.6 依赖图（`:app`）

```
:app
  ├─ :flutter          CORE
  ├─ :baselib          CORE
  ├─ :core:main        CORE (runtime/proot/init-host)
  ├─ :core:terminal-emulator / :core:terminal-view   可选(PTY UI)
  ├─ :uikit            可选
  ├─ :assists          可砍P0*（HttpController 被聊天复用，禁裸删）
  └─ omniinferImplementation(:omniinfer-server)  可选 edition
```

`accessibility` / `omniintelligence` 多经 `assists`/`uikit` 间接进入，不一定在 app 的 `dependencies {}` 顶层直连。

Channel 总线：`app/.../ui/channel/ChannelManager.kt` 在 `configureFlutterEngine` 挂载全表 Channel（见 `02-flutter-ui.md`）。

App 内逻辑 monorepo 包（**Gradle 边界 ≠ 包边界**）：

```
app/src/main/java/cn/com/omnimind/bot/
  App.kt, activity/, agent/, codex/, im/, localmodel/, manager/,
  mcp/, prompt/, quicklog/, share/, terminal/, termux/, ui/,
  update/, util/, vlm/, voice/, webchat/, workspace/
+ com.ai.assistance.operit.terminal.TerminalManager
+ SelectToSpeak 伪装包
```

---

## 4. 依赖（谁依赖谁）

| 方向 | 内容 |
|------|------|
| app → | flutter, baselib, core:*, uikit, assists, (omniinfer) |
| 被依赖 | 无其它 Gradle 模块依赖 `:app`（它是叶宿主） |
| 构建依赖 | Flutter SDK + 生成 `ui/.android`；web 工具链（preBuild）；NDK（工程钉死版本，standard 亦受影响） |
| 运行依赖 | 主引擎 + Channel；Codex 另依赖 Alpine/proot 资产（见 03/04） |

---

## 5. 耦合

| 耦合点 | 强度 | 说明 |
|--------|------|------|
| settings ↔ `ui/.android` | **极高** | 无 include_flutter.groovy 无法配置工程 |
| preBuild ↔ Flutter web | **高** | 任意 assemble 都先 web 构建；MCP/webchat 静态资源 |
| app 巨石包 | **高** | codex/agent/terminal/mcp/im 全在 `:app`，模块边界不等于包边界 |
| ChannelManager 上帝注册表 | **高** | UI 功能几乎全走 channel |
| flavor edition ↔ omniinfer submodule | **中** | 裸 `assemble` 会逼 submodule；standard 任务可避 |
| SelectToSpeak Manifest | **中** | 与自动化产品绑定；Codex-only 可砍但要改 Manifest/引导 |

---

## 6. 标签

| 切片 | 标签 |
|------|------|
| settings 模块图 + `:app` 壳 | **CORE必留** |
| `App` / `MainActivity` / `LauncherActivity` | **CORE必留** |
| `ChannelManager` + 主聊天/Codex/权限/缓存/网络 channel | **CORE必留**（子集） |
| product flavor `standard` + develop debug | **CORE必留**（Codex-first） |
| `omniinfer` edition / submodule | **可砍P0** |
| IM / QuickLog / MCP UI / Shizuku / TerminalActivity UI | **可选** |
| SelectToSpeak + MediaProjection a11y 栈 | **可砍P0** |
| `split_assets.gradle` | **后置**清理 |
| CI/release 脚本、web preBuild 工具链 | **构建专用** |

---

## 7. 拆装风险

| 动作 | 风险 |
|------|------|
| 未 `flutter pub get` 就 assemble | settings 直接炸 |
| 裸 `./gradlew assemble` / `build` | 触发 omniinfer 强制检查 |
| 删 `:assists` 而不迁 `HttpController` | 聊天/网络 channel 编译与运行双炸 |
| 去 web preBuild 而不证伪 MCP/webchat 依赖 | assets 缺失或运行期 404 |
| 改 `applicationId` / 签名 | 本阶段明确禁止；影响 FileProvider/Shizuku/备份路径 |
| 砍 SelectToSpeak 但保留强制无障碍引导 | Codex 入口被产品策略挡住 |
| 误删 `:core:main` / proot assets | Codex Local app-server 全灭（见 03/04） |

---

## 8. 与 Codex / 终端 / 聊天壳

- 聊天壳与 Codex UI 在 Flutter；壳只负责 Engine + Channel + 生命周期
- Codex Local 经 `CodexAppServerChannel` → Manager → `TerminalManager` 长进程（**不经** TerminalActivity）
- 交互终端 UI 是旁路可选面

---

## 9. 瘦身构建路径（P0 推荐）

```bash
cd /root/workspace/omnibot-product/ui
flutter pub get   # 生成 .android/include_flutter.groovy

cd /root/workspace/omnibot-product
./gradlew :app:assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart
```

| 要做 | 不要做 |
|------|--------|
| 指定 `DevelopStandardDebug` | 裸 `assemble`/`build` |
| `-Ptarget=lib/main_standard.dart` | 默认可能偏 omniinfer/main.dart |
| `submodules: false`（CI 已证） | 为 Codex-only 强 init omniinfer |
| debug 默认签名 | 本阶段追 release 密钥 |

产物大致：`app/build/outputs/apk/developStandard/debug/`  
Debug 包名：`cn.com.omnimind.bot.debug`

---

## 10. 关键绝对路径

- `/root/workspace/omnibot-product/settings.gradle.kts`
- `/root/workspace/omnibot-product/build.gradle.kts`
- `/root/workspace/omnibot-product/gradle.properties`
- `/root/workspace/omnibot-product/split_assets.gradle`（遗留）
- `/root/workspace/omnibot-product/app/build.gradle.kts`
- `/root/workspace/omnibot-product/app/src/main/AndroidManifest.xml`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/App.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/activity/MainActivity.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/activity/LauncherActivity.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/ui/channel/ChannelManager.kt`
- `/root/workspace/omnibot-product/ui/`（Flutter module）
- `/root/workspace/omnibot-product/docs/P0-build-inventory.md`
