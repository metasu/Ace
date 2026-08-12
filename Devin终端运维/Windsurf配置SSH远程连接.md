# Windsurf 中配置 SSH 远程连接

---

## 一、配置 SSH config

在 Windsurf 中修改 `~/.ssh/config` 文件：

```
Host myvps
    HostName 66.154.118.2
    Port 2026
    User root
    IdentityFile ~/.ssh/pri1.pem
    IdentitiesOnly yes
```

---

## 二、255 错误处理

连接时报 255 错误通常是 SSH 主机指纹变更，清除旧缓存后重连：

```
ssh-keygen -R [66.154.118.2]:2026
```
