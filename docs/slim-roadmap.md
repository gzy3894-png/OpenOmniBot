# OmniBot 逐步精简路线（可跑 · 可回滚）

> 工作区：`/root/workspace/omnibot-product` · tip `b157e16`  
> 用户约束：**一步步精简**，禁止「先砍光再发现跑不起来」。  
> 原则：每一步 = **小 diff + 明确验收 + 失败可回滚**；默认只关能力/藏入口，**最后**才删模块。

交叉阅读：`docs/module-map/09-coupling-matrix.md` · `docs/P0-build-inventory.md`

---

## 0. 总纪律（全程）

| 规则 | 说明 |
|------|------|
| **一次一步** | 同时只推进一个 Stage；通过验收再开下一步 |
| **先关后拆** | Feature flag / 默认入口 / 权限引导 优先于删 Gradle 模块 |
| **生命线不碰** | Codex LOCAL：Manager/Session/Local + TerminalManager 长进程 + proot/alpine + baselib Binding + Flutter codex channel/reducer |
| **禁止裸删** | 不得直接 `settings` 去掉 `:assists` / `:accessibility`（须先迁 `HttpController`） |
| **禁止裸 assemble** | 任务名必须带 `Standard`（或明确 edition）；勿顶层 `assemble`/`build` 逼 omniinfer submodule |
| **出包** | 本机 Alpine **无** Flutter/Android SDK 时，APK 只走 **GHA/既有 release 脚本**；真机装测由用户做 |
| **回滚** | 每 Stage 结束记「回滚动作」；git 提交粒度 = 一个 Stage（你确认后再 commit） |
| **主线程** | 只调度/验收；子代理改代码时仍按 Stage 门禁 |

### 冒烟金线（任何 Stage 后必须仍满足，否则回滚）

**S-Smoke-Codex（P0 金线）**

1. App 能启动到聊天壳  
2. 能进 Codex 设置 / 模式  
3. Local Codex **connect** 成功（或明确环境缺 codex 的可读错误，而非崩溃）  
4. 发「在终端执行：`pwd && ls`」类指令后：  
   - **期望**：出现 `commandExecution` / 终端工具卡与输出  
   - **若模型仍不调工具**：至少完整 turn + 无崩溃 + Diag 可区分（不作为「精简回滚」条件，但需记录）  
5. **不开无障碍** 不应阻断上述 1–3（从 S2 起强制；S1 仅记录现状）

**S-Smoke-Build（构建金线）**

- `ui && flutter pub get` 后存在 `ui/.android/include_flutter.groovy`  
- `./gradlew :app:assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart` **配置期不因 omniinfer 空 submodule 失败**  
- 产物 APK 可安装（GHA 或有 SDK 环境）

---

## Stage 总览

| Stage | 名称 | 改代码？ | 风险 | 状态 |
|-------|------|----------|------|------|
| **S0** | 地图 + 路线冻结 | 仅文档 | 无 | **进行中→完成文档** |
| **S1** | 基线可复现（slim standard） | 无业务删减；最多文档/脚本注释 | 低 | **构建通过，待真机冒烟** |
| **S2** | 行为降级：不挡 Codex | 小：权限/默认入口/开关 | 中低 | 待 S1 |
| **S3** | 藏可选面（入口/构建） | 中：路由隐藏、CI standard-only | 中 | 待 S2 |
| **S4** | 解耦再拆自动化 | 高：迁 HttpController 等 | 高 | 待 S3 多次验收 |
| **S5** | 物理删模块 / 品牌 | 很高 | 极高 | 另开方案，用户书面确认 |

---

## S0 — 地图与路线（当前）

### 做
- [x] 只读模块地图 `docs/module-map/00`–`09`
- [x] 本路线 `docs/slim-roadmap.md`
- [ ] 用户知情：精简按 Stage，不一刀砍

### 不做
- 不改 `app/` `ui/lib` 业务、不改 applicationId、不发 fork APK

### 验收
- 地图与本文件可读；CORE/可砍边界清楚

### 回滚
- 删文档即可；无代码回滚

---

## S1 — 基线：能配置 · 能编 slim · 冒烟清单

### 目标
**在不删任何功能的前提下**，固定「官方瘦包路径」为日常真源，避免误踩 omniinfer。

### 做（按序）

1. **工具链**  
   - 有 Flutter 的环境：`cd ui && flutter pub get`（失败则 `flutter clean && flutter pub get`）  
   - 确认 `ui/.android/include_flutter.groovy` 存在  
   - 本机若无 Flutter/SDK：**不在本机硬编**；只固化文档 + 对齐 `.github/workflows/ci.yml` 已有 standard 路径

2. **钉死命令（写入 AGENTS/PRODUCT，不改 Gradle 逻辑）**
   ```bash
   # 唯一推荐日常 debug
   ./gradlew :app:assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart

   # 禁止（空 submodule 时）
   ./gradlew assemble
   ./gradlew build
   ./gradlew assembleDevelopOmniinferDebug   # 除非 init submodule
   ```

3. **冒烟清单落盘** `docs/smoke-codex.md`（真机步骤，用户执行）

4. **环境事实记录**（本机 2026-07-15）：  
   - `ui/.android`：**缺失**（待 pub get）  
   - `flutter`：**无**  
   - `ANDROID_HOME`：**unset**  
   - Java 17：有  
   - 结论：S1 构建验收优先 **CI standard job** 或后续补 SDK，不在 Alpine 上假编

### 不做
- 不删模块、不关功能、不改包名、不 init omniinfer

### 验收
- [ ] 文档三处（PRODUCT / slim-roadmap / P0-inventory）命令一致  
- [ ]（有 SDK 时）standard debug 配置成功；或 CI 绿  
- [ ] 冒烟清单用户可照做

### 回滚
- 仅文档回退；无代码

### 失败处理
- pub get 失败 → 记 Flutter 版本与报错，不改业务绕过  
- CI 红 → 先修构建，不进入 S2

---

## S2 — 行为降级：精简「体验」，代码几乎仍在

### 目标
用户路径默认走向 **Codex**；**无障碍不再是使用门禁**。模块一个都不删。

### 候选改动（**每次只合并一项**，每项单独验收）

| ID | 改动 | 验收 | 回滚 |
|----|------|------|------|
| S2.1 | 权限引导：accessibility **不强制**阻塞进聊天/Codex | 禁用无障碍仍能进壳 + Codex 设置 | 恢复强制 flag |
| S2.2 | 默认/推荐会话模式偏向 Codex（若有「首次模式」或入口高亮） | 冷启动不误进 VLM 任务流 | 恢复默认 |
| S2.3 | 设置页：Remote Codex / OTA 文案降为「高级/可选」 | 主路径不依赖 Worker/bridge | UI 文案回退 |
| S2.4 | 陪伴/任务中心入口降权（仍可进，不删路由） | 主页不抢 Codex | 恢复入口权重 |

### 硬门禁
- 每项合并后跑 **S-Smoke-Codex**  
- **禁止** 本 Stage 修改 `LocalCodex*` / `TerminalManager` 长进程 / proot assets

### 不做
- 不删 `:assists`、不摘 SelectToSpeak Manifest、不关 compile 依赖

---

## S3 — 藏可选面（构建与入口）

### 目标
减少误用与包体噪声；**运行时类仍可保留在 APK**。

### 候选（同样一次一项）

| ID | 改动 | 风险 | 验收 |
|----|------|------|------|
| S3.1 | 文档/脚本默认 **standard-only**；release 脚本加 `--edition standard` 示例 | 低 | 脚本 dry-run 正确 |
| S3.2 | Flutter：本地模型路由仅 omniinfer（已基本如此）— 复核 standard 无死链 | 低 | standard 无 `/home/local_models` 崩溃 |
| S3.3 | 隐藏交互终端主入口（保留进程工厂与设置里高级入口） | 中 | Codex shell 仍通；用户知如何开终端 |
| S3.4 | 评估去掉 **强制** Flutter web preBuild（须先证明 MCP/WebChat 无硬依赖） | 中高 | 无 web 资产时主壳+Codex 仍通 |
| S3.5 | CI：明确 standard job 为 gate；omniinfer 单独 optional job | 低 | PR 只强制 standard |

### 硬门禁
- S-Smoke-Build + S-Smoke-Codex  
- S3.4 必须单独 PR + 可秒回滚

---

## S4 — 解耦自动化（高风险，多 PR）

### 目标
为「将来可删 assists」做准备；**本 Stage 结束时模块仍在**，但边界清晰。

### 强制顺序（不可跳步）

1. **S4.1 盘点** `HttpController` 被谁 import（只读清单 PR）  
2. **S4.2 迁出或复制门面** 到 `baselib` 或 `app`（Agent LLM 改为新门面；assists 内保留 typealias 过渡）  
3. **S4.3** 编译全绿 + Agent 聊天（非 VLM）冒烟  
4. **S4.4** Channel：自动化 method 标 deprecated / no-op 开关 `awb.features.phone_automation=false` 一类 **运行时开关**（名称产品内定）  
5. **S4.5** 关闭 VLM/Companion 创建入口（开关）  
6. **S4.6** 再考虑 Manifest 上去掉 SelectToSpeak（**独立 PR**，可秒回滚）

### 每步验收
- 全量 compile standard debug  
- S-Smoke-Codex  
- 开关=false 时：无法启动手机代操作；=true 时旧行为仍在（过渡期）

### 禁止
- 单 PR 删除整个 `:assists` 目录  
- 未做 S4.2 就删 accessibility

---

## S5 — 物理删除 / 品牌（仅书面确认后）

- 去 uikit 任务 UI、去 modules、改 applicationId、换签、自有 OTA  
- **另开方案文档**；默认不做  
- 每删一模块：依赖图 diff + 全量回归

---

## 回滚速查

| 症状 | 动作 |
|------|------|
| 装完闪退 | 回滚最近 Stage PR；取上一 APK |
| connect 失败且以前成功 | 查是否动了 Terminal/proot/Codex；立即回滚该 PR |
| 编译缺类 HttpController | 说明跳步删了 assists → 恢复模块 + 先做 S4.2 |
| 无障碍引导死循环 | 回滚 S2.1 相关 |
| 包体积暴涨/omniinfer 被编入 | 检查是否误用 omniinfer task / 裸 assemble |

---

## 当前执行指针

- **现在完成**：S0 文档；S1 standard 构建门禁  
- **待完成**：S1 真机冒烟（见 `docs/smoke-codex.md`）  
- **下一步**：S1 冒烟通过后再单独确认是否进入 S2；不自动跨 Stage

---

## 变更记录

| 日期 | 内容 |
|------|------|
| 2026-07-15 | 初版：S0–S5 可跑可回滚精简路线 |
