# EXEC · 去掉自动审（Wave A / 方案 A）· 2026-07-19

> 真源：`PLAN-2026-07-19-codex-open-fixes.md` §P0 Wave A  
> 阶段：**IMPLEMENTED**（待 GHA / stage / 真机）  
> 约束：以**删减**为主，净减代码；默认 **请求审批**；全放行保留  
> 站规：push 仅 mine · GHA only · tip ≠ PASS

## 改动

| 文件 | 动作 |
|------|------|
| `chat_input_area.dart` | enum 仅 `defaultMode, fullAccess`；删 auto 图标常量 |
| `chat_input_area_composer.dart` | 标签/图标 switch 去 auto |
| `chat_page_codex.dart` | 映射/标签/roots 守卫去 auto；reviewer 恒 `user` |
| `chat_input_area_test.dart` | 菜单断言 2 项；选 fullAccess |

模式仅内存态（默认 `defaultMode`），无 prefs 降级逻辑。

## 账本

| 字段 | 值 |
|------|-----|
| 源码 HEAD | （commit 后填） |
| GHA | （待） |
| APK | （待） |
| 真机 D1 菜单无自动审 | （待） |

## 验收

- D1 菜单只有「请求审批」「全放行」  
- D2 默认请求审批（on-request + user + workspaceWrite）  
- D3 全放行仍可选  
- tip ≠ PASS  

---
*claude · 2026-07-19*
