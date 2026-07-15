# 主线程作业手册（用户不管这些）

## 角色
- **用户**：只看 `docs/results/DELIVERY.md` + 交报告  
- **主线程**：Stage 调度、出包、验收门禁、禁止跳步砍模块  
- **仓内 Codex**（用户侧）：按模板自测产报告  

## 日常循环
1. 读 `slim-roadmap.md` 当前 Stage  
2. 出/取 APK → 写 `results/DELIVERY.md` §2  
3. 等报告 → 判定 GATE  
4. PASS 才开下一最小 diff；FAIL 回滚  

## 出包（fork）
- 远程：`git@` / `https://github.com/gzy3894-png/OpenOmniBot.git`（**不要**往 `omnimind-ai/OmniBot` 推二次开发提交）  
- 推荐 workflow：`Baseline Standard Debug`（workflow_dispatch）  
- 产物：artifact 下载 → stage 到 `/storage/emulated/0/Download/` → 填 DELIVERY  

## 禁止
- 无 GATE 进 S4/S5  
- 裸删 assists  
- 裸 `./gradlew assemble`  
- 把 AWB 再当主线  
