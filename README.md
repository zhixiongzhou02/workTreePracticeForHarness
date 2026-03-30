# Harness Worktree Runtime Prototype

一个围绕 `Harness engineering` 中 `Increasing application legibility` 落地的本地运行时原型。

这个仓库当前做的事情，不是实现某个业务应用，而是把“按 git worktree 独立启动应用”这件事先收敛成一套可执行的工程约束、脚本入口和运行时契约。目标是让人和 agent 都能通过统一入口，稳定发现、启动、查询、停止和重置当前 worktree 对应的本地实例。

## 从参考文档到本项目目标

这个仓库的“项目目标”不是直接照抄参考文档里的标题，而是从参考文档的问题定义一路往下拆出来的。

### 1. 参考文档给出的上层目标

[Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md) 在 `Increasing application legibility` 里真正强调的是：

- 随着代码产出速度提升，瓶颈变成了人的 QA 能力
- 如果 agent 只能改代码、不能自己验证结果，人仍然会成为系统瓶颈
- 因此要让 agent 能独立拉起应用、驱动实例、观察运行态并完成验证

原文里 `per git worktree boot` 不是孤立的技巧，而是服务于这个更高层目标：

`让 agent 获得独立、自洽、可销毁的本地验证环境，从而减少对人工 QA 的依赖。`

### 2. 从上层目标拆出第一个工程子目标

如果要让 agent 真的拥有这种验证环境，第一步不是先接 UI 自动化，也不是先接日志和指标，而是先解决一个更基础的问题：

`每一次变更，能不能稳定拥有一个属于自己的本地实例？`

这就是为什么本项目当前只聚焦于 `per git worktree boot`。

因为在这个阶段，必须先把下面这些基础能力做出来：

- 当前实例有稳定身份
- 当前实例有稳定地址
- 当前实例的状态不和其他任务混在一起
- 当前实例能通过统一入口被启动和停止
- 当前实例的信息能被 agent 直接读取

如果这一层没有先成立，后面的 UI 自动化、日志查询、指标校验都没有稳定锚点。

### 3. 本项目目标的形成方式

基于上面的拆解，这个仓库最终收敛出的“项目目标”不是“完成 Increasing application legibility 的全部能力”，而是：

`把 agent 自主验证所需的第一层基础设施，先收敛成一套可执行的 per-worktree runtime contract。`

这些目标并不是另起炉灶，而是从参考文档的高层目标往下拆解后，当前节点真正可落地、可验证的一层。

### 4. 当前节点的边界

所以，这个仓库当前解决的是：

- agent 如何拥有一个属于当前 worktree 的隔离运行态

它还没有解决的是：

- agent 如何驱动真实业务 UI
- agent 如何查询日志、指标和 trace
- agent 如何在真实业务应用上完成完整验证闭环

这些能力依然属于参考文档里的整体目标，但在当前仓库中，它们被有意放到了后续节点。

## 项目目标

基于前面的拆解，当前节点只回答：

`这个原型仓库当前到底要交付哪一层能力？`

当前交付范围是：

- 为每个 worktree 派生稳定的 `WORKTREE_ID`
- 为每个 worktree 派生稳定的端口
- 为每个 worktree 隔离本地状态目录
- 通过统一脚本管理生命周期
- 把运行时信息写成机器可读元数据，供后续 agent 工具直接消费

也就是说，本项目当前交付的是：

`agent 自主验证闭环的第一层运行时基础设施。`

当前项目仍然是原型，不等同于“完整 per-worktree runtime 已完成”。更准确的状态是：

`worktree 运行时脚手架已经建立，但真实 git worktree 验收和真实业务应用接入还没有完成。`

## 设计原则

只要当前节点的目标是“让 agent 稳定拥有属于当前 worktree 的可验证实例”，就会自然推出几条必须贯彻到实现里的原则。

### 1. 统一入口优先于框架命令

因为启动和停止动作必须走同一套入口，agent 不能每次靠猜 `npm run dev`、`pnpm dev` 或其他私有命令。

当前仓库把统一入口收口到：

- `scripts/dev-up`
- `scripts/dev-status`
- `scripts/dev-down`
- `scripts/dev-reset`

### 2. 运行时契约优先于口头约定

因为当前实例的信息必须能被机器直接读取，而不是依赖人脑中的记忆。

所以仓库需要把这些事实显式落盘：

- 当前实例身份
- 当前实例端口
- 当前实例目录
- 当前实例状态
- 当前实例启动来源

对应产物就是 `env.json`、`ports.json`、`status.json`、`runtime.env`。

### 3. 隔离优先于共享

因为 per-worktree boot 的本质，就是让每次变更拥有自己可销毁的运行态，而不是共享一个本地实例。

所以每个 worktree 都应拥有自己独立的：

- 端口
- `.local/worktrees/<WORKTREE_ID>/...`
- 日志
- 缓存
- 产物
- PID 和状态文件

### 4. 可验证优先于“能跑就行”

因为对 agent 来说，进程存在不等于已经可以开始验证。

所以运行态必须有明确语义，而不是只靠“进程还活着”来判断。当前实现已经把生命周期状态收敛到：

- `prepared`
- `starting`
- `ready`
- `failed`
- `stopped`
- `reset`

并把 readiness 检查纳入正式契约。

## 当前状态

### 已实现

- worktree 身份稳定派生
- 按 worktree 的确定性端口分配
- `.local/worktrees/<WORKTREE_ID>/...` 运行态隔离目录
- `scripts/dev-up`、`scripts/dev-status`、`scripts/dev-down`、`scripts/dev-reset` 统一生命周期入口
- `scripts/app-start` 仓库级真实应用入口
- `env.json`、`ports.json`、`status.json`、`runtime.env` 机器可读元数据
- `prepared / starting / ready / failed / stopped / reset` 生命周期状态
- readiness URL / command 契约
- `review-only`、`code-only`、`app-validate` 三种 task profile
- `prototype` / `strict-git` 两种 worktree 模式
- 最小单进程示例应用与整条启动链路验证

### 未实现

- 两个真实 git worktree 的并行验收
- 真实业务应用的正式接入
- 多进程或多服务编排的正式契约
- UI 自动化接入
- 日志、指标、trace 的查询与验证闭环

### 当前适用定位

基于上面的实现范围，这个仓库当前更适合作为：

- 设计约束的事实源
- worktree runtime 的实现原型
- 后续接真实应用前的工程骨架

而不是一个已经完成业务落地的应用仓库。

## 核心机制

### 1. 身份、端口和目录一起派生

当前实现不是分别处理 worktree 身份、端口和状态目录，而是把三者当成同一个运行时契约来生成。

- 仓库根目录稳定派生 `WORKTREE_ID`
- `WORKTREE_ID` 再确定性派生 `APP_PORT`、`API_PORT`、`METRICS_PORT`、`AUX_PORT`
- 所有可变运行态统一落到 `.local/worktrees/<WORKTREE_ID>/...`

其中状态目录结构固定为：

```text
.local/
  worktrees/
    <WORKTREE_ID>/
      run/
        env.json
        ports.json
        runtime.env
        status.json
        app.pid
        app.pgid
      data/
      cache/
      logs/
      artifacts/
      tmp/
```

### 2. 生命周期与真实应用入口分离

当前仓库把“运行时框架”和“真实应用怎么启动”明确拆开：

- `scripts/dev-*` 负责 worktree 运行时生命周期
- [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start) 负责仓库级真实应用入口

这样 `dev-up` 不需要理解具体框架命令，真实应用如何启动被收口在仓库内，后续即使从单进程演进到多进程，外部入口也不需要变化。

### 3. 用状态语义表达“是否可验证”

当前实现不把“进程还活着”当成最终判断，而是显式区分：

- `prepared`
- `starting`
- `ready`
- `failed`
- `stopped`
- `reset`

同时支持 readiness 契约，优先级如下：

1. `HARNESS_APP_READY_COMMAND`
2. `HARNESS_APP_READY_URL`
3. `scripts/app-start --print-ready-command`
4. `scripts/app-start --print-ready-url`
5. 如果应用已配置，则回退到 `APP_URL`

### 4. 用 task profile 决定是否默认启动实例

为了避免把“worktree”误解成“每次都必须拉起应用”，当前模型把任务分成三类：

- `review-only`
- `code-only`
- `app-validate`

默认值是：

```bash
app-validate
```

也就是说，当前仓库不是简单地“有无运行时”二选一，而是在 worktree 隔离、运行时隔离和真实应用启动之间做了分层。

## 快速开始

### 1. 最小路径：只准备运行时环境

```bash
scripts/dev-up
scripts/dev-status
```

在没有真实应用启动命令时，`dev-up` 会：

- 计算 `WORKTREE_ID`
- 分配端口
- 创建 `.local/worktrees/<WORKTREE_ID>/...`
- 生成 `env.json`、`ports.json`、`status.json`、`runtime.env`
- 停在 `prepared`

### 2. 示例路径：跑通完整启动链路

仓库内置了一个最小单进程示例应用：

- [scripts/example-single-process-server.py](/Users/mac/code/harnessV2/scripts/example-single-process-server.py)

可以直接这样验证：

```bash
HARNESS_TASK_PROFILE=app-validate \
HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py' scripts/dev-up

scripts/dev-status
scripts/dev-down
```

这条链路会经过：

```text
scripts/dev-up
  -> scripts/app-start
     -> 真实单进程命令
```

### 3. 接入路径：连接真实单进程应用

复制模板：

```bash
cp scripts/app-start.command.example scripts/app-start.command
```

然后把里面的示例命令改成真实应用命令，例如：

```bash
exec npm run dev -- --port "$APP_PORT"
```

之后统一通过：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
```

### 可选模式

如果你需要更严格的环境约束或本地调试回退，可以再使用下面两个开关。

#### 严格 git 模式

当前仓库默认工作在原型模式：

```bash
HARNESS_WORKTREE_MODE=prototype
```

如果你希望只有在真实 git worktree 环境下才允许启动，可以使用：

```bash
HARNESS_WORKTREE_MODE=strict-git scripts/dev-up
```

#### 柔性端口回退

```bash
HARNESS_PORT_CONFLICT_MODE=soft scripts/dev-up
```

## 关键产物

启动后，后续工具最常用的是这四个文件：

- `run/env.json`：当前 worktree 的解析后环境契约
- `run/ports.json`：当前最终端口与端口分配来源
- `run/status.json`：生命周期状态、ready 信息和失败原因
- `run/runtime.env`：可直接 `source` 的 shell 环境变量

## 仓库文档

建议阅读顺序：

1. [README.md](/Users/mac/code/harnessV2/README.md)
2. [Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md)
3. [increasing-application-legibility-node-1-per-worktree-boot-design.md](/Users/mac/code/harnessV2/increasing-application-legibility-node-1-per-worktree-boot-design.md)
4. [worktree-phase-summary.md](/Users/mac/code/harnessV2/worktree-phase-summary.md)
5. [worktree-implementation-review-2026-03-30.md](/Users/mac/code/harnessV2/worktree-implementation-review-2026-03-30.md)
