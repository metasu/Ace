# pCloud 反代排障指南

## 常见问题与解决方案

### 问题 1：访问域名显示 NPM 默认页，而非 pCloud 内容

**症状**：
- 浏览器访问 `https://your-domain.com` 显示 "Congratulations!" 或其他默认页
- NPM 面板里已配置 Proxy Host，但不生效

**可能原因**：

#### 1.1 NPM 里根本不存在该域名的 Proxy Host
**排查**：
```bash
# 检查 NPM 配置目录
ls -lh /opt/npm/npm_data/nginx/proxy_host/
grep -r "your-domain.com" /opt/npm/npm_data/nginx/proxy_host/
```

**解决**：在 NPM 管理面板新建 Proxy Host，确保：
- Domain Names 填写正确
- 保存后检查 `npm_data/nginx/proxy_host/` 是否生成 `.conf` 文件
- 若未生成，说明 `nginx -t` 校验失败，检查 Advanced 配置语法

#### 1.2 宝塔站点与 NPM 抢占 80/443 端口
**排查**：
```bash
# 查看谁占用了 80/443
ss -tlnp | grep -E ':80\s|:443\s'

# 查看宝塔站点配置
cat /www/server/panel/vhost/nginx/siteXXXXX.local.conf | grep "listen"
```

**解决**：
- 确保宝塔 nginx 已退避到 10080/10443（参考 [宝塔Nginx端口改到10080与10443](https://github.com/metasu/Ace/blob/main/BTpanel_宝塔面板运维/宝塔Nginx端口改到10080与10443.md)）
- 若宝塔站点写了 `listen 80;`，改为其他端口（如 `listen 15777;`）

#### 1.3 NPM 容器未 reload 新配置
**排查**：
```bash
# 检查容器内配置是否与宿主机一致
docker exec npm_-npm-app-1 ls -lh /data/nginx/proxy_host/
```

**解决**：
```bash
# 手动 reload
docker exec npm_-npm-app-1 nginx -s reload
```

---

### 问题 2：配置语法错误导致保存失败

**症状**：NPM 面板保存后，配置未写入磁盘，或显示 "nginx -t failed"

**常见错误**：

#### 2.1 `sub_filter` 引号不配对（原文档有此问题）
❌ **错误**（第 33 行）：
```nginx
sub_filter '"dirpath": "\/' '"dirpath": "'";
```
末尾多了一个悬空的 `"`，nginx 会报错。

✅ **正确**：
```nginx
sub_filter '"dirpath": "\/' '"dirpath": "';
```

#### 2.2 正则表达式语法错误
```nginx
# 错误：未转义点号
location ~ ^/(?!.well-known/)

# 正确：点号需要转义
location ~ ^/(?!\.well-known/)
```

**排查方法**：
```bash
# 在容器内手动测试
docker exec npm_-npm-app-1 nginx -t
```

---

### 问题 3：sub_filter 不生效，页面显示原始 pCloud 链接

**症状**：
- 页面能访问，但资源链接还是 `filedn.eu/luAFbRWknPyfToYDs9VNNI8/...`
- 点击链接跳转到 pCloud 官网

**可能原因**：

#### 3.1 上游返回 gzip 压缩内容
nginx 的 `sub_filter` 不处理压缩流。

**排查**：
```bash
# 查看访问日志的 Gzip 字段
tail -f /opt/npm/npm_data/logs/proxy-host-XX_access.log
# 示例：[Gzip 2.79] 说明内容被压缩了
```

**解决**：配置里已包含 `proxy_set_header Accept-Encoding "";` 告诉上游别压缩，但有些 CDN 会忽略该头。若仍压缩，需在 NPM 侧解压：
```nginx
# 在 location 块最前面添加
gunzip on;
```

#### 3.2 MIME 类型未覆盖
`sub_filter_types` 需包含实际响应的 Content-Type。

**排查**：
```bash
curl -sI https://your-domain.com/ | grep -i content-type
```

**解决**：确保 `sub_filter_types` 包含该类型：
```nginx
sub_filter_types text/html text/css text/javascript application/javascript application/json;
```

---

## 架构选型：单层 vs 双层

### 单层架构（pCloud 等纯反代）

```
浏览器 → NPM:443 → proxy_pass https://filedn.eu/... → 返回
```

**特点**：
- 所有逻辑在 NPM 的 nginx 层完成（反代 + sub_filter）
- **不需要**宝塔站点参与
- 即使 NPM 基础设置里填了 Forward Port（如 15777），正则 location 优先级更高，实际不会转发到该端口

**配置要点**：
- 在 NPM Advanced 标签页粘贴完整配置
- Forward 设置可随意填（不会生效）

### 双层架构（WordPress 等动态站）

```
浏览器 → NPM:443 (SSL终止) → 127.0.0.1:15888 → 宝塔站点 (PHP/MySQL) → 返回
```

**特点**：
- NPM 只做 SSL 证书管理和端口转发
- 宝塔提供完整 LNMP 环境
- **需要**宝塔站点监听对应端口（如 15888）

**配置要点**：
- NPM 的 Advanced 留空或只写简单 header
- 不要在 Advanced 里写 `proxy_pass`，会覆盖基础设置的转发

### 优先级判断

**nginx location 匹配顺序**（从高到低）：
1. 精确匹配 `location = /exact-path`
2. **正则匹配 `location ~ ^/pattern`** ← Advanced 里的配置
3. 前缀匹配 `location /` ← NPM 基础设置生成的

所以 Advanced 里的正则 location 会"截胡"基础设置的转发。

---

## 完整配置（已修正错误）

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

**变量替换**：
- `luAFbRWknPyfToYDs9VNNI8` → 你的 pCloud share code
- `your-domain.com` → 你的实际域名

---

## 快速排障清单

1. ✅ NPM 面板里是否存在对应域名的 Proxy Host？
2. ✅ `/opt/npm/npm_data/nginx/proxy_host/` 是否有该域名的 `.conf` 文件？
3. ✅ 宝塔站点配置是否监听了 80/443（需改为其他端口）？
4. ✅ `docker exec npm_-npm-app-1 nginx -t` 是否通过？
5. ✅ NPM 容器是否已 reload？（`docker exec npm_-npm-app-1 nginx -s reload`）
6. ✅ Advanced 配置的引号、正则是否正确？
7. ✅ 访问日志 `[Gzip ...]` 字段是否为 `-`（若有数字说明被压缩）？

---

## 参考文档

- [pCloud反代配置.md](./pCloud反代配置.md)（原版，需修正第 33 行语法错误）
- [宝塔Nginx端口改到10080与10443](https://github.com/metasu/Ace/blob/main/BTpanel_宝塔面板运维/宝塔Nginx端口改到10080与10443.md)
- [Nginx location 匹配规则详解](https://nginx.org/en/docs/http/ngx_http_core_module.html#location)
