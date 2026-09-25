# Hermes MCP 定制补丁（可移植）

对齐 Windows 教程：`notes/Hermes Agent Windows本地便携部署教程.html` 中 AtlasCloud 原生 API 与 kuaipao OpenAI 兼容路径规则。

## 目录

```text
mcp-patches/
├── README.md
├── xiaoyi-grok-image/{handlers.js,definitions.js,config.index.js}
├── atlascloud-seedream-v5-pro/{handlers.js,definitions.js}
├── atlascloud-seedream-edit/{handlers.js,definitions.js}
├── atlascloud-seedream-edit-sequential/{handlers.js,definitions.js}
├── atlascloud-wan-edit/{handlers.js,definitions.js}
└── atlascloud-wan-edit-pro/{handlers.js,definitions.js}
```

> 历史注：早期版本使用 `kuaipao-image` 作为图像生成 MCP，现已替换为 `xiaoyi-grok-image`（同样的 OpenAI 兼容 `/v1/images/generations` 路径，修复逻辑已带入 handlers.js）。若仍需 kuaipao 渠道，参考 git 历史中的 `kuaipao-image/` 目录。

应用：

```bash
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh restart
/opt/hermes/hermesctl.sh mcp
```

导出（改运行目录后固化）：

```bash
/opt/hermes/hermesctl.sh mcp-export-patches
```

从上游重建并自动再应用补丁：

```bash
/opt/hermes/hermesctl.sh mcp-rebuild
```

## 根因与修复

### 1) xiaoyi-grok-image（原 kuaipao-image）：`/v1/v1/` 双前缀

- 上游 handler 请求路径写死 `/v1/images/generations`
- 若 `config.yaml` 的 `API_URL` 已带 `/v1`，axios baseURL 再拼 `/v1/...` → 404
- **补丁**：`handlers.js` 中 `apiUrl.endsWith('/v1') ? apiUrl : apiUrl + '/v1'` 智能拼接；推荐 `API_URL=https://xiaoyiapi.xyz/v1`（裸域名也可）

### 2) AtlasCloud：不能用 OpenAI `/v1/images/*`

Windows 教程明确：

- `POST {API_URL}/api/v1/model/generateImage` 提交任务
- `GET {API_URL}/api/v1/model/prediction/{id}` 异步轮询至 `completed/succeeded`
- 本地图先 `POST {API_URL}/api/v1/model/uploadMedia` 得 `download_url`，再放进 `images[]`
- **不发送** `moderation`（0 审查客户端侧）
- `API_URL` 必须是裸域名 `https://api.atlascloud.ai`（不要 `/api` 或 `/v1`）

直接套 kuaipao OpenAI 路径会 `ECONNRESET` / `400 bad request`。

### 3) 参数格式差异

| Profile | size | 其它 |
|---------|------|------|
| Seedream t2i/edit/seq | `WIDTH*HEIGHT`（如 `2048*2048`），像素 ≥ 3686400 | seq 支持 `max_images` 1–15；可选 `output_format` |
| Wan 2.7 / Pro | 档位 `1K` / `2K` | `n` 1–4；`thinking_mode` 默认 true；`images` 最多 9 |

### 4) 上游 config 陷阱

上游 `build/config/index.js` 默认 `defaultEditImageModel=gpt-image-1`。  
Atlas 补丁的 `defaultModel()` **忽略** 该通用默认，优先 `DEFAULT_IMAGE_MODEL` / 非 `gpt-image-1` 的 `DEFAULT_EDIT_IMAGE_MODEL`。

## config.yaml 推荐 env

```yaml
mcp_servers:
  xiaoyi-grok-image:
    env:
      API_URL: https://xiaoyiapi.xyz/v1
      DEFAULT_IMAGE_MODEL: grok-imagine-image
      DEFAULT_IMAGE_SIZE: 2048x2048
      DEFAULT_OUTPUT_PATH: /opt/hermes/data/output
      REQUEST_TIMEOUT: "600000"
  atlascloud-seedream-v5-pro:
    env:
      API_URL: https://api.atlascloud.ai   # 裸域名
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/text-to-image
  atlascloud-seedream-edit:
    env:
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit
  atlascloud-seedream-edit-sequential:
    env:
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential
  atlascloud-wan-edit:
    env:
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: alibaba/wan-2.7/image-edit
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7/image-edit
  atlascloud-wan-edit-pro:
    env:
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit
```

## 移植到其它 VPS

```bash
# 源机
scp -r /opt/hermes/mcp-patches root@新机:/opt/hermes/
# 可选：同步 config 中 mcp_servers 段 / .env 密钥

# 新机（已有 hermes-deploy 产物）
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh restart
/opt/hermes/hermesctl.sh mcp
```

或新机仅两个脚本 + 补丁目录：

```bash
FORCE=1 bash /opt/hermes/hermes-deploy.sh   # 会构建上游 MCP 并应用 mcp-patches
/opt/hermes/hermesctl.sh start
```

## 本机验证记录（2026-07-13，kuaipao 时代）

- kuaipao `generate_image` → 200，写出 `local_path` + `source_url`
- seedream-v5-lite t2i `2048*2048` → poll completed
- seedream-edit（URL 图）→ completed
- wan-2.7 image-edit（URL 图, size=2K）→ completed

> 以上为 kuaipao-image 时代的历史验证记录，保留作参考。xiaoyi-grok-image 上线后尚未补充新验证记录。
