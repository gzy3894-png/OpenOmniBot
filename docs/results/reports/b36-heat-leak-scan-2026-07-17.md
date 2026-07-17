# B36 发热 / 内存泄漏扫描 · 2026-07-17

**范围：** PLAN-2026-07-17-b34-fast-perm-leak §5  
**模式：** 只读静态 + OmniBotLogs 对照 → 有硬证据后最小修复  
**基线：** B30–B33 `5542b47`

---

## 总表

| # | 嫌疑点 | 严重度 | 结论 | 本波动作 |
|---|--------|--------|------|----------|
| 1 | Codex event / permission / config 监听 bind-unbind | P2 低 | ChatPage dispose 配对 cancel；无未 dispose 硬泄漏 | 未改 |
| 2 | `writeLocalConfig` 无条件 `session?.disconnect()` | **P0 高** | Fast/auto-compact/阈值写 conf 杀 session → `thread not found` + 重连热 | **已修** 软字段跳过 disconnect |
| 3 | 顶栏 `onHeightChanged` setState 风暴 | P2 低 | post-frame 去抖 + 0.5px 阈值 | 未改 |
| 4 | B31 slash/skills panel flag | P2 低 | shouldUpdate 门闸；@ 每键 setState 属预期 | 未改 |
| 5 | Fast/perm 连续 setState | P2 低 | same-mode early return；perm 不写 conf | 未改 |
| 6 | Remote 2s poll / debugPrint | P1 中 | remote 会话 2s snapshot；每 event debugPrint | 未改（待真机确认 remote 是否常开） |

---

## P0 硬证据与修复

### 证据

`CodexAppServerManager.kt` 原 `writeLocalConfig` 成功后：

```kotlin
sessionMutex.withLock {
    session?.disconnect()
    session = null
    ...
}
```

任意 conf 写（含 Fast / auto_compaction / threshold）都会拆 session。  
真机 log `OmniBotLogs/omnibot-debug-20260717.log`：`fast_set` ×3 伴随 `thread not found`。

### 修复（本波）

- 写前读取 previous remote + existing toml/auth  
- **仅** 当 remote 硬字段 或 local model/baseUrl/apiKey 变化（或首次 bootstrap）时 disconnect  
- soft：`fast_mode` / `auto_compaction` / `service_tier` / threshold / effort / defaultGoal → **保留 session**

文件：`app/src/main/java/cn/com/omnimind/bot/codex/CodexAppServerManager.kt`

---

## 监听生命周期（无泄漏）

| 位置 | 行为 |
|------|------|
| `chat_page_lifecycle.dart` init/dispose | events listen + cancel |
| `CodexAppServerService` | 进程级 broadcast 单例 listen |
| `CodexAppServerChannel.kt` | onListen / onCancel 对称 |

**未改原因：** 无未 dispose 硬证据。

---

## 其它热源（未改）

1. Remote `Timer.periodic(2s)` thread snapshot — 常开 remote 时持续 RPC  
2. 每 Codex event `debugPrint` — 长 turn logcat 噪  
3. Tool strip 1.2s / greeting 轮播 — dispose 已 cancel  

---

## 真机下一步

1. 只拨 Fast 开/关 5 次：不应再出现 `thread not found`；session 保持  
2. 改 baseUrl/model/apiKey：仍应 reconnect  
3. 5–10 min 对话对比发热（主观）  
4. 可选 logcat：`disconnect` 次数 vs 改 conf 次数  

---

## Top 3

1. **P0** conf 写无条件杀 session — **本波已软字段跳过**  
2. **P1** remote 2s poll（若常开）  
3. **P2** 监听正常；height/panel 无风暴硬证据  
