#!/usr/bin/env python3
"""Render repository-local service configuration without executing templates."""

from __future__ import annotations

import os
import re
import tempfile
import ipaddress
from pathlib import Path


ASSIGNMENT = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
PLACEHOLDER = re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}")
REQUIRED = {
    "NETBOOT_INTERFACE",
    "NETBOOT_SERVER_IP",
    "NETBOOT_SUBNET",
    "NETBOOT_DHCP_PROXY_RANGE",
    "NETBOOT_DHCP_MODE",
    "NETBOOT_DNSMASQ_PORT",
    "NETBOOT_HTTP_PORT",
    "NETBOOT_HTTP_ROOT",
    "NETBOOT_TFTP_ROOT",
    "NETBOOT_UEFI_BOOTSTRAP",
    "NETBOOT_BIOS_BOOTSTRAP",
    "NETBOOT_IPXE_MENU_URL",
}


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match:
            raise ValueError(f"invalid config line {number}: {raw}")
        key, value = match.groups()
        if value.startswith(('"', "'")) or any(char in value for char in "`$()"):
            raise ValueError(f"shell syntax is not permitted in {key}")
        values[key] = value
    missing = sorted(REQUIRED - values.keys())
    if missing:
        raise ValueError("missing required variables: " + ", ".join(missing))
    return values


def render(template: Path, destination: Path, values: dict[str, str]) -> None:
    source = template.read_text(encoding="utf-8")

    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in values:
            raise ValueError(f"unknown or unset placeholder {key} in {template}")
        return values[key]

    output = PLACEHOLDER.sub(replace, source)
    unresolved = PLACEHOLDER.findall(output)
    if unresolved:
        raise ValueError(f"unresolved placeholders in {template}: {unresolved}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(output)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def dhcp_values(values: dict[str, str]) -> dict[str, str]:
    mode = os.environ.get("NETBOOT_DHCP_MODE_OVERRIDE") or values["NETBOOT_DHCP_MODE"]
    if mode not in {"proxy", "server"}:
        raise ValueError("NETBOOT_DHCP_MODE must be proxy or server")
    values = dict(values)
    values["NETBOOT_DHCP_MODE"] = mode
    if mode == "proxy":
        values["NETBOOT_DHCP_RANGE_LINE"] = f"dhcp-range={values['NETBOOT_DHCP_PROXY_RANGE']},proxy"
        values["NETBOOT_DHCP_OPTIONS"] = ""
        return values

    required = {
        "NETBOOT_DHCP_RANGE_START",
        "NETBOOT_DHCP_RANGE_END",
        "NETBOOT_DHCP_LEASE_TIME",
        "NETBOOT_DHCP_GATEWAY",
        "NETBOOT_DHCP_DNS",
        "NETBOOT_DHCP_LEASE_FILE",
    }
    missing = sorted(key for key in required if not values.get(key))
    if missing:
        raise ValueError("server DHCP mode is missing: " + ", ".join(missing))
    network = ipaddress.ip_network(values["NETBOOT_SUBNET"], strict=False)
    start = ipaddress.ip_address(values["NETBOOT_DHCP_RANGE_START"])
    end = ipaddress.ip_address(values["NETBOOT_DHCP_RANGE_END"])
    server = ipaddress.ip_address(values["NETBOOT_SERVER_IP"])
    gateway = ipaddress.ip_address(values["NETBOOT_DHCP_GATEWAY"])
    if not (start in network and end in network and start <= end):
        raise ValueError("server DHCP range must be ordered and inside NETBOOT_SUBNET")
    if server >= start and server <= end:
        raise ValueError("server DHCP range must not include NETBOOT_SERVER_IP")
    if gateway not in network:
        raise ValueError("NETBOOT_DHCP_GATEWAY must be inside NETBOOT_SUBNET")
    values["NETBOOT_DHCP_RANGE_LINE"] = (
        f"dhcp-range={start},{end},{network.netmask},{values['NETBOOT_DHCP_LEASE_TIME']}"
    )
    values["NETBOOT_DHCP_OPTIONS"] = "\n".join(
        (
            f"dhcp-option=option:router,{values['NETBOOT_DHCP_GATEWAY']}",
            f"dhcp-option=option:dns-server,{values['NETBOOT_DHCP_DNS']}",
            "dhcp-authoritative",
            f"dhcp-leasefile={values['NETBOOT_DHCP_LEASE_FILE']}",
        )
    )
    return values


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    env_path = root / "config" / "netboot.env"
    try:
        values = dhcp_values(read_env(env_path))
        generated = root / ".runtime" / "generated"
        render(root / "config" / "dnsmasq.conf", generated / "dnsmasq.conf", values)
        if values["NETBOOT_DHCP_MODE"] == "server":
            print("WARNING: authoritative DHCP mode is enabled; disable every other DHCP server on this LAN.", file=os.sys.stderr)
        render(root / "config" / "Caddyfile", generated / "Caddyfile", values)
    except (OSError, ValueError) as error:
        print(f"render-netboot-config: {error}", file=os.sys.stderr)
        return 1
    print(f"Rendered service configuration under {generated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
