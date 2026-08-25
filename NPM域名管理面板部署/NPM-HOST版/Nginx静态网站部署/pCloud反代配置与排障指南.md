# pCloud 反代配置与排障指南

将 pCloud 公开分享链接（`filedn.eu/luAFbRWknPyfToYDs9VNNI8`）反代到自有域名，实现自定义域名访问 pCloud 文件。

---

## 一、快速配置

### 1.1 NPM 面板操作

1. **新建 Proxy Host**
   - **Domain Names**: `your-domain.com`
   - **Scheme**: `https`
   - **Forward Hostname**: `filedn.eu`（占位，会被 Advanced 覆盖）
   - **Forward Port**: `443`
   - 勾选 **Websockets Support**

2. **配置 SSL 证书**
   - 在 SSL 标签页申请 Let's Encrypt 证书
   - 或上传自有证书

3. **粘贴反代配置**
   - 切换到 **Advanced** 标签页
   - 粘贴下方完整配置（记得替换域名和 code）
   - 点击 Save（NPM 会自动执行 `nginx -t` 校验）

### 1.2 完整 Nginx 配置

```nginx
# ① 长链接 → 短链接（可选）
location ~ ^/luAFbRWknPyfToYDs9VNNI8/(.*)$ {
  return 301 https://your-domain.com/$1$is_args$args;
}

# ② 主代理：your-domain.com → filedn.eu/luAFbRWknPyfToYDs9VNNI8
location ~ ^/(?!\.well-known/) {
    proxy_ssl_server_name on;
    proxy_ssl_name filedn.eu;
    proxy_http_version 1.1;
    proxy_set_header Host filedn.eu;
    proxy_set_header Referer "";
    proxy_set_header Origin "";
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header Accept-Encoding "";

    # JS: path = code + dirpath，让最终链接变成 /en/ 而不是 //en/
    sub_filter '"code": "luAFbRWknPyfToYDs9VNNI8"' '"code": ""';
    sub_filter '"dirpath": "\/' '"dirpath": "';
    sub_filter '/luAFbRWknPyfToYDs9VNNI8/' '/';

    # 去掉跳转 pCloud 官网的链接
    sub_filter 'href="https://www.pcloud.com/"' 'href="/"';
    sub_filter 'https://www.pcloud.com/' '/';

    sub_filter_once off;
    sub_filter_types text/html text/css text/javascript application/javascript application/json;

    proxy_hide_header X-Frame-Options;
    proxy_hide_header Content-Security-Policy;
    proxy_hide_header Access-Control-Allow-Origin;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS" always;
    add_header Content-Disposition "inline" always;

    proxy_set_header Range $http_range;
    proxy_set_header If-Range $http_if_range;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;

    proxy_pass https://filedn.eu/luAFbRWknPyfToYDs9VNNI8$request_uri;
}
```

**必须替换的变量**：
- `luAFbRWknPyfToYDs9VNNI8` → 你的 pCloud share code
- `your-domain.com` → 你的实际域名

### 1.3 配置说明

| 指令 | 作用 |
|---|---|
| `proxy_set_header Accept-Encoding ""` | 告诉上游不要发送 gzip 压缩内容（sub_filter 不处理压缩流） |
| `sub_filter` | 改写 HTML/JS 中的 pCloud 链接，确保资源通过反代加载 |
| `location ~ ^/(?!\.well-known/)` | 正则匹配所有路径（排除 Let's Encrypt 验证路径） |
| `proxy_hide_header` | 移除安全头，允许 iframe 嵌入和跨域访问 |

---

## 二、常见问题排查

### 问题 1：访问域名显示 NPM 默认页

**症状**：浏览器显示 "Congratulations!" 或其他默认页，而非 pCloud 内容

#### 原因 1.1：NPM 里不存在该域名的 Proxy Host

**排查**：
```bash
# 检查配置文件是否存在
ls -lh /opt/npm/npm_data/nginx/proxy_host/
grep -r "your-domain.com" /opt/npm/npm_data/nginx/proxy_host/
```

**解决**：在 NPM 面板新建 Proxy Host，确认保存后生成了 `.conf` 文件

#### 原因 1.2：宝塔站点抢占 80/443 端口

**排查**：
```bash
# 查看谁占用了 80/443
ss -tlnp | grep -E ':80\s|:443\s'

# 检查宝塔站点配置
cat /www/server/panel/vhost/nginx/siteXXXXX.local.conf | grep "listen"
```

**解决**：
- 确保宝塔 nginx 已退避到 10080/10443
- 若宝塔站点写了 `listen 80;`，改为其他端口（如 `listen 15888;`）

#### 原因 1.3：NPM 容器未 reload

**解决**：
```bash
docker exec npm_-npm-app-1 nginx -s reload
```

---

### 问题 2：配置保存失败或 nginx -t 报错

#### 原因 2.1：引号不配对

❌ **错误示例**：
```nginx
sub_filter '"dirpath": "\/' '"dirpath": "'";
```
末尾多了一个悬空的 `"`

✅ **正确写法**：
```nginx
sub_filter '"dirpath": "\/' '"dirpath": "';
```

#### 原因 2.2：正则表达式未转义

❌ **错误**：
```nginx
location ~ ^/(?!.well-known/)
```

✅ **正确**：
```nginx
location ~ ^/(?!\.well-known/)  # 点号需要转义
```

**排查方法**：
```bash
# 在容器内手动测试
docker exec npm_-npm-app-1 nginx -t
```

---

### 问题 3：sub_filter 不生效

**症状**：页面能访问，但资源链接还是 `filedn.eu/luAFbRWknPyfToYDs9VNNI8/...`

#### 原因 3.1：上游返回 gzip 压缩内容

nginx 的 `sub_filter` 不处理压缩流。

**排查**：
```bash
# 查看访问日志的 Gzip 字段
tail -f /opt/npm/npm_data/logs/proxy-host-XX_access.log
# 示例：[Gzip 2.79] 说明内容被压缩
```

**解决**：配置里已包含 `proxy_set_header Accept-Encoding "";`，若仍压缩可添加：
```nginx
gunzip on;  # 在 location 块最前面
```

#### 原因 3.2：MIME 类型未覆盖

**排查**：
```bash
curl -sI https://your-domain.com/ | grep -i content-type
```

**解决**：确保 `sub_filter_types` 包含该类型：
```nginx
sub_filter_types text/html text/css text/javascript application/javascript application/json;
```

---

## 三、架构选型

### 3.1 单层架构（pCloud 等纯反代）

```
浏览器 → NPM:443 → proxy_pass https://filedn.eu/... → 返回
```

**特点**：
- 所有逻辑在 NPM 的 nginx 层完成
- **不需要**宝塔站点参与
- 即使 Forward 设置填了端口（如 15777），正则 location 优先级更高，实际不会转发

**适用场景**：纯反代（pCloud、图床、CDN）

### 3.2 双层架构（WordPress 等动态站）

```
浏览器 → NPM:443 (SSL终止) → 127.0.0.1:15888 → 宝塔 (PHP/MySQL) → 返回
```

**特点**：
- NPM 只做 SSL 证书管理和端口转发
- 宝塔提供完整 LNMP 环境
- **需要**宝塔站点监听对应端口

**适用场景**：本地动态应用（WordPress、Laravel）

### 3.3 nginx location 优先级

匹配顺序（从高到低）：
1. 精确匹配 `location = /exact-path`
2. **正则匹配 `location ~ ^/pattern`** ← Advanced 配置
3. 前缀匹配 `location /` ← NPM 基础设置生成

所以 Advanced 里的正则 location 会"截胡"基础设置的转发。

---

## 四、快速排障清单

逐项检查：

1. ✅ NPM 面板里是否存在对应域名的 Proxy Host？
2. ✅ `/opt/npm/npm_data/nginx/proxy_host/` 是否有该域名的 `.conf` 文件？
3. ✅ 宝塔站点配置是否监听了 80/443（需改为其他端口）？
4. ✅ `docker exec npm_-npm-app-1 nginx -t` 是否通过？
5. ✅ NPM 容器是否已 reload？
6. ✅ Advanced 配置的引号、正则是否正确？
7. ✅ 访问日志 `[Gzip ...]` 字段是否为 `-`（若有数字说明被压缩）？

---

## 五、相关文档

- [宝塔Nginx端口改到10080与10443](https://github.com/metasu/Ace/blob/main/BTpanel_宝塔面板运维/宝塔Nginx端口改到10080与10443.md)
- [Nginx location 匹配规则详解](https://nginx.org/en/docs/http/ngx_http_core_module.html#location)
- [NPM 官方文档](https://nginxproxymanager.com/guide/)
