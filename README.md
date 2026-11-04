# Kivotos

基于 Ubuntu 26.04 的开发环境镜像，提供 SSH / SFTP、常用开发工具和系统监控工具。当前仅支持 `linux/amd64`，因为 Blender 使用官方 Linux x64 发行包。

镜像地址：`ghcr.io/xconvolutnn/kivotos:latest`。

## 内置工具

| 类别 | 内容 |
| --- | --- |
| 开发环境 | uv、Python、Go、Rust / Cargo、Node.js LTS / npm / npx、GNU 编译工具 |
| 三维工具 | Blender，默认版本由 Dockerfile 的 `BLENDER_VERSION` 指定 |
| 常用工具 | Git、Vim、Nano、sudo、screen、htop、btop、nvtop |
| 网络工具 | ping、traceroute / tracert、ip / ss、dig、nc、tcpdump、iperf3 等 |
| 远程访问 | OpenSSH、SFTP、SSH 本地 / 远程 / 动态端口转发 |

开发工具安装在 `/opt`、`/usr/local` 等共享目录，普通用户也可以使用。

## Docker Compose 部署

在安装了 Docker Engine 和 Compose 插件的宿主机上，将 [compose.yaml](compose.yaml) 放到部署目录，然后执行：

```bash
docker compose pull
docker compose up -d
```

默认将宿主机 `127.0.0.1:2222` 映射到容器 SSH 端口 `22`。如需从其他机器访问，在同目录的 `.env` 中配置监听地址和端口，再执行 `docker compose up -d`：

```dotenv
SSH_BIND_IP=0.0.0.0
SSH_PORT=2222
```

允许远程访问时，应通过宿主机防火墙限制来源。若 GHCR 镜像为私有包，拉取前需使用具有包读取权限的账号登录 `ghcr.io`。

### 创建 SSH 用户

镜像禁止 root 通过 SSH 登录，同时禁用密码和键盘交互认证，使用 SSH 公钥登录。自定义配置位于 `/etc/ssh/sshd_config.d/00-kivotos.conf`，发行版的 `/etc/ssh/sshd_config` 保持原样，SFTP 沿用发行版默认配置。

首次启动后创建普通用户，并安装本机的 SSH 公钥。下面以已有的 `~/.ssh/id_ed25519.pub` 为例，可替换为自己的公钥路径：

```bash
docker compose exec kivotos useradd -m -s /bin/bash developer
docker compose cp ~/.ssh/id_ed25519.pub kivotos:/tmp/developer.pub
docker compose exec kivotos bash -euc '
  install -d -m 700 -o developer -g developer /home/developer/.ssh
  install -m 600 -o developer -g developer /tmp/developer.pub /home/developer/.ssh/authorized_keys
  rm -f /tmp/developer.pub
'
```

连接容器；从其他机器连接时，将 `127.0.0.1` 换成宿主机地址：

```bash
ssh -p 2222 developer@127.0.0.1
sftp -P 2222 developer@127.0.0.1
```

### 数据与日常管理

Compose 使用命名卷保存 `/home`，包括用户的 `authorized_keys`。**用户账号和组信息不在该卷内**；更新镜像或重建容器后，需用原 UID / GID 重新创建用户。SSH 主机密钥也会在重建容器后重新生成，示例未持久化这些密钥。

```bash
docker compose logs -f
docker compose exec kivotos bash
docker compose stop
docker compose start
```

更新镜像并重建容器：

```bash
docker compose pull
docker compose up -d
```

`docker compose down` 保留命名卷；加上 `-v` 会删除卷内数据。

### GPU（可选）

使用 NVIDIA GPU 时，宿主机需先安装驱动并配置 [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)，然后取消 `compose.yaml` 中 `gpus: all` 的注释并重建容器。该配置需要 Compose 2.30.0 或更新版本。其他 GPU 的设备映射需按宿主机环境配置。

## nvtop 与 UTF-8

- 构建时通过 `setcap -r /usr/bin/nvtop` 清除软件包附带的文件 capabilities；若原本没有 capabilities，则跳过。
- 安装 `locales`，实际生成 `en_US.UTF-8`，再设置 `LANG` 和 `LC_ALL`。系统默认 locale 与容器环境变量同时配置，供 SSH 登录和 `docker compose exec` 使用。
- btop 使用 UTF-8；终端也需要支持相应的 Unicode 字符。nvtop 的 GPU 监控仍需容器能够访问对应 GPU 设备和驱动库。

可在容器中检查：

```bash
docker compose exec kivotos locale charmap
docker compose exec kivotos getcap /usr/bin/nvtop
docker compose exec kivotos btop --version
docker compose exec kivotos nvtop --version
```

`locale charmap` 应输出 `UTF-8`，`getcap` 应无输出。

## 本地构建

在源码目录构建，并通过 `KIVOTOS_IMAGE` 指定本地镜像：

```bash
docker build --pull -t kivotos:local .
KIVOTOS_IMAGE=kivotos:local docker compose up -d --pull never
```

如需长期使用本地镜像，可将 `KIVOTOS_IMAGE=kivotos:local` 写入部署目录的 `.env`。Blender 版本可通过 `--build-arg BLENDER_VERSION=<版本>` 指定，需确保官方发行包和校验文件存在。

## 自动构建

于 **2026-11-04** 核对以下官方稳定发布，工作流使用对应的完整提交 SHA 固定 Action：

| Action | 已核对版本 | 用途 |
| --- | --- | --- |
| [actions/checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) | `v7.0.1` | 检出源码 |
| [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action/releases/tag/v4.4.1) | `v4.4.1` | 设置 Buildx / BuildKit |
| [docker/build-push-action](https://github.com/docker/build-push-action/releases/tag/v7.4.0) | `v7.4.0` | 构建并加载待检查的镜像 |
| [docker/metadata-action](https://github.com/docker/metadata-action/releases/tag/v6.2.0) | `v6.2.0` | 生成镜像标签与 OCI 元数据 |
| [docker/login-action](https://github.com/docker/login-action/releases/tag/v4.7.0) | `v4.7.0` | 登录 GHCR |

这些版本使用 Node.js 24 Action 运行时。继续使用 `ubuntu-24.04` 托管 runner，保留 `persist-credentials: false`，仅在允许发布的分支和事件中使用 GHCR 写权限。后续更新 Action 时，应重新核对官方发布与提交 SHA。

[GitHub Actions](.github/workflows/docker.yml) 在推送、PR、手动触发和每周一 `01:10 UTC` 时构建并检查镜像，包括普通用户工具访问、UTF-8 locale、nvtop capabilities 和 SSH 配置。只有检查成功后，`main` 分支及 `v*` 标签构建才会发布到 GHCR；`main` 发布 `latest`，版本标签发布同名镜像标签。

uv、Python、Go、Rust 和 Node.js 按 Dockerfile 的策略在构建时选择稳定版或 LTS；Ubuntu 与 Blender 使用 Dockerfile 指定的版本。定时构建禁用层缓存以更新工具链。同一源码在不同时间重新构建，工具版本可能不同。

### 构建缓存

采用 Docker 官方支持的 [Registry cache](https://docs.docker.com/build/cache/backends/registry/)，缓存位置为 `ghcr.io/xconvolutnn/kivotos:buildcache-amd64`。该标签保存 BuildKit 缓存，与 `latest`、`main` 和提交标签分开，不用于部署。

- 构建通过 `cache-from` 读取缓存，`main` 分支通过 `cache-to` 和 `mode=max` 保存构建层；PR 和版本标签构建不覆盖共享缓存。
- GHCR 登录在构建前执行，使用仓库的临时 `GITHUB_TOKEN`。正式镜像仍在全部检查通过后发布，发布时直接推送已经测试的镜像。
- 首次构建或缓存已被删除时会正常执行完整构建；后续构建复用未变化的工具链层。修改靠后的 SSH 配置时，可复用前面的安装层。
- 每周定时构建使用 `no-cache`，刷新工具链和软件包后更新共享缓存。
- 手动清理 GHCR 镜像时，可保留 `buildcache-amd64` 标签。清理缓存会使下次构建重新下载和安装依赖；旧的未标记缓存版本可按需清理。

缓存主要减少重复下载和安装的时间，镜像导出、加载、检查及推送仍有开销。性能应以实际缓存命中构建的耗时为准。

## 参考

- [Ubuntu locale-gen](https://manpages.ubuntu.com/manpages/resolute/man8/locale-gen.8.html)
- [Ubuntu update-locale](https://manpages.ubuntu.com/manpages/resolute/man8/update-locale.8.html)
- [Ubuntu setcap](https://manpages.ubuntu.com/manpages/resolute/man8/setcap.8.html)
- [Docker Compose 服务配置](https://docs.docker.com/reference/compose-file/services/)
