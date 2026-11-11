# Kivotos

[English](README.en.md)

> [!WARNING]
> 本项目包含 AI 生成的内容，使用前请自行核查。

基于 Ubuntu 26.04 的开发环境，内置 Python / uv、Go、Rust、Node.js LTS、Blender、Git / gh、tmux 和常用系统、网络工具。

## 启动

在项目目录执行：

```bash
docker compose pull
docker compose up -d
docker compose exec kivotos bash
```

默认镜像为 `ghcr.io/xconvolutnn/kivotos:latest`，用户目录 `/home` 使用命名卷保存。

## SSH 连接

首次启动后创建用户并写入本机公钥：

```bash
docker compose exec kivotos useradd -m -s /bin/bash developer
docker compose cp ~/.ssh/id_ed25519.pub kivotos:/tmp/developer.pub
docker compose exec kivotos bash -euc '
  install -d -m 700 -o developer -g developer /home/developer/.ssh
  install -m 600 -o developer -g developer /tmp/developer.pub /home/developer/.ssh/authorized_keys
  rm -f /tmp/developer.pub
'
ssh -p 2222 developer@127.0.0.1
```

可在 `.env` 中设置 SSH 监听地址和端口，执行 `docker compose up -d` 应用：

```dotenv
SSH_BIND_IP=127.0.0.1
SSH_PORT=2222
```

## 本地构建

```bash
docker build --pull -t kivotos:local .
KIVOTOS_IMAGE=kivotos:local docker compose up -d --pull never
```
