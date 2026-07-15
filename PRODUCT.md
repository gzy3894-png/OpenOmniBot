# OmniBot 二次开发产品说明

> 工作区：`/root/workspace/omnibot-product`  
> 上游：https://github.com/omnimind-ai/OmniBot （remote 保留）  
> 决策：2026-07-15 放弃 `android-agent-product` AWB 自研主线

## 目标
在 **OmniBot 已通的 Codex 控制面 + Flutter 壳** 上做二次开发与**逐步精简**，  
**不再**维护 AWB `impl/` Host+Adapter 产品线。

## 工作方式（强制）
- **一步步精简**，禁止一刀砍模块后再修编译。  
- 顺序真源：[`docs/slim-roadmap.md`](docs/slim-roadmap.md)（S0→S5）  
- 模块认知：[`docs/module-map/`](docs/module-map/)  
- 真机金线：[`docs/smoke-codex.md`](docs/smoke-codex.md)  
- 每步：**可验收 · 可回滚**；未过冒烟不得进入下一 Stage

## 当前指针
| 项 | 状态 |
|----|------|
| S0 地图+路线 | 文档完成 |
| S1 基线 slim standard | **进行中**（本机无 Flutter/SDK 时先固化命令与 CI 对齐） |
| S2+ | 未开始 |

## P0 构建命令（唯一推荐 debug）
```bash
cd ui && flutter pub get   # 生成 .android；本机无 flutter 则改在 CI/SDK 机执行
cd ..
./gradlew :app:assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart
```
**禁止**裸 `./gradlew assemble` / `build`（会逼 `third_party/omniinfer` submodule）。

## P0 业务验收
真机 Codex：`pwd && ls` 工具链 — 见 `docs/smoke-codex.md`。  
通过后再谈包名/品牌（S5）。

## 许可
上游分段 AGPL/商业许可，见 `LICENSE`。个人二次开发默认遵守 AGPL。

## 与 AWB 关系
- AWB：`/root/workspace/android-agent-product` → `ABANDONED.md`  
- 只复用审计教训；**不复用** AWB 业务骨架

## 角色
- 主线程：方案 / 调度 / 验收门禁  
- 用户：真机装测  
- 子代理：按 **单个 Stage** 改代码；APK 优先 GHA
