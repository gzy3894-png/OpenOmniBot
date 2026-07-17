# 下阶段清单 · 2026-07-16 真机回归缺口 + Fast 计费事故

> 角色：**主线程只方案/调度/验收**；禁止主线程写业务码  
> 真源：`codex-cli-core-implementation-logic.zh-CN.md` + `/tmp/codex-schema.PDR9ft/v2/*` + 本机 `/root/.codex/config.toml` + 设备日志 `Download/OmniBotLogs/omnibot-debug-20260716.log`  
> 仓：`omnibot-product` · `secondary/s1-baseline` · push **仅 mine**  
> 上一包：`ee07854` / GHA 29438529208 / APK s1-standard-debug READY  
> 本文件：缺口真源；**已实现并 READY**（见 DELIVERY · `4902430`）

---

## 0. P0 事故结论：Fast「关了」但可能仍在计费

### 0.1 用户现象
- UI 提示已关 Fast、按钮也关
- 后台仍显示 Fast 未关 → **巨额费用**
- 要求：去掉「通用运行偏好」默认写入 fast/goal；默认必须写入 **fast=false**；对照本机 codex 配置，禁止瞎猜

### 0.2 设备日志（DebugFileLog）
| 时间 | 事件 | 含义 |
|------|------|------|
| 08:12:48 | `[model] fast_on serviceTier=fast` | UI 打开 Fast，**仅打了本地日志** |
| 08:13:43 | `[model] fast_off serviceTier=off` | UI 关闭 Fast，**同样仅本地日志** |

日志**没有** `thread/settings/update`、`serviceTier` 下发成功/失败、config.toml 写回、turn 实际 `serviceTier` 回执。  
→ 当前日志**无法证明**服务端/会话已关 Fast；只能证明 UI 状态翻转。

### 0.3 代码根因（已读证，非猜测）

| # | 位置 | 问题 |
|---|------|------|
| R1 | `chat_page_codex.dart` `_setCodexFastEnabled` | 只做：`setState` + `_writeCodexPreference(service_tier, fast\|off)` + 本地 tip + `DebugFileLog`。**不调用** `updateThreadSettings(serviceTier:…)`，**不写** config.toml |
| R2 | `_activeCodexServiceTierOrNull` | Fast 关时返回 **`null`**，不是显式 `"off"` / 标准档。`startThread` / `startTurn` 里 `if (serviceTier != null && notEmpty)` → **关 Fast 时 RPC 根本不带 serviceTier** → 服务端继续吃 config/会话默认（常为 fast） |
| R3 | 偏好 null 回落 | `serviceTier` 偏好为 null 时读 `readLocalConfig().isFastEnabled`；若 config 仍有 `service_tier=fast` 或 feature 开着，冷启动又变 Fast |
| R4 | Kotlin `normalizeCodexServiceTier` | `"off"/"false"/"default"` → **写成 null 并从 toml 省略**，无法用 config 钉死「关」；开才写 `service_tier = "fast"` |
| R5 | 本机 codex 真源 `/root/.codex/config.toml` | 存在 **`fast_mode = true`**（features 区）与 **`goals = true`**。产品侧若只动 `service_tier` 字符串、不处理 `features.fast_mode`，与官方/本机配置语义不对齐 |
| R6 | 设置页 `codex_setting_page` | 关 Fast 时 `serviceTier: ''` 写本地配置，同样是「省略」语义，不是显式 false |

### 0.4 协议/本机配置对齐（必须遵守）

- 协议：`/fast` = 更新 **serviceTier** 并**持久化**（`codex-cli-core-implementation-logic` 命令表）
- Schema：`TurnStartParams` / `ThreadSettingsUpdateParams` / `ThreadStartParams` 均有 `serviceTier`
- 本机 config 布尔特征：
  ```toml
  [features]   # 或同级 features 块内
  fast_mode = true   # 关必须 = false，禁止只删行
  goals = true
  ```
  另可有 `service_tier = "fast"`（字符串档）。**两套都要查清再写，禁止只猜 service_tier。**

### 0.5 P0 修复规格（下阶段执行，主线程验收）

**锁：L-Fast（billing）** — 最高优先，先于一切 UI 微调。

1. **关 Fast 必须三写 + 一证**：
   - A. 活跃 thread：`thread/settings/update` **显式** `serviceTier` 为标准档（查 schema/本机：非 fast；若协议用 null 表示 standard，须在日志打印服务端回读值）
   - B. 后续 `thread/start` / `turn/start`：关时**不得省略**到「吃默认 fast」；策略二选一（实现前用 schema+实测定一种）：
     - 显式 standard/off 值；或
     - 省略前先保证 config `fast_mode=false` 且无 `service_tier=fast`
   - C. 持久化 config：**写 `fast_mode = false`**（布尔），并清除/不写 `service_tier=fast`；**禁止**再靠「删 key」冒充关闭
2. **开 Fast**：`serviceTier=fast` + 若 features 需要则 `fast_mode=true` + 偏好 + settings/update
3. **去掉「通用运行偏好」默认写入 fast/goal**（用户明确要求）：
   - 禁止冷启动/初始化把 `service_tier=fast` 或 goal 默认写进 config/偏好
   - 默认：**fast=false**；goal 不默认开启模式（features.goals 可为能力开关，≠ UI 目标模式默认开）
4. **可观测性（否则仍算 bug）**：
   - DebugFileLog：`fast_set` 含 `ui= / pref= / settingsRpc=ok|fail / configFastMode= / turnServiceTier=`
   - 关失败必须 tip 错误，**禁止** UI 已关、底层仍开
5. **验收**：关 Fast 后立刻发 turn → 日志与（若可得）usage/响应头无 fast/priority；重启 app 仍为关；config 文件含 `fast_mode = false`

---

## 1. 下阶段 Bug 清单（用户本轮 + 日志补证）

| ID | 级 | 标题 | 根因摘要（已定位） | 锁 | 验收 |
|----|----|------|-------------------|----|------|
| **B14** | **P0** | Fast UI 关了底层仍可能 fast，产生巨额费用 | 见 §0：只写偏好、关时 serviceTier=null 省略、不写 fast_mode=false、无 RPC | L-Fast | 三写+回读日志；计费档标准 |
| **B15** | P1 | `/` 列表去掉 **stop** 与 **skill(s)** | `chat_page_ui` slash 白名单仍含 `/stop`、`/skills`；@ 已覆盖技能 | L-Slash | 列表无二者；@ 仍可用技能 |
| **B16** | P2 | `@` 按钮颜色与其它控件不一致 | `chat_input_area_composer` `@` 用 Text+IconTheme/灰底 `0xFF54627A`；slash 用 `_commandSvg` 主题 | L-Layout | 与 `/` 等同色同态 |
| **B17** | P1 | 压缩无明确成功/失败感知 | 代码有「已开始/失败/compacted」tip，但用户未见；且 **无 compact DebugFileLog**；tip 可能被清或通道未显示 | L-Compact | 开始/成功/失败三条可感知 + 日志有 compact_* |
| **B18** | P1 | 点 slash 项后：列表不收 **或** 收了但连键盘也收（goal） | 各 command 对 `_hideSlashCommandPanel` / `_requestComposerFocus` / unfocus 不一致 | L-Slash | 点后列表收起；**保留键盘**（除明确需关键盘的命令） |
| **B19** | P0/P1 | 思考等级仍可选 **max/ultra** 等模型不支持项并报错 | `_normalizeCodexReasoningEffort` 默认 `_ => text` 放行；merge 虽列 low..xhigh，仍可从列表外写入；日志已见 `effort=max`→`ultra`→`high` | L-Model | 选项=模型 `supported_reasoning_efforts`；不支持不可选；非法拒绝+tip |
| **B20** | **P0** | 权限按钮未对齐官方：默认档无法执行需授权动作，**无授权弹窗**；自动审查同失效 | `_setCodexPermissionMode` **仅 setState+tip**，不 `updateThreadSettings`；default/autoReview 的 `sandboxPolicy=null` 吃服务端默认；审批事件依赖 `requestApproval` 链路 | L-Perm | 切换即 RPC；default=on-request+user 弹窗可批；auto_review 用 schema `auto_review`；full=never+dangerFullAccess |
| **B21** | P1 | 关键路径日志不足 / 失败静默 | Fast/权限/compact/settings 缺少 RPC 级日志；用户要求「没日志也算 bug」 | L-Log | 见 §2 日志矩阵 |

### 日志已旁证（同日）
- Goal set/get、skill_path 注入、review 附言：**有日志**（B13/B3/B5 方向有效）
- `effort=max` / `ultra`：**有日志且无 effort_failed** → B19 坐实
- Fast on/off：**仅 UI 日志** → B14 坐实
- **无** permission / compact / settings 行 → B17/B20/B21

---

## 2. 日志矩阵（下阶段必补，B21）

| 事件 | 最低字段 |
|------|----------|
| fast_set | enabled, pref, settingsRpc, configFastMode, activeThreadId |
| turn_start | serviceTier(实际下发), effort, approvalPolicy, sandboxType |
| permission_set | mode, approvalPolicy, approvalsReviewer, sandbox, settingsRpc |
| approval_prompt / decision | requestId, decision |
| compact_start / compacted / compact_fail | threadId, error? |
| effort_set | value, allowedFromModel, settingsRpc |

文件仍：`Download/OmniBotLogs/`。

---

## 3. 模块锁与建议波次

| 锁 | Bugs | 并行 |
|----|------|------|
| **L-Fast** | B14 | **最先单独合入**（计费） |
| **L-Perm** | B20 | 与 L-Fast 后紧接；同改 startTurn/settings |
| **L-Model** | B19 | 可与 L-Slash 并行 |
| **L-Slash** | B15 B18 | |
| **L-Compact** | B17 | 与 L-Log 协作 |
| **L-Layout** | B16 | 小改 |
| **L-Log** | B21 | 贯穿所有锁，每锁顺带埋点 |

Wave0：只读确认 config 键名（`fast_mode` vs `service_tier`）在 **设备上** codex-home 的实际文件。  
Wave1：B14 → B20 → B19。  
Wave2：B15 B18 B17 B16 + 日志。  
Wave3：GHA + stage + DELIVERY + 真机关 Fast 计费回归。

---

## 4. 明确非目标（本阶段）

- 不改 applicationId / 上架
- 不 push origin / omnimind-ai
- 主线程不写业务码
- 不把「通用运行偏好」再做成默认开 fast/goal 的入口

---

## 5. 状态

- [x] 本轮用户缺口整理
- [x] Fast 根因只读定位（代码+日志+本机 config）
- [x] 下阶段实现（B14–B21 工作树已落地；Wave3 ship）
- [ ] 真机计费回归（DELIVERY READY，等用户）

---

## 6. 本轮交付回顾（上阶段）

- 12bugs+B13 包 READY：`OpenOmniBot-s1-standard-debug.apk`  
  sha256 `48e489540fa8b427ceec2c09288f07ce9df6b4e297d3ce9e53c13870da5e2ea7`  
  GHA success `29438529208` · 功能 `4c8ea35` · CI `ee07854`
- 真机新开缺口以 **本清单 B14–B21** 为准，不混入已 READY 包的「已修」声明
