# Worktree 实现审查

## 背景

本文档记录对当前仓库中 `Increasing application legibility` 第一节点，也就是 `per git worktree boot` 落地情况的审查结论。

审查基准：

- [Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md)
- [increasing-application-legibility-node-1-per-worktree-boot-design.md](/Users/mac/code/harnessV2/increasing-application-legibility-node-1-per-worktree-boot-design.md)
- 当前脚本实现：
  - [scripts/lib/worktree-runtime.sh](/Users/mac/code/harnessV2/scripts/lib/worktree-runtime.sh)
  - [scripts/dev-up](/Users/mac/code/harnessV2/scripts/dev-up)
  - [scripts/dev-down](/Users/mac/code/harnessV2/scripts/dev-down)
  - [scripts/dev-reset](/Users/mac/code/harnessV2/scripts/dev-reset)
  - [scripts/dev-status](/Users/mac/code/harnessV2/scripts/dev-status)
  - [scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start)

审查时间：

- 2026-03-30

说明：

- 本文档中的“主要偏离点”是 2026-03-30 审查时刻的快照。
- 其中第 1、2、4 点已在同日后续实现中完成修复或收敛。
- 第 3 点的边界定义已经通过 `prototype` / `strict-git` 模式和文档澄清完成修正，但“真实 git worktree 验收”本身仍未完成。

## 总体结论

当前实现的主方向没有偏离。

已经对齐的部分包括：

- 按 worktree 派生 `WORKTREE_ID`
- 按 worktree 派生端口
- 按 worktree 隔离状态目录
- 通过固定 `scripts/dev-*` 暴露统一生命周期入口
- 产出机器可读运行时元数据

但如果以原文的真实目标来判断，当前状态更准确地说是：

`worktree 运行时脚手架已经建立，但还没有形成足以支撑 agent 独立复现、驱动、验证和销毁实例的完整运行面。`

换句话说，当前实现还不能把“准备运行时环境”与“让 agent 可验证地使用该实例”完全等同。

## 后续修复状态

相对于本次审查时刻，当前仓库后续已经补上的内容如下：

### 1. `scripts/app-start` 已重新收口为仓库级入口

当前的实际分工已经变成：

- `scripts/dev-up` 负责 worktree 运行时契约、端口分配、状态目录和生命周期状态机
- `scripts/app-start` 负责仓库级真实应用启动入口
- `HARNESS_SINGLE_PROCESS_COMMAND` 和 `scripts/app-start.command` 只作为 `scripts/app-start` 的当前单进程实现细节

也就是说，审查时担心的“`dev-up` 理解应用内部细节”已经被收口掉了。

### 2. 生命周期语义已经升级为 readiness 驱动

当前状态机已经包含：

- `prepared`
- `starting`
- `ready`
- `failed`
- `stopped`
- `reset`

同时已经补了：

- readiness URL / command 契约
- `dev-up` 启动后等待 readiness
- `dev-status` 重新计算 ready 状态
- 进程组优先停止，PID 作为回退

因此，这一项在“单进程原型是否足以支撑 agent 判断实例是否可用”这个层面，已经完成当前阶段修复。

### 3. `per git worktree` 的边界已经被明确标注

当前不再把原型目录模式误描述成“真实 git worktree 已验收”。

已经落下的边界包括：

- `HARNESS_WORKTREE_MODE=prototype`
- `HARNESS_WORKTREE_MODE=strict-git`
- 在 `strict-git` 模式下，无法解析真实 git worktree 根目录时会直接失败

所以这里剩下的问题，不再是“定义模糊”，而是“真实 git worktree 双实例验收尚未执行”。

### 4. 文档漂移已经完成一轮同步修复

当前主设计文档、阶段总结文档和脚本注释，已经同步到下面这些事实状态：

- `scripts/app-start` 是仓库级入口
- 生命周期以 `starting / ready / failed` 为核心语义
- 当前仓库处于 `prototype` 原型模式，而不是真实 git worktree 验收完成态
- 单进程示例应用已经完成一条真实闭环验证链路

后续仍然需要继续保持同步，但“审查时已经发生明显漂移”的问题，当前已经做过一轮实质修复。

## 审查基准中的关键目标

[Harness engineering.md](/Users/mac/code/harnessV2/Harness%20engineering.md) 中 `Increasing application legibility` 的重点，不是单纯让应用在不同目录下启动，而是降低人的 QA 负担，让 agent 能直接使用应用、日志和后续的可观测性能力自行验证结果。

关键目标可以收敛为一句话：

`任意一个 git worktree，都应能被 agent 通过统一入口稳定拉起、发现、驱动、验证、停止，并且整个过程对其他 worktree 隔离。`

## 与目标一致的部分

### 1. 运行时隔离思路是对的

当前脚本已经把以下运行态信息纳入 worktree 维度：

- 身份
- 端口
- 目录
- 元数据

这与“每次变更都拥有自己的可销毁实例”这一目标是一致的。

### 2. 统一入口思路是对的

通过 `scripts/dev-up`、`scripts/dev-down`、`scripts/dev-reset`、`scripts/dev-status` 收口生命周期，也符合“人和 agent 使用同一套操作入口”的目标。

### 3. 机器可读元数据方向正确

`env.json`、`ports.json`、`status.json`、`runtime.env` 这些文件，为后续 agent 工具读取当前实例状态提供了稳定落点。这一点符合“让系统本身对 agent 可理解”的原则。

## 主要偏离点（审查时快照）

### 1. `scripts/app-start` 的职责被收窄成了“单进程包装器”

设计目标里，`scripts/app-start` 应该是仓库级真实应用启动入口。

它的角色应当是：

- 封装真实应用启动方式
- 屏蔽底层框架差异
- 承接单进程、双进程或多服务编排

但当前实现里，[scripts/app-start](/Users/mac/code/harnessV2/scripts/app-start) 已经被落成“单进程真实应用接入器”，并把真实命令继续下沉到了 `HARNESS_SINGLE_PROCESS_COMMAND` 或 `scripts/app-start.command`。

这会带来两个问题：

- `scripts/dev-up` 开始了解单进程接入细节，而不是只认仓库级入口
- 后续从单进程扩展到前后端双进程或多服务时，现有接口语义会变窄

这不是彻底跑偏，但已经在把“稳定仓库入口”收缩成“当前单进程方案的包装层”。

建议：

- 把 `scripts/app-start` 重新定义为唯一的仓库级应用启动入口
- 单进程只是 `scripts/app-start` 的一种实现方式，而不是 `dev-up` 需要理解的特殊模式
- `dev-up` 应只决定运行时契约，不应理解 `app-start.command` 这类应用内部细节

### 2. 生命周期语义还不足以支撑 agent 验证闭环

当前脚本已经有 `prepared`、`running`、`stopped`、`reset` 等状态，但这些状态更多是在描述脚本动作，而不是在描述“agent 能否真正开始验证”。

现在的缺口主要有：

- `running` 更接近“命令已后台启动”，不等于“实例已可访问”
- `dev-status` 主要依赖 PID 和元数据，不代表 ready 或 healthy
- `dev-down` 只管理单个 `app.pid`
- 对多进程场景还没有正式的进程组或多 PID 契约

这意味着脚本可以说“正在运行”，但 agent 仍然不知道：

- 当前页面是否可打开
- API 是否可访问
- 实例是否已经 ready
- 停止动作是否真的把整组进程都收干净

建议：

- 先补生命周期状态机，再继续扩展真实接入
- 至少明确 `prepared -> starting -> ready -> stopped/failed`
- 把 ready 判定方式纳入正式契约
- 把单 PID 模型升级为进程组或多 PID 记录模型
- 让 `dev-status` 输出“是否可被 agent 开始验证”，而不是仅输出“是否有进程”

### 3. `per git worktree` 目前仍是“目录级近似”，还不是真正验证过的 worktree 语义

当前实现在非 git 仓库下，会退回使用 `pwd` 解析 `REPO_ROOT` 和 `WORKTREE_ID`。

这使得脚手架在当前仓库里能工作，但也意味着：

- 现在还没有真正站在 git worktree 语义上验证设计
- 还没有在两个真实 worktree 上并行启动做过验收
- 还不能证明当前的身份派生、端口派生和状态隔离，在真实 worktree 下没有边界问题

因此，当前更准确的说法应该是：

`已经实现了面向 worktree 的运行时契约原型，但还没有完成真实 git worktree 场景下的验收。`

建议：

- 在真实项目阶段，把“是否处于 git worktree 环境”变成明确前提
- 如果保留非 git 模式，应该明确标注它只是兼容或原型模式
- 不要把当前状态描述成“per git worktree boot 已完成”

### 4. 文档已经出现会伤害 legibility 的漂移

原始文章强调，过期文档会直接误导 agent。

当前仓库中已经出现两类漂移：

- 主设计文档中的“当前仓库状态”仍停留在脚手架尚未实现之前
- 阶段总结里有少量表述已经比代码行为更理想化

如果这些漂移继续存在，后续 agent 会同时读到：

- 设计目标
- 过期现状
- 已变化的代码行为

这会直接削弱“repository as system of record”的目的。

建议：

- 严格区分“设计目标”“当前实现”“审查结论”
- 对入口解析规则、状态语义、真实接入前提，只保留一个事实源
- 后续每次脚本语义调整，都同步更新阶段总结或实现审查文档

## 建议的收敛方向

如果继续沿这条线推进，建议优先按下面顺序收敛。

### 1. 先重新定义节点 1 的验收标准

不要把“能生成元数据并后台起进程”当作节点完成标准。

更合适的验收标准应该是：

`agent 可以通过统一入口稳定发现当前实例，并知道它何时可开始验证、何时已彻底停止。`

### 2. 把仓库级入口重新收口到 `scripts/app-start`

目标是让：

- `dev-up` 负责运行时契约和生命周期框架
- `app-start` 负责真实应用如何启动
- 具体框架命令只存在于 `app-start` 内部

### 3. 先补运行态契约，再补更多集成

在 ready/health/process-group 语义没有稳定前，不建议继续往上接：

- CDP
- 浏览器自动化
- 日志查询能力
- 指标和 trace 校验

否则上层能力会建立在不稳定的运行态语义上。

### 4. 把“真实 git worktree 验收”视为节点 1 的必要部分

至少需要补下面的验收场景：

- 两个真实 worktree 并行启动
- 端口隔离验证
- 状态目录隔离验证
- 停止和重置不会相互污染
- 元数据能让外部脚本稳定发现当前实例

## 供后续使用的判断语句

为了避免后续继续口头漂移，当前阶段推荐统一使用下面这句描述：

`当前仓库已经实现了面向 worktree 的运行时隔离脚手架，但还没有完成面向 agent 自主验证闭环的完整 per-worktree runtime。`
