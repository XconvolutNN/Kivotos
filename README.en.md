# Kivotos

[简体中文](README.md)

> [!WARNING]
> This project contains AI-generated content. Review it before use.

An Ubuntu 26.04 development environment with Python / uv, Go, Rust, Node.js LTS, Blender, Git / gh, tmux, and common system and networking tools.

## Start

Run from the project directory:

```bash
docker compose pull
docker compose up -d
docker compose exec kivotos bash
```

The default image is `ghcr.io/xconvolutnn/kivotos:latest`. A named volume stores user home directories under `/home`.

## SSH connection

After the first start, create a user and install your local public key:

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

Set the SSH bind address and port in `.env`, then run `docker compose up -d` to apply:

```dotenv
SSH_BIND_IP=127.0.0.1
SSH_PORT=2222
```

## Local build

```bash
docker build --pull -t kivotos:local .
KIVOTOS_IMAGE=kivotos:local docker compose up -d --pull never
```
