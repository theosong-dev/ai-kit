# wrap 触发与执行测试

7 条测试 prompt:3 normal / 2 edge / 2 out-of-scope。每条给「期望:触发 / 不触发」与「执行检查点」。
用于回归验证 description 是否只在该触发时触发、执行是否遵守六段结构与体积检查。

## normal(应触发)

1. **「收尾吧」**
   - 期望:触发
   - 执行检查点:先区分进度 / 决策 / 踩坑 / 纠正四类;更新 PROGRESS 六段;写完用 skill 根的绝对路径跑 `bash "<SKILL_ROOT>/scripts/check_size.sh" "<PROJECT_ROOT>"`,exit 0 才算完成。

2. **「结束前把进度整理一下」**
   - 期望:触发
   - 执行检查点:进度日志最上方加一行(日期 + 一句话);只勾选已端到端验证的任务;只有确有决策 / 踩坑 / 纠正时才动 DECISIONS / GOTCHAS / 用户纠正段。

3. **「wrap up this session」**
   - 期望:触发
   - 执行检查点:更新顶部「最后更新」日期;本次用户纠正追加到「用户纠正(待蒸馏)」段;`check_size.sh` 报 OVER 就先归档再写,不硬塞。

## edge(边界,仍应触发但要判断)

4. **「更新下进度,不过这次没啥决策也没踩坑」**
   - 期望:触发
   - 执行检查点:只更新 PROGRESS,不硬写 DECISIONS / GOTCHAS;用户纠正段这次没内容就不动它(宁缺毋滥)。

5. **(在 PROGRESS 进度日志已有 10+ 条的仓里)「收尾一下」**
   - 期望:触发
   - 执行检查点:`check_size.sh` 会报「进度日志条目数 OVER」并 exit 1;按输出把最老的多余条目追加到 `.ai/archive/PROGRESS-YYYY-MM.md`(archive 留原文、本文件留压缩一行),再跑一次脚本确认 exit 0 才写更新。

## out-of-scope(不应触发,或应转交)

6. **「把这些反复出现的坑升成可复用规则」**
   - 期望:不触发
   - 执行检查点:这是 /distill 的职责;wrap 只如实记录到 GOTCHAS,不做提炼分流,应提示改用 /distill。

7. **「顺便把这个 bug 修了」**
   - 期望:不触发
   - 执行检查点:wrap 不改功能代码、不跑构建;只负责收尾记录。

## 跨宿主回归

- Claude Code 与 Codex 各在 cwd 不等于目标项目根、目标路径含空格的 fixture 中执行;不依赖宿主注入的 skill 目录变量,检查同一脚本均收到正确项目根。
