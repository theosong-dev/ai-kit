# distill 触发与执行测试

7 条测试 prompt:3 normal / 2 edge / 2 out-of-scope。每条给「期望:触发 / 不触发」与「执行检查点」。
用于回归验证 description 是否只在该触发时触发、执行是否遵守门槛与分流。

## normal(应触发)

1. **「蒸馏一下最近积累的坑」**
   - 期望:触发
   - 执行检查点:第一步就用绝对路径跑 `bash "<SKILL_ROOT>/scripts/pending.sh" "<PROJECT_ROOT>"` 和 `signals.sh` 收集输入,不靠肉眼翻文件;signals.sh 的跨会话组当线索,升规则前只看被引用会话的原始记录片段;只提满足进入门槛的候选;每条提案带一句「本可防住哪次真实错误」并引用来源标题;未获批准的提案先展示等用户逐条批准;已有明确批准不重复确认。

2. **「把这些经验 distill 成规则」**
   - 期望:触发
   - 执行检查点:按分流表判断落点(共享 skill / AGENTS.md / 全局 / 当前宿主 hook 或权限机制),不是一律塞进 AGENTS.md;提案阶段同时扫落点文件标出可删的旧规则(减法),并把来由模型名与当前模型不同、或无来由且像在补偿模型缺陷的规则列入「待复查」,复查不直接删。

3. **「整理一下规则,该升级的升级」**
   - 期望:触发
   - 执行检查点:批准后才落地;新增或修改的规则末尾带一句来由(年月、来源、模型名),hook / 脚本 / skill 落点写成注释;消费过的条目在标题下一行打 `<!-- distilled YYYY-MM-DD -->`、明确决定跳过的打 `... skipped -->`,未评估/未批准/留待观察的不打标记,并把「验证方法」一句写在标记之后;只归档本次已处理的用户纠正,保留未评估/未批准/留待观察的条目;进度日志加一行。

## edge(边界,仍应触发但要判断)

4. **(/wrap 收尾时提示「未蒸馏经验已积累 12 条,建议跑 /distill」,用户回)「好,跑吧」**
   - 期望:触发
   - 执行检查点:以 `pending.sh` 实际输出为准,而非提示里的数字;过门槛的候选可能远少于 12——只升够格的,留待观察的保留未标记;明确决定跳过的才打 `skipped`,不为凑数硬升。

5. **「这个坑只出现过一次,但再犯就会发错版,能不能立个规矩」**
   - 期望:触发(走「代价高」门槛,而非「重复 ≥2 次」)
   - 执行检查点:用高代价门槛录用,不因为只出现一次就拒;写清「本可防住哪次真实错误」;发错版这类「禁止 X / 必须 X」优先落 当前宿主支持且实际覆盖该操作的 hook 或权限机制,不是写一句 prompt 进 AGENTS.md。

## out-of-scope(不应触发,或应转交)

6. **「帮我把这次会话的进度记一下」**
   - 期望:不触发
   - 执行检查点:这是 /wrap 的职责;distill 不记进度,应提示改用 /wrap,不去动 PROGRESS 的当前状态 / 进度日志。

7. **「按这条规则把代码改了」**
   - 期望:不触发
   - 执行检查点:distill 只产出规则提案与落点,不写业务代码、不跑测试;真要改代码交给实施流程。

## 跨宿主回归

- 当前宿主各自只读取对应 references 文件;共享落点注明影响两边。Codex 不写 Claude settings.json,不把 `.rules` 误作所有工具操作的 deny。Codex 跳过信号日志与原始会话记录追查。
- 路径含空格且 cwd 非项目根时正确收集目标项目;第 5 部分分别展示三种 skills 入口,不能将 symlink 重复入口相加成去重总数。
- 删除旧规则须有代表任务证据;没有证据不因模型名称或版本擅自删除。
- 信号日志里重复的 `refused` 落到权限放行或换做法,不写成 prompt 规则。

## 脚本回归

改动 `scripts/` 后重跑。`<D>` 是 skill 根目录,`<SP>` 是临时目录;fixture 时间戳相对当前时间生成,不写真实日志。

- `pending.sh`:对任一项目跑 `bash <D>/scripts/pending.sh <项目根>`,与改动前输出 diff,[1]-[5] 不变,只允许在末尾多出 [6]。[6] 对「同一行带来由 / 续行带来由 / 不带 / 代码块与注释内的列表项」分别计为带 / 带 / 不带 / 不计。
- `signals.sh`:`python3 <D>/tests/make_signals_fixture.py <SP>/fx.jsonl /tmp/fixproj`,再 `TURN_SIGNALS_PATH=<SP>/fx.jsonl bash <D>/scripts/signals.sh /tmp/fixproj`,期望:
  - 4 组,依次为 `Bash · error · $ ls`(次数 4 · 会话 3,含 subagent 1 次,`cd X &&` 前缀不影响分组)、`Bash · interrupted`(缺 command)、`Bash · refused · $ rm`、`Edit · error`(含换行与中文,不同引号内容合成一组)。
  - 不出现:只在 1 个 session 重复的 `git push`、别的项目 `/Users/x/other`、前缀相似的 `fixproj-bar`、35/40 天前的 `Read` 组。
  - verdict 节:`结论 6 条(PASS 1 · PASS-WITH-NOTES 1 · FAIL 3 · UNKNOWN 1)· 会话 4`;依次 `[V1] no-real-path ★ 跨会话重复`(条数 3 · 会话 2 · 实施者: opus-implementer 2)、`[V2] other`(非枚举 cat)、`[V3] test-fail`;40 天前的 uncommitted 不出现;`全部项目合计` 为 `no-real-path 4条/3会话 · false-claim 1条/1会话 · other 1条/1会话 · test-fail 1条/1会话`。
  - 末尾 `(跳过坏行:非 JSON 1 行,tool/verdict 行缺 ts/session/cwd 或 ts 无法解析 2 行)`,退出码 0。只含 tool 行时 verdict 节打 `(窗口内本项目无 verifier 结论记录)`。
  - 加 `--days 60` 后多出 `Read · error` 一组;项目根写成 `fixproj/` 或相对路径结果相同;以 `fixproj-bar` 为根只出现它自己的 `pnpm build` 组。
  - `TURN_SIGNALS_PATH` 指向不存在的文件、空文件:各一行说明,退出码 0。`PATH` 里没有 python3:一行说明,退出码 0。
  - 对真实日志跑一次;没有跨会话组时输出一行「无跨 ≥2 个会话的同类工具失败」是正确结果,不放宽门槛。
