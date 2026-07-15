# S1 基线状态

- 业务：相对 `b157e16` **零业务逻辑改动**（仅文档 + 基线 CI + **固定 debug 签名**）
- 签名：`app` debug 优先 `stableDebug`（env `AWB_DEBUG_*`）；GHA secrets 已配置于 `gzy3894-png/OpenOmniBot`
- 期望 cert SHA256：`6D79D352E68FC7E1956FE14C41B6AFFAD2A1403EB22AF9E76B4E213FA10244C6`
- 旧包（临时签，勿深配）：`34d08d8e…` / GHA 29379975277
- 新包：构建中 → 见 `docs/results/DELIVERY.md`
- 未删模块、未改 applicationId 品牌
