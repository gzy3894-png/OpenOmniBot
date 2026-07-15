# 冒烟报告 — {{DATE}} — {{STAGE}}

## 元信息
| 项 | 值 |
|----|-----|
| 报告人 | 用户 / 仓内 Codex / 其他 |
| Stage | S1 基线 / S2.x / … |
| APK 文件名 | |
| versionName / versionCode | |
| sha256 | |
| 安装方式 | 覆盖 / 卸载重装 |
| 设备 | 型号 · Android 版本 |
| 是否开无障碍 | 是 / 否 |

## 结果总表

| # | 步骤 | 结果 PASS/FAIL/SKIP | 备注 |
|---|------|---------------------|------|
| 1 | 冷启动进壳 | | |
| 2 | Codex 模式/设置 | | |
| 3 | Local connect | | |
| 4 | 发 `pwd && ls` 类指令 turn 完成 | | |
| 5 | 工具：PASS-A 有 commandExecution / PASS-B 仅文本 / FAIL 崩溃 | | |
| 6 | 再闲聊稳定 | | |

## 总判定
- [ ] **GATE-PASS**（可进入下一 Stage）  
- [ ] **GATE-FAIL**（阻塞，要求回滚）  
- [ ] **PASS-B**（壳稳但无工具 — 可继续行为降级，不可删模块）

## 日志摘要（打码密钥）
```
（粘贴 codex / app-server / proot 相关行）
```

## 建议下一动作
（主线程填或报告人建议）
