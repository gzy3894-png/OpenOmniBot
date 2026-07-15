# 04 — Terminal / ReTerminal

> 真源：`TerminalManager` + `app/.../terminal/*` + `ReTerminal/core/*`  
> 范围：两套终端栈、ReTerminal 模块、EmbeddedRuntime、与 Codex Local 耦合  
> 纪律：只读地图；Codex 用 Process 工厂，**不要**合并到 PTY UI 栈

---

## 1. 职责

为 OmniBot 提供 **嵌入式 Linux 用户态运行时**（proot + Alpine）与可选 **交互终端 UI**。

两套栈必须分清：

| 栈 | 名称 | 用途 | 标签 |
|----|------|------|------|
| **A** | Process 工厂 | Codex app-server、hidden 探测命令、无头长进程 | **CORE** |
| **B** | PTY UI | 用户可见终端页 / Flutter PlatformView | **可选** |

共享层：Alpine rootfs、proot、`init-host.sh` / `init`、EmbeddedRuntime 安装器。

---

## 2. 入口

### 栈 A — Process 工厂（CORE）

| 入口 | 路径 |
|------|------|
| API | `com.ai.assistance.operit.terminal.TerminalManager` |
| 长进程 | `startLongLivedAlpineProcess(command, executorKey, env...)` |
| 隐藏命令 | `executeHiddenCommand(...)` |
| Codex 调用方 | `LocalCodexAppServerConnection` / `defaultLocalProcessStarter` |
| executorKey 示例 | `"codex-app-server"` |

### 栈 B — PTY UI（可选）

| 入口 | 路径 |
|------|------|
| Activity | `cn.com.omnimind.bot.activity.TerminalActivity` |
| PlatformView | `cn.com.omnimind.bot/embedded_terminal_view` |
| ReTerminal 会话 | `com.rk.terminal.service.SessionService` |
| App 桥 | `ReTerminalSessionBridge`、`EmbeddedTerminalSessionRegistry` |
| 首次启动 | `LauncherActivity` 标记 `prepare_embedded_terminal_on_first_launch` 等 |

### 运行时安装

| 入口 | 路径 |
|------|------|
| Installer | `ReTerminal/core/main/.../runtime/EmbeddedRuntimeInstaller.kt` |
| Host 脚本资产 | `ReTerminal/core/main/src/main/assets/init-host.sh` |
| Guest init | `.../assets/init.sh` → 写入 `local/bin/init` |
| App 侧协调 | `EmbeddedTerminalInitCoordinator` / `EmbeddedTerminalSetupManager` / `EmbeddedTerminalRuntime` / `EmbeddedTerminalAutoStartManager` / `EmbeddedTerminalLaunchHelper` |

---

## 3. 实现要点

### 3.1 栈 A：Process 工厂如何跑 Codex

```
LocalCodexAppServerConnection
  → TerminalManager.getInstance(context)
  → startLongLivedAlpineProcess(
        command = 进入 alpine 并 exec codex app-server,
        executorKey = "codex-app-server",
        extraEnvironment = ...
     )
  → 底层经 init-host / proot 起进程
  → 返回 java.lang.Process
  → 连接层持有 stdin writer + stdout reader（JSONL）
```

`TerminalManager` 还提供 `executeHiddenCommand`：Manager 用来做 config/auth/环境探测，**同样不经 PTY UI**。

关键文件：

- `/root/workspace/omnibot-product/app/src/main/java/com/ai/assistance/operit/terminal/TerminalManager.kt`
- 同包 `provider/` `setup/` `utils/` `data/`（执行器类型、文件系统、安装辅助）
- 单测：`app/src/test/java/com/ai/assistance/operit/terminal/TerminalManagerTest.kt`

### 3.2 栈 B：PTY UI 如何给用户敲命令

```
用户打开 TerminalActivity
  或 Flutter 嵌入 embedded_terminal_view
  → terminal-view + terminal-emulator
  → SessionService / ReTerminalSessionBridge
  → 同一套 Alpine 环境的交互 shell（PTY）
```

与 Codex 差异：

- 目标是人机交互，不是 app-server 协议
- 生命周期跟 UI/Session 走
- 去掉栈 B **不应**破坏栈 A（若 Process API 与 runtime 资产仍在）

### 3.3 ReTerminal Gradle 模块

`settings.gradle.kts` 映射：

| Gradle 模块 | 目录 | 职责 | 标签 |
|-------------|------|------|------|
| `:core:main` | `ReTerminal/core/main` | runtime 安装、SessionService、init 资产、libcommons、设置、UpdateManager、部分 Compose 终端 UI | **CORE**（runtime）+ UI 可选 |
| `:core:components` | `ReTerminal/core/components` | Compose 组件 | **可选** |
| `:core:resources` | `ReTerminal/core/resources` | 资源 | **CORE** 弱 |
| `:core:terminal-emulator` | `ReTerminal/core/terminal-emulator` | 模拟器核心 | **可选**（PTY） |
| `:core:terminal-view` | `ReTerminal/core/terminal-view` | 视图控件 | **可选**（PTY UI） |

`:app` dependencies 显式：

```kotlin
implementation(project(":core:main"))
implementation(project(":core:terminal-view"))
implementation(project(":core:terminal-emulator"))
```

Codex-first 视角：`core:main` 的 **runtime/installer/assets** 不能砍；`terminal-view/emulator` 可随交互终端降级。

### 3.4 Embedded runtime 与 init-host

`init-host.sh` 概念步骤：

1. 定位 `PREFIX`、Alpine 目录 `local/alpine`、归档 `files/alpine.tar.gz|tar`
2. 安装 `proot` 到 `local/bin/proot`
3. 准备 tmp/shm bind
4. `$LINKER .../proot -r alpine ... /bin/sh local/bin/init "$@"`

相关 Kotlin：

- `EmbeddedRuntimeInstaller` — 释放/校验运行时
- `AlpineRepositoryManager` — 包/镜像源
- `ShellAssetWriter` — 可执行脚本写出
- `UpdateManager` — 刷新 init-host 等
- `OmnibotTerminalEnvironment` / `FileUtil.alpineDir()` — 路径约定

App 侧大文件：

- `EmbeddedTerminalRuntime.kt`（体量大，状态/路径/安装编排）
- `EmbeddedTerminalSetupManager.kt` / `InitCoordinator.kt` / `AutoStartManager.kt`

### 3.5 DocumentProvider / 其它

- `com.rk.AlpineDocumentProvider` — 把 alpine home 暴露给系统文件选择（可选能力）
- Shizuku 等特权在 app Manifest，可增强终端/命令能力，**非** Codex 最小闭环硬依赖

### 3.6 LocalCodex 与 Terminal 耦合点（点名）

| 耦合 | 说明 |
|------|------|
| `LocalCodexAppServerConnection` → `TerminalManager.startLongLivedAlpineProcess` | **硬依赖** |
| `executorKey="codex-app-server"` | 进程池/复用键；乱改导致多开或错杀 |
| Session 内 `exec codex app-server` | 依赖 alpine PATH 上 codex 已安装 |
| Manager → `executeHiddenCommand` | 配置/登录/探测 |
| 共享 rootfs | Codex 与交互终端改同一 alpine 会互相影响包与文件 |
| **不耦合** | `SessionService`、`terminal-view`、PlatformView 输入事件 |

---

## 4. 依赖

```
栈 A:
  Codex Local
    → TerminalManager (app 源码树 operit.terminal)
    → ReTerminal runtime assets / proot / alpine (core:main)
    → 设备文件系统 PREFIX (app private)

栈 B:
  TerminalActivity / PlatformView
    → core:terminal-view + terminal-emulator
    → SessionService (core:main)
    → 同一 alpine 环境

app/terminal/* 协调类
  → 安装状态、自动启动、Registry、LaunchHelper
  → 被 Launcher/Main/Flutter overlay 触发
```

反向：

- baselib **不**依赖 ReTerminal core
- assists/a11y **不**走 TerminalManager 主路径

---

## 5. 耦合

| 点 | 强度 | 栈 |
|----|------|-----|
| Codex Local ↔ TerminalManager 长进程 API | **极高** | A |
| TerminalManager ↔ init-host/proot/alpine 资产完整性 | **极高** | A/B 共享 |
| EmbeddedTerminalRuntime 上帝状态 | **高** | 共享 |
| Launcher 首次 prepare 与用户可进终端/Codex 时序 | **高** | 共享 |
| PlatformView ↔ Activity/Engine | **中** | B |
| SessionService ↔ UI | **中** | B |
| AlpineDocumentProvider / Shizuku | **低~中** | 可选增强 |

**ReTerminal core ↔ baselib：低/无边**（与 09 矩阵一致）。

---

## 6. 标签

### CORE必留

- `TerminalManager.startLongLivedAlpineProcess` / `executeHiddenCommand`
- proot + alpine 归档/目录约定 + `init-host.sh` + guest `init`
- `EmbeddedRuntimeInstaller` 与保证 Codex 能 `exec codex app-server` 的安装链
- `:core:main` 中 runtime/libcommons/assets 部分
- Codex 使用的 app 私有 PREFIX 布局

### 可选

- `TerminalActivity`、Flutter `embedded_terminal_view`
- `:core:terminal-view` / `:core:terminal-emulator`
- `SessionService` / `ReTerminalSessionBridge` / headless PTY 若仅 UI 用
- Compose 终端 UI（`com.rk.terminal.ui.*`）
- `AlpineDocumentProvider`
- AutoStart/花活启动体验（可降级为静默安装）

### 可砍P0

- 仅展示用的终端主题/字号/虚拟键增强（不影响 Process API）
- 与 Codex 无关的 ReTerminal 更新 UI 文案

### 后置

- 将 operit `TerminalManager` 与 ReTerminal 包边界理清（现跨 namespace）
- Process 工厂与 PTY 会话统一监控/杀进程策略
- runtime 资产增量更新与校验强化

### 构建专用

- 打包 alpine/proot/codex 进 assets 的脚本/任务
- CI 是否带完整 runtime（包体 vs 首启下载策略）

---

## 7. 拆装风险

| 动作 | 风险 |
|------|------|
| 删 `:core:main` | 栈 A/B 全灭；Codex Local 必挂 |
| 只删 terminal-view 但误删 assets | Codex 挂 |
| 改 init-host bind 挂载 | 权限/路径错，proot 起不来 |
| 合并 Codex 到 SessionService | 协议与生命周期错误（用户已否决方向） |
| 首启跳过 runtime 安装又无懒加载 | connect 失败 |
| 多 executorKey 冲突 / 杀进程过猛 | app-server 被误杀 |
| 在 alpine 内手动升级 codex 与 App 期望协议不一致 | reducer/事件不匹配 |
| 本机 Alpine（proot 外）当发布环境 | 与 App 内 PREFIX 布局不同，不能替代集成验证 |

---

## 8. 与 Codex / 聊天壳

```
[CORE 生命线]
聊天壳 Codex 模式 → Channel → Manager → LocalConnection
  → TerminalManager 长进程 → init-host/proot/alpine → codex app-server

[可选旁路]
聊天壳/设置入口 → TerminalActivity 或 embedded_terminal PlatformView
  → SessionService PTY → 同一 alpine 给人用

[共享但可独立降级 UI]
EmbeddedRuntime 安装成功是两者的前提；
UI 可关，Process API + rootfs 必须留。
```

---

## 9. 关键绝对路径

### Process 工厂 / App 终端协调

- `/root/workspace/omnibot-product/app/src/main/java/com/ai/assistance/operit/terminal/TerminalManager.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalRuntime.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalInitCoordinator.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalSetupManager.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalAutoStartManager.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalLaunchHelper.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/EmbeddedTerminalSessionRegistry.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/terminal/ReTerminalSessionBridge.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/ui/platformview/EmbeddedTerminalPlatformViewFactory.kt`
- `/root/workspace/omnibot-product/app/src/main/java/cn/com/omnimind/bot/codex/LocalCodexAppServerConnection.kt`

### ReTerminal core

- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/terminal/runtime/EmbeddedRuntimeInstaller.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/terminal/runtime/AlpineRepositoryManager.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/terminal/service/SessionService.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/terminal/service/RunCommandService.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/assets/init-host.sh`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/assets/init.sh`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/libcommons/FileUtil.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/main/src/main/java/com/rk/libcommons/ShellAssetWriter.kt`
- `/root/workspace/omnibot-product/ReTerminal/core/terminal-view/`
- `/root/workspace/omnibot-product/ReTerminal/core/terminal-emulator/`

### 交叉文档

- `/root/workspace/omnibot-product/docs/module-map/03-codex-stack.md`
- `/root/workspace/omnibot-product/docs/module-map/09-coupling-matrix.md`
