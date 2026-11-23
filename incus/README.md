# Kivotos Incus 镜像

用 [distrobuilder](https://linuxcontainers.org/distrobuilder/docs/latest/)（Incus 官方镜像构建工具）把根 `Dockerfile` 的内容做成可导入 Incus / LXD 的系统容器镜像。`incus/kivotos.yaml` 是镜像定义，`systemd` 作为 PID 1，`ssh.service` 常驻 `Port 22`。

## 构建

```bash
sudo apt install distrobuilder debootstrap rsync gpg
sudo distrobuilder build-incus --type=unified --compression=xz-6 incus/kivotos.yaml dist
```

产物：`dist/kivotos.tar.xz`（统一镜像：`metadata.yaml` + `rootfs/`）。

## 导入

```bash
sudo incus image import dist/kivotos.tar.xz --alias kivotos
sudo incus launch kivotos devbox
sudo incus exec devbox -- blender --version
```

LXD 用法相同：`lxc image import ... --alias kivotos`。

## 说明

- root 无密码且禁止登录，先用 `incus exec devbox -- bash` 创建用户并写入公钥，再走 SSH。
- 工具链位置与 Docker 镜像一致：`/opt/blender`、`/opt/node`、`/opt/uv/python`、`/opt/rustup`、`/usr/local/go`。
- 定义里的包列表和安装步骤需要与根 `Dockerfile` 手工同步；不依赖 Docker 构建产物。
- 镜像不含 NVIDIA 用户态库，GPU 需在宿主机配置后 `incus config device add devbox gpu gpu`。