# Debug 固定签名（二次开发内测）

## 为什么

GHA runner 默认 debug keystore **每次/每机可能不同**。  
换签后无法覆盖安装 → 用户配置的 GPT/模型会随卸载清空。

## 机制

| 层 | 行为 |
|----|------|
| `app/build.gradle.kts` | `signingConfigs.stableDebug` 读 `AWB_DEBUG_KEYSTORE_FILE`（或 `PATH`）+ store/key 密码与 alias |
| debug buildType | 若 keystore 文件存在且四元组齐全 → 用 `stableDebug`；否则回落 AGP 默认 debug |
| GHA `baseline-standard-debug.yml` | 从 secrets 解出 jks 到 `RUNNER_TEMP`，导出 env；**缺 secret 直接失败**（禁止静默临时签） |

Secrets（fork `OpenOmniBot`，勿写入 git）：

- `AWB_DEBUG_KEYSTORE_BASE64`
- `AWB_DEBUG_STORE_PASSWORD`
- `AWB_DEBUG_KEY_ALIAS`
- `AWB_DEBUG_KEY_PASSWORD`

## 证书指纹（期望）

```
Alias: agent-workbench-debug
SHA256: 6D:79:D3:52:E6:8F:C7:E1:95:6F:E1:4C:41:B6:AF:FA:D2:A1:40:3E:B2:2A:F9:E7:6B:4E:21:3F:A1:02:44:C6
```

与历史 AWB 内测 jks 同源，便于本机工具链复用；**不**等于正式 release 签。

## 装包

- applicationId：`cn.com.omnimind.bot.debug`
- 首次从临时签切到固定签：需卸载一次
- 之后同证书 APK 可直接覆盖升级，保留数据
