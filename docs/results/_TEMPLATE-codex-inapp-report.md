# 仓内 Codex 功能自测报告 — {{DATE}}

> 用法：在 **OmniBot 已 connect 的 Codex 会话**里，把下面「给 Codex 的提示词」整段发出；  
> 把 Codex 的回复与工具输出整理进本报告（或让它按结构直接写 Markdown）。

## 给 Codex 的提示词（可复制）

```text
你是本机 OmniBot 内的 Codex。请做功能自测并输出 Markdown 报告，不要问我确认。
约束：只读优先；需要 shell 时用最小命令；不要泄露 API key / token / 文件里的密钥。

请按序执行并记录每步：PASS/FAIL、命令、关键输出（截断到 20 行内）：

1) 环境：pwd；uname -a；whoami；echo "CODEX_HOME=$CODEX_HOME"；ls -la /workspace 2>/dev/null || ls -la /root
2) codex 可用性：command -v codex；codex --version 2>&1 | head -5
3) 工作区写：在 /workspace 或当前可写目录创建文件 omnibot-selftest-<时间戳>.txt 写入一行 hello，再 cat 验证，最后 rm
4) 网络（若策略允许）：curl -sI https://example.com | head -5；若失败只记错误类型
5) 结论：用表格输出步骤结果；最后一行写 GATE: PASS 或 GATE: FAIL 及一句话原因

报告标题：# OmniBot In-App Codex Selftest
```

## 执行元信息
| 项 | 值 |
|----|-----|
| APK / 版本 | |
| 会话模式 | Local Codex |
| 模型 | |
| 开始/结束时间 | |

## Codex 原始输出（可附）
```
```

## 结构化结果（人工整理或 Codex 已输出）

| 步骤 | 结果 | 证据摘要 |
|------|------|----------|
| 1 环境 | | |
| 2 codex CLI | | |
| 3 写文件 | | |
| 4 网络 | | |

## GATE
- [ ] PASS — shell 工具闭环可用  
- [ ] FAIL — 原因：

## 对精简主线的含义
- PASS → S1/S2 金线满足工具侧  
- FAIL 在 connect 之后 → 查 proot/codex 安装，**不要**用删 assists 来「修」  
- 仅聊天无工具 → 标 PASS-B，保持壳，查模型/上下文
