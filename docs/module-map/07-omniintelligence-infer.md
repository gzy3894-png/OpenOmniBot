# 07 — omniintelligence / omniinfer

> 真源：`/root/workspace/omnibot-product` tip `b157e16` (0.5.6.4)  
> 范围：`:omniintelligence`、`third_party/omniinfer`（submodule）、product flavor `standard` / `omniinfer`、Flutter local_model  
> 纪律：只读地图；**禁止改业务代码**

---

## 1. 一页结论

| 问题 | 答案 |
|------|------|
| `:omniintelligence` 是什么 | **薄 DTO 库**：`AgentRequest` / `HostResponse` 等 sealed 模型，无推理引擎 |
| 标签 | 随自动化栈 **后置 / 可选**；非 Codex 生命线 |
| `third_party/omniinfer` | **空 submodule 目录**（未 init）；`.gitmodules` 指向 OmniInfer |
| 标签（submodule） | **可砍P0**（Codex-only / standard 出包） |
| P0 出包 | `assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart` |
| 勿做 | 裸 `assemble` / `build` / `check` / `test`（会触发 submodule 门禁） |
| 与 Codex / ReTerminal | **无耦合** |

---

## 2. `:omniintelligence` — 薄 DTO

### 2.1 职责

Android Library（`cn.com.omnimind.omniintelligence`），**仅模型定义**，描述「智能体请求宿主做什么 / 宿主回什么」。

历史名像「智能引擎」，实际仓库内 **没有** 推理 runtime、没有 native so、没有网络客户端。

### 2.2 入口

无 Application/Service。被 assists / uikit 以 **类型依赖** 引入（`api`/`implementation`）。

### 2.3 源文件（完整清单）

```
omniintelligence/src/main/java/cn/com/omnimind/omniintelligence/models/
├── AgentRequest.kt      # sealed：点击/输入/截图/VLM/LLM/广告/桌面判断...
├── HostResponse.kt      # sealed：对应响应 + 流式卡片等
├── Common.kt            # RequestHeader/ResponseHeader/TaskType/ScrollDirection...
├── InputMode.kt         # DIRECT / PASTE / PASTE_REPLACE
└── TaskState.kt         # PENDING/RUNNING/COMPLETED/FAILED/CANCELLED
```

`AgentRequest` 覆盖的能力域（摘要）：

- 坐标点击 / 长按 / 滑动 / 文本输入 / 剪贴板
- 启动应用 / 列安装应用 / 回桌面 / 返回
- 截图 Image/Bitmap/XML / 当前 Activity
- 页面稳定 / Loading / 登录页 / 广告拦截
- 发 VLM/LLM（含流式）/ 请求 VLM 执行
- 任务结束 / 类型更新 / 用户接管 / 聊天机器人摘要卡片

→ 这些是 **自动化 Agent ↔ 宿主** 协议，不是 Codex app-server 协议。

### 2.4 依赖

```text
implementation(kotlinx-coroutines)
implementation(project(":baselib"))   # 如 ImageQuality 等少量类型
```

| 方向 | 内容 |
|------|------|
| omniintelligence → | baselib（轻） |
| 被谁依赖 | `:assists`（api）、`:uikit`； assits 任务链使用 DTO |
| app 是否直接依赖 | 通常经 assists 传递；settings 单独 `include(":omniintelligence")` |

### 2.5 与 Codex / 终端

| 关系 | 说明 |
|------|------|
| Codex | **无** import、**无** 协议复用 |
| ReTerminal | **无** |
| 自动化 | **软必需**（类型面）；删模块前需改 assists/uikit 签名 |

### 2.6 标签

| 标签 | **后置**（随 assists 自动化；Codex-first 不优先动） |
|------|------------------------------------------------------|
| 若已迁出/删除 assists | 可一并移除 |
| 风险 | 单独删除会炸 assists/uikit 编译；收益低 |

---

## 3. `third_party/omniinfer` — 本地推理 submodule

### 3.1 职责（设计意图）

上游 OmniInfer：端侧模型服务（MNN 等），经 Gradle 模块 `:omniinfer-server` 链入 **omniinfer flavor**。

### 3.2 工作区实况

| 项 | 值 |
|----|-----|
| `.gitmodules` | `third_party/omniinfer` → `https://github.com/omnimind-ai/OmniInfer.git` |
| 当前目录 | **空**（无 `android/omniinfer-server/build.gradle.kts` marker） |
| 嵌套（完整版） | 文档/CI 提到 `framework/mnn`、`framework/llama.cpp` 等 |
| standard CI | `submodules: false`，**不需要** init |

### 3.3 settings 条件 include

`settings.gradle.kts` 逻辑摘要：

1. 若 marker 文件存在 **或** 任务名含 `omniinfer` / 等于 `build|assemble|check|test`  
2. 则 `requireOmniInferModule`：marker 不存在 → **GradleException**，提示 `git submodule update --init third_party/omniinfer`  
3. 成功则 `include(":omniinfer-server")` 并改 `projectDir`

→ **P0 必须带** `-Ptarget=lib/main_standard.dart` 的 **具体** `assembleDevelopStandardDebug` 等任务名，避免顶层 `assemble`。

### 3.4 app flavor 绑定

`app/build.gradle.kts` productFlavors（摘要）：

| flavor | `LOCAL_MODEL_FEATURE_ENABLED` | `APP_EDITION` | 依赖 omniinfer-server |
|--------|-------------------------------|---------------|------------------------|
| `standard` | `false` | `"standard"` | 否 |
| `omniinfer` | `true` | `"omniinfer"` | `omniinferImplementation(project(":omniinfer-server"))`（若 project 存在） |

另有 source set：

- `app/src/standard/java/.../LocalModelFeatureInstaller.kt` — 空/关
- `app/src/omniinfer/java/...` — Mnn 管理、Channel、Installer
- `app/src/omniinfer/assets/omniinfer_mnn_model_market.json`

### 3.5 标签

| 组件 | 标签 |
|------|------|
| omniinfer submodule + flavor | **可砍P0**（Codex-only / 只要 standard） |
| 完整本地推理产品 | 可选后置能力，非 Codex 依赖 |

---

## 4. Flutter local_model 面

### 4.1 入口分流

| 文件 | 行为 |
|------|------|
| `ui/lib/main_standard.dart` | `configureStandardLocalModelFeature()` → bootstrap |
| `ui/lib/main_omniinfer.dart` | omniinfer local_model feature |
| `ui/lib/main.dart` | **默认 re-export omniinfer**（历史默认；P0 构建必须显式 `-Ptarget`） |

### 4.2 仅 omniinfer 的能力

| 项 | 说明 |
|----|------|
| `features/local_model/local_model_feature_omniinfer.dart` | 内置 profile `omniinfer-local` 等 |
| `services/mnn_local_models_service.dart` | 后端名：`omniinfer-mnn` / `executorch-qnn` / `litert` |
| `features/home/pages/local_models/*` | 本地模型管理页 |
| 原生 Channel | `app/src/omniinfer/.../MnnLocalModelsChannel.kt` |

standard 侧：`local_model_feature_standard.dart` + 空 Installer，**无** Mnn Channel。

### 4.3 baselib 桥（跨 flavor）

- `MnnLocalProviderStateStore` / `LocalModelProviderBridge` 在 **baselib**
- flavor 决定是否 `setEnabled` / 注入 `Delegate`
- standard 下 bridge 保持关闭，不拉 submodule

---

## 5. P0 构建路径（钉死）

### 推荐（CI 同源）

```bash
# 前置：cd ui && flutter pub get   # 生成 .android / include_flutter.groovy
./gradlew :app:assembleDevelopStandardDebug \
  -Ptarget=lib/main_standard.dart
```

| 要求 | 说明 |
|------|------|
| 不要 | 裸 `./gradlew assemble` / `build` |
| 不要 | 为 P0 强制 `git submodule update --init third_party/omniinfer` |
| 需要 | Flutter SDK、`ui/.android` 已生成 |
| 另注 | app preBuild 仍可能跑 Flutter **web**（webchat assets）——属构建耦合，见 P0 inventory / 08 |

Release 脚本：

```bash
bash scripts/build-local-release.sh --edition standard ...
# 或 both（才会要 omniinfer submodule）
```

### CNB / 全量

`.cnb.yml` 路径会 init omniinfer + 嵌套 framework——**全量 edition**，非 P0。

---

## 6. 耦合矩阵（本切片）

| 模块 | Codex | ReTerminal | 自动化 assists | 聊天壳 | 标签 |
|------|-------|------------|----------------|--------|------|
| `:omniintelligence` | ○ | ○ | ● 类型 | ○ | **后置** |
| omniinfer-server / submodule | ○ | ○ | ○ | ◎ local_model UI | **可砍P0** |
| flavor standard | ● P0 | ● | ◎ | ● | **CORE 出包** |
| flavor omniinfer | ○ 非必须 | ○ | ○ | ◎ | **可选** |
| `LocalModelProviderBridge` | ○ | ○ | ◎ 经 HttpController | ◎ | baselib 常驻、默认关 |

```
[无边]
Codex/*  ──x──  omniintelligence
Codex/*  ──x──  omniinfer-server
ReTerminal/core ──x── omniintelligence / omniinfer

[有边 · 自动化]
assists / uikit ──► omniintelligence (DTO)

[有边 · 仅 omniinfer flavor]
app omniinfer sources ──► :omniinfer-server
Flutter main_omniinfer ──► local_model pages ──► MnnLocalModelsChannel
```

---

## 7. 拆装建议（只建议）

1. **文档/CI 钉死 standard-only** 命令（已有 ci.yml）  
2. 二次开发默认入口考虑改为 `main_standard`（**后置**，需产品确认）  
3. Codex-first 不 init submodule；忽略 omniinfer 路由  
4. 真要减依赖：flavor 维度关闭即可，不必先删 DTO 库  
5. 删除 `:omniintelligence` 仅在 assists 协议重写之后  

---

## 8. 相关路径

| 路径 | 说明 |
|------|------|
| `/root/workspace/omnibot-product/omniintelligence/` | 薄 DTO 模块 |
| `/root/workspace/omnibot-product/third_party/omniinfer/` | 空 submodule 占位 |
| `/root/workspace/omnibot-product/settings.gradle.kts` | 条件 include + 门禁 |
| `/root/workspace/omnibot-product/app/build.gradle.kts` | flavors / LOCAL_MODEL |
| `/root/workspace/omnibot-product/ui/lib/main_standard.dart` | P0 Flutter 入口 |
| `/root/workspace/omnibot-product/ui/lib/main_omniinfer.dart` | 本地模型入口 |
| `/root/workspace/omnibot-product/docs/P0-build-inventory.md` | 构建清单 |
| `/root/workspace/omnibot-product/docs/module-map/09-coupling-matrix.md` | 总矩阵 |
