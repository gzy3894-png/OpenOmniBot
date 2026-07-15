# 结果交付区（你只看这里）

> 角色：主线程编排 · 你只收结果 · 真机/仓内 Codex 可填报告  
> 路线：[`../slim-roadmap.md`](../slim-roadmap.md)

## 目录约定

| 路径 | 谁写 | 内容 |
|------|------|------|
| `DELIVERY.md` | 主线程 | 当前该装哪个包、测什么、通过标准 |
| `reports/YYYY-MM-DD-*.md` | 你或仓内 Codex | 测试报告（用模板复制） |
| `../smoke-codex.md` | 固定清单 | 冒烟步骤真源 |
| `_TEMPLATE-smoke-report.md` | 模板 | 复制改名填写 |
| `_TEMPLATE-codex-inapp-report.md` | 模板 | 应用内 Codex 自测报告 |

## 你怎么配合（最少动作）

1. 打开本目录 `DELIVERY.md` → 装指定 APK  
2. 按清单点测，或把清单丢给**已能跑 shell 的仓内 Codex**，让它写 `reports/...`  
3. 把报告路径丢回主线程（或只说 PASS/FAIL + 卡在第几步）

## 主线程承诺

- 不一次砍模块；每步可回滚  
- 交付单写清：包从哪来、sha256、Stage、期望  
- FAIL → 只回滚当前 Stage，不叠刀
