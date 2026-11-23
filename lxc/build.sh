#!/usr/bin/env bash
# Build an importable LXC/Incus container image from the repository Dockerfile.
#
# Pipeline
#   1. docker build   base devbox image   (root Dockerfile, unchanged)
#   2. docker build   system-container layer (lxc/Dockerfile: systemd + ssh.service)
#   3. docker export  flattened root filesystem
#   4. normalize      replace Docker runtime files with LXC-safe state
#   5. package        unified image tarball (metadata.yaml + rootfs/)
#
# Output
#   ${OUT_DIR:-<repo>/dist}/kivotos-lxc-<version>-amd64.tar.xz     unified image (+ .sha256)
#   ${OUT_DIR:-<repo>/dist}/kivotos-rootfs-<version>-amd64.tar.zst plain root filesystem
#
# Import
#   sudo incus image import kivotos-lxc-<version>-amd64.tar.xz --alias kivotos
#   sudo lxc image import    kivotos-lxc-<version>-amd64.tar.xz --alias kivotos   # LXD
#   sudo pct restore <vmid>  kivotos-rootfs-<version>-amd64.tar.zst --rootfs local-lvm:8
#
# Environment
#   BASE_IMAGE   base image tag to build/consume   (default kivotos:lxc-base)
#   IMAGE        system-container layer tag        (default kivotos:lxc)
#   OUT_DIR      artifact directory                (default <repo>/dist)
#   PLATFORM     docker platform                   (default linux/amd64)
#   XZ_LEVEL     xz compression level              (default 6)
#   REUSE_BASE=1 reuse an existing BASE_IMAGE instead of rebuilding it
#   BLENDER_VERSION  forwarded to the root Dockerfile when non-empty
#
# Requires a running Docker daemon (root or docker group), tar, xz and git.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

BASE_IMAGE=${BASE_IMAGE:-kivotos:lxc-base}
IMAGE=${IMAGE:-kivotos:lxc}
OUT_DIR=${OUT_DIR:-${REPO_DIR}/dist}
PLATFORM=${PLATFORM:-linux/amd64}
XZ_LEVEL=${XZ_LEVEL:-6}
REUSE_BASE=${REUSE_BASE:-0}
BLENDER_VERSION=${BLENDER_VERSION:-}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die 'docker is required'
command -v xz >/dev/null || die 'xz is required'
docker info >/dev/null 2>&1 || die 'cannot reach the Docker daemon'

# ---------------------------------------------------------------- version -----
version=$(git -C "$REPO_DIR" describe --tags --always --dirty 2>/dev/null || true)
[[ -n "$version" ]] || version=$(date -u +%Y%m%d%H%M%S)
version=${version#v}
version=${version//\//-}
created=$(date -u +%s)
archive="kivotos-lxc-${version}-amd64.tar.xz"

work=$(mktemp -d "${TMPDIR:-/tmp}/kivotos-lxc.XXXXXX")
container=''
cleanup() {
    if [[ -n "$container" ]]; then docker rm -f "$container" >/dev/null 2>&1 || true; fi
    rm -rf "$work"
}
trap cleanup EXIT

# -------------------------------------------------------------- 1. base ------
log "base image: ${BASE_IMAGE}"
build_args=()
if [[ -n "$BLENDER_VERSION" ]]; then
    build_args+=(--build-arg "BLENDER_VERSION=${BLENDER_VERSION}")
fi
if [[ "$REUSE_BASE" == 1 ]] && docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "reusing ${BASE_IMAGE}"
else
    docker build --platform "$PLATFORM" --pull "${build_args[@]}" \
        -t "$BASE_IMAGE" "$REPO_DIR"
fi

# --------------------------------------------------------- 2. lxc layer ------
log "system-container layer: ${IMAGE}"
docker build --platform "$PLATFORM" -f "$REPO_DIR/lxc/Dockerfile" \
    --build-arg "BASE=${BASE_IMAGE}" -t "$IMAGE" "$REPO_DIR"

# ------------------------------------------------------------- 3. export -----
log "export root filesystem"
mkdir -p "$work/rootfs" "$work/stage"
container=$(docker create --platform "$PLATFORM" "$IMAGE")
docker export "$container" -o "$work/export.tar"
tar -xpf "$work/export.tar" --numeric-owner --xattrs --xattrs-include='*' \
    -C "$work/rootfs"
rm -f "$work/export.tar"
docker rm -f "$container" >/dev/null
container=''

rootfs="$work/rootfs"

# ---------------------------------------------------------- 4. normalize -----
log "normalize root filesystem"
# Docker runtime files: the daemon bind-mounts these during build, so whatever the
# export contains belongs to the build host, not to the image.
rm -f "$rootfs/.dockerenv"
install -d -m 755 "$rootfs/var/lib/dbus"
ln -sfn /etc/machine-id "$rootfs/var/lib/dbus/machine-id"

# LXC/Incus mount their own /dev, /proc, /sys and /run; ship empty mount points only.
rm -rf "$rootfs/dev" "$rootfs/proc" "$rootfs/sys" "$rootfs/run" "$rootfs/tmp" "$rootfs/var/tmp"
install -d -m 755 "$rootfs/dev" "$rootfs/dev/pts" "$rootfs/dev/shm" \
    "$rootfs/proc" "$rootfs/sys" "$rootfs/run" "$rootfs/run/lock"
install -d -m 1777 "$rootfs/tmp" "$rootfs/var/tmp"

# Static network identity. Incus/LXD and Proxmox VE overwrite these with their own
# generated files; plain LXC keeps them, so make them usable as-is.
printf 'kivotos\n' > "$rootfs/etc/hostname"
cat > "$rootfs/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	kivotos
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
EOF
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\noptions edns0 trust-ad\n' \
    > "$rootfs/etc/resolv.conf"
chmod 644 "$rootfs/etc/hostname" "$rootfs/etc/hosts" "$rootfs/etc/resolv.conf"

# SSH host keys are generated per container on first start, never baked in.
rm -f "$rootfs"/etc/ssh/ssh_host_*

# Drop build leftovers that must not travel into the image.
rm -rf "$rootfs/var/lib/apt/lists" "$rootfs/var/cache/apt/archives"
install -d -m 755 "$rootfs/var/lib/apt/lists" "$rootfs/var/lib/apt/lists/partial"
install -d -m 755 "$rootfs/var/cache/apt/archives" \
    "$rootfs/var/cache/apt/archives/partial"
rm -f "$rootfs/root/.bash_history"

# ------------------------------------------------------------- 5. verify -----
log "verify root filesystem"
for path in \
    sbin/init \
    usr/lib/systemd/systemd \
    usr/sbin/sshd \
    etc/ssh/sshd_config.d/00-kivotos.conf \
    etc/systemd/system/ssh.service \
    etc/systemd/system/multi-user.target.wants/ssh.service \
    usr/local/bin/uv \
    usr/local/bin/blender \
    usr/local/bin/go \
    usr/local/bin/cargo \
    usr/local/bin/node \
    opt/blender/blender \
    etc/profile.d/99-dev-tools.sh \
    etc/environment; do
    [[ -e "$rootfs/$path" ]] || die "missing /$path in root filesystem"
done
[[ -L "$rootfs/etc/systemd/system/ssh.socket" ]] || die 'ssh.socket is not masked'
[[ "$(readlink "$rootfs/etc/systemd/system/ssh.socket")" == /dev/null ]] \
    || die 'ssh.socket does not point at /dev/null'
[[ -z "$(find "$rootfs/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -print -quit)" ]] \
    || die 'SSH host keys were baked into the image'
[[ ! -e "$rootfs/.dockerenv" ]] || die '.dockerenv survived normalization'
[[ -e "$rootfs/etc/machine-id" && ! -s "$rootfs/etc/machine-id" ]] \
    || die '/etc/machine-id must exist and be empty'
grep -q 'LANG=en_US.UTF-8' "$rootfs/etc/default/locale" \
    || die 'LANG missing from /etc/default/locale'

# ------------------------------------------------------------ 6. package -----
log "package root filesystem: kivotos-rootfs-${version}-amd64.tar.zst"
mkdir -p "$OUT_DIR"
rootfs_archive="kivotos-rootfs-${version}-amd64.tar.zst"
if command -v zstd >/dev/null; then
    rootfs_part="$OUT_DIR/.${rootfs_archive}.part"
    tar -C "$rootfs" --numeric-owner --xattrs --xattrs-include='*' --acls \
        -I 'zstd -T0 -3 -q' -cf "$rootfs_part" .
    mv "$rootfs_part" "$OUT_DIR/$rootfs_archive"
else
    echo 'zstd not found: skipping the plain rootfs artifact'
    rootfs_archive=''
fi

log "package unified image: ${archive}"
sed -e "s|^creation_date: .*|creation_date: ${created}|" \
    -e "s|^  version: .*|  version: \"${version}\"|" \
    -e "s|^  serial: .*|  serial: \"${created}\"|" \
    "$REPO_DIR/lxc/metadata.yaml" > "$work/stage/metadata.yaml"
mv "$rootfs" "$work/stage/rootfs"

mkdir -p "$OUT_DIR"
part="$OUT_DIR/.${archive}.part"
tar -C "$work/stage" --numeric-owner --xattrs --xattrs-include='*' --acls \
    -I "xz -T0 -${XZ_LEVEL}" -cf "$part" metadata.yaml rootfs
mv "$part" "$OUT_DIR/$archive"
( cd "$OUT_DIR" && sha256sum "$archive" > "$archive.sha256" )

log "done"
printf 'image:   %s\n' "$OUT_DIR/$archive"
printf 'size:    %s\n' "$(du -h "$OUT_DIR/$archive" | cut -f1)"
printf 'sha256:  %s\n' "$(cut -d' ' -f1 "$OUT_DIR/$archive.sha256")"
if [[ -n "$rootfs_archive" ]]; then
    printf 'rootfs:  %s (%s)\n' "$OUT_DIR/$rootfs_archive" \
        "$(du -h "$OUT_DIR/$rootfs_archive" | cut -f1)"
fi
printf '\nimport with:\n  incus image import "%s" --alias kivotos\n  incus launch kivotos <name>\n' \
    "$OUT_DIR/$archive"