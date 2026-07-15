# 08 — workers / tools / scripts / skills / CI 周边

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 范围：`workers/`、`tools/codex-bridge`、`scripts/`、`skills/`、`builtin_skills`、`.github/workflows`、`.cnb`、`public/`、`docs/`、`fonts/`  
> 纪律：只读地图；**禁止改业务代码**

---

## 1. 一页结论

| 切片 | 运行时进 APK？ | 标签 | Codex 最小闭环 |
|------|----------------|------|----------------|
| `workers/app-update-worker` | 否（Cloudflare） | **可选** OTA | 不需要 |
| `tools/codex-bridge` | 否（PC Node） | **可选** Remote Codex | Local 不需要 |
| `scripts/build-local-release.sh` | 否 | **构建专用** | 出包用 |
| `app/.../assets/builtin_skills` | **是** | **CORE**（Agent skill 体系） | Codex 弱依赖 |
| 根目录 `skills/wechat.json` | 视打包引用 | **可砍** | 不需要 |
| GHA ci/release | 否 | **构建专用** | P0 对齐 ci |
| GHA sync-to-cnb / codex-bot | 否 | **可砍P0**（fork 维护向） | 不需要 |
| `public/` `docs/` `fonts/` | docs/public 否；fonts 视引用 | **后置** | 不挡 Codex |

**Runtime vs CI：** 真机 Codex 闭环只依赖 app+flutter+baselib+terminal 资产；本文件多数是 **发布/远程/文档** 旁路。

---

## 2. `workers/app-update-worker` — 可选 OTA

### 2.1 职责

Cloudflare Worker：应用更新检查、R2 APK 分发、管理台、Analytics Engine 统计。

### 2.2 入口 / 结构

```
workers/app-update-worker/
├── worker.js              # Worker 主逻辑
├── admin-ui.js            # 内嵌管理台
├── wrangler.toml.example
└── README.md
```

公开路由（摘要）：

| 路由 | 用途 |
|------|------|
| `GET /updates?...&edition=...` | App 检查更新（`AppUpdateManager`） |
| `GET /downloads/:tag/:asset` | APK 下载（R2） |
| `GET /admin` + `/admin/api/*` | 管理台（`ADMIN_TOKEN`） |

### 2.3 与 App 运行时耦合

| 侧 | 说明 |
|----|------|
| App | `AppUpdateManager` 读 `BuildConfig.APP_UPDATE_WORKER_URL` / `APP_EDITION` |
| 无 Worker | 更新检查失败或空——**不挡** Codex connect/shell |
| CI 发布 | `release.yml` 可选把产物推 Worker（需 `APP_UPDATE_WORKER_URL` + token secrets） |

### 2.4 标签

**可选**。Codex-first / 内测旁路可关 OTA；自建分发时再部署 Worker。

---

## 3. `tools/codex-bridge` — 可选 Remote

### 3.1 职责

PC 侧自托管桥：WebSocket 把手机 **Remote Codex** 接到 PC 上的 `codex app-server`（或桌面 socket 代理），并提供远程 FS HTTP API。

### 3.2 结构

```
tools/codex-bridge/
├── server.mjs             # 主程序 ~55KB
├── package.json           # @thuocean/codex-bridge 0.1.4；bin: codex-bridge
├── package-lock.json
└── README.md
```

依赖：`ws`、`qrcode-terminal`；Node ≥ 18。

能力摘要：

- 交互式选网卡 / token（记忆 `~/.omnibot/codex-bridge.json`）
- `GET /health`、`/fs/list|read`、`POST /fs/write|delete|move`
- 会话协议与本地 app-server 对齐，便于同一套 session list

### 3.3 与 App 运行时耦合

| 侧 | 说明 |
|----|------|
| App | `RemoteCodexBridgeConnection`、`CodexRemoteBridgeConfigStore`、扫码/远程 UI |
| Local Codex | `LocalCodexAppServerConnection` + proot——**不经过** bridge |
| 标签 | **可选**；Remote 产品向 |

### 3.4 标签

**可选**。砍 Remote 模式不影响 Local Codex shell。

---

## 4. `scripts/` — 构建专用

| 脚本 | 职责 | 标签 |
|------|------|------|
| `build-local-release.sh` | 本地/CI 正式包：`--edition standard\|omniinfer\|both`，签包、产物目录、可选 publish | **构建专用** |
| `upload_release_asset_to_worker.py` | 发布物流到 Update Worker | **构建专用** / 可选 OTA |
| `mirror_github_release_to_cnb.py` | GitHub → CNB 镜像 | **后置** / 镜像 |
| `setup-git-hooks.sh` | hooks 安装 | 开发环境 |

`build-local-release.sh` 要点：

- 默认 edition **both**（P0 应用 `--edition standard`）
- 协调 Flutter、NDK 版本、assembleProduction*、sha256、manifest
- 与 `release.yml` 同源思想

---

## 5. Skills 资产

### 5.1 `app/src/main/assets/builtin_skills` — CORE（Agent）

`manifest.json` 注册内置 skill（抽样）：

| id | 用途 |
|----|------|
| `self-improving-agent` | 失败/纠错写入 workspace learnings |
| `skill-creator` | 写 skill 指南 |
| `find-install-skills` | 查找安装 skill（含脚本） |

另有目录资产如 `hatch-pet`（宠物相关脚本/参考）等，以目录为准。

| 关系 | 说明 |
|------|------|
| Agent | `AssistsCoreManager` skill 安装/启用 API 读 assets |
| Codex | Alpine 内 Codex skills **另一套**；builtin_skills 对 Codex **弱** |
| 标签 | **CORE**（保留 Agent 能力时）；纯 Codex-only 可后置精简但非第一刀 |

### 5.2 根目录 `skills/wechat.json` — 可砍

微信场景 skill 描述（「用其他应用打开 → 小万」步骤 JSON）。

| 标签 | **可砍**（Codex-only / 非微信自动化） |
|------|----------------------------------------|
| 风险 | 低；确认无强制打包引用即可 |

---

## 6. CI / 镜像 / Bot

### 6.1 `.github/workflows`

| Workflow | APK？ | 标签 | 说明 |
|----------|-------|------|------|
| `ci.yml` | Debug standard | **构建专用** / P0 对齐 | `assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart`；`submodules: false` |
| `release.yml` | Release standard+omniinfer | **构建专用** | 密钥：keystore / 可选 Worker |
| `release.yml.self-hosted.bak` | — | 备份 | 非活跃 |
| `sync-to-cnb.yml` | 否 | **可砍P0**（fork） | 需 CNB token |
| `codex-bot.yml` | 否 | **可砍P0** | Maintainer `@codex`；需 `OPENAI_API_KEY` |

### 6.2 `.cnb/` / `.cnb.yml`

CNB 镜像与全量构建（会 init omniinfer + nested frameworks）。  
标签：**后置 / 镜像专用**；P0 不依赖。

### 6.3 secrets 形态（不写值）

- Release：`RELEASE_KEYSTORE`、`RELEASE_PASSWORD`、`RELEASE_KEY_ALIAS`
- OTA：`APP_UPDATE_WORKER_URL`、`APP_UPDATE_WORKER_TOKEN`
- 镜像/Bot：`CNB_TOKEN`、`OPENAI_API_KEY` 等  
→ 记忆与文档 **禁止** 落入密钥明文。

---

## 7. `public/` / `docs/` / `fonts/` — 后置

| 路径 | 内容 | 标签 |
|------|------|------|
| `public/images/` | 如 `mask-group.svg` | **后置**（营销/静态） |
| `docs/` | 教程图、reference、**module-map**、P0 inventory | **后置**（人读）；module-map 为二次开发 CORE 文档 |
| `fonts/` | NotoSerifCJK、tiempos woff2 等大文件 | **后置**；确认 UI 引用前勿盲删 |

运行时：上述目录 **不是** Gradle `include` 模块；对 Codex 进程树无边。

---

## 8. Runtime vs CI 耦合矩阵

图例：● 运行时硬依赖 / ◎ 软 / ○ 无 / 🛠 仅构建发布

| 资产 | 真机 Local Codex | 真机 Remote Codex | Agent 聊天 | OTA 更新 | 出包 CI |
|------|------------------|-------------------|------------|----------|---------|
| proot/alpine + TerminalManager | ● | ○ | ○ | ○ | 🛠 打进 assets |
| baselib DB / Flutter 壳 | ● | ● | ● | ○ | 🛠 |
| tools/codex-bridge | ○ | ●（PC 侧） | ○ | ○ | ○ |
| workers update | ○ | ○ | ○ | ◎ | 🛠 可选上传 |
| builtin_skills assets | ○ | ○ | ● | ○ | 🛠 打进 APK |
| skills/wechat.json | ○ | ○ | ◎ | ○ | ◎ |
| build-local-release / GHA release | ○ | ○ | ○ | ◎ | 🛠 |
| ci.yml standard debug | ○ | ○ | ○ | ○ | 🛠 P0 |
| codex-bot / sync-cnb | ○ | ○ | ○ | ○ | 🛠 可砍 |
| omniinfer submodule | ○ | ○ | ◎ flavor | ◎ edition | 🛠 非 standard |
| public/docs/fonts | ○ | ○ | ○ | ○ | ○/后置 |

```
[运行时生命线 — 本文件不覆盖]
Flutter codex → Channel → Manager → LocalConnection → TerminalManager → proot

[本文件旁路]
Remote UI ──WS──► tools/codex-bridge (PC) ──► codex app-server
AppUpdateManager ──HTTP──► workers/app-update-worker ──R2──► APK
GHA/scripts ──► 签名 APK ──可选──► Worker / GitHub Release / CNB
```

---

## 9. 标签汇总与拆装建议

| 优先级 | 项 |
|--------|-----|
| **CORE**（Agent） | `builtin_skills` assets |
| **可选** | Update Worker、Remote bridge、OTA 相关 BuildConfig |
| **可砍P0** | `skills/wechat.json`、codex-bot CI、sync-cnb、根 `fonts/` 大文件（确认未引用后） |
| **构建专用** | `build-local-release.sh`、upload/mirror 脚本、ci/release workflows |
| **后置** | public、docs 图床、CNB 全量、edition both 默认 |

建议（不执行）：

1. P0 只认 **ci.yml standard** 命令  
2. 内测可关 OTA URL / 不部署 Worker  
3. Remote 文档化可选，不进最小包验收  
4. 不要为了「干净」误删 `builtin_skills` 除非已放弃 Agent skill  
5. 大字体与镜像脚本最后再动  

---

## 10. 相关路径

| 路径 | 说明 |
|------|------|
| `/root/workspace/omnibot-product/workers/app-update-worker/` | OTA Worker |
| `/root/workspace/omnibot-product/tools/codex-bridge/` | Remote PC 桥 |
| `/root/workspace/omnibot-product/scripts/build-local-release.sh` | 发布构建 |
| `/root/workspace/omnibot-product/app/src/main/assets/builtin_skills/` | 内置 skills |
| `/root/workspace/omnibot-product/skills/wechat.json` | 微信场景 JSON |
| `/root/workspace/omnibot-product/.github/workflows/` | ci/release/bot/sync |
| `/root/workspace/omnibot-product/docs/P0-build-inventory.md` | 构建密钥与路径清单 |
| `/root/workspace/omnibot-product/docs/module-map/09-coupling-matrix.md` | 总矩阵 |

---

## 11. 与 05–07 的衔接

| 文档 | 衔接点 |
|------|--------|
| 05 baselib/uikit | OTA 用 baselib 网络/日志；UIKit 与 workers 无边 |
| 06 assists | builtin_skills / wechat 场景服务 Agent/自动化，不服务 Codex Process |
| 07 omniintelligence-infer | release `--edition both` 才碰 omniinfer；standard P0 与 Worker edition 字段独立 |
| 09 总矩阵 | 阶段 1 构建可复现；可选面隔离含 OTA/Remote/omniinfer |
