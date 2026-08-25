# pCloud 云盘反代配置（filedn.eu → 自有域名）

## 用途

通过 NPM 的 Custom Locations 功能，将 pCloud 公开分享链接（`filedn.eu/luAFbRWknPyfToYDs9VNNI8`）反代到自有域名，实现自定义域名访问 pCloud 文件。

## Nginx 配置

将以下配置填入 NPM 对应 Proxy Host 的 **Custom Locations** 或 **Advanced** 标签页：

```nginx
# ① 长链接 → 短链接
location ~ ^/luAFbRWknPyfToYDs9VNNI8/(.*)$ {
  return 301 https://m.anut.top/$1$is_args$args;
}

# ② 主代理：m.anut.top = filedn.eu/luAFbRWknPyfToYDs9VNNI8
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

    # JS: path = code + dirpath，必须让最终链接变成 /en/ 而不是 //en/ 或 /./en/
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

## 关键说明

- **`luAFbRWknPyfToYDs9VNNI8`** 是 pCloud 分享的 code，需替换为你自己的
- **`m.anut.top`** 是示例域名，替换为你的实际域名
- **`sub_filter`** 用于改写页面中的 pCloud 链接，确保资源通过反代加载而非跳转到原站
- **`\.well-known/`** 排除 Let's Encrypt 证书验证路径
- **`proxy_hide_header`** 移除安全头以允许 iframe 嵌入和跨域访问
