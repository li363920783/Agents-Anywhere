# 鸿蒙端补齐计划

目标：把现有 MVP（登录 / 会话列表 / 会话详情 / 审批 / 设备 / 设置）补齐到与桌面端、Android 的核心体验对齐。

## 现状

- `harmony/` 22 个 `.ets` / 2409 行。
- 已有：HTTP（ApiClient）、WebSocket 实时流（心跳/重连）、登录（PBKDF2 + QR）、会话列表、会话详情（纯文本时间线 + composer + takeover + interrupt + 审批响应）、设备、设置、HUKS 加密 token。
- 缺口：Markdown/代码高亮、模型/权限选择、附件、文件预览下载、会话中发消息、分组/worktree/分支。

## 优先级与逐项任务

### P0-1 Markdown + 代码块渲染
- 新增 `entry/src/main/ets/core/markdown/MarkdownParser.ets`：解析标题、粗体、斜体、行内代码、代码块、无序/有序列表、引用、链接、分隔线。
- 新增 `entry/src/main/ets/ui/MarkdownView.ets`：行内用 `Text` + `Span`，代码块用等宽卡片。
- 代码高亮：先做轻量着色（关键字 / 字符串 / 注释 / 数字），可后续增强。
- 参考：`android/.../sessiondetail/AgentMarkdownText.kt`。
- 接入：`SessionDetail.ets` 的 assistant/message 渲染。
- 验收：assistant 消息中的 markdown 正确渲染，代码块有独立样式。

### P0-2 模型 / 权限选择
- 新增 `entry/src/main/ets/core/model/Catalog.ets`：模型、权限目录 DTO。
- `SessionDetail.ets` composer 增加模型 / 权限两个选择器。
- API：`GET /sessions/{id}/runtime/model-catalog`、`/permission-catalog`（对齐 Android）。
- 发送时带 `selections`。
- 验收：能选择并生效。

### P0-3 文件预览 / 下载
- 新增 `pages/FilePreview.ets`：文本预览 + 下载。
- API：connector `fs/read` + 下载地址。
- 下载：`@ohos.file.fs` + `picker` 保存。
- 接入：时间线里的文件引用可点击。
- 验收：能预览并保存到本地。

### P0-4 会话中发消息
- `SessionDetail.ets` `send()`：running / waiting / pending 时仍可发送（server 会排队）。
- UI：running 时输入区保持可用。
- 验收：agent 运行中仍能发消息，消息排队。

### P0-5 附件上传
- `SessionDetail.ets` composer 增加附件选择（图片 / 文件）。
- 上传 API + 发送时带 `attachments`。
- 验收：能发带附件的消息。

### P1-6 分组 / worktree / 分支
- `Session.ets` `SessionView` 增加 `gitBranch`。
- 列表副标题显示 worktree，详情显示分支。
- 验收：与桌面端一致。

## 风险

- Markdown 解析在 ArkTS 下需自研（无成熟库），是最大工作量。
- ArkTS 约束（禁 `any`、解构、spread、JSX），需按规范重写。
- 所有改动需用 DevEco Studio / hvigor 构建验证。
