# Worktree 阶段性结论

## 背景

这份文档用于总结 [Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md) 中 `Increasing application legibility` 章节第一步，也就是 `per git worktree boot`，在当前仓库里的阶段性设计结论、落地进展、使用方式和后续工作。

对应的主设计文档是：

- [increasing-application-legibility-node-1-per-worktree-boot-design.md](/Users/mac/code/harnessV2/increasing-application-legibility-node-1-per-worktree-boot-design.md)
- [worktree-implementation-review-2026-03-30.md](/Users/mac/code/harnessV2/worktree-implementation-review-2026-03-30.md)

## 当前设计是什么

当前围绕 `worktree` 的设计目标，不是单纯把代码放进不同目录，而是让每个 worktree 都拥有自己独立的运行态。

这套设计的核心约束是：

- 从当前 worktree 根目录稳定派生 `WORKTREE_ID`
- 所有端口按 `WORKTREE_ID` 确定性分配
- 所有本地可变状态统一落到 `.local/worktrees/<WORKTREE_ID>/...`
- 启动、停止、重置、查询统一走固定脚本接口
- 运行时信息必须写成机器可读元数据，供人和 agent 共同使用

换句话说：

- `git worktree` 负责代码隔离
- `scripts/dev-*` 负责运行态隔离

两者配合后，未来每个 worktree 才能独立启动、独立验证、独立销毁，而不会互相污染。

## 当前已经做到哪一步

截至目前，这套设计已经完成了三层内容。

### 1. 设计契约已经成文

节点 1 的完整工程设计已经落成文档，包括：

- `WORKTREE_ID` 规则
- 端口分配规则
- `.local` 目录布局
- 生命周期脚本接口
- 运行时元数据契约
- Phase 2 的真实应用启动入口规范

对应文档：

- [increasing-application-legibility-node-1-per-worktree-boot-design.md](/Users/mac/code/harnessV2/increasing-application-legibility-node-1-per-worktree-boot-design.md)

### 2. Phase 1 运行时脚手架已经实现

仓库里已经有一套可运行的引导脚本：

- [scripts/lib/worktree-runtime.sh](/Users/mac/code/harnessV2/scripts/lib/worktree-runtime.sh)
- [scripts/dev-up](/Users/mac/code/harnessV2/scripts/dev-up)
- [scripts/dev-down](/Users/mac/code/harnessV2/scripts/dev-down)
- [scripts/dev-reset](/Users/mac/code/harnessV2/scripts/dev-reset)
- [scripts/dev-status](/Users/mac/code/harnessV2/scripts/dev-status)

这部分已经实现：

- worktree 身份派生
- 端口派生
- `.local` 状态目录创建
- `env.json`、`ports.json`、`status.json` 生成
- `runtime.env` 生成
- 端口冲突 `strict` / `soft` 双模式
- `prototype` / `strict-git` 两种 worktree 模式
- `starting` / `ready` / `failed` 生命周期语义
- readiness 检查契约

### 3. Phase 2 接入规范已经补齐

真实应用如何接入，已经不再依赖临时口头约定，而是被固定成了统一入口设计：

- 优先使用 `HARNESS_APP_START_COMMAND`
- 否则在仓库内存在可执行且已配置的 `scripts/app-start` 时，退回使用 `scripts/app-start`
- 如果两者都没有，就只准备运行时环境，不启动真实应用

同时，仓库里已经补了仓库级真实入口与单进程命令模板：

- [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)
- [scripts/app-start.command.example](/Users/mac/code/harnessV2/scripts/app-start.command.example)

### 4. 单进程真实应用入口已经落到脚本

在本轮推进里，单进程接入已经从“模板讨论”推进到“可执行入口”。

当前仓库中已经有：

- [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)
- [scripts/app-start.command.example](/Users/mac/code/harnessV2/scripts/app-start.command.example)

这意味着：

- `scripts/dev-up` 不再只会准备运行时
- 在提供真实单进程命令后，它已经可以通过仓库级入口真正启动应用
- `dev-up` 不再理解单进程命令来源细节，而是只识别仓库级入口 `scripts/app-start`
- 单进程应用的推荐接入方式已经固定下来

### 5. 关键脚本已经补了中文注释

为了避免后续继续靠口头解释，当前关键脚本都补了中文注释，主要说明：

- 脚本职责边界
- `dev-up -> app-start -> app-start.command` 的调用链
- 运行时库和真实应用入口的分工

涉及文件：

- [scripts/dev-up](/Users/mac/code/harnessV2/scripts/dev-up)
- [scripts/dev-status](/Users/mac/code/harnessV2/scripts/dev-status)
- [scripts/dev-down](/Users/mac/code/harnessV2/scripts/dev-down)
- [scripts/dev-reset](/Users/mac/code/harnessV2/scripts/dev-reset)
- [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)
- [scripts/lib/worktree-runtime.sh](/Users/mac/code/harnessV2/scripts/lib/worktree-runtime.sh)

### 6. 单进程示例应用已经完成真实链路验证

为了验证当前实现不只是“脚手架存在”，而是真的能启动一个单进程应用，本轮还加入了一个最小示例应用：

- [scripts/example-single-process-server.py](/Users/mac/code/harnessV2/scripts/example-single-process-server.py)

这个示例应用会：

- 监听 `APP_PORT`
- 暴露一个最小 HTTP 接口
- 返回当前 worktree 运行时信息

验证方式不是直接手工运行示例服务，而是严格走现有启动链路：

```text
scripts/dev-up
  -> scripts/app-start
     -> 内部解析真实单进程命令
        -> example-single-process-server.py
```

本轮已经验证通过的点包括：

- `scripts/dev-up` 可以成功拉起真实单进程应用
- `scripts/dev-status` 可以进入 `ready`
- 实际 HTTP 请求可以访问 `APP_URL`
- HTTP 返回内容与 worktree 运行时元数据一致
- `scripts/dev-down` 可以正确停止应用进程

这一步非常关键，因为它说明当前 worktree 设计已经不只是“准备环境”，而是已经验证了“能够通过统一链路启动一个真实单进程应用”。

## 2026-03-30 审查结论

本轮已基于原始文章、设计文档和脚本实现，补充了一份实现审查文档：

- [worktree-implementation-review-2026-03-30.md](/Users/mac/code/harnessV2/worktree-implementation-review-2026-03-30.md)

审查后的核心结论是：

- 当前主方向没有偏离，worktree 运行时隔离思路是正确的
- 当前仓库已经具备 worktree 运行时脚手架，但还不足以支撑 agent 独立复现、驱动、验证和销毁实例
- 现阶段更准确的描述应是“runtime contract prototype”或“worktree 运行时脚手架”，而不是“完整 per-worktree runtime 已完成”

基于审查结果，本轮已经完成一轮关键收口：

- `scripts/app-start` 已重新收口为仓库级入口，`dev-up` 不再理解 `scripts/app-start.command` 这类内部细节
- 生命周期语义已从“running”收敛到“starting / ready / failed”，并接入 readiness 检查
- 已引入 `prototype` / `strict-git` 模式区分原型环境与真实 git worktree 环境
- 主设计文档、阶段总结文档和实现审查文档已经完成一轮同步修复

仍然没有完成的主要问题是：

- 当前仓库还不是真实 git worktree 场景，尚未完成真实 worktree 验收
- 还没有真实业务应用代码
- 还没有把真实业务应用正式接入仓库默认启动命令

后续推进时，建议优先参考审查文档中的“建议的收敛方向”，不要直接把当前脚手架视为节点 1 的最终完成态

## 现在还没有完成的部分

虽然运行时框架已经有了，但整个节点 1 还没有彻底完成。

当前还缺少：

- 当前目录还不是一个真实 git 仓库
- 还没有真实应用代码
- 还没有把真实业务应用命令正式写进 `scripts/app-start.command`
- 还没有在两个真实 worktree 上做并行启动验证

所以当前阶段更准确的结论是：

`worktree 的运行时设计、脚手架和单进程接入入口已经建立，但真实业务应用还没有正式接入，且尚未形成足以支撑 agent 自主验证闭环的完整 per-worktree runtime。`

## 现在应该怎么用

### 基本命令

当前可以直接使用下面几个脚本：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
scripts/dev-reset
```

### 当前默认行为

在没有真实应用启动入口时：

- `scripts/dev-up` 会准备 worktree 对应的运行时环境
- 会生成元数据和目录
- 但不会真正拉起应用进程
- 此时状态通常是 `prepared`

在已经提供单进程真实命令时：

- `scripts/dev-up` 会继续先准备 worktree 运行时
- 然后通过 `scripts/app-start` 启动真实应用
- 此时 `dev-status` 会先经过 `starting`，readiness 通过后进入 `ready`
- `env.json` 中会记录当前启动来源

### 端口冲突处理方式

默认模式是 `strict`：

```bash
scripts/dev-up
```

这适合 agent 和自动化任务，遇到端口冲突会直接失败。

如果本地调试想用柔性回退模式：

```bash
HARNESS_PORT_CONFLICT_MODE=soft scripts/dev-up
```

这会在受控范围内尝试后续 offset，而不是直接报错。

如果想手工指定起始 offset：

```bash
HARNESS_PORT_OFFSET=37 scripts/dev-up
```

### 模拟真实应用启动

如果要在当前阶段临时模拟一个真实应用启动入口，可以这样：

```bash
HARNESS_APP_START_COMMAND='sleep 5' scripts/dev-up
```

这样可以验证：

- `dev-up` 会进入真实启动链路
- `dev-status` 会看到状态变化
- `env.json` 会记录启动来源

### 当前已经验证通过的一条真实链路

除了上面的临时命令方式，本轮还已经用最小示例应用验证通过了下面这条真实启动链路：

```text
scripts/dev-up
  -> scripts/app-start
     -> HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py'
        -> 示例 HTTP 服务监听 APP_PORT
```

验证结果包括：

- `scripts/dev-up` 成功启动进程
- `scripts/dev-status` 返回 `STATE=ready`
- `curl $APP_URL` 成功返回 JSON
- 返回 JSON 中的 `worktreeId`、`appPort`、`stateRoot` 等信息与元数据一致
- `scripts/dev-down` 成功停止进程

### 当前最推荐的正式接入方式

现在最推荐的仓库级接入方式已经明确下来：

1. 复制 [scripts/app-start.command.example](/Users/mac/code/harnessV2/scripts/app-start.command.example) 为 `scripts/app-start.command`
2. 把真实应用启动命令写进去
3. 后续统一使用：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
```

也就是说，后续不再推荐直接运行框架命令，而是始终从 `scripts/dev-up` 进入。

## 运行后会产生什么

当前 worktree 根目录下会出现：

```text
.local/
  worktrees/
    <WORKTREE_ID>/
      run/
        env.json
        ports.json
        runtime.env
        status.json
      data/
      cache/
      logs/
      artifacts/
      tmp/
```

其中关键文件包括：

- `run/env.json`
  保存当前 worktree 的运行时契约
- `run/ports.json`
  保存最终分配出来的端口和分配来源
- `run/status.json`
  保存当前生命周期状态
- `run/runtime.env`
  保存可直接 `source` 的 shell 环境变量

## 后面需要怎么做

下一阶段真正要推进的是下面三件事。

### 1. 把仓库推进到真实项目状态

至少需要：

- 初始化真实 git 仓库
- 确立真实应用 scaffold
- 让 worktree 语义不再只是兼容层，而是进入真实使用场景

### 2. 落真正的 `scripts/app-start`

当前已经有仓库级入口 [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)，下一步应该：

1. 为单进程应用创建 `scripts/app-start.command`，或在调用前设置 `HARNESS_SINGLE_PROCESS_COMMAND`
2. 接入真实框架启动命令
3. 让真实应用显式使用这些变量：
   - `APP_PORT`
   - `API_PORT`
   - `STATE_ROOT`
   - `DATA_ROOT`
   - `LOG_ROOT`
   - `TMP_ROOT`

结合本轮进展，这一步现在已经收敛为更具体的动作：

1. 创建 `scripts/app-start.command`
2. 把真实业务应用命令写进去
3. 用 `scripts/dev-up` 验证它能在当前 worktree 下被正确启动
4. 检查 `env.json`、`ports.json`、`status.json`、`runtime.env` 是否与真实启动结果一致

## 真实应用接入方式讨论

围绕 `scripts/app-start` 的真实接入方式，当前有两条主要路线：

- 单进程接入
- 前后端双进程接入

这里的区别不是代码仓库怎么拆，而是 `scripts/app-start` 最终拉起一个主进程，还是同时拉起前端和后端两个长期运行进程。

### 方案 A：单进程接入

单进程接入指的是：

- `scripts/app-start` 只启动一个主进程
- 这个进程自己负责提供完整应用能力
- 对外通常只暴露一个主入口端口

适用场景通常包括：

- 服务端渲染应用
- 单体 Web 服务
- 本地演示型应用
- 当前阶段为了先打通 worktree 运行时链路而构造的最小可用应用

优点：

- 启动链路最短，接入成本最低
- `dev-up`、`dev-down`、`dev-status` 的行为最容易稳定
- agent 更容易推理应用是如何启动和停止的
- 日志、PID、失败原因都更容易集中管理
- 更适合作为节点 1 的第一版真实落地形态

缺点：

- 如果真实产品天然就是前后端分离，单进程方案可能只是过渡结构
- 后续拆成多进程时，`scripts/app-start` 内部实现会发生变化
- 一些真实问题在单进程模型下无法提前暴露，例如前后端启动顺序、跨进程依赖、独立健康检查

### 方案 B：前后端双进程接入

前后端双进程接入指的是：

- `scripts/app-start` 在一个入口里同时拉起前端进程和后端进程
- 前端和后端分别绑定不同端口
- `scripts/app-start` 负责协调这两个进程的生命周期

适用场景通常包括：

- 前后端本来就是独立服务
- 本地开发需要和真实生产结构尽量一致
- 后续 agent 需要分别观测前端和后端行为

优点：

- 更贴近真实前后端分离系统
- 可以更早验证 `APP_PORT` 和 `API_PORT` 的双端口约束
- 后续接 UI 自动化、接口验证、日志采集时边界更清晰
- 有利于后面继续扩展成多服务运行模型

缺点：

- `scripts/app-start` 会明显更复杂
- 需要处理两个进程的启动顺序、失败联动和退出清理
- 日志、PID、健康检查都要分别管理
- 对当前还没有真实应用的仓库来说，第一步实现成本更高
- 节点 1 当前阶段的验证目标可能会被额外复杂度稀释

## 当前建议

如果目标是尽快把文章第一步真正落成，我当前更建议：

- 第一阶段先按单进程接入
- 等 worktree 运行时、端口分配、`.local` 状态目录、元数据消费都稳定后，再演进到前后端双进程

原因是：

- 节点 1 的核心目标首先是验证“每个 worktree 能独立拉起自己的应用实例”
- 这个目标不依赖一开始就把应用做成双进程
- 单进程可以先把启动入口、状态隔离、端口契约、元数据契约都跑通
- 等这些基础稳定后，再增加双进程复杂度，问题会更容易定位

更直接地说：

- 单进程更适合“先把 worktree 启动这件事做对”
- 双进程更适合“在 worktree 启动已经成立之后，进一步逼近真实系统”

## 当前已经落下的单进程接入器

仓库里现在已经有：

- [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)
- [scripts/app-start.command.example](/Users/mac/code/harnessV2/scripts/app-start.command.example)

这意味着单进程接入已经不再只是模板讨论，而是进入了可执行阶段。

当前规则是：

- `scripts/dev-up` 会优先使用 `HARNESS_APP_START_COMMAND`
- 如果没有配置它，则会尝试使用仓库级的 [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)
- `scripts/app-start` 自己负责判断是否已配置，并在内部选择真实单进程命令来源

推荐的仓库级接入方式是：

1. 复制 [scripts/app-start.command.example](/Users/mac/code/harnessV2/scripts/app-start.command.example) 为 `scripts/app-start.command`
2. 把里面的命令改成真实应用启动命令
3. 继续通过 `scripts/dev-up` 启动，而不是直接运行框架命令

本轮已经验证过三种路径：

- 未提供真实命令时，`scripts/dev-up` 会保持 `prepared`
- 提供 `HARNESS_SINGLE_PROCESS_COMMAND` 时，`scripts/dev-up` 会通过 `scripts/app-start` 进入真实启动链路
- 提供最小示例应用命令时，已经完成了从 `dev-up` 到 `ready`、再到真实 HTTP 响应、最后到 `dev-down` 的完整闭环验证

### `scripts/app-start.command` 的推荐格式

这个文件本质上不是 JSON，也不是 `.env`，而是一段会被 `sh -lc` 执行的 shell 命令内容。

推荐格式规则如下：

1. 尽量写成单进程命令，不要在这里启动多个长期运行进程
2. 最后真正启动应用时，优先使用 `exec`
3. 不要硬编码端口，统一使用 `"$APP_PORT"`
4. 不要把应用放到后台运行，不要使用 `&`
5. 如果需要写本地数据，统一使用：
   - `"$APP_DATA_DIR"`
   - `"$APP_CACHE_DIR"`
   - `"$APP_LOG_DIR"`
   - `"$APP_TMP_DIR"`
6. 如果只是单纯启动应用，推荐最小写法就是：

```bash
exec npm run dev -- --port "$APP_PORT"
```

如果需要在启动前准备目录，也可以写成多行：

```bash
mkdir -p "$APP_DATA_DIR" "$APP_CACHE_DIR" "$APP_TMP_DIR"
exec npm run dev -- --port "$APP_PORT"
```

不推荐的写法包括：

- `npm run dev -- --port 3000`
  问题：硬编码端口，破坏 worktree 隔离
- `npm run dev &`
  问题：把进程放后台后，生命周期会脱离 `scripts/dev-up`
- 同时启动多个长期运行服务
  问题：这会把单进程入口悄悄变成多进程入口，后续排查会很乱

### `scripts/app-start.command` 和 `HARNESS_APP_START_COMMAND` 怎么选

推荐原则是：

- 日常仓库使用：优先 `scripts/app-start.command`
- 临时实验、一次性验证、外部脚本编排：使用 `HARNESS_APP_START_COMMAND`

原因是：

- `scripts/app-start.command` 会进入仓库版本控制，适合作为团队默认启动方式
- `HARNESS_APP_START_COMMAND` 更适合临时覆盖，不适合作为长期约定

所以如果你的目标是“把真实应用正式接进仓库”，优先把命令写进 `scripts/app-start.command`。

### 当前启动调用链

当前单进程接入下，真实启动链路如下：

```text
用户或 Agent
  -> scripts/dev-up
     -> 解析 WORKTREE_ID
     -> 分配端口
     -> 创建 .local/worktrees/<WORKTREE_ID>/...
     -> 写入 env.json / ports.json / status.json / runtime.env
     -> 选择真实应用启动入口
        -> 如果存在 HARNESS_APP_START_COMMAND，直接使用它
        -> 否则使用 scripts/app-start
           -> 由 scripts/app-start 自己判断是否已配置
           -> 由 scripts/app-start 自己解析真实单进程命令
           -> 执行真实单进程应用命令
```

换成一句更直白的话就是：

- 外部永远执行 `scripts/dev-up`
- `scripts/dev-up` 负责 worktree 运行时
- `scripts/app-start` 负责仓库级真实应用接入
- `scripts/app-start.command` 可以作为单进程实现里的命令来源之一

### 最推荐的启动方式

当前最推荐的仓库级使用方式是：

1. 创建 `scripts/app-start.command`
2. 把真实应用命令写进去
3. 后续统一执行：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
```

这样做的好处是：

- 人和 agent 使用同一条启动链路
- worktree 运行时约束始终生效
- 真实应用命令被版本化保存，不依赖临时 shell 输入

## 推荐推进顺序

基于当前仓库状态，推荐按下面顺序推进：

1. 先做单进程版本的 `scripts/app-start`
2. 验证 `dev-up`、`dev-status`、`dev-down` 在真实应用下全部跑通
3. 验证 `.local`、端口、元数据文件都符合预期
4. 再决定是否升级为前后端双进程版本

如果后续确认真实产品一定是前后端双服务结构，那么最稳的做法不是一开始就把节点 1 做复杂，而是：

- 先用单进程形态验证 worktree 机制
- 再在 `scripts/app-start` 内部演进为双进程实现
- 保持 `dev-up` 的外部接口不变

这样能够保证：外部使用方式稳定，内部实现逐步复杂化。

### 3. 做真实双 worktree 验证

最终要验证的不是“脚本存在”，而是下面这些结果真的成立：

1. 两个 worktree 可以在同一台机器上同时启动
2. 端口不会冲突
3. `.local` 状态不会互相污染
4. `dev-status` 能正确反映各自实例状态
5. 元数据文件可以被后续 agent 工具稳定消费

## 当前阶段一句话总结

当前已经完成的是：

`把文章里“按 worktree 独立启动应用”的想法，落成了一套明确的运行时设计、第一版可执行脚手架、单进程真实应用接入入口，以及基于 readiness 的基础状态机。`

当前还没有完成的是：

`真实业务应用命令的正式接入，以及在真实 git worktree 环境下的端到端验证。`

补充一句更具体的当前结论：

`至少在单进程场景下，这套 worktree 启动链路已经被最小示例应用真实验证通过。`
