# Linux 与 Docker Compose 运维

---

## 一、Linux 系统基础

### 1.1 获取 ROOT 权限

```
sudo -i
```

### 1.2 安装常用基础工具 (Debian/Ubuntu)

```
apt update -y
apt install -y sudo curl wget socat net-tools
```

### 1.3 DD 重装系统脚本

> 会重装整个系统，请谨慎使用。

DD 为 Debian 10：

```
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -d 10 -v 64 -p yourpasswd -port 22
```

DD 为 Ubuntu 20.04：

```
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') -u 20.04 -v 64 -p yourpasswd -port 22
```

### 1.4 Oracle Cloud (甲骨文云) 开放所有端口

**Ubuntu 系统：**

```
# 允许所有流量
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
```

```
# 清除默认防火墙规则并重启
apt-get purge netfilter-persistent -y
reboot
```

**CentOS 系统：**

```
# 停止并禁用防火墙
systemctl stop firewalld.service
systemctl disable firewalld.service
```

---

## 二、SSH 配置

### 2.1 允许 Root 用户通过密码远程登录

```
# 适用于 Debian/Ubuntu/CentOS
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
# CentOS 可能需要额外执行
sed -i 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config

# 重启 SSH 服务
systemctl restart sshd
```

### 2.2 配置 ed25519 密钥登录 (更安全)

**生成密钥对**（直接显示私钥和公钥，请妥善保存）：

```
ssh-keygen -t ed25519 -q -N "" -C "" -f tmp ; cat tmp ; echo ; cat tmp.pub ; rm -f tmp tmp.pub
```

**在服务器上配置公钥：**

```
# 创建 .ssh 目录并设置权限
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# 写入公钥
echo "你的公钥内容" > ~/.ssh/authorized_keys

# 设置权限
chmod 600 ~/.ssh/authorized_keys
```

**修改 SSH 配置：**

```
vim /etc/ssh/sshd_config
```

确保以下两项开启（去掉 `#`）：

```
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
```

修改后按 `ESC`，输入 `:wq` 保存退出。或用 nano：

```
nano /etc/ssh/sshd_config
```

修改后 `Ctrl+X` 再 `Y` 保存。重启 SSH 服务：

```
systemctl restart sshd
```

**通过密钥登录：**

```
ssh -i private.pem root@你的服务器IP
```

---

## 三、网络与性能优化

### 3.1 开启 BBR 加速

```
bash <(curl -l -s https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)
```

### 3.2 修改服务器时区

以新加坡为例：

```
sudo tzselect
# 选择 Asia -> Singapore

sudo ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
reboot
```

### 3.3 设置 IPv4 优先

在 `/etc/gai.conf` 文件中加上：

```
precedence ::ffff:0:0/96  100
```

验证：

```
getent ahosts google.com
# 第一行应为 IPv4 地址

curl -v http://google.com
# Trying ... 处应优先显示 IPv4
```

### 3.4 BlueSkyXN 综合工具箱

包含系统信息、BBR 安装、流媒体检测等多种功能：

```
wget -O box.sh https://raw.githubusercontent.com/BlueSkyXN/SKY-BOX/main/box.sh && chmod +x box.sh && clear && ./box.sh
```

### 3.5 服务器性能与网络测试

```
# CPU 信息
lscpu

# Superbench.sh - 全面性能测试 (中文)
bash <(curl -Lso- https://git.io/superbench)

# Bench.sh - 性能与IO测试 (英文)
wget -qO- bench.sh | bash

# 三网回程路由测试
curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh|bash

# 测试 IPv4 / IPv6 访问优先级
curl ip.p3terx.com
```

### 3.6 流媒体解锁检测

```
# 全媒体解锁测试 (Netflix, Disney+, Bilibili 等)
bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)

# Netflix 解锁测试 (x86_64)
wget -O nf https://github.com/sjlleo/netflix-verify/releases/download/latest/nf_linux_amd64 && chmod +x nf && clear && ./nf

# Netflix 解锁测试 (ARM)
wget -O nf https://github.com/sjlleo/netflix-verify/releases/download/latest/nf_linux_arm64 && chmod +x nf && clear && ./nf
```

---

## 四、Windows 字符干扰问题

### 4.1 安装 dos2unix

```
# Ubuntu
sudo apt-get update && sudo apt-get install dos2unix

# CentOS/RHEL
sudo yum install dos2unix
```

### 4.2 转换脚本文件

```
dos2unix opengemini.sh
```

### 4.3 VS Code 配置（避免换行符错误）

按 `Ctrl + Shift + P` → 输入 `Preferences: Open User Settings (JSON)`：

```json
{
  "files.eol": "\n",
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true
}
```

---

## 五、Docker 安装 (Ubuntu)

### 5.1 卸载旧版本

```
sudo apt-get remove docker docker-engine docker.io containerd runc docker-ce docker-ce-cli docker-compose-plugin -y
```

### 5.2 安装依赖包

```
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
```

### 5.3 添加 Docker 官方 GPG 密钥

```
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

### 5.4 设置 APT 仓库

```
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 5.5 安装 Docker 引擎与 Compose V2

```
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin -y
sudo apt-get install docker-compose-plugin -y
```

### 5.6 验证与配置

```
# 检查版本
sudo docker --version
docker-compose --version

# 免 sudo 使用
sudo usermod -aG docker $USER
newgrp docker
```

### 5.7 全局限制容器日志大小

在 `/etc/docker/daemon.json` 中配置：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
```

```
# 重启并设置开机自启
systemctl restart docker
systemctl enable docker
```

---

## 六、Docker & Compose V2 常用命令

### 6.1 基础命令

```
# 查看 Docker 版本
docker -v

# 查看 Compose 版本
docker-compose --version

# 重启 Docker 服务
systemctl restart docker
```

### 6.2 容器 (Container) 管理

```
# 查看正在运行的容器
docker ps

# 查看所有容器（包括已停止的）
docker ps -a

# 启动 / 停止 / 重启 / 删除 / 强制停止
docker start [容器名/ID]
docker stop [容器名/ID]
docker restart [容器名/ID]
docker rm [容器名/ID]
docker kill [容器名/ID]

# 查看容器日志
docker logs -f [容器名/ID]
```

### 6.3 批量操作所有容器

```
# 停止所有正在运行的容器
docker stop $(docker ps -a -q)

# 删除所有已停止的容器
docker rm $(docker ps -a -q)

# 查看所有容器的服务名
docker inspect --format '{{.Name}} => {{index .Config.Labels "com.docker.compose.service"}}' $(docker ps -q)
```

### 6.4 镜像 (Image) 管理

```
# 查看所有本地镜像
docker images

# 删除指定镜像
docker rmi [镜像ID]
docker rmi [镜像名:标签]

# 删除所有本地镜像
docker rmi $(docker images -q)

# 删除所有未使用的镜像
docker image prune -a
docker image prune -a -f
```

### 6.5 Docker Compose V2 管理

```
# 前台启动（调试用，显示日志）
docker compose up

# 后台启动
docker compose up -d

# 拉取 / 更新镜像
docker compose pull

# 重启服务
docker compose restart

# 停止并删除服务容器
docker compose down

# 查看服务日志
docker compose logs -f
```

---

## 七、Docker Compose v2 项目迁移教程

### 7.1 概述

- 适用于 Docker Compose v2 项目，项目目录为 `/opt/npm`，数据以绑定卷（bind mounts）方式存放
- 迁移目标：打包整个项目目录 = 配置 + 数据，在新机一键恢复
- 默认 SSH 端口：22
- 新服务器 IP 示例：`168.231.116.119`

> 停容器再打包可避免写入中的文件被截断，保证数据一致性。

### 7.2 旧服务器：停服务并打包

```
# 停止容器
cd /opt/npm
docker compose down

# 打包整个项目目录
cd /opt
tar -czvf npm.tgz npm

# 可选：生成校验值
sha256sum /opt/npm.tgz
```

打包内容包含 `docker-compose.yml`、`.env` 和数据文件夹（挂载卷）。

### 7.3 传输压缩包

```
# 旧机 → 新机（VPS 互传）
scp -P 22 /opt/npm.tgz root@168.231.116.119:/opt/

# 服务器 → 本地（下载）
scp -P 22 root@旧服务器IP:/opt/npm.tgz .

# 本地 → 服务器（上传）
scp -P 22 npm.tgz root@168.231.116.119:/opt/
```

> `-P`（大写）是 scp 的端口参数。图形 SFTP 客户端需在连接设置里改端口为 22。

### 7.4 避坑：REMOTE HOST IDENTIFICATION HAS CHANGED!

表示新服务器 SSH 主机指纹与本地缓存不一致。

**1）在新服务器上确认真实指纹：**

```
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# 或
ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
```

也可在发起端获取再比对：

```
ssh-keyscan -T 5 -t ed25519,ecdsa 168.231.116.119 | ssh-keygen -lf -
```

**2）删除旧的 known_hosts 条目：**

```
ssh-keygen -f ~/.ssh/known_hosts -R 168.231.116.119
ssh-keygen -f ~/.ssh/known_hosts -R '[168.231.116.119]:22'
```

**3）重新传输（严格校验）：**

```
ssh-keyscan -H -T 5 -t ed25519,ecdsa 168.231.116.119 > /tmp/new_known_hosts
scp -P 22 -o UserKnownHostsFile=/tmp/new_known_hosts -o StrictHostKeyChecking=yes \
  /opt/npm.tgz root@168.231.116.119:/opt/
```

### 7.5 新服务器：解压与启动

```
# 解压
cd /opt
tar -xzvf npm.tgz

# 启动
cd /opt/npm
docker compose up -d

# 验证
docker compose ps
docker compose logs -f

# 可选：校验压缩包完整性
sha256sum /opt/npm.tgz
```

### 7.6 常见问题与排查

- **端口/防火墙：** 新机需放行业务端口（如 80/443），SSH 端口 22
- **架构差异（x86_64 ↔ arm64）：** 需重新拉取镜像：

```
docker compose pull
docker compose up -d --remove-orphans
```

- **权限：** 容器内非 root 用户写入时，迁移后可能需修正属主：

```
chown -R 1000:1000 /opt/npm/你的数据目录
```

- **外部网络/卷：** 使用了 `external: true` 的网络/卷，需先在新机创建：

```
docker network create 你的网络名
```

- **.env/域名：** 更换服务器后需更新域名解析、回调地址等配置
- **断点续传：** scp 断了需重来，可改用 rsync：

```
rsync -P -e 'ssh -p 22' /opt/npm.tgz root@168.231.116.119:/opt/
```

### 7.7 速查清单

**旧机：**

```
cd /opt/npm && docker compose down
cd /opt && tar -czvf npm.tgz npm
sha256sum /opt/npm.tgz
scp -P 22 /opt/npm.tgz root@168.231.116.119:/opt/
```

**如遇指纹变更：**

```
ssh-keygen -f ~/.ssh/known_hosts -R 168.231.116.119
ssh-keygen -f ~/.ssh/known_hosts -R '[168.231.116.119]:22'
scp -P 22 /opt/npm.tgz root@168.231.116.119:/opt/
```

**新机：**

```
cd /opt && tar -xzvf npm.tgz
cd /opt/npm && docker compose up -d
docker compose ps
```
