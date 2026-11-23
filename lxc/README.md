# Kivotos LXC 容器镜像

把仓库根目录的 `Dockerfile` 构建成可以被 Incus / LXD / Proxmox VE 导入的系统容器镜像。

根 `Dockerfile` 仍是唯一来源：工具链版本、locale、apt 源、sshd 策略都在那里。`lxc/Dockerfile` 只补系统容器必需、而 Docker 不需要的部分，`lxc/build.sh` 负责导出、规范化与打包。

## 构建

需要一台装有 Docker 的机器（本机有守护进程权限，或 `sudo`）：

```bash
lxc/build.sh
```

产物在 `dist/`：

| 文件 | 用途 |
| --- | --- |
| `kivotos-lxc-<version>-amd64.tar.xz` | 统一镜像（`metadata.yaml` + `rootfs/`），Incus / LXD 直接导入 |
| `kivotos-rootfs-<version>-amd64.tar.zst` | 纯 rootfs，用于 Proxmox VE `pct restore` 或裸 LXC |

可选环境变量：`BASE_IMAGE`、`IMAGE`、`OUT_DIR`、`PLATFORM`、`XZ_LEVEL`、`REUSE_BASE=1`（跳过基础镜像重建）、`BLENDER_VERSION`。

## 导入与启动

Incus（推荐）：

```bash
sudo incus image import dist/kivotos-lxc-*.tar.xz --alias kivotos
sudo incus launch kivotos devbox
sudo incus exec devbox -- bash -lc 'go version && node --version && blender --version'
```

LXD：

```bash
sudo lxc image import dist/kivotos-lxc-*.tar.xz --alias kivotos
sudo lxc launch kivotos devbox
```

Proxmox VE（8.2+）：

```bash
sudo pct restore 100 dist/kivotos-rootfs-*.tar.zst --rootfs local-lvm:8 --unprivileged 1
sudo pct start 100
```

裸 LXC：

```bash
sudo install -d /var/lib/lxc/kivotos/rootfs
sudo tar -xJf dist/kivotos-lxc-*.tar.xz -C /tmp rootfs
sudo cp -a /tmp/rootfs/. /var/lib/lxc/kivotos/rootfs/
```

配置里至少需要 `lxc.init.cmd = /sbin/init` 和 `lxc.mount.auto = proc:rw sys:rw cgroup:mixed`；systemd 在非特权容器里还需要 cgroup v2 委派，发行版自带的 `lxc-unpriv-start` 会处理好这一点。

## 与 Docker 镜像的差异

| 项 | Docker 镜像 | LXC 镜像 |
| --- | --- | --- |
| PID 1 | `bash -c 'ssh-keygen -A && exec sshd -D'` | `systemd`（`/sbin/init`） |
| SSH | 前台进程，容器停即断 | `ssh.service` 由 systemd 管理，`systemctl restart ssh` 生效 |
| SSH 主机密钥 | 启动时生成 | 首次启动由 `ssh.service` 的 `ExecStartPre` 生成 |
| `/etc/hosts`、`/etc/hostname`、`/etc/resolv.conf` | Docker 运行时挂载 | 打包时写入静态文件，Incus/PVE 会用自己生成的版本覆盖 |
| `/.dockerenv`、`/dev`、`/run`、apt 缓存 | 由 Docker 管理 | 打包时清理，`/dev`、`/proc`、`/sys`、`/run` 只留空挂载点 |
| `machine-id` | 无关 | 置空，首次启动由 systemd 生成 |

sshd 策略、用户、locale、工具链位置（`/opt/blender`、`/opt/node`、`/opt/uv/python`、`/opt/rustup`、`/usr/local/go`）与 Docker 镜像完全一致，因为都来自同一个 `Dockerfile`。

## 已知限制

- `ssh.socket`（Ubuntu 新版本的 socket 激活）被 mask，容器固定监听 `sshd_config.d/00-kivotos.conf` 里的 `Port 22`，与 Docker 行为一致。
- root 密码被锁定且 `PermitRootLogin no`，先用 `incus exec devbox -- bash` 或 `pct enter 100` 进入容器创建用户、写入公钥，再走 SSH。
- 镜像内不含 NVIDIA 用户态库：GPU 需要宿主机配置 NVIDIA Container Toolkit / `nvidia.runtime`，Incus 用 `incus config device add devbox gpu gpu`。
- 只有 `linux/amd64`：`Dockerfile` 的 Blender 步骤显式检查 `dpkg --print-architecture` 为 `amd64`。
- 构建在 CI 上约 15–25 分钟（Blender / Rust / Go / Node 下载为主），产物约 1.5–2 GB。