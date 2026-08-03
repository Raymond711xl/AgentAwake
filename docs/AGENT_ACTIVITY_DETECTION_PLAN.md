# AgentAwake Agent 活动检测路线图

状态：阶段 A、B、C 已实现并通过短时工程验收；阶段 D 待增加已验证的 Bridge 预设。

确认日期：2026-08-01。实现更新：2026-08-03。

## 1. 目标

AgentAwake 的核心任务仍然只有一个：在 Agent 真正工作时暂时阻止 Mac
空闲休眠，任务结束后把休眠控制权交还给 macOS。

扩展更多 Agent 时，优先级依次为：

1. 长时间运行时保持低内存、低 CPU、低磁盘读取；
2. 下载后即可使用，默认路径不要求登录、密钥、终端或修改配置；
3. 需要更高准确度的用户，可以明确选择并随时撤销精确集成；
4. 所有判断默认在本机完成，不读取或保存提示词、响应正文和 API 密钥；
5. 不把 Token 统计、费用面板或全局网络抓包扩展成产品主线。

## 2. 两个用户层级

两层是逐级增强关系，不是互斥的全局开关。自动检测始终是安全兜底；
用户可以只为需要的 Agent 开启精确跟踪。

### 第一层：自动检测（无需配置）

面向所有用户，默认启用在 Agent 模式中。

用户体验：

- 下载并双击启动后即可使用；
- 不修改任何第三方 Agent 配置；
- 不需要账号、Cookie、API Key、系统扩展或网络代理；
- 自动发现本机已存在且格式受支持的活动记录；
- 设置页说明当前 Agent 是“自动检测”“暂不支持”还是“可启用精确跟踪”。

数据来源：

- 本地 JSONL、SQLite 或其他明确的会话状态文件；
- 文件新增和追加写入事件；
- 必要时读取极少量元数据，例如文件大小、修改时间和会话标识；
- 只解析判断开始、心跳、结束所需的字段或标记。

自动检测的边界：

- 允许状态有数秒延迟；
- 第三方升级并改变本地格式后，适配器可能需要更新；
- 仅发现常驻进程不能证明 Agent 正在工作，因此不能单独触发长期唤醒；
- 找不到可靠本地活动源时，明确显示“需要精确跟踪”，不伪装成已支持；
- 不从加密网络字节数估算 Token，也不把普通同步、遥测或更新流量当作任务。

### 第二层：精确跟踪（需要配置）

面向愿意进行一次设置、希望开始和结束更及时的用户。

用户体验：

- 用户按 Agent 单独选择是否启用；
- 修改前预览目标配置文件和将新增的命令；
- 首次修改已有配置前创建备份；
- 安装、修复和移除必须幂等且可撤销；
- 设置页显示“精确跟踪中”，失败时自动回退到第一层并说明原因。

精确数据源按实现顺序分为：

1. Agent 原生生命周期 Hooks；
2. 通用的一次性 AgentAwake Bridge 命令；
3. 用户自己开发的 Agent 所使用的轻量 SDK/middleware；
4. 只有在官方提供安全、稳定接口时才接入官方活动 API。

统一事件只需要：

```json
{
  "schema_version": 1,
  "provider_id": "custom-agent",
  "display_name": "Custom Agent",
  "session_id": "session-123",
  "event": "start",
  "occurred_at": "2026-08-01T04:20:00Z"
}
```

`event` 首版只支持 `start`、`heartbeat` 和 `stop`。不需要 prompt、response、
Token 明细或模型输出。通用命令应当是短暂运行、写入事件后立即退出的 helper，
而不是第二个常驻后台服务。

## 3. 判断优先级

同一会话同时出现多个来源时，按以下顺序处理：

1. 精确生命周期 Hook 或 Bridge 事件；
2. 自动检测到的本地会话状态；
3. 过期保护租约。

高优先级来源对同一会话具有权威性。例如精确事件已经发出 `stop` 时，
较慢写入的 transcript 不能再次把该会话错误地标为活动。所有活动状态都必须有
超时租约，异常退出不能让 Mac 永久保持唤醒。

进程名、域名和网络字节流暂不进入正式优先级。它们可以在未来作为实验信号，
但必须独立开关、清楚标为“推测”，且不能单独建立长期电源断言。

## 4. 低内存架构约束

### 4.1 必须遵守

- 保持原生 Swift 实现，不引入 Electron、内嵌浏览器或第二套运行时；
- 未开启时不创建 Agent 文件监听器、不扫描日志、不持有电源断言；
- 精确 Hook/Bridge 使用一次性 helper，不增加常驻子进程；
- 自动检测使用一个共享的 macOS 原生文件事件流，而不是为每个目录创建线程；
- 文件变化后按 Agent 和路径去抖，只读取新增字节；
- 周期性完整校准采用低频、可退避策略，不进行每几秒递归扫描；
- 解析任务串行化，避免多个大文件同时进入内存；
- SQLite 只读查询必须带 `LIMIT`，查询后立即关闭连接；
- 缓存有明确上限，过期会话及时淘汰；
- 不保存 transcript 正文，日志中也不得输出用户内容。

### 4.2 首版容量上限

- 最多缓存 128 个最近会话的轻量状态；
- 所有增量解析缓冲区合计不超过 1 MiB；
- 单个异常记录不得导致缓冲区无限增长；
- 每个 Agent 的文件事件在 500–1,000 毫秒窗口内合并；
- 正常文件事件驱动下，每 15 分钟进行一次低优先级校准；
- 原生事件不可用时才进入退避轮询，等待状态不短于 60 秒一次。

旧实现曾每 4 秒递归枚举 Claude 与 Codex 的近期日志。阶段 B 已将这条路径替换为
一个共享的原生 FSEvents 流、目标文件增量读取、60 秒租约检查和 15 分钟完整校准；
原生事件不可用时才按不短于 60 秒的间隔退避校准。

## 5. 资源验收预算

下面是首轮工程预算。`基线` 指同一台参考 Mac、同一构建、启动并稳定 10 分钟后，
“未开启”状态的 RSS。系统版本和 SwiftUI 缓存会影响绝对值，因此同时检查
绝对值和相对增量。

| 场景 | 内存目标 | CPU / 行为目标 |
| --- | --- | --- |
| 未开启 | 相对基线增加不超过 2 MiB | 平均 CPU 低于 0.1%，无 Agent 扫描与监听 |
| 自动检测等待 | 相对基线增加不超过 10 MiB；参考机稳定 RSS 不超过 100 MiB | 平均 CPU 低于 0.5%，只保留一个共享事件流 |
| 自动检测活动 | 相对基线增加不超过 20 MiB | 除短暂解析峰值外平均 CPU 低于 2% |
| 精确跟踪等待 | 相对基线增加不超过 5 MiB | 平均 CPU 低于 0.2%，无常驻 helper |
| 8 小时稳定性 | RSS 漂移不超过 10 MiB | 文件句柄、线程和会话缓存不持续增长 |

这些是发布门槛，不因新增 Agent 静默放宽。若某个适配器无法满足预算，
应当单独禁用或继续优化，而不是拖累所有用户的默认路径。

## 6. 核心代码结构规划

### 6.1 通用身份

阶段 A 已把原先只有 Codex 和 Claude 的 `AgentKind` 迁移到可扩展稳定标识：

- `providerID`：机器使用的稳定小写 ID；
- `displayName`：界面名称；
- `sessionID`：会话标识；
- `source`：`automaticLocal`、`preciseHook` 或 `preciseBridge`；
- `confidence`：`automatic` 或 `precise`。

解码器继续兼容已经写入本地的 Codex/Claude 租约文件。

### 6.2 适配器

每个第三方 Agent 只实现自己的差异，核心调度器不出现不断增长的路径判断：

```text
AgentActivityAdapter
├── identity
├── logRoots / watchRoots
├── capabilities
├── bootstrapPatterns
├── updatedActivityState(currentState, line)
└── sessionIdentifier(activityURL)
```

适配器必须声明自己支持：仅自动检测、自动加精确跟踪，或仅精确跟踪。SQLite、
官方 API 等非增量行日志来源在阶段 D 通过新的有界 source 类型扩展，不能把无限查询
或全库扫描塞进现有接口。

## 7. 设置页现状与后续

设置页已经增加“Agent 活动检测”区域：

- 顶部说明“自动检测无需配置；精确跟踪需要按 Agent 启用”；
- 可用时显示“启用精确跟踪”；
- 安装前展示修改预览，安装后提供“修复”和“移除”；
- 通用 Agent Bridge 让用户填写 Agent ID 与显示名称，并分别复制任务开始、
  长任务心跳和任务结束命令；
- 界面明确说明命令应放入对应生命周期 Hook，并解释如何把
  `$AGENT_SESSION_ID` 映射为稳定任务 ID；
- 精确事件失效时显示“已回退到自动检测”，而不是静默降低准确度。

不增加首次启动向导，不把可选配置变成双击后的必经步骤。各 Agent 的“最后活动
时间”和更细的运行时来源标记，等阶段 D 适配器能稳定提供统一元数据后再加入，
避免当前界面展示无法验证的时间。

## 8. 分阶段实施顺序

### 阶段 A：资源基线与核心模型（已实现）

目标：先建立不会随 Agent 数量线性膨胀的骨架，不改变现有用户行为。

完成标准：

- 建立通用 Agent 身份、来源和置信度模型；
- 建立适配器协议和统一活动事件；
- Codex/Claude 通过适配器继续通过现有测试；
- 增加可重复的 RSS、CPU、线程和文件句柄测量流程；
- 旧租约数据兼容测试通过。

### 阶段 B：第一层低资源自动检测（已实现）

目标：用原生文件事件替换每 4 秒递归扫描，再扩展第三方 Agent。

完成标准：

- Codex/Claude 在零配置下保持现有识别能力；
- 等待和活跃场景通过第 5 节资源预算；
- 文件事件丢失、目录新建和 App 长时间运行都有校准兜底；
- 大量历史会话下只读取新增数据，缓存不突破上限；
- 未开启时没有文件事件流和扫描任务。

### 阶段 C：第二层通用精确跟踪（已实现）

目标：统一现有 Hooks，并让任意可执行命令的 Agent 都能接入。

完成标准：

- Claude/Codex 使用统一事件模型；
- 一次性 Bridge 支持 `start`、`heartbeat`、`stop`；
- 自定义 Agent 可以通过一条运行时命令绑定；
- helper 执行后立即退出，App 不增加常驻服务；
- 设置页支持预览、安装、修复、移除和自动回退；
- 不保存 prompt、response、Token 或凭证。

### 阶段 D：逐个增加 Bridge 接入预设（后续）

只研究公开提供可靠生命周期 Hook、插件事件或命令回调的 Agent。每个预设负责把
第三方的开始、持续、完成、取消和失败事件映射到 Bridge，并把第三方提供的稳定任务
ID 映射到 `$AGENT_SESSION_ID`。没有可靠生命周期入口的 Agent 暂不适配，也不通过
进程名、全量日志扫描或加密流量进行推测。

单个预设的完成标准：

- 官方生命周期契约、配置位置和适用版本已实际验证；
- 开始与结束事件必需，长任务心跳和异常结束路径写清楚；
- 同一次任务始终使用稳定且一致的会话 ID；
- 若由 AgentAwake 修改配置，必须先预览、备份并支持幂等移除；
- 上游契约变化时安全失效，不错误地永久保持唤醒；
- README 和设置页只宣称已实际验证的平台与版本。

### 阶段 E：API 开发者接入

目标：为用户自己编写的 OpenAI-compatible 或其他 API Agent 提供精确事件入口。

首选 Bridge/SDK middleware；不要求用户把 API 请求经过 AgentAwake，
也不接管或保存 API Key。只有能稳定取得生命周期事件时才算正式支持。

### 暂缓：全局网络流量推测

抓包、HTTPS 中间人代理、根证书、Network Extension 和域名流量推测不属于
当前两个正式层级。它们带来权限、隐私、兼容性和资源成本，且不能可靠判断
Token 或任务是否结束。只有前述阶段完成后，才决定是否建立独立实验。

## 9. 当前决定

- 用户只看到“自动检测”和“精确跟踪”两个层级；
- 自动检测是默认、零配置路径；
- 精确跟踪按 Agent 选择，是自动检测的增强而不是替代；
- 通用 Bridge 是其他 Agent 的精确接入底座，优先优化接入说明和复制体验；
- 后续只为具有可靠生命周期入口的 Agent 增加已验证 Bridge 预设；
- 没有可靠生命周期 Hooks 的 Agent 暂不适配；
- 先支持活动生命周期，不建设 Token Monitor 式统计面板；
- 每增加一个具名预设，都必须先通过资源、隐私和异常释放验收。

## 10. 2026-08-02 实现与验收记录

阶段 A–C 已落地：

- `AgentKind` 已改为可扩展的 `providerID + displayName` 身份，并兼容旧版
  Codex/Claude 字符串租约；同一 Provider ID 不会因显示名称变化失去身份一致性；
- `AgentActivityAdapter` 自己提供增量行解析、反向启动标记与会话 ID 规则，
  自定义 Marker 适配器测试不需要修改核心调度器；
- 自动检测只在 Agent 模式启用，使用一个共享 FSEvents 流；文件追加只更新目标
  日志，目录变化或事件丢失才完整校准；
- 会话缓存上限 128，所有未完成行缓冲合计上限 1 MiB，单行上限 64 KiB，
  单次 FSEvents 批次最多保留 256 个 URL，单个租约文件最多读取 16 KiB；
- Codex/Claude Hooks 与 Bridge 共用 `start`、`heartbeat`、`stop` 模型；
  helper 单次写入后退出，没有新增常驻服务；
- 设置页展示 Hooks 的配置路径和新增命令预览，保留首次备份、幂等安装、修复、
  移除与自动日志回退；自定义 Agent 可复制 Bridge 命令模板；
- 自测覆盖旧租约、自定义 Provider、自定义适配器、Hook 权威覆盖、Bridge 启停、
  新目录、事件丢失、增量读取、缓存上限和真实 FSEvents 回调。

参考 Mac 上的 release/native 短时样本如下。关闭态为同一构建的比较基线；每组
60 秒、5 秒间隔，历史目录样本另行标注：

| 场景 | RSS 结果 | CPU / 其他 |
| --- | --- | --- |
| 未开启 | 平均 79.8 MiB，漂移 0.0 MiB | 平均 0.000%，最大 3 线程、45 文件句柄 |
| 自动检测等待（空目录） | 平均 80.8 MiB，范围 80.4–81.3 MiB，漂移 +0.7 MiB | 平均 0.017%，最大 11 线程、56 文件句柄 |
| 自动检测活动（单日志） | 平均 80.4 MiB，范围 80.3–80.5 MiB，漂移 +0.2 MiB | 平均 0.000%，最大 3 线程、63 文件句柄 |
| Bridge 精确活动 | 平均 80.5 MiB，范围 80.3–80.7 MiB，漂移 +0.2 MiB | 平均 0.000%，最大 11 线程、56 文件句柄 |
| 真实历史目录（约 911 MiB / 488 文件，预热后 20 秒） | 平均 92.0 MiB，范围 91.9–92.1 MiB，漂移 +0.1 MiB | 平均 0.000%，最大 6 线程、67 文件句柄 |

真实历史目录的首次 60 秒包含一次解析高峰，RSS 曾短暂达到 111.7 MiB，随后稳定在
约 92 MiB；`vmmap` 显示稳定物理 footprint 为 26.5 MiB、峰值 30.5 MiB。
短时等待和稳定活动样本符合首轮预算，但 10 分钟正式基线与 8 小时漂移仍属于发布前
长时验收，不能用本次短测替代。可重复测量命令：

```bash
./scripts/measure-resources.sh --pid PID --duration 600 --interval 5
```

## 11. 2026-08-03 通用 Bridge 接入体验更新

- 设置页将“自定义 Agent Bridge”明确为“通用 Agent Bridge”，并先说明只适用于能在
  生命周期中执行本地命令的 Agent；
- 用户填写 Agent ID 与显示名称后，界面直接生成 `start`、`heartbeat`、`stop`
  三条命令，不再复制含 `EVENT` 占位符的模板；
- 界面明确说明三条命令应分别放进 Agent 的生命周期 Hook，而不是在终端依次执行；
- 所有命令统一使用 `$AGENT_SESSION_ID`，并解释如何映射 `task_id`、`session_id`
  或 `conversation_id`；无效 Agent ID 会禁用复制并就地提示；
- 隔离 QA home 中已验证命令生成、输入校验、原生设置窗口布局，以及同一会话的
  `BridgeStart → BridgeHeartbeat → BridgeStop` 状态转换。

## English summary

AgentAwake now exposes two progressive levels: zero-configuration automatic
detection from bounded local activity sources, and optional precise tracking
through lifecycle hooks or a one-shot local bridge. The precise level is enabled
per agent and keeps automatic detection as a fallback.

The implemented core remains native and event-driven, adds no resident helper,
and avoids packet interception. Future named integrations will be independently
verified Bridge presets for agents with reliable lifecycle entry points; agents
without such hooks are deferred.
