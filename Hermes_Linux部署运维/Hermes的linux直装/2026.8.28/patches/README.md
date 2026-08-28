# Hermes 前置补丁（部署脚本自动应用）

| 路径 | 作用 |
|------|------|
| `apply_webui_mobile_toolsets.py` | WebUI 窄屏圆形按钮面板加入 Toolsets/MCP |
| `fix_media_regex_asterisk.py` | 修复 `static/ui.js` / `static/messages.js` 的 `MEDIA:`/`file://` 正则会把 markdown `**加粗**` 符号吞入图片路径，导致图片渲染失败的问题 |
| `fix_session_visit_models_swr.py` | `/api/models?freshness=session_visit` 过期缓存立即返回，后台刷新，避免会话加载卡 4s |
| `../mcp-patches/` | Node MCP handlers/definitions 定制（xiaoyi-grok-image + Atlas 原生 API） |

由 `hermes-deploy.sh`（`step_webui_mobile_patch`）/ `hermesctl.sh webui-patch` 在安装、升级时自动调用，幂等、可重复执行。
