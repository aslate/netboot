#!/usr/bin/env bash

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DISCOVERED_ROOT="$(cd -- "$SETUP_DIR/../.." && pwd)"
NETBOOT_ENV="$DISCOVERED_ROOT/config/netboot.env"
if [[ ! -r "$NETBOOT_ENV" ]]; then
    echo "Missing readable $NETBOOT_ENV" >&2
    return 1
fi
# shellcheck disable=SC1090
source "$NETBOOT_ENV"
: "${NETBOOT_PROJECT_ROOT:?Set NETBOOT_PROJECT_ROOT in config/netboot.env}"
: "${NETBOOT_INTERFACE:?Set NETBOOT_INTERFACE in config/netboot.env}"
: "${NETBOOT_SERVER_IP:?Set NETBOOT_SERVER_IP in config/netboot.env}"
: "${NETBOOT_SUBNET:?Set NETBOOT_SUBNET in config/netboot.env}"
PROJECT_ROOT=$NETBOOT_PROJECT_ROOT

require_project_location() {
    if [[ "$DISCOVERED_ROOT" != "$PROJECT_ROOT" ]]; then
        echo "This project is configured for $PROJECT_ROOT but is running from $DISCOVERED_ROOT." >&2
        echo "Move it to $PROJECT_ROOT, or adapt every hardcoded HTTP/TFTP path before setup." >&2
        return 1
    fi
}

detect_host_family() {
    local release_file=${NETBOOT_OS_RELEASE:-/etc/os-release}
    [[ -r "$release_file" ]] || { echo "Cannot read $release_file." >&2; return 1; }
    local ID='' ID_LIKE='' PRETTY_NAME='' candidate family=''
    # shellcheck disable=SC1090
    source "$release_file"
    case "$ID" in
        arch|cachyos) printf 'arch\n'; return 0 ;;
        fedora) printf 'fedora\n'; return 0 ;;
    esac
    local -a like_ids=()
    read -r -a like_ids <<< "$ID_LIKE"
    for candidate in "${like_ids[@]}"; do
        case "$candidate" in
            arch|cachyos) candidate=arch ;;
            fedora) ;;
            *) continue ;;
        esac
        if [[ -n "$family" && "$family" != "$candidate" ]]; then
            echo "Ambiguous ID_LIKE in $release_file: $ID_LIKE" >&2
            return 1
        fi
        family=$candidate
    done
    if [[ -z "$family" ]]; then
        echo "Unsupported host: ${PRETTY_NAME:-${ID:-unknown}}." >&2
        return 1
    fi
    printf '%s\n' "$family"
}

require_supported_host() {
    detect_host_family >/dev/null
}

require_arch_host() {
    local family
    family=$(detect_host_family) || return 1
    [[ "$family" == arch ]] || { echo "This installer requires Arch Linux or CachyOS." >&2; return 1; }
}

require_fedora_host() {
    local family
    family=$(detect_host_family) || return 1
    [[ "$family" == fedora ]] || { echo "This installer requires Fedora." >&2; return 1; }
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        sudo "$@"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        return 1
    }
}
