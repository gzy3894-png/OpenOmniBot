# impl-b25-perm · 2026-07-17

> 证据属性：**历史实现快照，不代表当前候选已验证**。2026-07-18 从本地遗留报告定向纳入；原文件 SHA-256：`7f9a94faff53c53b009eaecc838eba25b6717ef7a5ed4e9fc329c449351d996d`。
> 治理审查：未发现 token、密钥、认证头、个人信息或需脱敏值；`/workspace` 是协议回退路径，不是个人目录。当前实施与交付状态只认 `docs/results/EXEC-2026-07-18-b38-approval-models.md`。

优先级：P0
锁：L-Perm（`chat_page_codex.dart` permission 段）+ L-Kotlin-Perm（`CodexAppServerManager.kt`）
真源：`docs/results/PLAN-2026-07-17-b22-b29.md` / `EXEC-2026-07-17-b22-b29.md`

## 结论

default / autoReview 不再下发 `writableRoots: []`（该空数组会覆盖原生 cwd 默认 → 无 exec、无审批弹窗）。
`thread/start` 改为 schema 正确的 `sandbox` SandboxMode kebab 字符串；turn/review 的 `sandboxPolicy` 在 Kotlin 侧补齐空 roots。

## 根因

1. B20 把 default/autoReview 的 sandbox 钉成显式 `workspaceWrite`，但 `writableRoots` 写死 `[]`。
   Schema 默认 `writableRoots=[]` 本意是「未指定时由 native 用 cwd」；**显式空数组会覆盖** cwd-rooted 默认。
2. Kotlin `startThread` 发 `sandboxPolicy` 对象；`ThreadStartParams` 字段是 `sandbox: SandboxMode`（`"workspace-write" | "danger-full-access" | "read-only"`），不是 policy 对象。

## 改动

| 文件 | 内容 |
|------|------|
| `ui/lib/features/home/pages/chat/chat_page_codex.dart` | `_codexResolvedWritableRoot`：remoteCwd → cwd → `/workspace`；`sandboxPolicy({required writableRoot})` 始终非空 roots；updateThreadSettings / startTurn / startReview 全路径注入；`sandboxType` 日志 getter |
| `app/.../CodexAppServerManager.kt` | `startThread` → `"sandbox" to resolveCodexSandboxMode(args)`；turn/review → `resolveCodexSandboxPolicy(..., cwd)` 填空 roots；新增 mode/policy 解析 helpers |
| `app/src/test/.../CodexAppServerProtocolPayloadTest.kt` | mode kebab 映射 + 空 roots 填充 + fullAccess 透传 |

### Dart 映射（保持 B20）

| mode | approvalPolicy | approvalsReviewer | sandboxPolicy |
|------|----------------|-------------------|---------------|
| default | `on-request` | `user` | `workspaceWrite` + **非空** `writableRoots:[cwd]` |
| autoReview | `on-request` | `auto_review` | 同上 |
| fullAccess | `never` | `user` | `dangerFullAccess`（无 roots） |

### Kotlin

- **thread/start**：`sandbox` = 显式 kebab，或从传入 policy type 推导，默认 `workspace-write`；仍带 `approvalPolicy` / 可选 `approvalsReviewer`。
- **turn/start & review/start**：`sandboxPolicy` 经 `resolveCodexSandboxPolicy`：空/缺 roots → cwd（sanitize 失败用 `DEFAULT_WORKSPACE_CWD=/workspace`）。
- fullAccess / readOnly 原样透传。

## 验收（静态）

- `rg "writableRoots.: <String>\\[\\]"` → 无
- `startThread` 含 `"sandbox" to resolveCodexSandboxMode`，无 `sandboxPolicy` 键
- turn/review 使用 `resolveCodexSandboxPolicy`
- ProtocolPayloadTest 含 B25 三测：mode kebab / 空 roots 填充 / 非空与 fullAccess 保留

## 未做 / 非本锁

- 未改 Fast 计费、effort max/ultra、@/# panel、goal enable
- 未扩 Dart `startThread` 传 approval/sandbox（turn/settings 已带 policy；Kotlin start 默认 workspace-write）
- 未 commit / push / Gradle / 真机
- `thread/settings/update` 仍透传 Flutter payload（Dart 已保证非空 roots）

## 真机测点

1. 默认权限：需授权动作 → 审批卡；可批后执行
2. 日志 `permission_set` / `turn_start`：sandbox=`workspaceWrite`，非 empty roots
3. fullAccess 仍可用（never + dangerFullAccess）
4. 新 thread：start 侧为 `sandbox=workspace-write`
