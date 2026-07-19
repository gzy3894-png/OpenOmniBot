# PLAN · Codex Goal / 配置 / 供应商 / 审批 / 性能 · 2026-07-19

> 阶段：`IMPLEMENTED · REMOTE_PENDING`
> 源码基线：`8f9355dc1bfa7116073cac59b7818b0dddbe9bbc`（`codex/b38-integration`）
> 设备日志：`/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-20260719.log`
> 最新历史账本：`docs/results/EXEC-2026-07-18-b38-approval-models.md`
> 约束：只修本文件冻结的五项 Codex 模式问题；本机不运行 Flutter、Dart、Gradle、assemble、lint 或 test。

## 0. 本轮交付结果

最终 APK 必须同时满足：

1. Goal 发出后，普通输入立即恢复为普通消息；更新 Goal 只能点击 Goal 条，在独立编辑器中完成。
2. Codex 设置页删除“通用运行偏好”；公共默认值由配置层一次性写入，不再让用户重复配置。
3. Codex 设置支持多个用户供应商记录（备注名、API、Key、独立模型库）切换；Codex 内部始终使用同一个 `omnimind` profile，切换原子、失败回滚且不打乱会话。
4. 默认审批与自动审批均走 Codex 原生审批机制，有端到端事件和决策证据。
5. 消除已证实的 Goal 拉取/线程恢复风暴和流式事件 UI 热路径，给出同 APK 的真机帧指标。

### 明确排除

- 不碰图片、语音、普通聊天、OpenClaw、VLM、无障碍业务和非 Codex 模式。
- 不新增媒体能力，不做模块裁剪，不改品牌、包名、签名或发布流程。
- 不把本轮变成 `chat_page` 全面重构；只拆出为五项修复所必需的局部状态/组件。
- 不以 toast、tip、开关高亮、`approval_effective_settings` 或“仓库全绿”代替设备功能验收。
- 不复用 B38 旧 run/APK 为本轮背书。旧九路 run `29656072103` 对应 `dad70e8`，当前基线已经是 `8f9355d`。

## 1. 日志与代码结论

| 项 | 已确认事实 | 结论 |
|---|---|---|
| Goal 输入劫持 | 日志 L54 首次设置 Goal；L59–60 用户随后输入 `？` 却再次成为 `goal set` 和 `/goal ？`；L63–65 再次重复 | 真 bug，且可稳定复现 |
| Goal 根因 | `chat_page_codex.dart:2104-2107` 把 `_codexGoalModeEnabled` 交给 planner；`codex_mode_submit.dart:212-228` 在该值为 true 时把所有普通正文变成 `setGoal`；Goal 成功/服务端更新又在 `chat_page_codex.dart:2057-2090,3217-3221` 保持 true | “有活动 Goal”和“正在编辑 Goal”错误共用一个状态 |
| 通用运行偏好 | `codex_setting_page.dart:940-1041` 仍展示 Fast、自动压缩、默认 Goal，且这些字段进入 controller/signature/save 链 | 与用户要求不符，应删除整段及其保存输入 |
| 单供应商 | Codex 路径的 `CodexLocalConfig`/`writeLocalConfig` 只有一组扁平 URL/model/key；Native 固定 `model_provider="omnimind"`、`[model_providers.omnimind]` 和一个 `OPENAI_API_KEY` | 固定 `omnimind` 是应保留的会话身份；缺的是应用层多供应商记录、当前选中项和每个供应商各自的模型库 |
| 审批配置 | 日志 L30–37 显示三档 triad 能写入；L56–65 的实际 turns 全是 `on-request + user + workspaceWrite` | triad 写入成功，不等于审批链成功 |
| 自动审批测试 | L30–33 切到 autoReview，随后 L34–37 又切 fullAccess、default；真正发送任务时已是 default | 本日志没有执行过 autoReview turn，不能据此宣称自动审批已通过或已断 |
| 默认审批测试 | 全日志没有 `requestApproval`、`approval_prompt`、`approval_decision`；测试文本又被 Goal 劫持，且没有确定性的 `/workspace` 越界动作 | 尚未真正触发升级条件，审批链仍为 `DEVICE_UNPROVEN` |
| 审批官方语义 | 上游 `AskForApproval::OnRequest` 是“模型在需要升级时请求”，不是“每次工具调用都弹卡”；官方 Default 是 workspace-write，越界/受限网络才请求 | 保持官方三档映射，先用正确探针验证，不盲改成 `untrusted` |
| 恢复卡顿 | 日志 L27 connect 6 次后失败；L28–31、L45–48、L50–53 连续清 stale/start/recover；Goal get 出现在 L26–27、L38、L50–53、L58、L62、L66 | 背景 Goal 读取和设置变更放大线程恢复开销 |
| UI 热路径 | `chat_page_codex.dart:3762-3785` 每 event 计数并逐条 `debugPrint`；coordinator `applyCodexEvent` 每 handled event `notifyListeners` 并调度持久化；handler 尾部 `:3954-3955` 又无条件整页 `setState` | 流式 delta 会造成重复通知、整页 rebuild、日志与 timer churn |
| 性能证据边界 | 三次 goal set→turn start 约 91ms、59ms、64ms，没有递增；现有日志没有 frame/GC/RPC duration | 不能臆断后端越来越慢；先处理可证热路径并补帧观测 |

## 2. 冻结设计

### G1 · Goal 状态与独立编辑器

1. 将状态彻底拆开：
   - 活动目标：`_codexActiveGoalText`，只表示当前 thread 的真实 Goal；
   - 编辑状态：独立 BottomSheet/Dialog 的局部 controller；关闭即销毁，不进入主 composer；
   - Goal 条是否显示只由活动目标是否非空决定。
2. 删除“活动 Goal 使主 composer 进入 Goal 模式”的语义：
   - 普通正文永远走 normal turn；
   - `planCodexComposerSubmit` 不再因活动 Goal 把普通正文转成 `setGoal`；
   - 显式 `/goal <text>`、`/goal clear` 保留为高级入口。
3. 点击根命令中的 Goal 或已有 Goal 条，打开独立编辑器并预填当前目标：
   - “保存并发送”只提交编辑器内容；
   - 先成功执行 `thread/goal/set`，再沿用现有 model-visible Goal turn；
   - 成功后关闭编辑器并恢复普通输入焦点；
   - 失败时编辑器保留，主输入草稿和旧 Goal 均不丢；
   - 取消不写入；Goal 条的 X 仍执行 clear。
4. 主 composer 移除 Goal 前缀 chip 和“更新目标…”提示；下一条 `？` 必须作为普通 user turn。
5. Goal 获取改为活动 thread 的同步数据，不再把“无 Goal”解释成一个持续的 composer 编辑模式。

预计区域：

- `ui/lib/features/home/pages/chat/utils/codex_mode_submit.dart`
- `ui/lib/features/home/pages/chat/chat_page.dart`
- `ui/lib/features/home/pages/chat/chat_page_codex.dart`
- `ui/lib/features/home/pages/chat/chat_page_ui.dart`
- `ui/lib/features/home/pages/chat/widgets/codex_goal_mode_bar.dart`
- `ui/lib/features/home/pages/command_overlay/widgets/chat_input_area*.dart`

### C1 · 删除通用运行偏好并写公共默认

1. 从 `CodexSettingPage` 删除整段“通用运行偏好”以及：
   - `_defaultGoalController`
   - `_fastEnabled`
   - `_autoCompactionEnabled`
   - 对应 listener、signature、toggle、load/save 参数和测试 key。
2. 配置层执行一次幂等迁移，公共基线固定为：
   - `features.fast_mode = false`
   - 删除 `service_tier = "fast"`，Fast 关闭时不写 `service_tier`
   - `features.auto_compaction = true`
   - 删除 `omnimind_default_goal`
3. 这些是公共默认，不属于任何用户供应商记录。首次迁移完成后：
   - 会话内现有 Fast/auto-compaction 命令仍可覆盖；
   - 切换供应商必须保留当前公共 feature 值，不得把供应商切换变成偏好重置。
4. 配置读写返回有效值，但设置页不再允许编辑这三项。

预计区域：

- `ui/lib/features/home/pages/codex/codex_setting_page.dart`
- `ui/lib/services/codex_app_server_service.dart`
- `app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerManager.kt`
- `app/src/test/java/cn/com/omnimind/bot/codex/CodexAppServerProtocolPayloadTest.kt`

### P1 · Codex 多供应商切换（固定内部 profile）

先冻结两个不同概念，禁止再混用：

- **Codex 内部 profile**：始终固定为 `model_provider = "omnimind"`、`[model_providers.omnimind]`、`name = "omnimind"`；无论用户选哪个供应商都不创建、不重命名、不切换这个 profile。
- **用户供应商记录**：应用层的一条配置，包含稳定 id、用户备注名、API base URL、API Key、该供应商自己的模型列表库和当前模型。备注名只帮助用户记忆，可以改名，也不得作为 TOML 名、存储主键或会话身份。

复用应用现有供应商记录作为真源，不另建第二套明文密钥库：

- 真源仍为 `ModelProviderConfigService.listProfiles()`，但在 Codex 设计和界面中称为“供应商记录”，避免与 Codex 内部 profile 混淆；
- Codex 只额外持久化 `activeCodexProviderId` 和每个供应商记录自己的 Codex 当前模型；
- 设置页提供供应商选择、当前供应商的模型选择和“管理供应商”入口；
- 旧扁平 Codex URL/key/model 作为第一个兼容供应商记录接入，但内部 profile 仍是 `omnimind`，密钥不得再复制一份明文。

每个供应商独立维护模型列表库：

1. 模型库按稳定供应商 id 隔离，包含该供应商的手动模型、远端 `/models` 拉取结果、缓存和当前选中模型；A 的模型不得出现在 B 的列表中。
2. 切换供应商时直接挂载该供应商自己的模型库；当前模型必须来自当前供应商的列表，或由用户为该供应商明确添加。
3. 修改备注名不迁移、不清空模型库；修改 API 地址只失效该供应商对应地址的远端缓存，不影响其他供应商。
4. Codex 仅允许 OpenAI-compatible 且支持 Responses API 的供应商；`chat_completions`-only、Anthropic-only、仅本地推理或依赖 Codex 当前不支持的自定义鉴权头时，禁用并显示具体原因。

切换事务：

1. 按稳定 id 解析选中的用户供应商记录，校验 API、Key、当前模型和 Responses 兼容性；用户备注名不参与运行时校验。
2. Native 生成权限为 0600 的临时 `config.toml` 与 `auth.json`；只在固定 `[model_providers.omnimind]` 下替换 `base_url`，同时替换 Key 和当前模型，绝不把用户备注名写入 Codex profile。
3. 原子替换两文件；全部成功后才提交 `activeCodexProviderId`、该供应商当前模型和界面选中态。
4. 使旧模型库请求 generation 失效，立即切到目标供应商自己的模型库；后台刷新只能更新目标供应商，旧供应商迟到结果不得闪回。
5. 硬配置变化如需重连或重启 Codex session，最多执行一次，并恢复原 conversation/thread binding；供应商切换不得清 binding、另建会话或改变内部 `omnimind` profile。
6. 任一步失败则回滚旧 config/auth、active id、模型库、session 和 thread binding；UI 显示真实失败，不出现假成功。
7. 日志只记稳定供应商 id、endpoint host、catalog generation 和结果；禁止记录 Key、token、完整 auth/header，用户备注名也不作为运行时身份。

预计区域：

- `ui/lib/services/model_provider_config_service.dart`
- `ui/lib/services/codex_app_server_service.dart`
- `ui/lib/services/codex_model_catalog_loader.dart`
- `ui/lib/features/home/pages/codex/codex_setting_page.dart`
- 可新增 `ui/lib/features/home/pages/codex/widgets/codex_provider_selector.dart`
- `app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerManager.kt`

### A1 · 默认审批与自动审批真实链

三档继续与上游 TUI 对齐：

| UI | approvalPolicy | approvalsReviewer | sandbox |
|---|---|---|---|
| 默认审批 | `on-request` | `user` | `workspaceWrite` + `/workspace` |
| 自动审批 | `on-request` | `auto_review` | `workspaceWrite` + `/workspace` |
| 完全访问 | `never` | `user` | `dangerFullAccess` |

不把普通 `pwd/ls` 无弹卡判为失败。真实验收使用确定性升级任务：

`只尝试创建 /root/omnibot-ap-probe.txt；不要改用 /workspace 或其他替代路径。`

实现与诊断要求：

1. 为一次请求补齐可关联的结构化链路日志：
   `turn_start → native_server_request_received → request_registered → flutter_event_received → approval_prompt/auto_review_started → decision → respondToServerRequest → terminal`。
2. Flutter 显式处理并记录上游：
   - `item/autoApprovalReview/started`
   - `item/autoApprovalReview/completed`
3. 默认审批必须能拒绝和批准：
   - 拒绝后文件不存在、turn 得到拒绝结果；
   - 批准后 `respondToServerRequest` 成功、动作继续。
4. 自动审批必须有 started/completed、outcome/decision source 和动作终态；正常自动决策不伪装成人工卡，只有上游明确升级人审时才显示卡。
5. 完全访问用同一任务不得出现人工审批卡。
6. 如果确定性探针仍失败，只修第一个缺失断点：
   - Native 连 `requestApproval` 都没收到：核对实际 turn policy、工具升级参数和 app-server schema；
   - Native 收到但未注册：修 envelope/method 解析与 lifecycle registry；
   - 已注册但 Flutter 未收到：修 EventChannel owner/generation/replay；
   - Flutter 收到但无 prompt/card：修 route/reducer identity；
   - card 有但 response 失败：修 generation/requestId/response registry。

禁止在不知道首个断点时重写整个审批模块。

预计区域：

- `app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerManager.kt`
- `ui/lib/services/codex_event_reducer.dart`
- `ui/lib/services/debug_file_log.dart`
- `ui/lib/features/home/pages/command_overlay/widgets/cards/codex_request_card.dart`
- 既有 Native lifecycle / Flutter reducer / card tests

### K1 · 性能与恢复收敛

1. Goal refresh：
   - thread 激活时至多拉取一次；
   - 同 `(conversationId, threadId)` 的 in-flight 请求合并；
   - Goal updated/cleared 走事件驱动；
   - `turn/completed` 不再无条件 `goal.get`；
   - 后台只读 `goal.get` 遇 stale 时只失效缓存，不主动新建 thread。
2. Thread/channel recovery：
   - 保留已有 `_codexThreadRecoveryFuture` single-flight；
   - 增加 conversation/generation key、同 stale id 冷却和耗时日志；
   - 同一批 stale 调用只能有一次 clear/rebind/start；
   - 旧 Flutter Engine 的 channel clear 不得拆掉新 owner。
3. 流式 UI：
   - 移除 event handler 尾部无条件整页 `setState`；
   - coordinator/message chrome 改为每帧最多一次局部通知；
   - 若消息列表仍需刷新，使用专用 notifier，不退回 event-per-page rebuild。
4. 持久化：
   - 每 runtime 保留一个 dirty 定时器，累积 flags，不在每个 delta 上反复 cancel/new；
   - turn terminal 立即 flush，异常退出也保留最后状态。
5. 日志：
   - streaming delta 不逐条 `debugPrint`，改 debug-only 采样/每 N 条汇总；
   - error、terminal、approval、recovery 仍逐条保留。
6. 观测：
   - 记录 events/s、reduce duration、frame coalesce 数、page rebuild 数、persist queue/flush duration；
   - `SchedulerBinding.addTimingsCallback` 记录 build/raster p50/p95/p99 和 >16.7ms、>32ms 帧；
   - 按 turn 前/中/后和消息数量分桶，禁止只凭主观“顺了”验收。

预计区域：

- `ui/lib/features/home/pages/chat/chat_page_codex.dart`
- `ui/lib/features/home/pages/chat/chat_page.dart`
- `ui/lib/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart`
- `ui/lib/services/codex_app_server_service.dart`
- `app/src/main/java/cn/com/omnimind/bot/ui/channel/CodexAppServerChannel.kt`

## 3. 执行顺序

严格按以下顺序集成，避免 Goal bug 继续污染审批测试：

1. G1 Goal 状态/独立编辑器。
2. C1 公共默认 + P1 供应商切换。
3. A1 原生审批链和自动审批事件。
4. K1 热路径与恢复收敛。
5. 最终静态 review → 远端九路 → 同 SHA APK → 真机矩阵。

## 4. 并行工作线与文件锁

目标编排为 1 个主线程 + 8 条 worker 工作线；主线程只做范围控制、冲突消解、diff 审查、门禁调度和验收。

当前运行时硬上限只有 4 个并发槽（主线程 + 3 子代理），所以本会话取证无法诚实宣称“8 个 agent 同时运行”。新对话若仍是该上限，则按两波滚动占满 3 个 worker 槽，完成即换手；逻辑工作线仍保持 8 条且禁止重复读取。

| Worker | 职责 | 独占锁 |
|---|---|---|
| W1 | Goal planner/state/RPC | `codex_mode_submit.dart`、`chat_page_codex.dart` Goal 段 |
| W2 | Goal bar/editor/composer Widget + widget tests | `codex_goal_mode_bar.dart`、新 editor、`chat_input_area*` |
| W3 | 公共默认迁移与 Native config tests | `CodexAppServerManager.kt` config builder 段、ProtocolPayloadTest |
| W4 | 用户供应商记录适配、独立模型库、固定 Codex profile 与 service tests | provider/codex service 与 catalog loader |
| W5 | Codex 设置页删除偏好 + provider selector Widget | `codex_setting_page.dart`、新 selector、Widget tests |
| W6 | Native approval request/registry/channel 断点 | Manager approval 段、LifecycleRegistryTest、Channel tests |
| W7 | Flutter approval/auto-review reducer/card/日志 | reducer、request card、DebugFileLog 及其测试 |
| W8 | 性能 coalesce/persistence/recovery 与指标 | runtime coordinator、`chat_page_codex.dart` 性能段、性能测试 |

锁规则：

- `chat_page_codex.dart` 是 W1/W8 的共享热点：W1 先交付并由主线程验收后，锁才转给 W8。
- `CodexAppServerManager.kt` 是 W3/W6 的共享热点：W3 完成 config 段后再转锁给 W6。
- 同一文件绝不并行写；其他 worker 可并行写测试或做只读审查。
- 子代理不得自行扩大到图片、语音、普通聊天或仓库清理。

## 5. 远端测试与真机验收

### 5.1 必补自动化

G1：

- active Goal + editor closed + 普通正文 → normal turn；
- 点击 Goal 条 → 预填 → 保存只调用一次 goal/set；取消零写入；
- 保存后下一条 `？` 是普通消息，Goal 不变；
- clear/complete/切会话不复活旧 editor 草稿。

C1：

- Codex 设置页不存在 Fast、自动压缩、默认 Goal 控件；
- 旧配置迁移一次后得到 `fast=false`、无 fast tier、`auto_compaction=true`、无 default Goal；
- 供应商切换不覆盖迁移后的公共 feature。

P1：

- 供应商记录序列化、备注名改名、兼容性禁用原因和 A→B→A；
- 所有切换前后 `model_provider`、provider table 和内部 `name` 均严格保持 `omnimind`；
- A/B 的手动模型、远端模型、缓存和当前模型完全隔离，迟到结果不能串库；
- config/auth 两文件原子替换与任一步失败回滚；
- active id 只在成功后提交；必要的 session 重连最多一次，并恢复同一 conversation/thread binding；
- catalog generation latest-wins，旧供应商结果不得闪回；
- key/header 不进入日志、文档或错误文本。

A1：

- triad 在 startThread/startTurn/settings 三处一致；
- 三类 `requestApproval` schema 均能注册、路由、响应；
- auto-review started/completed reducer 与日志；
- duplicate response first-wins、旧 generation invalidated、重连 replay 有界。

K1：

- 1000 个 delta 回放仍完整 reduce，但每帧最多一次 UI invalidate；
- 同一 thread 激活 Goal GET 至多一次；
- 并发 stale 只发生一次 recover/startThread；
- 旧 channel detach 不清除新 owner；
- persistence 累积 flags 且 terminal flush。

### 5.2 远端九路

最终整合 SHA 只触发：

`.github/workflows/baseline-standard-debug.yml`

必须同一 SHA 全部成功：

- Flutter test shard 0/1/2/3：4 路
- Flutter analyze：1 路
- Android unit / lint / signed APK：3 路
- source-policy：1 路
- `Nine-way gate summary` 汇总成功

本机禁止执行上述 Flutter/Gradle 命令。远端 APK 必须记录 run URL/ID、artifact id、commit SHA、APK SHA-256、证书 SHA-256 和固定 Download 路径。

### 5.3 同 APK 真机矩阵

| ID | 操作 | PASS |
|---|---|---|
| G1 | 设置 Goal 后依次发送 `？`、普通任务 | 两条均为普通 turn；Goal 不变 |
| G2 | 点击 Goal 条编辑、取消、再保存 | 取消不变；保存一次更新；X 可清除 |
| C1 | 打开 Codex 设置 | 无“通用运行偏好”；公共配置值符合迁移规则 |
| P1 | 用户供应商 A→B→A | 备注名/API/Key/当前模型及各自模型库同步切换；内部 profile 始终为 `omnimind`，conversation/thread 不变，必要重连最多一次 |
| P2 | 模拟错误 Key/不可兼容供应商 | 阻止或失败回滚；旧供应商、模型库和原会话配置仍完整 |
| P3 | 改供应商备注名后继续会话 | 模型库和当前模型不丢；内部 `omnimind` profile、conversation/thread 均不改变 |
| AP0 | default 下 `/workspace` 内 `pwd/ls` | 允许无卡，这是官方预期 |
| AP1 | default 下确定性 `/root/omnibot-ap-probe.txt` 越界写 | `requestApproval → approval_prompt/card` |
| AP2 | 对 AP1 先拒绝再批准 | 拒绝不写；批准 response 成功并继续 |
| AP3 | autoReview 下重复 AP1 | turn 为 `auto_review`；started/completed/outcome 可观测 |
| AP4 | fullAccess 下重复 AP1 | `never + dangerFullAccess`，无人工卡 |
| AP5 | 重连/双 Engine | 旧卡失效、单终态、新请求仍可响应 |
| K1 | 10 分钟长会话 + 流式工具输出 | 无 connect/thread/goal.get 风暴，无重复卡/回复 |
| K2 | 导出性能摘要 | 有 frame p50/p95/p99、jank、events、rebuild、persist 指标 |

探针文件在 AP2/AP4 完成后删除。任何一项失败，状态最高只能记 `DEVICE_PARTIAL`。

## 6. 交付状态与停止条件

状态只按证据推进：

`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_PARTIAL → DEVICE_PASS → READY`

- 源码改完但未远端九路：只能 `IMPLEMENTED`。
- 九路全绿但未装同 SHA APK：只能 `REMOTE_VERIFIED`。
- 真机没有完整 G/C/P/AP/K 证据：不得写 `DEVICE_PASS` 或 `READY`。
- 任一阶段发现需要扩大到五项之外，立即退回计划阶段，不自行顺手修。

请确认是否按此计划执行。
