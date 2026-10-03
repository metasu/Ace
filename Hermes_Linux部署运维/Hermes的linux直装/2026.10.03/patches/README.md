# Hermes 前置补丁（部署脚本自动应用）

| 路径 | 作用 |
|------|------|
| `apply_webui_mobile_toolsets.py` | WebUI 窄屏圆形按钮面板加入 Toolsets/MCP |
| `fix_media_regex_asterisk.py` | 修复 `static/ui.js` / `static/messages.js` 的 `MEDIA:`/`file://` 正则会把 markdown `**加粗**` 符号吞入图片路径，导致图片渲染失败的问题 |
| `fix_session_visit_models_swr.py` | `/api/models?freshness=session_visit` 过期缓存立即返回，后台刷新，避免会话加载卡 4s；并把配套回归测试 `webui_tests/test_issue4756_*.py` 一并部署到 `webui/tests/` |
| `fix_toolsets_mcp_additive.py` | 会话工具集覆盖改为追加语义：勾选 MCP 只追加到常规工具之上，不再取代 `hermes-cli` |
| `fix_compact_keep_tools.py` + `compact_request.py` | Kuaipao 瘦请求时永远保留 tools/tool_choice；不拆 assistant/tool 成对 |
| `fix_configured_model_dedupe.py` | 模型选择器去重：`provider/model` 复合徽标键不再让已配置模型重复成行 |
| `fix_stream_null_chunk.py` | 跳过上游 SSE 流里的 `data: null` 帧（SDK 解为 `None` chunk，否则 `chunk.choices` 崩溃、流式中途死亡被误判为截断） |
| `fix_qimen_grid_mobile.py` | 手机端奇门九宫格：`static/ui.js` 识别等宽 ASCII 盘面（`+---+` 边框 + ≥3 个`【宫位】`+ 神/星/门/天/引 行）加 `qimen-grid-block`，`static/style.css` 豁免移动端 pre-wrap、缩字号、横向触摸滚动 |
| `../mcp-patches/` | Node MCP handlers/definitions 定制（kuaipao-gpt-image + Atlas 原生 API） |

由 `hermes-deploy.sh`（`step_webui_mobile_patch`）/ `hermesctl.sh webui-patch` 在安装、升级时自动调用，幂等、可重复执行。
