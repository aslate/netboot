#!/usr/bin/env bash
set -euo pipefail

# Enable SSH in a running Fedora Live session and authorize the project key.
# Run locally from the live desktop or a TTY:
#   sudo bash enable-live-ssh.sh
#
# An alternate public-key file may be supplied as the first argument.

LIVE_USER="${LIVE_USER:-liveuser}"
DEFAULT_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1Uaj1C3AEh2tsLAsF6poXdD2GeCmIgG+SLljqPaLPj aslate@cachyos'
KEY_FILE="${1:-}"

[[ "$LIVE_USER" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || {
    echo "Invalid live-user name: $LIVE_USER" >&2
    exit 1
}

if (( EUID != 0 )); then
    exec sudo -- "$0" "$@"
fi

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

require_command getent
require_command install
require_command systemctl
require_command rpm

if ! getent passwd "$LIVE_USER" >/dev/null; then
    echo "User '$LIVE_USER' does not exist. Wait for the Fedora Live desktop to finish starting, then rerun this script." >&2
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1 || ! rpm -q openssh-server >/dev/null 2>&1; then
    if ! command -v dnf >/dev/null 2>&1; then
        echo "openssh-server is not installed and dnf is unavailable." >&2
        exit 1
    fi
    dnf -y install openssh-server
fi

require_command sshd
require_command ssh-keygen

if [[ -n "$KEY_FILE" ]]; then
    [[ -r "$KEY_FILE" ]] || {
        echo "Cannot read public-key file: $KEY_FILE" >&2
        exit 1
    }
    KEY_CONTENT="$(sed -n '1p' "$KEY_FILE")"
else
    KEY_CONTENT="$DEFAULT_KEY"
fi

[[ "$KEY_CONTENT" =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/]+={0,2}([[:space:]].*)?$ ]] || {
    echo "The supplied key is not a valid ssh-ed25519 public key." >&2
    exit 1
}

USER_HOME="$(getent passwd "$LIVE_USER" | awk -F: '{print $6}')"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || {
    echo "Home directory for '$LIVE_USER' was not found: $USER_HOME" >&2
    exit 1
}
USER_GROUP="$(id -gn "$LIVE_USER")"

SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
install -d -m 0700 -o "$LIVE_USER" -g "$USER_GROUP" "$SSH_DIR"
touch "$AUTHORIZED_KEYS"
grep -Fqx -- "$KEY_CONTENT" "$AUTHORIZED_KEYS" || printf '%s\n' "$KEY_CONTENT" >> "$AUTHORIZED_KEYS"
chown "$LIVE_USER:$USER_GROUP" "$AUTHORIZED_KEYS"
chmod 0600 "$AUTHORIZED_KEYS"

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/40-netboot-live.conf <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers $LIVE_USER
EOF

ssh-keygen -A
sshd -t
systemctl enable --now sshd.service

if command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld.service; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --add-service=ssh
    elif command -v firewall-offline-cmd >/dev/null 2>&1; then
        firewall-offline-cmd --add-service=ssh
    fi
fi

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF "$SSH_DIR" /etc/ssh/sshd_config.d
fi

echo "SSH is enabled for $LIVE_USER. Connect with: ssh $LIVE_USER@<live-system-ip>"
