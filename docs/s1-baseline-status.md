# S1 基线状态

- 业务：S1 基线本身不删模块、不改 applicationId；后续 Codex 修复仍在同一分支持续迭代
- 签名：`app` debug 优先 `stableDebug`（env `AWB_DEBUG_*`）；GHA secrets 已配置于 `gzy3894-png/OpenOmniBot`
- 期望 cert SHA256：`6D79D352E68FC7E1956FE14C41B6AFFAD2A1403EB22AF9E76B4E213FA10244C6`
- standard 构建：**PASS**，GHA `29542819162`（HEAD `4902430`）
- APK：`/storage/emulated/0/Download/OpenOmniBot-s1-standard-debug.apk`
- APK SHA256：`0817dadb1ab2f90a46cfbcef4be3be5be7cad8a7ae2466098c89575108a5af02`
- 未删模块、未改 applicationId 品牌；真机冒烟仍待用户点验
