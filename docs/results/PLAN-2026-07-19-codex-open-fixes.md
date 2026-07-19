# PLAN · Codex 待修清单与下一波方案 · 2026-07-19

> 阶段：**PLANNED**（等你确认执行范围）  
> 仓：`/root/workspace/omnibot-product` · 分支 tip `9f6af93` / 功能 `210fc98`（web_search）叠在 `secondary/s1-b38-hardening`  
> 站规：主线程方案/调度/验收 · 子代理实现 · push **仅 mine** · GHA only · 禁本机 assemble · tip ≠ PASS  
> 状态机：`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED → DEVICE_* → READY`  
> 本文件回答：**还有哪些要修、按什么顺序、本波建议做什么 / 明确不做什么**

---

## 0. 一句话现状

| 线 | 状态 | 对你体感 |
|----|------|----------|
| web_search P0+P1 | **APK_STAGED** `210fc98` · 真机未验 | 设置页可改；**不**解决自动审 |
| 供应商独立化 | **APK_STAGED** `ef757a0` · S1–S8 未跑 | 管理页隔离已有；真机矩阵空 |
| B38 审批环硬化 | 源码大量 IMPLEMENTED · **设备未证 requestApproval 端到端** | 三档 UI 在；自动审仍可选 |
| 「去掉自动审 + 默认更严」 | **从未实现**（上波 EXEC 写死不纳入） | **图里自动审还在 = 正常，不是装错包** |

**本版 `210fc98` 实际交付**：conf/设置的 `web_search` + 文案。  
**没有交付**：去掉自动审、默认 untrusted、审批链真机 PASS、供应商 S1–S8、web P2。

---

## 1. 待修 backlog（按用户伤害排序）

### P0 · 权限菜单：去掉「自动审」（你刚确认的主诉）

| 项 | 内容 |
|----|------|
| 现象 | composer 三档：请求审批 / **自动审** / 全放行；自动审对你 **不能用 / 不可信**，仍可选 |
| 代码 | `CodexPermissionMode { defaultMode, autoReview, fullAccess }` · 菜单 `CodexPermissionMode.values` 全列出 · 映射 `autoReview → on-request + auto_review + workspaceWrite` |
| 根因 | 产品仍暴露上游 `ApprovalsReviewer::auto_review` 档；本波未动 |
| 目标 | **菜单不再出现「自动审」**；已持久化的 autoReview 启动时 **降级** 到 default（请求审批） |
| 非目标 | 本波不实现可用的 auto_review/guardian 子代理自动决策（那是另一产品能力） |

**推荐映射（二选一，见 §3）**

| 档 | 现网 | 方案 A（推荐，改动小） | 方案 B（更严） |
|----|------|------------------------|----------------|
| 请求审批 | on-request + user + workspaceWrite | **保留为唯一默认** | 改为 **untrusted**（更底层：更多动作需批）+ user |
| 自动审 | on-request + auto_review | **删除 UI 入口**；读到历史值 → 降级 default | 同左 |
| 全放行 | never + dangerFullAccess | 保留（高危，文案警告） | 保留或二次确认 |

> 上游备注：官方 `OnRequest` ≠ 每次工具都弹；越界/升级才 `requestApproval`。  
> 用户口述「默认更底层 untrusted」→ 走 **方案 B**；若只要「别再看见自动审」→ **方案 A** 足够。

**改动面（文件所有权）**

| 文件 | 动作 |
|------|------|
| `ui/.../chat_input_area.dart`（两处 enum） | 去掉 `autoReview` 或 UI 白名单只暴露 2 档 |
| `ui/.../chat_input_area_composer.dart` | 菜单迭代改为显式列表，不含 autoReview |
| `ui/.../chat_page_codex.dart` | 映射/标签/settings 路径；读持久化 autoReview → default |
| `ui/.../chat_page.dart` 等引用 | 编译期清 enum |
| 单测 | 菜单项数、映射、降级 |

**验收（设备）**

- D1 菜单 **只有**「请求审批」「全放行」（或方案 B 文案）  
- D2 旧会话/旧 prefs 选过自动审 → 打开后是请求审批，**无**自动审入口  
- D3 请求审批下：能触发越界动作时出现 **requestApproval 卡**（若仍无卡 → 并入 P0.b）  
- D4 tip 单独 ≠ PASS

---

### P0.b · 审批链仍可能「只有 UI」（B38 T6 残余）

| 项 | 内容 |
|----|------|
| 现象 | 历史日志曾无 `requestApproval` / 决策线；triad 写入 ≠ 审批环成功 |
| 已做 | B38 大量 native/UI 硬化（generation、replay、幂等卡）· APK_STAGED 多代 · **DEVICE 未闭环** |
| 目标 | 固定探针：workspace 越界 shell / 网络 → 必出 `requestApproval` → 用户批/拒 → turn 继续/停 |
| 验收 | 日志含 request 与 decision；UI 卡可点；失败不假 success tip |

与 P0 可同包：先去自动审，再探针验 default/全放行两条。

---

### P1 · web_search 真机 + soft 热更新未知

| 项 | 内容 |
|----|------|
| 已做 | conf 读写、设置三段、S-Default-A、GHA 绿、APK stage |
| 未做 | 真机改设置看 `config.toml`；soft write 后 **进程是否立刻** 用新 mode |
| 可选加固 | 改 `web_search` 时 tip「新会话更稳妥」；或硬重启 session（与 soft 策略权衡） |
| P2 | MCP/smart-search 桥：**另波**，本清单只挂名 |

---

### P1 · 供应商独立化真机 S1–S8

| 项 | 内容 |
|----|------|
| 已做 | Store/管理页/catalog/switch · `ef757a0` 九路 · stage |
| 未做 | S1–S8 设备矩阵（隔离、切换回滚、模型库不串、失败不回落 Agent） |
| 动作 | **验收项**，不是新功能开发；装当前 tip 包跑矩阵写回 EXEC |

---

### P2 · 历史 UX / 性能债（有 PLAN，未当主诉）

| ID | 来源 | 摘要 | 建议 |
|----|------|------|------|
| Goal 输入劫持 | PLAN-07-19 goal-provider… G1 | 有活动 Goal 时普通输入变 setGoal | 若仍复现 → 单独立项 |
| 通用运行偏好设置段 | 同 PLAN C1 | 曾要求删 Fast/压缩/默认 Goal 段 | 与现网「命令可开关」冲突，**先确认是否仍要** |
| UI 热路径 | 同 PLAN 性能 | 每 event setState/debugPrint | 有卡顿证据再开 |
| Goal/技能/审查灰块 | PLAN-07-15-goal-skill-review-layout | 底栏/附言/排版 | 低优先，未批准不碰 |
| B38 models HTTP 真源 | B38 T3 | `/models` vs model/list | 供应商线部分 supersede；列表异常再开 |

---

### P3 · 明确不做 / 观望

- 上游 standalone `web.run`  
- 实现「真正能用的自动审」（guardian/auto_review 产品化）——与「去掉不能用的入口」相反  
- 本机 Gradle assemble  
- 未授权的 origin push  

---

## 2. 推荐下一波（一包说清）

### Wave A · **权限收口**（强烈推荐先做）

**范围**

1. 去掉「自动审」UI + 历史值降级（§1 P0）  
2. 默认策略：**方案 A 或 B**（你拍板）  
3. 全放行保留 + 危险文案  
4. 最小单测 + push mine + 九路 + stage  
5. 真机 D1–D4；有余力跑 P0.b 探针  

**不做**：web P2、供应商新功能、Goal/性能大改、重新发明审批协议  

**工期感**：1 实现波 + 1 GHA + 真机半小时级探针  

### Wave B · **验收债**（可并行由你/设备，少改码）

- web_search：设置 → conf 抽检  
- 供应商 S1–S8  
- 写回两份 EXEC  

### Wave C · **能力补全**（后置）

- web P2 MCP/search 桥  
- Goal 劫持若仍在  
- 性能帧指标  

---

## 3. 需要你拍板的 3 个点

1. **下一波是否 = Wave A（去自动审）？**  
2. **默认档**：  
   - **A** 保持「请求审批」= on-request + workspaceWrite（推荐，风险低）  
   - **B** 默认改 untrusted（更严，升级更勤；需对齐上游 AskForApproval 语义）  
3. **全放行**：保留 / 二次确认 / 暂时隐藏  

---

## 4. 实施步骤（Wave A 获批后）

| 步 | 谁 | 内容 |
|----|----|------|
| 1 | 主线程 | 锁方案 A/B；写 EXEC；文件锁 |
| 2 | 子代理 | enum/菜单/映射/降级/测 |
| 3 | 主线程 | 静态审 diff；禁密钥；push mine |
| 4 | GHA | 九路 SUCCESS |
| 5 | 主线程 | stage APK；更新 EXEC `APK_STAGED` |
| 6 | 设备 | D1–D4（+ 可选 requestApproval 探针） |
| 7 | 主线程 | 有证据再 `DEVICE_*`；禁止 tip=PASS |

---

## 5. 风险

| 风险 | 缓解 |
|------|------|
| 删 enum 漏引用导致编译挂 | 全仓 rg autoReview；GHA Flutter analyze |
| 历史 prefs 卡在 autoReview | 读时强制 map → default |
| 去入口后用户以为「更不能批了」 | 默认仍是请求审批；文案说明 |
| untrusted（B）触发过多卡 | 先 A，B 作可后续开关 |
| 与「自动审批要走原生」旧 PLAN 冲突 | 旧文是 **修好 auto 链**；你现裁决是 **不要这档** → 以本 PLAN 为准 |

---

## 6. 完成标准（Wave A）

- [ ] 菜单无「自动审」  
- [ ] 默认 = 你选的 A 或 B  
- [ ] 全放行行为符合拍板  
- [ ] 九路绿 + APK stage + sha/cert 入 EXEC  
- [ ] 真机 D1–D2 必过；D3/D4 记证据  
- [ ] **未** READY 除非 DEVICE_PASS  

---

*claude 主线程 · 2026-07-19 · PLANNED · 等确认*
