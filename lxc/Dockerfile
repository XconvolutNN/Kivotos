# Kivotos system-container layer.
#
# The base image is built from the repository root Dockerfile, so the toolchains,
# locale, SSH policy and apt sources stay a single source of truth. This layer adds
# only what a bootable LXC/Incus system container needs and a Docker container does not:
#
#   * systemd as PID 1 (/sbin/init instead of the Docker CMD)
#   * ssh.service as a real systemd unit with first-boot host key generation
#   * container-safe runtime state (empty machine-id, clean /run, no baked host keys)
#
# Build through lxc/build.sh, which supplies ${BASE} and does the export/packaging.
ARG BASE
FROM ${BASE}

SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# systemd is the init system of the resulting container; systemd-sysv provides /sbin/init.
RUN set -euxo pipefail; \
    apt-get update; \
    apt-get install -y --no-install-recommends systemd systemd-sysv; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    /usr/lib/systemd/systemd --version

# OpenSSH as a normal system service, with the same sshd policy the Docker image uses.
# The vendor unit layouts differ between Ubuntu releases (socket activation on newer
# releases), so ship an explicit unit and mask ssh.socket: the container listens on
# "Port 22" from sshd_config.d/00-kivotos.conf, exactly like the Docker image.
RUN set -euxo pipefail; \
    printf '%s\n' \
        '[Unit]' \
        'Description=Kivotos OpenSSH server' \
        'Documentation=man:sshd(8) man:sshd_config(5)' \
        'After=network.target' \
        '' \
        '[Service]' \
        'Type=simple' \
        'ExecStartPre=/bin/mkdir -p /run/sshd' \
        'ExecStartPre=-/usr/bin/ssh-keygen -A' \
        'ExecStart=/usr/sbin/sshd -D -e $SSHD_OPTS' \
        'ExecReload=/bin/kill -HUP $MAINPID' \
        'KillMode=process' \
        'Restart=on-failure' \
        'RestartSec=1s' \
        '' \
        '[Install]' \
        'WantedBy=multi-user.target' \
        > /etc/systemd/system/ssh.service; \
    ln -sfn /dev/null /etc/systemd/system/ssh.socket; \
    systemctl enable ssh.service; \
    test -L /etc/systemd/system/multi-user.target.wants/ssh.service; \
    /usr/sbin/sshd -t -f /etc/ssh/sshd_config

# Runtime state that Docker keeps outside the image but LXC expects inside it.
# /etc/hosts, /etc/hostname and /etc/resolv.conf are bind-mounted by the Docker
# daemon during build, so lxc/build.sh replaces them after the export.
RUN set -euxo pipefail; \
    : > /etc/machine-id; \
    install -d -m 755 /var/lib/dbus; \
    ln -sfn /etc/machine-id /var/lib/dbus/machine-id; \
    rm -rf /run/* /run/.[!.]* /tmp/* /var/tmp/*; \
    install -d -m 755 /run/sshd /run/lock; \
    chmod 1777 /tmp /var/tmp; \
    rm -f /etc/ssh/ssh_host_*; \
    ls -l /etc/machine-id /sbin/init