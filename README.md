# HarnessV2 Worktree Runtime Prototype

这个仓库当前沉淀的是一套围绕 `Increasing application legibility` 第一节点，也就是 `per git worktree boot` 的落地方案。

更具体地说，它解决的问题不是“怎么把应用跑起来”，而是“怎么让人和 Agent 都能通过统一入口，在每个 worktree 下稳定拉起、发现、验证、停止并清理一个彼此隔离的本地实例”。

当前状态可以准确概括为：

`面向 worktree 的运行时隔离脚手架已经落地，仓库级真实应用入口已经建立，单进程链路已经验证通过，但真实 git worktree 双实例验收和真实业务应用接入还没有完成。`

## 1. 这套方案要解决什么问题

原始背景来自 [Harness engineering.md](./Harness%20engineering.md) 里的 `Increasing application legibility`：

> We made the app bootable per git worktree, so Codex could launch and drive one instance per change.

这里的核心不是“多开几个开发环境”，而是把本地应用变成 Agent 可以直接消费的运行时对象。

如果没有 worktree 级隔离，会出现几个直接问题：

- 多个变更共享同一组端口，实例互相抢占。
- 本地数据、缓存、日志和测试产物混在一起。
- Agent 很难知道自己连到的是哪个实例。
- 同一个 bug 的复现、修复验证和回归检查会变得不稳定。

所以这套方案的目标是：

- 每个 worktree 都能派生出自己的运行时身份。
- 每个 worktree 都有自己的端口、状态目录和元数据。
- 人和 Agent 都通过同一套 `scripts/dev-*` 入口操作实例。
- 运行结果必须写成机器可读文件，而不是只靠控制台输出。

## 2. 我们的思考过程

这轮设计不是从“框架启动命令”开始的，而是从“Agent 要如何稳定使用应用”倒推出来的。

### 第一层：先定义 worktree 运行时身份

如果每个 worktree 不能稳定派生出唯一身份，那么后面的端口分配、状态目录、日志落点和实例发现都无从谈起。

所以第一步先固定：

- `WORKTREE_ID` 必须从当前 worktree 根目录稳定派生
- 同一目录多次重启结果一致
- 不同目录天然不同

### 第二层：再定义确定性端口和隔离目录

只有身份稳定还不够，还要让这个身份能映射出一整套稳定运行态：

- `APP_PORT`
- `API_PORT`
- `METRICS_PORT`
- `AUX_PORT`
- `.local/worktrees/<WORKTREE_ID>/...`

这样同一个 worktree 重启后，Agent 仍然知道应该去哪找应用、日志和产物。

### 第三层：把“启动应用”收口成统一入口

如果人用 `npm run dev`，Agent 用 `python xxx.py`，脚本再用另一套方式启动，那么运行态就会失真。

所以我们固定了统一入口：

- `scripts/dev-up`
- `scripts/dev-status`
- `scripts/dev-down`
- `scripts/dev-reset`

其中：

- `dev-up` 负责 worktree 运行时契约
- `app-start` 负责仓库级真实应用入口

### 第四层：状态不能只看 PID，必须看 readiness

“进程活着”不等于“实例可验证”。

因此这套方案明确引入了 readiness 语义，把生命周期状态定义为：

- `prepared`
- `starting`
- `ready`
- `failed`
- `stopped`
- `reset`

这里最关键的一点是：

- 只有 `ready` 才表示 Agent 可以开始验证

### 第五层：先做可执行原型，再做真实应用验收

当前仓库还没有真实业务应用代码，所以这轮工作没有停在概念文档，而是先落了一套可执行原型：

- worktree 运行时库
- 生命周期脚本
- 仓库级 `scripts/app-start`
- 单进程命令模板
- 一个最小示例应用

目的很直接：

- 先证明这条链路真的能跑通
- 再把真实业务应用接进来
- 最后再去做真实 git worktree 双实例验收

## 3. 当前落地方案是什么

### 3.1 统一生命周期入口

仓库当前提供四个标准脚本：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
scripts/dev-reset
```

职责分工如下：

- `scripts/dev-up`：准备运行时契约、分配端口、写元数据、拉起真实应用并等待 readiness
- `scripts/dev-status`：输出当前实例状态，并重新判断是否 ready
- `scripts/dev-down`：停止当前 worktree 对应的应用进程
- `scripts/dev-reset`：停止实例并清理可变运行态数据

### 3.2 仓库级真实应用入口

真实应用入口固定为：

```bash
scripts/app-start
```

它的对外语义是“仓库级真实应用启动入口”。

当前实现先采用单进程策略，但这是内部实现，不是对外接口语义。

当前命令来源优先级是：

1. `HARNESS_APP_START_COMMAND`
2. `scripts/app-start`
   由它内部继续解析：
   `HARNESS_SINGLE_PROCESS_COMMAND`
   `scripts/app-start.command`

也就是说：

- 外部只需要知道 `scripts/dev-up`
- 仓库内部真实应用如何启动，统一收口在 `scripts/app-start`

### 3.3 worktree 身份与目录布局

当前会从 worktree 根目录派生：

```text
WORKTREE_ID=<basename>-<hash8>
```

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

### 3.4 端口策略

当前端口按 `WORKTREE_ID` 确定性派生：

- `APP_PORT`：`4100-4199`
- `API_PORT`：`4200-4299`
- `METRICS_PORT`：`4300-4399`
- `AUX_PORT`：`4400-4499`

冲突策略分两种：

- `strict`
  默认模式。端口冲突直接失败，适合 Agent 和自动化。
- `soft`
  柔性回退模式。会在受控范围内尝试后续 offset，适合人工调试。

### 3.5 readiness 契约

当前 readiness 的优先级是：

1. `HARNESS_APP_READY_COMMAND`
2. `HARNESS_APP_READY_URL`
3. `scripts/app-start --print-ready-command`
4. `scripts/app-start --print-ready-url`
5. 如果应用已配置，则回退到 `APP_URL`

这意味着：

- `dev-up` 启动后会等待 readiness
- `dev-status` 不只看 PID，还会重新判断 ready 状态

### 3.6 worktree 模式

当前支持两种模式：

- `prototype`
  默认模式。当前目录不是 git 仓库时，允许退回 `pwd` 作为 worktree 根目录。
- `strict-git`
  必须能通过 `git rev-parse --show-toplevel` 解析真实 git worktree 根目录，否则直接失败。

这里的意思很明确：

- 当前仓库先保留原型能力
- 但不会再把当前状态误描述成“真实 git worktree 已验收”

## 4. 当前仓库里已经有哪些文件

核心文件如下：

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

可以把它们理解成三层：

- 文章和设计文档：说明为什么做、做成什么样
- 生命周期脚本和运行时库：负责 worktree 运行时契约
- `app-start` 和示例应用：负责证明真实启动链路是成立的

## 5. 怎么使用

### 5.1 只准备运行时环境

如果当前还没有真实应用命令，可以直接执行：

```bash
scripts/dev-up
scripts/dev-status
```

这时系统会：

- 计算 `WORKTREE_ID`
- 分配端口
- 创建 `.local/worktrees/<WORKTREE_ID>/...`
- 写入运行时元数据

你可以通过下面两种方式拿到当前解析结果：

- 直接执行 `scripts/dev-status`
- 或者读取 `.local/worktrees/<WORKTREE_ID>/run/runtime.env`

此时状态通常是：

```text
STATE: prepared
```

### 5.2 接入真实单进程应用

推荐方式是复制模板：

```bash
cp scripts/app-start.command.example scripts/app-start.command
```

然后把里面的命令改成你的真实应用命令，例如：

```bash
exec npm run dev -- --port "$APP_PORT"
```

之后统一通过下面的命令操作：

```bash
scripts/dev-up
scripts/dev-status
scripts/dev-down
```

### 5.3 临时覆盖启动命令

如果你不想立刻创建 `scripts/app-start.command`，也可以临时传环境变量：

```bash
HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py' scripts/dev-up
```

### 5.4 使用软端口回退模式

如果本机有端口冲突，但你希望本地调试先跑起来，可以用：

```bash
HARNESS_PORT_CONFLICT_MODE=soft scripts/dev-up
```

### 5.5 使用严格 git worktree 模式

当仓库进入真实 git worktree 场景后，可以用：

```bash
HARNESS_WORKTREE_MODE=strict-git scripts/dev-up
```

如果当前目录不是 git worktree，这个命令会直接失败。

## 6. 当前已经验证了什么

这一轮已经验证过两类场景。

### 场景 A：未配置真实应用时的行为

执行：

```bash
scripts/dev-reset
scripts/dev-up
scripts/dev-status
```

验证结果：

- 状态为 `prepared`
- 健康状态为 `not_configured`
- 运行时目录和元数据会被正确生成

### 场景 B：最小示例应用完整链路

执行：

```bash
HARNESS_SINGLE_PROCESS_COMMAND='exec python3 scripts/example-single-process-server.py' scripts/dev-up
scripts/dev-status
# 使用 scripts/dev-status 输出里的 APP_URL 访问示例服务
scripts/dev-down
```

验证结果：

- `dev-up` 能拉起真实应用
- `dev-status` 会进入 `ready`
- `curl` 能拿到示例应用返回的运行时 JSON
- JSON 中的 `worktreeId`、`appPort`、`stateRoot` 等信息与元数据一致
- `dev-down` 能正常停止进程

## 7. 当前还没完成什么

这套方案现在不是最终完成态，当前还缺下面几件事：

- 当前目录还不是一个真实 git 仓库
- 还没有真实业务应用代码
- 还没有把真实业务应用正式接入默认启动命令
- 还没有做两个真实 git worktree 的并行启动验收
- 还没有继续往上接 CDP、日志查询、指标和 trace 校验

所以现阶段最准确的判断不是“per git worktree boot 已完成”，而是：

`per-worktree runtime prototype 已经落地，并且在单进程场景下完成了真实链路验证。`

## 8. 下一步建议

如果继续沿当前方案推进，优先级应该是：

1. 把真实业务应用命令写进 `scripts/app-start.command`
2. 为真实应用显式定义 readiness URL 或 readiness command
3. 审计真实应用的本地写入路径，尽量全部收敛到 `.local/worktrees/<WORKTREE_ID>/...`
4. 把仓库放进真实 git 环境，完成双 worktree 并行验收
5. 如果真实系统是前后端双进程，再在 `scripts/app-start` 内部演进为多进程编排

## 9. 文档索引

如果你要继续深入，建议按这个顺序读：

1. [README.md](./README.md)
2. [Harness engineering.md](./Harness%20engineering.md)
3. [increasing-application-legibility-node-1-per-worktree-boot-design.md](./increasing-application-legibility-node-1-per-worktree-boot-design.md)
4. [worktree-phase-summary.md](./worktree-phase-summary.md)
5. [worktree-implementation-review-2026-03-30.md](./worktree-implementation-review-2026-03-30.md)

这几个文件的分工是：

- README：给第一次进入仓库的人快速建立整体认知
- 设计文档：给实现层和后续演进使用
- 阶段总结：给当前状态和使用方式做收口
- 审查文档：记录审查时发现的问题和后续修复状态
