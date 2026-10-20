# Agents Anywhere — HarmonyOS 客户端

鸿蒙 HarmonyOS NEXT 原生客户端（ArkTS + ArkUI 声明式 UI），复用 v2 HTTP + WebSocket 协议，
协议与 DTO 逻辑移植自 iOS 客户端（`ios/`）与 Web 客户端（`web-next/`）的既有行为。

## 架构

```
ets/
  entryability/EntryAbility.ets   启动入口，恢复登录态
  pages/                          UI 层
    Index.ets                     根路由（登录态分发 + Tab 壳）
    Login.ets                     Server 配置 + 账号密码登录 + QR 登录
    Sessions.ets                  Session 列表（搜索态、归档切换、pin/archive/read、下拉刷新）
    SessionDetail.ets             Timeline + composer + takeover + interrupt + notice 响应
    Devices.ets                   Connector 列表
    SettingsPage.ets              账号信息 + 退出登录
  core/
    net/ApiClient.ets             v2 HTTP 客户端（@ohos.net.http，Bearer 鉴权）
    net/RealtimeStream.ets        WS 实时流（ticket 换取 + 45s 心跳看门狗，与 iOS 对齐）
    store/TokenVault.ets          HUKS AES-256-GCM 硬件密钥库加密 token
    store/Prefs.ets               preferences（server URL、账号摘要）
    crypto/PasswordVerifier.ets   PBKDF2-SHA256 派生（与 web 端逐字节一致）
    model/                        wire DTO（auth / session / connector）
    util/                         JSON 安全读取、base64url、时间格式化
```

## 与 iOS 客户端的行为对齐点

- 登录流：`POST /auth/password-salt` → PBKDF2(120000, SHA-256) → `POST /auth/login`
- QR 登录：`/auth/mobile-login/{request,confirm,status,exchange}`（当前为粘贴 QR payload；
  摄像头扫码待接入 Scan Kit）
- WS 帧：`{type:"keepalive"}` 过滤；事件 `timeline.item_created/item_updated/snapshot`、
  `session.meta.updated`、`runtime.notice.snapshot/updated`、`session.refetch_required`
- 心跳：服务端 ~15s 一帧，45s 无帧强制重连
- 视觉：黑白主题，语义色只用于状态（在线/待审批/错误）

## 构建

用 DevEco Studio 打开 `harmony/` 目录：

1. `File > Sync and Refresh Project`（ohpm 无外部依赖，无需联网）。
2. 签名：`Project Structure > Signing Configs` 打开自动签名，DevEco 会用
   `~/.ohos/config/default_agents-anywhere-harmony_*` 的调试材料回填 `build-profile.json5`。
   （CLI 构建前需先完成这一步；`bundleName` 已固定为 `com.morin.agentsanywhere`。）
3. 连接真机或模拟器，Run `entry`。

命令行（在 IDE 完成自动签名后）：

```bash
cd harmony
$DEVECO_SDK/ets/build-tools/ets-loader/../../../../bin/hvigorw assembleHap -p product=default -p buildMode=debug
```

产物：`harmony/entry/build/default/outputs/default/entry-default-signed.hap`

## 已验证 / 未验证

已通过 SDK 23 自带 ArkTS 检查器（`ets-loader/lib/ets_checker` 独立模式）验证：全部
`@ohos.*`/`@kit.*` 导入解析、HUKS/cryptoFramework/Base64Helper API 成员名、HTTP/WS
事件类型、DTO 字段与服务器路由一致。UI DSL 层（`$$this` 双向绑定、builder 链）无法在
独立模式下完整解析（已知工具限制，参照项目 HarmonyX 有同样表现），需在 IDE 内编译确认。

未接入：摄像头扫码（Scan Kit）、文件浏览、Terminal、推送（服务端当前无推送能力，
与 iOS 第一阶段范围一致）。
