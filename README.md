# Worktree Runtime Prototype for Harness

一个面向 Agent 的本地开发运行时原型。

这个项目围绕 `Harness engineering` 里 `Increasing application legibility` 的第一步展开：让应用可以按 worktree 独立启动，使人和 Agent 都能通过统一入口拉起、发现、验证、停止和清理当前实例。

## 项目定位

这个仓库不是某个具体业务应用，而是一套 worktree 级本地运行时方案的实现原型。

它关注的是：

- 如何为每个 worktree 派生稳定的运行时身份
- 如何为每个 worktree 分配隔离的端口和状态目录
- 如何通过统一脚本暴露启动、停止、重置、查询能力
- 如何把运行结果写成机器可读元数据，供人和 Agent 共同消费

## 设计思想

这套方案背后的核心思想，不是“再包装一层开发脚本”，而是把本地应用运行时变成一个对 Agent 直接可理解、可驱动、可验证的系统。

### 1. Agent-first，而不是 command-first

这里优先考虑的不是某个框架应该怎么启动，而是：

- Agent 怎么找到当前实例
- Agent 怎么判断实例是否可用
- Agent 怎么稳定复现、验证和停止一次变更

所以对外暴露的是统一生命周期入口，而不是框架私有命令。

### 2. 运行时契约优先于临时约定

如果端口、目录、状态和启动方式只存在于人的口头约定里，Agent 就无法稳定推理。

因此这套方案把运行时关键信息固定成契约：

- worktree 身份是可派生的
- 端口是可推导的
- 目录是可定位的
- 状态是可枚举的
- 元数据是机器可读的

### 3. 隔离优先于共享

worktree 的价值不只是代码副本隔离，还包括运行态隔离。

所以这里默认假设：

- 每个 worktree 都应该有自己的端口
- 每个 worktree 都应该有自己的 `.local`
- 每个 worktree 都应该有自己的日志、缓存、产物和 PID

这样实例之间不会互相污染，验证结果也更稳定。

### 4. 确定性优先于“能跑就行”

为了让人和 Agent 都能稳定复用结果，这套方案尽量采用确定性规则：

- `WORKTREE_ID` 按路径稳定派生
- 端口按 `WORKTREE_ID` 稳定派生
- 目录按 `WORKTREE_ID` 稳定落盘

“每次运行结果都差不多”是不够的，这里追求的是“每次都能被推理出来”。

### 5. ready 优先于 pid

一个进程还活着，不代表实例真的可以被验证。

因此这套方案不把“进程存在”当成最终状态，而是把 readiness 当成正式语义：

- `starting` 表示进程已经起来，但实例还未准备好
- `ready` 才表示当前实例可以开始验证

### 6. 仓库即事实源

这套方案尽量把规则写进仓库，而不是留在外部说明里。

包括：

- 启动入口在仓库里
- 运行时契约在仓库里
- 使用方式在仓库里
- 示例应用也在仓库里

这样无论是人还是 Agent，进入仓库后都能从文件系统本身读出这套系统是如何工作的。

## 设计思路

这套方案的出发点不是“怎么运行一个框架命令”，而是“怎么让 Agent 能稳定使用当前实例”。

因此设计顺序是：

1. 先为当前 worktree 派生稳定的 `WORKTREE_ID`
2. 再按 `WORKTREE_ID` 确定性派生端口
3. 再把可变运行态收敛到 `.local/worktrees/<WORKTREE_ID>/...`
4. 再通过统一生命周期脚本管理实例
5. 最后通过 readiness 语义定义“什么时候实例真的可用”

这里最关键的原则有两个：

- 统一入口优先于框架命令
- `ready` 优先于“进程还活着”

## 核心能力

### 1. worktree 级运行时身份

当前会从 worktree 根目录派生：

```text
WORKTREE_ID=<basename>-<hash8>
```

同一目录重启保持稳定，不同目录天然隔离。

### 2. worktree 级端口分配

当前端口按 `WORKTREE_ID` 确定性派生：

- `APP_PORT`：`4100-4199`
- `API_PORT`：`4200-4299`
- `METRICS_PORT`：`4300-4399`
- `AUX_PORT`：`4400-4499`

支持两种冲突模式：

- `strict`：默认模式，冲突直接失败
- `soft`：受控回退模式，适合人工调试

### 3. worktree 级状态目录

所有可变运行态默认写入：

```text
.local/worktrees/<WORKTREE_ID>/
```

目录结构如下：

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

### 4. 统一生命周期入口

项目提供四个标准脚本：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
scripts/dev-reset
```

职责分工：

- `scripts/dev-up`：准备运行时契约、分配端口、写元数据、启动真实应用并等待 readiness
- `scripts/dev-status`：输出当前实例状态，并重新判断是否 ready
- `scripts/dev-down`：停止当前 worktree 对应的应用进程
- `scripts/dev-reset`：停止实例并清理可变运行态数据

### 5. 仓库级真实应用入口

真实应用统一从下面这个入口接入：

```bash
scripts/app-start
```

当前实现采用单进程策略，但对外语义保持为“仓库级真实应用启动入口”。

当前命令来源优先级：

1. `HARNESS_APP_START_COMMAND`
2. `scripts/app-start`
   由它内部继续解析：
   `HARNESS_SINGLE_PROCESS_COMMAND`
   `scripts/app-start.command`

### 6. readiness 状态语义

当前生命周期状态包括：

- `prepared`
- `starting`
- `ready`
- `failed`
- `stopped`
- `reset`

readiness 优先级：

1. `HARNESS_APP_READY_COMMAND`
2. `HARNESS_APP_READY_URL`
3. `scripts/app-start --print-ready-command`
4. `scripts/app-start --print-ready-url`
5. 如果应用已配置，则回退到 `APP_URL`

## 仓库结构

主要文件如下：

- [Harness engineering.md](./Harness%20engineering.md)
- [AGENTS.md](./AGENTS.md)
- [increasing-application-legibility-node-1-per-worktree-boot-design.md](./increasing-application-legibility-node-1-per-worktree-boot-design.md)
- [worktree-phase-summary.md](./worktree-phase-summary.md)
- [worktree-implementation-review-2026-03-30.md](./worktree-implementation-review-2026-03-30.md)
- [scripts/lib/worktree-runtime.sh](./scripts/lib/worktree-runtime.sh)
- [scripts/dev-up](./scripts/dev-up)
- [scripts/dev-status](./scripts/dev-status)
- [scripts/dev-down](./scripts/dev-down)
- [scripts/dev-reset](./scripts/dev-reset)
- [scripts/app-start](./scripts/app-start)
- [scripts/app-start.command.example](./scripts/app-start.command.example)
- [scripts/example-single-process-server.py](./scripts/example-single-process-server.py)

## 快速开始

### 1. 只准备运行时环境

```bash
scripts/dev-up
scripts/dev-status
```

这会：

- 计算 `WORKTREE_ID`
- 分配端口
- 创建 `.local/worktrees/<WORKTREE_ID>/...`
- 写入运行时元数据

你可以通过下面两种方式读取当前解析结果：

- 执行 `scripts/dev-status`
- 读取 `.local/worktrees/<WORKTREE_ID>/run/runtime.env`

### 2. 接入真实单进程应用

复制模板：

```bash
cp scripts/app-start.command.example scripts/app-start.command
```

然后把文件内容改成真实应用命令，例如：

```bash
exec npm run dev -- --port "$APP_PORT"
```

之后统一通过下面的命令操作：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
```

### 3. 临时覆盖启动命令

如果你不想创建 `scripts/app-start.command`，也可以临时传环境变量：

```bash
HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py' scripts/dev-up
```

### 4. 使用柔性端口回退

```bash
HARNESS_PORT_CONFLICT_MODE=soft scripts/dev-up
```

### 5. 使用严格 git 模式

```bash
HARNESS_WORKTREE_MODE=strict-git scripts/dev-up
```

## 示例验证

项目内置了一个最小单进程示例应用：

- [scripts/example-single-process-server.py](./scripts/example-single-process-server.py)

可以直接这样验证整条启动链路：

```bash
HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py' scripts/dev-up
scripts/dev-status
scripts/dev-down
```

如果需要访问示例服务，可以使用 `scripts/dev-status` 输出里的 `APP_URL`。

## 文档索引

建议按这个顺序阅读：

1. [README.md](./README.md)
2. [Harness engineering.md](./Harness%20engineering.md)
3. [increasing-application-legibility-node-1-per-worktree-boot-design.md](./increasing-application-legibility-node-1-per-worktree-boot-design.md)
4. [worktree-phase-summary.md](./worktree-phase-summary.md)
5. [worktree-implementation-review-2026-03-30.md](./worktree-implementation-review-2026-03-30.md)
