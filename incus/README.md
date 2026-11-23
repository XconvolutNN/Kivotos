# Kivotos Incus 镜像

[distrobuilder](https://linuxcontainers.org/distrobuilder/docs/latest/) 镜像定义，内容对应根 `Dockerfile`。systemd 作为 PID 1，SSH 监听 22 端口。

## 构建与导入

```bash
sudo apt install distrobuilder debootstrap rsync gpg
sudo distrobuilder build-incus --type=unified --compression=xz-6 incus/kivotos.yaml dist
sudo incus image import dist/kivotos.tar.xz --alias kivotos
sudo incus launch kivotos devbox
```

## 说明

- root 已锁定：先 `incus exec devbox -- bash` 创建用户并写入公钥，再走 SSH。
- 工具链路径：`/opt/blender`、`/opt/node`、`/opt/uv/python`、`/opt/rustup`、`/usr/local/go`。
- GPU：宿主机配置 NVIDIA 驱动后 `incus config device add devbox gpu gpu`。