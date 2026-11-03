FROM ubuntu:26.04

SHELL ["/bin/bash", "-c"]
WORKDIR /root

ARG DEBIAN_FRONTEND=noninteractive
ARG BLENDER_VERSION=5.2.3

ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    RUSTUP_HOME=/opt/rustup \
    RUSTUP_AUTO_INSTALL=0

# Base utilities, network commands, build dependencies, and Blender libraries.
RUN set -euxo pipefail; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget jq \
        locales libcap2-bin \
        tar gzip xz-utils unzip openssl \
        git nano vim sudo htop btop nvtop screen openssh-server \
        build-essential pkg-config \
        net-tools iproute2 \
        iputils-ping iputils-tracepath iputils-arping \
        traceroute mtr-tiny inetutils-telnet \
        bind9-dnsutils netcat-openbsd tcpdump iperf3 \
        libgl1 libegl1 libx11-6 libxi6 \
        libxrender1 libxext6 libsm6 libxkbcommon0 \
        libxfixes3 libxxf86vm1 libxrandr2 \
        libxinerama1 libxcursor1; \
    if [[ -n "$(getcap /usr/bin/nvtop)" ]]; then \
        setcap -r /usr/bin/nvtop; \
    fi; \
    printf '%s\n' 'en_US.UTF-8 UTF-8' > /etc/locale.gen; \
    locale-gen; \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    ln -s "$(command -v traceroute)" /usr/local/bin/tracert; \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Apply shared toolchain locations to future login users too.
RUN set -eux; \
    printf '%s\n' \
        'export UV_PYTHON_INSTALL_DIR=/opt/uv/python' \
        'export UV_PYTHON_BIN_DIR=/usr/local/bin' \
        'export RUSTUP_HOME=/opt/rustup' \
        'export RUSTUP_AUTO_INSTALL=0' \
        > /etc/profile.d/99-dev-tools.sh; \
    printf '%s\n' \
        'UV_PYTHON_INSTALL_DIR=/opt/uv/python' \
        'UV_PYTHON_BIN_DIR=/usr/local/bin' \
        'RUSTUP_HOME=/opt/rustup' \
        'RUSTUP_AUTO_INSTALL=0' \
        >> /etc/environment

# uv: latest stable, globally installed, no root-home setup.
RUN set -euxo pipefail; \
    curl -fsSL --retry 3 https://astral.sh/uv/install.sh -o /tmp/uv-install.sh; \
    UV_UNMANAGED_INSTALL=/usr/local/bin sh /tmp/uv-install.sh; \
    rm -f /tmp/uv-install.sh; \
    uv --version

# Python: newest stable CPython supported by uv, shared read-only.
RUN set -euxo pipefail; \
    uv python install --default; \
    chmod -R a+rX /opt/uv/python; \
    python --version; \
    python3 --version

# Blender LTS: official Linux x64 tarball and SHA256 verification.
RUN set -euxo pipefail; \
    test "$(dpkg --print-architecture)" = amd64; \
    tmpdir="$(mktemp -d)"; \
    archive="blender-${BLENDER_VERSION}-linux-x64.tar.xz"; \
    base="https://download.blender.org/release/Blender${BLENDER_VERSION%.*}"; \
    curl -fsSL --retry 3 "${base}/${archive}" -o "${tmpdir}/${archive}"; \
    curl -fsSL --retry 3 "${base}/blender-${BLENDER_VERSION}.sha256" -o "${tmpdir}/SHA256"; \
    checksum="$(awk -v f="${archive}" '$2 == f || $2 == "*" f {print $1}' "${tmpdir}/SHA256")"; \
    test -n "${checksum}"; \
    printf '%s  %s\n' "${checksum}" "${tmpdir}/${archive}" | sha256sum -c -; \
    tar -xJf "${tmpdir}/${archive}" -C /opt; \
    mv "/opt/blender-${BLENDER_VERSION}-linux-x64" /opt/blender; \
    ln -s /opt/blender/blender /usr/local/bin/blender; \
    rm -rf "${tmpdir}"; \
    blender --version

# Go: latest stable release from Go's official JSON API.
RUN set -euxo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in amd64|arm64) ;; *) exit 1 ;; esac; \
    info="$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | \
        jq -r --arg arch "${arch}" \
        '[.[] | select(.stable == true)][0].files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | [.filename, .sha256] | @tsv')"; \
    read -r filename checksum <<< "${info}"; \
    test -n "${filename}"; \
    test -n "${checksum}"; \
    tmpdir="$(mktemp -d)"; \
    curl -fsSL --retry 3 "https://go.dev/dl/${filename}" -o "${tmpdir}/${filename}"; \
    printf '%s  %s\n' "${checksum}" "${tmpdir}/${filename}" | sha256sum -c -; \
    tar -xzf "${tmpdir}/${filename}" -C /usr/local; \
    ln -s /usr/local/go/bin/go /usr/local/bin/go; \
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    rm -rf "${tmpdir}"; \
    go version

# Rust: latest stable toolchain; rustup/toolchain are globally readable.
# User-specific Cargo crate caches continue to use the user's account.
RUN set -euxo pipefail; \
    mkdir -p /opt/rustup /opt/rust-cargo; \
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 \
        https://sh.rustup.rs -o /tmp/rustup.sh; \
    CARGO_HOME=/opt/rust-cargo RUSTUP_HOME=/opt/rustup \
        sh /tmp/rustup.sh -y --no-modify-path \
        --profile default --default-toolchain stable; \
    for tool in rustup rustc cargo rustdoc rustfmt cargo-fmt cargo-clippy clippy-driver; do \
        if [[ -x "/opt/rust-cargo/bin/${tool}" ]]; then \
            ln -s "/opt/rust-cargo/bin/${tool}" "/usr/local/bin/${tool}"; \
        fi; \
    done; \
    chmod -R a+rX /opt/rustup /opt/rust-cargo; \
    rm -f /tmp/rustup.sh; \
    rustc --version; \
    cargo --version

# Node.js: newest LTS from official release index, with npm and npx.
RUN set -euxo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
        *) exit 1 ;; \
    esac; \
    version="$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json | \
        jq -r --arg platform "linux-${node_arch}" \
        '[.[] | select((.lts | type) == "string") | select(.files | index($platform))] | .[0].version // empty')"; \
    test -n "${version}"; \
    archive="node-${version}-linux-${node_arch}.tar.xz"; \
    base="https://nodejs.org/dist/${version}"; \
    tmpdir="$(mktemp -d)"; \
    curl -fsSL --retry 3 "${base}/${archive}" -o "${tmpdir}/${archive}"; \
    curl -fsSL --retry 3 "${base}/SHASUMS256.txt" -o "${tmpdir}/SHASUMS256.txt"; \
    checksum="$(awk -v f="${archive}" '$2 == f {print $1; found=1} END {if (!found) exit 1}' "${tmpdir}/SHASUMS256.txt")"; \
    printf '%s  %s\n' "${checksum}" "${tmpdir}/${archive}" | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf "${tmpdir}/${archive}" -C /opt/node --strip-components=1; \
    for tool in node npm npx; do \
        ln -s "/opt/node/bin/${tool}" "/usr/local/bin/${tool}"; \
    done; \
    rm -rf "${tmpdir}"; \
    node --version; \
    npm --version

# SSH/SFTP configuration embedded directly into Dockerfile.
# TCP local/remote/dynamic forwarding; remote bind address client-selected.
RUN set -eux; \
    printf '%s\n' \
        'Port 22' \
        'SyslogFacility AUTHPRIV' \
        'LogLevel INFO' \
        'PermitRootLogin no' \
        'PubkeyAuthentication yes' \
        'AuthorizedKeysFile .ssh/authorized_keys' \
        'PasswordAuthentication yes' \
        'PermitEmptyPasswords no' \
        'KbdInteractiveAuthentication no' \
        'UsePAM yes' \
        'Subsystem sftp internal-sftp' \
        'DisableForwarding no' \
        'AllowTcpForwarding yes' \
        'AllowStreamLocalForwarding yes' \
        'GatewayPorts clientspecified' \
        'PermitOpen any' \
        'PermitListen any' \
        'PermitTTY yes' \
        'PrintMotd no' \
        'AcceptEnv LANG LC_*' \
        > /etc/ssh/sshd_config; \
    chmod 600 /etc/ssh/sshd_config; \
    chown root:root /etc/ssh/sshd_config; \
    mkdir -p /run/sshd; \
    ssh-keygen -A; \
    /usr/sbin/sshd -t; \
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub; \
    echo "root:$(openssl rand -base64 30)" | chpasswd

# Verify main command entry points during image build.
# RUN set -eux; \
#    uv --version; \
#    python --version; \
#    blender --version; \
#    go version; \
#    rustc --version; \
#    cargo --version; \
#    node --version; \
#    npm --version; \
#    command -v ping traceroute tracert telnet dig nc ip ss

EXPOSE 22

# Generate unique SSH host keys at container startup if missing.
CMD ["/bin/bash", "-c", "mkdir -p /run/sshd && ssh-keygen -A && exec /usr/sbin/sshd -D -e"]
