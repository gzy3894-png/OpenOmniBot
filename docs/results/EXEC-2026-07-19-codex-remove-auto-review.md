# EXEC · 去掉自动审（Wave A / 方案 A）· 2026-07-19

> 真源：`PLAN-2026-07-19-codex-open-fixes.md` §P0 Wave A  
> 阶段：**APK_STAGED**（待真机 D1–D3）  
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
| 源码 HEAD | `c84f1dcfbc080d0f8ef3e207ae2128d246163ccb` |
| 分支 | `secondary/s1-b38-hardening` |
| GHA | [29689075337](https://github.com/gzy3894-png/OpenOmniBot/actions/runs/29689075337) · success · 九路全绿 |
| Artifact | `8443118879` (`omnibot-standard-debug-apk`) |
| APK_SHA256 | `8010a4dace5956d2ec42eed0a16be613769cd68ccc3e440ea9354ee895619a7d` |
| CERT_SHA256 | `6D79D352E68FC7E1956FE14C41B6AFFAD2A1403EB22AF9E76B4E213FA10244C6` |
| stable | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk` |
| immutable | `/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug-c84f1dc-8010a4da.apk` |
| 真机 D1 菜单无自动审 | （待） |
| 真机 D2 默认请求审批 | （待） |
| 真机 D3 全放行可选 | （待） |

## 验收

- D1 菜单只有「请求审批」「全放行」  
- D2 默认请求审批（on-request + user + workspaceWrite）  
- D3 全放行仍可选  
- tip ≠ PASS · 无 DEVICE_PASS 不标 READY  

## 状态机

`PLANNED → IMPLEMENTED → REMOTE_VERIFIED → APK_STAGED` ✅  
下一站：`DEVICE_*`（装 immutable 包验 D1–D3）

---
*claude · 2026-07-19*
