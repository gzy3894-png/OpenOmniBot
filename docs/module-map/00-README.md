# OmniBot 模块地图（只读分析）

> 工作区：`/root/workspace/omnibot-product`  
> 上游 tip：`b157e16` (0.5.6.4)  
> 纪律（用户 2026-07-15）：**先摸清再拆装**；本阶段 **禁止改业务代码 / 改包名 / 出产品 APK**。  
> 并行度：≤8 只读子代理。

## 目标
对每个 Gradle/Flutter/工具模块产出：
1. **职责**（一句话 + 对外能力）
2. **入口**（Application / Activity / Channel / main.dart / Service）
3. **实现要点**（关键类/目录，不贴全文）
4. **依赖**（依赖谁 / 被谁依赖）
5. **耦合度**（低/中/高 + 耦合点）
6. **与 Codex / 终端 / 聊天壳** 的关系
7. **二次开发标签**：`CORE必留` | `可选` | `可砍P0` | `后置` | `构建专用`
8. **拆装风险**（若移除会炸什么）

## 输出文件
| 文件 | 范围 |
|------|------|
| `01-gradle-app-shell.md` | settings/app 壳、Application、原生入口 |
| `02-flutter-ui.md` | `ui/` Flutter 模块、路由、features |
| `03-codex-stack.md` | app codex/* + channel + Flutter codex services |
| `04-terminal-reterminal.md` | ReTerminal/core/* + TerminalManager |
| `05-baselib-uikit.md` | baselib, uikit |
| `06-assists-accessibility.md` | assists, accessibility（无障碍/自动化） |
| `07-omniintelligence-infer.md` | omniintelligence + third_party/omniinfer |
| `08-workers-tools-bridge.md` | workers, tools/codex-bridge, scripts, skills |
| `09-coupling-matrix.md` | 总耦合矩阵 + 建议拆装顺序（**只建议，不执行**） |

## 非目标
- 不改 `applicationId`、不删模块、不发 AWB/Omni 产品包
- 不做「先能装再分析」的捷径

## 状态
- [x] `01-gradle-app-shell.md`
- [x] `02-flutter-ui.md`
- [x] `03-codex-stack.md`
- [x] `04-terminal-reterminal.md`
- [x] `05-baselib-uikit.md`
- [x] `06-assists-accessibility.md`
- [x] `07-omniintelligence-infer.md`
- [x] `08-workers-tools-bridge.md`
- [x] `09-coupling-matrix.md`（总矩阵 + 建议拆装顺序，**未执行**）
- [ ] 用户确认地图后进入阶段 1（构建可复现）
