# Agents Anywhere — HarmonyOS 客户端

HarmonyOS NEXT 原生客户端（ArkTS + ArkUI 声明式 UI），对接 Server 的 v2 HTTP + WebSocket 协议。
与 iOS / Web / Android 客户端并列，协议行为以 Server 为准。

- bundleName：`com.morin.clauderelay`（**借用了已废弃的 ClaudeRelay 应用身份**，见第 9 节）
- 显示名：Agents Anywhere（`AppScope/resources/base/element/string.json` 的 `app_name`，与 bundleName 无关）
- API namespace：`/api/v2`
- 生产 Server：`https://m-cc.ynzykj.com`

---

## 1. 现状速览

| 能力 | 状态 |
| --- | --- |
| 账号密码登录（客户端派生 PBKDF2） | ✅ 真机验证 |
| 登录态持久化（AssetStoreKit） | ✅ 真机验证，冷重启不用重登 |
| 会话列表（全量、按项目分组、折叠） | ✅ 真机验证 |
| 搜索 / 按设备筛选 / 归档切换 | ✅ |
| 会话详情：Timeline、composer、附件、takeover、interrupt、审批 | ✅ |
| 工具块默认折叠成一行，点击展开原文 | ✅ 真机验证 |
| 附件三来源：拍照 / 相册 / 文件 | ✅ 真机验证 |
| 工作区文件浏览 + 文本预览 | ✅ 真机验证 |
| 工作区命令执行（一次性 `shell/exec`） | ✅ 真机验证 |
| 消息乐观发送（pending 气泡） | ✅ |
| 系统通知（需审批 / 回合结束）+ 点击直达会话 | ✅ 模拟器端到端验证 |
| 应用角标（未读数） | ✅ 实测生效 |
| 后台保活（仅在回合运行中） | ⚠️ 代码就绪，模拟器不一定放行 |
| 实况窗（锁屏/状态栏进度） | ✅ 真机验证（依赖第 9 节的身份） |
| 切后台回来自动重连 | ✅ 已修，见第 5.6 节 |
| 模型 / 权限选择按会话记忆 | ✅ 从 `/runtime/state` 恢复 |
| QR 扫码登录 | ❌ 只支持粘贴 payload，未接 Scan Kit |
| 真机推送（服务端主动） | ❌ 无，见「已知限制」 |

---

## 2. 目录结构

```
entry/src/main/ets/
  entryability/EntryAbility.ets    应用入口：恢复登录态、启停 DashboardWatcher、处理通知点击的 want
  pages/
    Index.ets                      根路由（登录态分发 + Tab 壳 + 通知深链跳转）
    Login.ets                      Server 配置 + 账号密码登录 + QR payload 登录
    Sessions.ets                   会话列表：分组 / 折叠 / 搜索 / 设备筛选 / 归档 / 滑动归档与 Pin
    SessionDetail.ets              Timeline + composer + takeover + interrupt + 审批 + 文件预览
    Workspace.ets                  ★ 会话工作区：文件浏览 + 文本预览 + 一次性命令执行
    Devices.ets                    Connector 列表
    SettingsPage.ets               账号信息 + 通知开关 + 系统通知权限 + 退出登录
  core/
    AppState.ets                   全局态：serverUrl / token / user，登录登出时启停 watcher
    net/ApiClient.ets              v2 HTTP（@ohos.net.http，Bearer）
    net/RealtimeStream.ets         单条 WS 连接（ticket 换取 + 45s 心跳看门狗）
    net/DashboardWatcher.ets       ★ 应用级 dashboard socket：状态跳变 → 通知 / 角标 / 保活 / 实况窗
    notify/Notifier.ets            ★ 本地通知：slot、发布、取消、角标、权限申请
    notify/KeepAlive.ets           ★ 回合运行期间的 dataTransfer 长时任务
    notify/LiveView.ets            ★ 实况窗（无权益自动跳过）
    store/TokenVault.ets           token 存储（AssetStoreKit）
    store/Prefs.ets                preferences：serverUrl、账号摘要、通知开关
    crypto/PasswordVerifier.ets    PBKDF2-SHA256 派生（与 Server 逐字节一致）
    model/                         wire DTO（auth / session / connector / bodies / nav）
    util/                          JSON 安全读取、base64、时间与状态格式化
    ui/Theme.ets                   设计 token（全部取自 sys.color.*，跟随系统深浅色）
  ui/MarkdownView.ets              Markdown 渲染（避免百分比宽度，防溢出）
```

★ = 2026-10 这一轮新增的模块。

---

## 3. 构建与安装

### 3.1 命令行构建（已验证）

```bash
cd harmony
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default
```

产物：`harmony/entry/build/default/outputs/default/entry-default-signed.hap`

`build-profile.json5` 的 `products[0].signingConfig` 已指向 `default`，所以命令行直接产出**已签名** HAP；
真机必须装签名版，模拟器可以装未签名版。签名材料由 DevEco Studio 生成在 `~/.ohos/config/`。

> ⚠️ **`build-profile.json5` 不入库**（已 gitignore）。它含有签名证书的密码和本机绝对路径，
> 换机器必须在 DevEco 里重新配一次签名（且要指向 ClaudeRelay-release 那套证书，
> 否则实况窗权益对不上，见第 9 节），否则装不上真机。

### 3.2 安装与调试

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc

$HDC list targets                                    # 列设备
$HDC -t <serial> install -r <hap>                    # 覆盖安装
$HDC -t <serial> uninstall com.morin.agentsanywhere  # 签名不一致时才需要
$HDC -t <serial> shell aa force-stop com.morin.agentsanywhere
$HDC -t <serial> shell aa start -a EntryAbility -b com.morin.agentsanywhere
```

UI 自动化（没有 UI 测试框架也能跑）：

```bash
$HDC -t <serial> shell uitest dumpLayout -p /data/local/tmp/l.json
$HDC -t <serial> shell cat /data/local/tmp/l.json          # 取控件 bounds
$HDC -t <serial> shell uitest uiInput click <x> <y>
$HDC -t <serial> shell uitest uiInput inputText <x> <y> "<text>"
$HDC -t <serial> shell uitest uiInput keyEvent 2055         # 退格
$HDC -t <serial> shell uitest uiInput keyEvent 2            # 返回
$HDC -t <serial> shell snapshot_display -f /data/local/tmp/s.jpeg
$HDC -t <serial> file recv /data/local/tmp/s.jpeg /tmp/s.jpeg
```

日志：`$HDC -t <serial> shell hilog -x | grep -E "AA-Watch|AA-Notifier|AA-Vault|AA-KeepAlive|AA-LiveView"`

---

## 4. 服务端契约（本端用到的部分）

### HTTP

| 用途 | 接口 |
| --- | --- |
| 取盐 / 登录 | `POST /auth/password-salt`、`POST /auth/login` |
| 当前用户 | `GET /auth/me` |
| Connector 列表 | `GET /connectors` |
| 会话快照（详情页初值） | `GET /sessions/{id}/snapshot?limit=N` |
| 发消息 | `POST /sessions/{id}/messages` |
| 改元信息（pin / archive / 重命名） | `PATCH /sessions/{id}/meta` |
| takeover / 模型 / 权限 | `PATCH /sessions/{id}/runtime/selections` |
| 审批响应 | `POST /sessions/{id}/notices/{noticeId}/respond` |
| 模型 / 权限目录 | `GET /sessions/{id}/runtime/catalogs/{model,permission}` |
| 工作区目录列表 | `POST /connectors/{id}/fs/list?root=<cwd>`，body `{path}` |
| 读文本（预览） | `POST /connectors/{id}/fs/readText?root=<cwd>`，body `{path}` |
| 一次性执行命令 | `POST /connectors/{id}/shell/exec?root=<cwd>`，body `{command, cwd?, timeoutMs}` |
| WS ticket | `POST /ws-ticket` |

**注意**：`MessageCreateRequest` 是 `extra="forbid"`，消息体只能带 `content` / `attachments` /
`clientMessageId`。模型和权限走 `PATCH /runtime/selections`，塞进消息体会 422。

### WebSocket

- 会话流：`/api/v2/sessions/{id}/ws?ticket=…`
- 应用级流：`/api/v2/dashboard/ws?ticket=…`

帧类型：`dashboard.snapshot`、`timeline.item_created`、`timeline.item_updated`、`timeline.snapshot`、
`session.meta.updated`、`runtime.notice.snapshot`、`runtime.notice.updated`、
`session.refetch_required`、`keepalive`。

### 两个容易踩的语义

1. **`unread` 不是数据库列**，是 Server 查询时算的 `latest_turn_end_seq > last_read_seq`。
   造测试数据让它变未读，要压低 `last_read_seq`，改 `seq` 没用。
2. **`dashboard.snapshot.sessions` 来自 `list_session_inventory`** —— 不分页、含归档、已排除
   `title_source='resume_log'`。所以列表只用这一条 socket 就能拿到全部会话，不需要再调分页的
   `GET /sessions`。

---

## 5. 关键设计决策

### 5.1 通知由「状态跳变」驱动，而不是轮询

`DashboardWatcher` 持有应用级 dashboard socket（带退避重连），把每帧 `dashboard.snapshot` 与上一帧
做 diff，只在跳变时发通知：

- 会话进入 `waiting_approval` → 「需要审批」
- `unread` 由 false 变 true（回合结束会重新置位）→ 「已完成」

首帧只做基线，不通知 —— 打开应用时已经未读的东西不算新消息。

**正在看的会话不打扰**，并且离开详情页后还有 10 秒宽限期：`unread` 由
`latest_turn_end_seq > last_read_seq` 推出，用户自己刚发的消息也会读成未读，
没有宽限期就会通知用户自己。

### 5.2 只在有回合运行时保活

`KeepAlive` 用 `dataTransfer` 长时任务让 socket 在后台活着，但**只在有会话处于
running / pending / stopping / waiting 时**启动。常驻会常亮一条通知并耗电，
而值得为它醒着的只有正在跑的回合。需要在 `module.json5` 声明
`ohos.permission.KEEP_BACKGROUND_RUNNING` 和 ability 的 `backgroundModes: ["dataTransfer"]`。

### 5.3 通知权限必须主动申请，且时机在登录之后

发布本地通知本身不需要权限，但用户没开通知时 `publish` 会被**静默丢弃**。
`Notifier.askOnce()` 在 `DashboardWatcher.start()` 里调用（即已登录时），只问一次；
设置页另有入口可重新申请。放在 `EntryAbility.onCreate` 会因为没有登录态而永远不触发。

### 5.4 token 用 AssetStoreKit 存

之前是手写 HUKS AES-GCM，`save` 能成功但 `load` 永远失败（`finishSession` 解密报
"parameter does not exist"），表现就是「登录成功、下次打开又要登录」。
现在直接用 `@kit.AssetStoreKit`：不需要碰密钥材料，系统负责加密并绑定应用，
`DEVICE_FIRST_UNLOCKED` 保证重启后后台重连也能读到。

### 5.5 列表不用分页接口

`GET /sessions` 一页最多 100 条，而工作区有 566 个会话。改用 dashboard 的全量 inventory 后，
未读角标、归档过滤、搜索都变成客户端的事，也不再需要无限滚动。

### 5.6 切后台回来必须无条件重连

HarmonyOS 对后台应用的网络管控很硬：**退到后台约 2 秒后网络被冻结、约 12 秒后释放**。
连接对象本身不会被回收，但它的 IP/端口已经被清掉，而且**通常不会触发 `close` 事件** ——
所以 App 会一直以为自己是连着的，界面显示"在线"其实早断了。

因此 `EntryAbility.onForeground()` 里**无条件**调 `DashboardWatcher.reconnect()`，
不等任何事件。同时给 WebSocket 配了 `pingInterval` / `pongTimeout`（单位是秒），
让传输层自己发现死连接，而不是只靠 45 秒的收帧看门狗。

顺带一提：`DATA_TRANSFER` 长时任务对"只收推送的被动 socket"并不成立 ——
系统有一致性校验，且要求通过实况窗更新进度，否则 10 分钟没进度就会被取消。
现在这个任务只在有回合运行时申请，并且和实况窗配套（实况窗本身就是在跑回合的进度展示）。

---

## 6. ArkTS / ArkUI 踩坑清单

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 页面全白，只剩返回键 | `navDestination` 的 @Builder 每个分支根节点**必须**是 `NavDestination()`，否则整棵子树被静默丢弃 | 见 `Index.PageMap` |
| 文字溢出气泡背景 | `constraintSize({maxWidth})` + 子节点 `width('100%')` 造成百分比循环依赖 | 内部不设 `width('100%')`，靠内容撑开 |
| `tabBar` 里加 badge 不显示 | `tabContent.tabBar(CustomBuilder)` 只渲染自己的文本（选中变色会更新，说明 builder 重跑了） | 未读数放页面头部，不放 tab |
| `arkts-no-untyped-obj-literals` | `Want.parameters` 不能用裸对象字面量 | `const p: Record<string,Object> = {}` 逐项赋值 |
| 组头点击无响应 | `ListItemGroup` 的 header 收不到点击 | 换成普通 `ListItem` 渲染组头 |
| 折叠不生效 | `ForEach` 只在 key 变化时才重跑分支 | key 拼上折叠状态 |
| `@State tabIndex` 编译冲突 | 与 `CustomComponent` 内置成员同名 | 改名 `activeTab` |
| 带类型的 catch 不可用 | ArkTS 不支持 catch 参数类型标注 | 用 `(e as Error).message` |

---

## 7. 已知限制 / 待办

1. **没有真机推送。** 通知全部是进程内产出的本地通知，依赖 `KeepAlive` 保活。
   应用被系统彻底杀掉后收不到任何通知。要真正远程通知，需要接 HMS Push：
   Server 侧通过 AGC 下发，客户端接 `@kit.PushKit` + `RemoteNotificationExtensionAbility`。
   （`entry/agconnect-services.json` 是历史遗留，当前代码未使用；该文件已被 `.gitignore`
   忽略，不要提交。）
2. **实况窗未验证。** 需要在华为 AGC 申请实况窗权益，`isLiveViewEnabled()` 才会返回 true。
   代码路径已就绪且无权益时安全跳过。
3. **后台保活未在真机验证。** 模拟器对长时任务放行不稳定。
4. **QR 登录只支持粘贴 payload**，没接 Scan Kit 摄像头扫码。
5. **命令执行是一次性的，不是交互式终端。** 走 `POST /connectors/{id}/shell/exec`，
   每次一条命令、拿到 stdout/stderr 后结束，没有 PTY、没有 ANSI、没有长驻会话。
   要做真正的终端，需要接 `POST /terminals-v2` 创建终端 + WebSocket
   `/connectors/{id}/terminals-v2/{tid}/stream?token=<jwt>`（注意这条流用 Bearer token，
   不是 `/ws-ticket` 的 ticket，现有 `RealtimeStream` 不能直接复用），再叠一个 ANSI 渲染器。
   Git 面板同样还没有。
6. **会话列表没有虚拟化。** 566 条一次性建视图，目前可用但长列表滚动不是最优，
   要优化就把 `List` 换成 `LazyForEach` + `IDataSource`。

---

## 8. 交接注意

- 改 **API 字段 / WS 事件**时先改 `contracts/`，再同步 Server 和各客户端。
- `harmony/` 没有外部 ohpm 依赖，`ohpm install` 不需要联网。
- 提交前至少跑一次 `assembleHap` —— ArkTS 的很多错误是编译期才暴露的。
- 仓库根目录的 `HANDOFF-*.md` 是历史草稿，本文档是鸿蒙端的权威说明。

---

## 9. 为什么 bundleName 是 com.morin.clauderelay

**实况窗权益是绑定 AGC 应用（bundleName + 签名证书）的，不能转移到别的包名。**
这个客户端最初用 `com.morin.agentsanywhere`，无论场景值填 `PROGRESS` 还是 `TIMER`，
`startLiveView` 一律返回 `1003500005` —— 这个码字面是"权益未开通"，
但**场景值对不上也报同一个码**，所以光看错误码分不清是哪种。

用户此前为另一个应用 `com.morin.clauderelay`（ClaudeRelay，已废弃）申请过实况窗，
于是本项目直接沿用那个身份：

| 项 | 值 |
| --- | --- |
| bundleName | `com.morin.clauderelay` |
| 签名证书 | `~/MorinData/publicKey/huaweikey/ClaudeRelay-release.{p12,cer,p7b}` |
| AGC 配置 | `entry/agconnect-services.json`（`package_name` 已是 clauderelay，已 gitignore） |
| 实况窗场景 | `TIMER`（`LiveView.ets` 的 `EVENT`，必须和 AGC 开通时选的一致） |

代价与注意：

- 设备上这个 App 会**顶掉**原来的 ClaudeRelay；两者不能共存。
- 换 bundleName 等于换应用，数据沙箱是新的 —— 升级后需要重新登录一次。
- `harmony/build-profile.json5` 现在**不入库**（里面有发布证书的密码），
  换机器要重新配签名，否则装不上真机。
- 想改回独立身份，就得在 AGC 为 `com.morin.agentsanywhere` 单独申请实况窗权益（需要审核），
  再把 bundleName 和签名换回去 —— 代码里只有 4 处 `BUNDLE_NAME` 常量 + `AppScope/app.json5`。

显示名和身份无关：`app_name` 字符串想叫什么都可以，不影响实况窗权益。

---

## 10. 视觉：跟随系统，而不是自绘深色

早期版本用的是手绘深色盘（"Slate"）。**这是个错误**，而且代价是可见的：

- 状态栏、导航栏、TabBar、系统材质**都跟系统主题走**。深色 App 跑在浅色系统的机器上，
  就被一圈浅色 chrome 框住，看着像没做完。
- `HdsTabs` 的 `systemMaterialEffect` 材质也跟系统主题走，深色 App 下会渲染成浅色，
  白字压在浅灰上基本看不见；`barBackgroundColor` 会被 HDS 忽略，救不回来。
- `colorInvert` 只在文字/图标使用 `sys.color.*` 资源时才生效，硬编码 hex 触发不了。

现在 `core/ui/Theme.ets` 全部改成系统资源：

| 用途 | token |
| --- | --- |
| 页面底色 | `sys.color.ohos_id_color_background` |
| 卡片 / 次级面 | `sys.color.ohos_id_color_sub_background` |
| 输入框 / 抬升面 | `sys.color.ohos_id_color_text_field_bg` |
| 主 / 次 / 三级文字 | `ohos_id_color_primary` / `_secondary` / `_tertiary` |
| 强调色（选中、链接、强调） | `ohos_id_color_emphasize` |
| 危险 | `ohos_id_color_alert` |
| 警告 | `ohos_id_color_warning` |
| 分割线 | `ohos_id_color_list_separator` |

于是 App 自动跟随浅色/深色，`HdsTabs` 的悬浮材质也终于能正常显示。

**注意**：`sys.color.*` / `sys.symbol.*` 的真实名字以
`$SDK/openharmony/ets/build-tools/ets-loader/sysResource.js` 为准 —— 网上和智能体给的
`sys.color.font_primary`、`sys.symbol.document` 这类名字**并不存在**（写错是运行时静默失效，
不报编译错）。已核对的可用图标：`folder`、`doc_plaintext`、`arrow_left`、`arrow_clockwise`、
`plus`、`paperplane`、`gearshape`、`message`、`chevron_right`、`chevron_down`。

设计语言另外两条：卡片用阴影抬升而不是描边（每张卡都描边会读成表格）；
间距走 4pt 刻度（`Theme.spaceXs..Xl`），不再各写各的数字。
