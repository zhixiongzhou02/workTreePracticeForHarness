# 增强应用可理解性
## 节点 1：按 worktree 独立启动的工程设计

## 背景

本文档对应 [Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md) 中 `Increasing application legibility` 章节的第一个实现节点：让应用能够按 git worktree 独立启动，使 agent 可以针对每一次变更拉起、驱动、验证并销毁一个彼此隔离的应用实例。

当前实现与设计目标之间的阶段性偏离分析，见：

- [worktree-implementation-review-2026-03-30.md](/Users/mac/code/harnessV2/worktree-implementation-review-2026-03-30.md)

对应的原始表述是：

> “We made the app bootable per git worktree, so Codex could launch and drive one instance per change.”

结合当前仓库状态来看，这个仓库仍然没有真实业务应用代码，但已经具备一套面向 worktree 的运行时脚手架、单进程接入入口和最小示例应用验证链路。因此，这个节点已经从纯设计约束推进到了可执行原型阶段，但还没有完成真实 git worktree 和真实业务应用场景下的最终验收。

## 为什么这一点重要

原文这一节强调的瓶颈不是代码生成速度，而是人的 QA 容量。按 worktree 独立启动，是让 agent 具备“自我验证”能力的第一前提。

如果没有按 worktree 隔离：

- 多个 agent 任务会争抢同一组端口。
- 本地数据会互相污染。
- 日志和指标会混在一起。
- 问题复现和修复验证会变得不稳定。
- 基于 UI 的自动化验证会非常脆弱。

如果实现了按 worktree 隔离：

- 每个变更都可以运行在自己的可销毁环境里。
- agent 可以独立完成复现、修复、重启和再次验证。
- 后续的 UI 自动化和可观测性能力都可以挂接到同一个隔离实例上。

## 设计目标

需要满足下面这个不变量：

`任意一个 git worktree，都可以在本机并行启动一个完整的本地应用实例，并使用隔离的运行态状态和稳定派生的配置，且不需要人工手动拼装环境。`

## 范围

本节点覆盖：

- worktree 身份标识
- 稳定的按 worktree 派生端口
- 按 worktree 隔离的本地状态目录
- 标准化的启动、停止、重置、查询生命周期命令
- 为后续 UI 自动化和可观测性层提供稳定的运行时契约

本节点暂不覆盖：

- 浏览器自动化
- Chrome DevTools Protocol 集成
- 日志、指标、trace 的采集接入
- agent 技能和任务编排

## 当前仓库状态

截至 2026-03-30，这个仓库的可观察状态如下：

- 根目录包含 [Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md)。
- 已经存在面向 worktree 的运行时脚手架与生命周期脚本。
- 已经存在仓库级真实应用入口 [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)。
- 已经存在单进程接入模板与示例应用验证链路。
- 仍然没有真实业务应用代码。
- 当前目录仍然不是一个真实 git 仓库，因此还没有完成真实 git worktree 语义下的验收。

结论：这项工作已经从纯设计阶段进入可执行原型阶段，但仍需要在真实应用和真实 git worktree 场景下完成收敛。

## 核心要求

如果要说“应用已经支持按 git worktree 独立启动”，至少必须同时满足下面几个条件。

### 1. 唯一的 worktree 身份

每个运行中的环境，都必须从当前 worktree 稳定派生出一个 `WORKTREE_ID`。

要求：

- 同一个 worktree 多次重启时保持稳定
- 同一台机器上的不同 worktree 之间彼此不同
- 可以安全用于目录名、进程名和元数据文件名
- 保留足够的人类可读性，便于排查问题

### 2. 隔离的端口分配

所有对外监听的进程都不能依赖硬编码共享端口。

要求：

- 端口必须由 `WORKTREE_ID` 确定性派生
- 前端、后端和辅助服务使用不同端口
- 同一个 worktree 再次启动时拿到相同端口
- 不同 worktree 在正常使用下不会冲突

### 3. 隔离的本地运行态

所有可变的本地运行态数据，都必须落到某个按 worktree 隔离的根目录下。

这包括：

- 本地数据库
- 上传文件
- 缓存
- 临时文件
- PID 文件
- 运行日志
- 测试产物

### 4. 标准化的生命周期命令

仓库必须暴露一套统一的本地运行生命周期入口。

必需命令：

- `scripts/dev-up`
- `scripts/dev-down`
- `scripts/dev-reset`
- `scripts/dev-status`

agent 不应该靠猜测框架命令来启动应用。

### 5. 机器可读的运行时契约

环境启动后，必须把解析后的运行态信息写成机器可读文件，供后续 agent 工具直接消费。

最少需要输出：

- `WORKTREE_ID`
- 应用访问地址
- API 基地址
- 分配得到的端口
- 状态目录根路径
- 日志目录根路径

## 设计方案

## A. worktree 身份

### 建议的来源

`WORKTREE_ID` 由当前 worktree 的绝对根路径派生。

建议算法：

1. 读取当前 worktree 的绝对仓库根路径。
2. 取目录 basename 作为可读前缀。
3. 对绝对路径计算一个短哈希。
4. 拼接为：

`WORKTREE_ID=<basename>-<hash8>`

示例：

- worktree 路径：`/Users/mac/code/harnessV2`
- basename：`harnessV2`
- 哈希后缀：`a1b2c3d4`
- 最终结果：`harnessV2-a1b2c3d4`

### 原因

- 基于路径，能保证同一个 worktree 在重启后保持稳定。
- 保留 basename，便于人工识别。
- 增加哈希，避免同名目录或相似命名目录冲突。

### 契约

在一次启动周期内，运行时必须把 `WORKTREE_ID` 视为不可变值。

## B. 端口分配

### 建议规则

端口从固定区间内，按照 `WORKTREE_ID` 的哈希结果确定性派生。

建议区间：

- 前端：`4100-4199`
- 后端 API：`4200-4299`
- 指标或调试端口：`4300-4399`
- 可选辅助服务：`4400-4499`

建议算法：

1. 将 `WORKTREE_ID` 哈希为整数。
2. 计算偏移量 `0-99`。
3. 分配：

- `APP_PORT = 4100 + offset`
- `API_PORT = 4200 + offset`
- `METRICS_PORT = 4300 + offset`
- `AUX_PORT = 4400 + offset`

### 原因

- 同一个 worktree 内端口稳定。
- 同一组服务共享相同 offset，便于人工排查。
- 不同类型服务处于不同区间，结构清晰。

### 冲突策略

启动前必须先做端口占用检测。

策略如下：

- 默认先尝试按 `WORKTREE_ID` 派生出来的确定性端口。
- 如果当前 worktree 已经存在上一次成功分配的端口记录，则优先尝试复用那组端口。
- 如果目标端口空闲，直接使用。
- 如果目标端口冲突，则根据端口冲突模式决定后续行为。

### 端口冲突模式

这一设计支持两种模式：

- `strict`
  适合 agent、CI 和自动化验证。只要检测到端口冲突，就直接失败。
- `soft`
  适合人工本地调试。检测到冲突后，不立刻失败，而是在受控范围内尝试下一个候选 offset。

默认模式为：

- `strict`

### `strict` 模式规则

- 使用确定性派生端口。
- 如果端口被占用，则立即报错并终止启动。
- 不做静默重分配。

这是因为 agent 更看重可预测性，不能让端口在没有明确记录的情况下漂移。

### `soft` 模式规则

- 先尝试确定性派生端口。
- 如果冲突，则在固定候选范围内继续尝试后续 offset。
- 默认最多尝试 20 个候选 offset。
- 一旦找到可用端口，就使用该组端口继续启动。
- 如果尝试范围耗尽仍然冲突，则报错退出。

这里的“柔和”不是无限随机找端口，而是受控回退。

### 运行时记录规则

无论最终使用的是默认派生端口，还是 `soft` 模式下的回退端口，都必须写入运行时元数据。

当前实现里：

- 最终端口写入 `run/ports.json`
- 同时写入 `run/env.json`
- 后续再次启动时，会优先尝试复用 `run/ports.json` 中上次成功分配的端口

这样做的目的不是追求“永远固定”，而是保证“最终结果始终可发现、可复用、可推理”。

### 推荐使用方式

- agent 或自动化任务：使用默认 `strict` 模式
- 人工本地调试：必要时使用 `HARNESS_PORT_CONFLICT_MODE=soft scripts/dev-up`
- 特殊情况下，也可以通过 `HARNESS_PORT_OFFSET` 手动指定起始 offset

## C. 按 worktree 隔离的状态目录

### 建议目录布局

所有可变本地运行态统一放到：

`.local/worktrees/<WORKTREE_ID>/`

建议子目录结构：

```text
.local/
  worktrees/
    <WORKTREE_ID>/
      run/
        pids/
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

### 各目录用途

- `run/`：进程记录和解析后的运行时元数据
- `data/`：该 worktree 的本地数据库和持久开发态数据
- `cache/`：可以安全清理的缓存
- `logs/`：应用和辅助服务日志
- `artifacts/`：截图、录屏、测试报告，以及未来 agent 验证产物
- `tmp/`：临时文件

### 规则

只要能重定向，运行时写入就不应默认落到全局共享的系统临时目录，而应归入当前 worktree 的状态根目录。

## D. 生命周期脚本

仓库需要定义一层稳定的操作接口，既服务人，也服务 agent。

### 谁来触发启动

这个设计里，启动动作既可以由人触发，也可以由 agent 触发，但两者都必须走同一套标准入口。

规则是：

- 人工本地调试时，通过 `scripts/dev-up` 启动。
- agent 执行任务时，也通过 `scripts/dev-up` 启动。
- 不允许把 `npm run dev`、`pnpm dev`、框架私有命令或临时 shell 命令当作对外约定的启动接口。

原因是：

- 人和 agent 必须看到一致的运行态结果。
- 启动逻辑必须只有一个可信入口，避免不同调用方式生成不同环境。
- 后续 UI 自动化、日志采集、健康检查都要依赖这层统一入口。

换句话说，`谁触发` 不是关键，`是否通过统一入口触发` 才是关键。

### 启动规则

`scripts/dev-up` 的标准启动规则如下：

1. 在当前 worktree 根目录执行。
2. 解析当前 worktree 的 `WORKTREE_ID`。
3. 根据端口冲突模式解析当前 worktree 的最终端口。
4. 创建当前 worktree 的状态目录。
5. 写入运行时元数据文件。
6. 如果已经配置真实应用启动命令，则启动应用进程。
7. 如果已配置真实应用启动入口，则先进入 `starting`，通过 readiness 检查后进入 `ready`。
8. 如果尚未配置真实应用启动命令，则只进入 `prepared` 状态，不启动应用进程。
9. 如果进程提前退出或 readiness 超时，则进入 `failed`。

这意味着当前阶段的 `dev-up` 既可以作为“真正启动器”，也可以作为“运行时准备器”。

### `scripts/dev-up`

职责：

- 解析 `WORKTREE_ID`
- 解析派生端口
- 创建必要目录
- 物化环境变量
- 启动所有本地所需服务
- 写入机器可读元数据
- 输出简洁启动摘要

输出契约：

- 面向人的启动摘要
- `run/env.json`
- `run/ports.json`
- `run/status.json`
- `run/runtime.env`

### Phase 2：真实应用启动入口规范

为了把当前端口策略真正接入应用，仓库需要定义一个稳定的真实应用启动入口。

推荐规则：

- 仓库级标准入口为 `scripts/app-start`
- `scripts/dev-up` 优先使用 `HARNESS_APP_START_COMMAND`
- 如果没有显式配置 `HARNESS_APP_START_COMMAND`，则退回使用仓库级 `scripts/app-start`
- `scripts/dev-up` 不再理解 `scripts/app-start.command` 这类应用内部细节，只判断 `scripts/app-start` 是否“已配置”
- 如果两者都不存在，则保持当前 `prepared` 行为，只准备运行时环境，不启动应用

这样做的目标是：

- 人和 agent 不需要知道具体框架命令
- 真实应用启动逻辑可以在仓库内版本化
- 后续从单进程扩展到前后端双进程、多服务编排时，`dev-up` 不需要改接口

### `scripts/app-start` 的职责

`scripts/app-start` 不是新的生命周期管理器，而是“真实应用如何启动、如何声明 readiness”的仓库内实现点。

它需要负责：

- 使用 `dev-up` 提供的端口变量启动应用
- 确保应用把可变状态写到当前 worktree 的状态目录
- 暴露 readiness 信息，供 `dev-up` 和 `dev-status` 判断实例何时可开始验证
- 在需要时同时拉起多个应用子进程
- 把应用日志写入当前 worktree 的日志目录

它不需要负责：

- 计算 `WORKTREE_ID`
- 分配端口
- 创建 `.local` 目录
- 管理 `env.json`、`ports.json`、`status.json`

这些都应该继续由 `scripts/dev-up` 和运行时库统一处理。

### `scripts/app-start` 必须遵守的输入契约

在 `scripts/dev-up` 调用真实应用启动入口时，下列环境变量必须已经准备好：

- `REPO_ROOT`
- `WORKTREE_ID`
- `APP_PORT`
- `API_PORT`
- `METRICS_PORT`
- `AUX_PORT`
- `APP_URL`
- `API_URL`
- `STATE_ROOT`
- `RUN_ROOT`
- `DATA_ROOT`
- `CACHE_ROOT`
- `LOG_ROOT`
- `ARTIFACT_ROOT`
- `TMP_ROOT`

此外，`scripts/dev-up` 还会把一份 shell 可直接 source 的环境文件写到：

- `run/runtime.env`

这份文件是为真实应用接入、手工调试和后续辅助脚本准备的。

### 生命周期状态语义

为了让 agent 能判断“是否已经可以开始验证”，当前契约将状态语义定义为：

- `prepared`
  运行时环境已准备，但尚未启动真实应用
- `starting`
  应用进程已启动，但 readiness 检查尚未通过
- `ready`
  应用已经通过 readiness 检查，可以开始验证
- `failed`
  应用在启动或 readiness 阶段失败
- `stopped`
  应用已被显式停止
- `reset`
  当前 worktree 的可变运行态已被重置

这里的关键变化是：

- `running` 不再是最终语义
- “有进程”不再等于“可被 agent 开始验证”
- 只有进入 `ready`，才表示实例真的可以被使用

### Readiness 契约

当前实现支持把 readiness 作为正式契约输出，而不是仅靠 PID 推断。

优先级如下：

1. `HARNESS_APP_READY_COMMAND`
2. `HARNESS_APP_READY_URL`
3. `scripts/app-start --print-ready-command`
4. `scripts/app-start --print-ready-url`
5. 默认回退到 `APP_URL`

这意味着：

- `dev-up` 启动后会主动等待 readiness
- `dev-status` 会重新判定当前实例是否 ready
- readiness 失败会进入 `failed`，而不是继续伪装成“正在运行”

### Worktree 模式

为了区分“真实 git worktree 验收”和“当前原型目录模式”，当前契约引入两种 worktree 模式：

- `prototype`
  默认模式。若当前目录不是 git 仓库，则允许退回使用 `pwd`
- `strict-git`
  要求必须能通过 `git rev-parse --show-toplevel` 解析真实 git worktree 根目录，否则直接失败

这条规则的目的是：

- 在当前仓库里继续保留原型能力
- 同时为后续真实项目阶段提供严格模式
- 避免继续把当前状态误描述成“真实 per git worktree 验收已完成”

### Phase 2 推荐实现方式

为了降低后续接框架时的摩擦，推荐按下面顺序实现：

1. 在仓库级入口 `scripts/app-start` 内部实现真实应用接入
2. 如果是单进程场景，可由 `scripts/app-start` 继续读取 `scripts/app-start.command`
3. 让应用显式读取并使用 `APP_PORT`、`API_PORT` 和状态目录变量
4. 明确 readiness URL 或 readiness command
5. 确保应用所有本地写入都落在 `.local/worktrees/<WORKTREE_ID>/...` 下
6. 再考虑健康检查、CDP、日志采集等后续能力

### `scripts/dev-down`

职责：

- 读取当前 worktree 的运行态元数据
- 停止该 worktree 启动的进程
- 保留日志和产物
- 将状态标记为已停止

### `scripts/dev-reset`

职责：

- 执行 `dev-down`
- 删除当前 worktree 的可变本地状态
- 只保留团队明确决定需要保留的内容

默认应清理：

- `data/`
- `cache/`
- `tmp/`
- 运行时 PID 和状态文件

### `scripts/dev-status`

职责：

- 显示当前 worktree 实例是否在运行
- 报告解析后的端口
- 报告关键路径
- 在可用时输出健康检查状态

这个命令应该足够轻量，并且容易被机器消费。

## E. 运行时元数据契约

后续 agent 工具必须有一个稳定位置来发现当前实例。

最少需要下面几个文件。

### `run/env.json`

用途：

- 保存当前 worktree 的解析后环境契约

示例结构：

```json
{
  "worktreeId": "harnessV2-a1b2c3d4",
  "repoRoot": "/Users/mac/code/harnessV2",
  "appUrl": "http://127.0.0.1:4107",
  "apiUrl": "http://127.0.0.1:4207",
  "appStart": {
    "source": "repo-script",
    "command": "/Users/mac/code/harnessV2/scripts/app-start"
  },
  "ports": {
    "app": 4107,
    "api": 4207,
    "metrics": 4307
  },
  "paths": {
    "stateRoot": ".local/worktrees/harnessV2-a1b2c3d4",
    "logRoot": ".local/worktrees/harnessV2-a1b2c3d4/logs",
    "artifactRoot": ".local/worktrees/harnessV2-a1b2c3d4/artifacts"
  }
}
```

### `run/status.json`

用途：

- 保存当前生命周期状态和进程记录

最少字段：

- `state`
- `startedAt`
- `pids`
- `health`

### `run/runtime.env`

用途：

- 为真实应用启动脚本和辅助调试脚本提供可直接 `source` 的环境变量导出

最少应包含：

- 端口变量
- worktree 标识
- 状态目录路径
- 元数据文件路径

## 实施阶段

虽然当前还没有真实业务应用代码，但 worktree 运行时脚手架、仓库级启动入口和最小示例应用验证链路已经存在。因此这里不再只是“待设计阶段”，而是“分阶段收敛阶段”。

### Phase 0：仓库契约

交付物：

- 本设计文档
- 约定好的命名规则
- 约定好的脚本接口
- 约定好的运行时元数据契约

退出标准：

- 后续所有应用脚手架工作都必须遵守这份契约

当前进度：

- 已完成

### Phase 1：引导层工具

交付物：

- 一个共享的 shell 工具或小型 CLI，用于计算 `WORKTREE_ID`
- 端口派生逻辑
- 状态目录创建逻辑
- 元数据写入工具

退出标准：

- 在任意 worktree 中运行时，都能稳定产出一致的 ID、路径和端口

当前进度：

- 已完成 shell 版本实现，核心脚本为 `scripts/lib/worktree-runtime.sh`

### Phase 2：应用启动接入

交付物：

- `scripts/dev-up`
- `scripts/dev-down`
- `scripts/dev-status`
- `scripts/dev-reset`
- `scripts/app-start`
- 应用启动命令接入派生环境变量

退出标准：

- 两个 worktree 可以在同一台机器上并行启动而不冲突

当前进度：

- 已完成仓库级入口 `scripts/app-start`
- 已完成单进程接入原型
- 已完成 readiness 契约和 `starting -> ready / failed` 状态机
- 已完成最小示例应用验证
- 尚未完成真实业务应用接入
- 尚未完成真实 git worktree 双实例并行验收

### Phase 3：面向 agent 的运行准备

交付物：

- 通过元数据稳定发现应用 URL
- `artifacts` 目录接入
- 适合自动化的稳定启动与销毁行为

退出标准：

- 后续浏览器自动化不需要猜测端口和路径

当前进度：

- 部分前置条件已具备，但整体仍待后续阶段继续落地

## 验收标准

只有下面所有条件都成立，节点 1 才算完成：

1. 同一台机器上的两个 git worktree 可以同时运行应用。
2. 前端和后端端口不会冲突。
3. 数据、日志和临时文件不会混用。
4. 有统一命令启动环境。
5. 有统一命令停止环境。
6. 运行时元数据被写到固定路径。
7. 外部自动化工具无需解析控制台输出，就能发现当前应用地址。

## 风险和失败模式

### 1. 隐藏的共享状态

某些框架或依赖仍然可能向全局 temp 或 cache 写数据。

缓解方式：

- 在应用脚手架阶段审计文件系统写入
- 已知可配置路径统一重定向到 worktree 状态根目录

### 2. 与其他本地服务发生端口冲突

按规则派生出来的端口可能恰好已被手工启动的本地进程占用。

缓解方式：

- 启动前端口探测
- 明确错误提示
- 提供清晰修复指引

### 3. 脚本接口扩散

如果不同人或不同 agent 持续增加临时启动方式，统一接口就会失效。

缓解方式：

- 把 `scripts/dev-*` 固定为唯一支持的本地运行入口

### 4. 运行时契约漂移

如果元数据文件与真实运行状态不一致，下游自动化会变脆。

缓解方式：

- 元数据必须由真正启动服务的同一套逻辑生成
- 后续增加结构校验

## 待确认问题

这些问题需要在真实应用脚手架出现后继续确认：

1. 未来应用是单进程还是多进程？
2. 本地开发是基于 Docker，还是保持原生进程模式？
3. 本地数据存储会选 SQLite、Postgres 还是其他服务？
4. 是否需要进程管理器来托管本地服务？
5. 日志第一阶段是先写文件，还是直接进入后续可观测性管道？

## 下一步工程任务

当前基础设计已经基本定稿，下一批最直接的工作不再是“继续定义契约”，而是“把契约接进真实应用并完成验收”：

1. 把真实业务应用命令写入 `scripts/app-start.command`，或在外部编排里显式提供 `HARNESS_APP_START_COMMAND`。
2. 为真实应用明确 readiness URL 或 readiness command。
3. 审计真实应用的本地写入路径，确保尽量收敛到 `.local/worktrees/<WORKTREE_ID>/...`。
4. 在真实 git 仓库和真实 `git worktree` 场景下，完成双 worktree 并行启动验收。
5. 如果真实系统是前后端双进程或多服务，再在 `scripts/app-start` 内部演进为多进程编排，而不是修改 `scripts/dev-up` 的外部接口。

## 当前已落地的脚手架与原型

仓库中已经加入这一设计的当前实现：

- `scripts/lib/worktree-runtime.sh`
- `scripts/dev-up`
- `scripts/dev-down`
- `scripts/dev-reset`
- `scripts/dev-status`
- `scripts/app-start`
- `scripts/app-start.command.example`

这部分脚手架目前已经实现：

- 从 worktree 根路径稳定派生 `WORKTREE_ID`
- 支持按 worktree 派生端口，并支持 `strict` / `soft` 两种冲突策略
- 创建按 worktree 隔离的运行态目录布局
- 将运行时信息写入 `run/env.json`、`run/ports.json`、`run/status.json`
- 将 shell 可直接消费的运行时环境写入 `run/runtime.env`
- 为单进程真实应用接入提供 `scripts/app-start` 入口和 `scripts/app-start.command.example` 模板
- 为 readiness 和真实 git worktree 收敛提供状态机与模式约束
- 即使还没有真实应用，也能先把运行时契约准备好

当前限制：

- 只有在配置 `HARNESS_APP_START_COMMAND`，或由仓库级 `scripts/app-start` 判断出真实应用已配置时，`scripts/dev-up` 才会真正拉起应用进程。在真实应用脚手架出现之前，这个命令默认只准备目录和元数据，不启动长期运行的应用。
- 当前 `soft` 模式只处理“端口占用冲突”这一类问题，不处理应用内部启动失败、依赖服务缺失等更高层错误。

## `.local` 的放置位置

这里的 `.local` 不是用户主目录下的全局 `~/.local`，而是当前 worktree 根目录下的隐藏目录。

也就是说：

- 对当前这个目录，它的实际位置是 `/Users/mac/code/harnessV2/.local`
- 如果未来还有另一个 worktree，例如 `/Users/mac/code/harnessV2-feature-a`，那么它会有自己的 `/Users/mac/code/harnessV2-feature-a/.local`

规则是：

- 每个 worktree 只管理自己根目录下的 `.local`
- 不同 worktree 之间不共享 `.local`
- `.local` 下面再按 `WORKTREE_ID` 划分更细的运行态目录

当前脚本中的实际规则是：

- `STATE_ROOT="$REPO_ROOT/.local/worktrees/$WORKTREE_ID"`

所以 `.local` 的层级关系是：

```text
<当前 worktree 根目录>/
  .local/
    worktrees/
      <WORKTREE_ID>/
        run/
        data/
        cache/
        logs/
        artifacts/
        tmp/
```

## 什么是“当前 worktree 根目录”

这里的“当前 worktree 根目录”，指的是你此刻执行命令所在的那一份仓库工作副本的顶层目录。

如果把 `git worktree` 用直白的话来说：

- 一个 git 仓库可以同时在多个目录下展开出多份工作副本
- 每一份工作副本都对应一个独立目录
- 每一份工作副本通常服务一个分支、一个任务，或者一个变更上下文
- 这些目录共享同一个 git 历史来源，但运行时文件和本地状态不应该混用

在这个设计里：

- `/Users/mac/code/harnessV2` 可以是一份 worktree
- `/Users/mac/code/harnessV2-feature-a` 也可以是另一份 worktree
- 你在哪个目录里执行 `scripts/dev-up`，哪个目录就是“当前 worktree 根目录”

也就是说，“当前”不是一个全局概念，而是一个命令执行上下文概念。

### 在这个设计里的识别方式

脚本会优先执行：

- `git rev-parse --show-toplevel`

如果当前目录真的是一个 git worktree，这个命令会返回该 worktree 的根目录。

如果当前目录暂时还不是一个真实 git 仓库，脚本会退化为：

- 使用当前 shell 的工作目录 `pwd`

所以当前脚本的规则是：

- 优先信任 git 返回的 worktree 根目录
- 没有 git 上下文时，临时把当前目录当作 worktree 根目录

### 为什么要基于“根目录”来派生运行态

因为这个设计需要把“代码副本”和“运行态副本”绑定在一起。

同一个 worktree 根目录，会稳定派生出：

- 一个 `WORKTREE_ID`
- 一组固定端口
- 一组固定状态目录
- 一组固定的运行时元数据文件

这样 agent 或人只要进入某个 worktree 根目录，就总能得到同一套运行态结果。

## `git worktree` 和这个设计的对应关系

在这个设计里，`git worktree` 解决的是“代码隔离”，而 `scripts/dev-*` 解决的是“运行态隔离”。

两者分工如下：

- `git worktree add ...`
  作用：创建一份新的代码工作副本
- `scripts/dev-up`
  作用：为这份代码工作副本拉起对应的独立运行环境
- `scripts/dev-down`
  作用：停止这份工作副本对应的运行环境
- `scripts/dev-reset`
  作用：清空这份工作副本对应的本地可变状态

换句话说：

- `git worktree` 负责“多目录”
- 我们的运行时脚本负责“每个目录有自己独立的运行态”

这两个层面缺一不可。

## 一个具体例子

假设未来仓库已经是一个真实 git 仓库，存在两份 worktree：

```text
/Users/mac/code/harnessV2
/Users/mac/code/harnessV2-feature-a
```

那么：

在 `/Users/mac/code/harnessV2` 里执行：

```bash
scripts/dev-up
```

会得到这一份 worktree 自己的：

- `WORKTREE_ID`
- 端口
- `.local/worktrees/<WORKTREE_ID>/...`

在 `/Users/mac/code/harnessV2-feature-a` 里执行：

```bash
scripts/dev-up
```

会得到另一份 worktree 自己的：

- `WORKTREE_ID`
- 端口
- `.local/worktrees/<WORKTREE_ID>/...`

两边即使同时运行，也不应该互相冲突。

## 对当前仓库状态的补充说明

当前这个目录还不是一个真实的 git 仓库，所以我们现在讨论和实现的其实是“worktree 语义兼容层”。

这意味着：

- 设计目标仍然是面向未来真实 `git worktree` 工作流
- 当前脚本先把“目录即 worktree 上下文”的规则固化下来
- 等仓库初始化为真实 git 仓库后，这套规则就可以自然切换到 `git rev-parse --show-toplevel`

## 初始讨论结论摘要

围绕节点 1 的第一次讨论，最终沉淀出 4 条直接实施建议：

1. 先定义 `WORKTREE_ID` 的生成规则。
2. 所有端口都从 `WORKTREE_ID` 派生，不允许硬编码。
3. 所有本地可变状态统一收敛到按 worktree 隔离的目录下。
4. 启动和销毁统一收口到固定脚本接口，避免 agent 依赖猜测。

这份文档就是后续沿这条路线继续实现的起点。
