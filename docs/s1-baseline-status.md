# S1 基线状态

Date: 2026-07-15

## 已完成（文档/门禁）
- [x] `docs/slim-roadmap.md` Stage 定义 + 回滚
- [x] `docs/smoke-codex.md` 真机金线
- [x] `PRODUCT.md` 指针与推荐命令
- [x] `AGENTS.md` 顶部纪律（覆盖过时 `./gradlew build` 习惯）
- [x] CI 已确认：`ci.yml` = standard debug + `main_standard.dart` + `submodules: false`

## 本机环境事实
| 项 | 状态 |
|----|------|
| tip | `b157e16` |
| `ui/.android` | **缺失**（需 flutter pub get） |
| flutter | **未安装** |
| ANDROID_HOME | **unset** |
| Java | 17 有 |
| omniinfer submodule | 空（standard 不需要） |

## 未完成（构建金线）
- [ ] 在 **有 Flutter 3.38.x + Android SDK** 的环境执行 `ui && flutter pub get`
- [ ] 执行 `./gradlew :app:assembleDevelopStandardDebug -Ptarget=lib/main_standard.dart`
- [ ] 或：推送/workflow 跑绿 `ci.yml` 取 artifact（若 CI 上传 APK；当前 ci 以 verify 为主，release 另走 tag）
- [ ] 用户真机按 `smoke-codex.md` 跑一轮 **基线**（精简前对照）

## S1 退出标准
文档一致 +（CI 或 SDK 机）standard 可编 + 用户至少完成一次冒烟记录 → 才开 **S2.1**（无障碍不强制），且 S2 **每次只合一项**。

## 明确不做（防跑死）
- 不删 assists/accessibility/uikit
- 不改 applicationId
- 不 init omniinfer「为了能编」
- 不在本机 Alpine 无 SDK 时假装 assemble 成功
