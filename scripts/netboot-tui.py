#!/usr/bin/env python3
"""Passive PXE/liveboot monitor for the netboot server.

The monitor does not alter dnsmasq or Caddy.  It observes DHCP, TFTP, and
plaintext HTTP traffic on the selected interface, and enriches that stream
with the repository-local service logs. Progress is therefore best-effort: the
tool can only count bytes visible on the wire.
"""

from __future__ import annotations

import argparse
import curses
import json
import re
import socket
import struct
import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


DEFAULT_INTERFACE = ""
DEFAULT_HTTP_PORT = 80
DEFAULT_SERVER_IP = "0.0.0.0"
DEFAULT_TFTP_ROOT = Path("tftp")
DEFAULT_HTTP_ROOT = Path("http")


def load_netboot_env() -> dict[str, str]:
    """Read the repository env file as data, never as Python or shell code."""
    path = Path(__file__).resolve().parents[1] / "config" / "netboot.env"
    values: dict[str, str] = {}
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key.isidentifier() and key.isupper() and not any(token in value for token in ("$", "`", "(", ")")):
                values[key] = value
    except OSError:
        pass
    return values


NETBOOT_ENV = load_netboot_env()
DEFAULT_INTERFACE = NETBOOT_ENV.get("NETBOOT_INTERFACE", DEFAULT_INTERFACE)
DEFAULT_SERVER_IP = NETBOOT_ENV.get("NETBOOT_SERVER_IP", DEFAULT_SERVER_IP)
DEFAULT_HTTP_PORT = int(NETBOOT_ENV.get("NETBOOT_HTTP_PORT", DEFAULT_HTTP_PORT))
DEFAULT_TFTP_ROOT = Path(NETBOOT_ENV.get("NETBOOT_TFTP_ROOT", str(DEFAULT_TFTP_ROOT)))
DEFAULT_HTTP_ROOT = Path(NETBOOT_ENV.get("NETBOOT_HTTP_ROOT", str(DEFAULT_HTTP_ROOT)))


def now() -> float:
    return time.time()


def format_age(timestamp: float) -> str:
    delta = max(0, int(now() - timestamp))
    if delta < 60:
        return f"{delta}s"
    if delta < 3600:
        return f"{delta // 60}m"
    return f"{delta // 3600}h"


def format_bytes(value: Optional[int]) -> str:
    if value is None:
        return "?"
    units = ("B", "KiB", "MiB", "GiB")
    number = float(value)
    for unit in units:
        if number < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(number)} {unit}"
            return f"{number:.1f} {unit}"
        number /= 1024
    return f"{value} B"


def format_rate(value: Optional[float]) -> str:
    if value is None or value <= 0:
        return ""
    return f"{format_bytes(int(value))}/s"


def safe_text(value: Any, limit: int) -> str:
    text = str(value).replace("\n", " ").replace("\r", " ")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def ip_checksum_ok(packet: bytes) -> bool:
    if len(packet) < 20:
        return False
    length = (packet[0] & 0x0F) * 4
    if length < 20 or len(packet) < length:
        return False
    return sum(struct.unpack(f"!{length // 2}H", packet[:length])) & 0xFFFF == 0xFFFF


@dataclass
class Packet:
    timestamp: float
    src_ip: str
    dst_ip: str
    protocol: str
    src_port: Optional[int] = None
    dst_port: Optional[int] = None
    payload: bytes = b""
    seq: Optional[int] = None
    flags: int = 0
    raw: bytes = b""


def decode_packet(raw: bytes, timestamp: Optional[float] = None) -> Optional[Packet]:
    """Decode Ethernet/IPv4/TCP or UDP packets without third-party modules."""
    if len(raw) < 14:
        return None
    ethertype = struct.unpack("!H", raw[12:14])[0]
    offset = 14
    if ethertype in (0x8100, 0x88A8):
        if len(raw) < 18:
            return None
        ethertype = struct.unpack("!H", raw[16:18])[0]
        offset = 18
    if ethertype != 0x0800 or len(raw) < offset + 20:
        return None
    ip = raw[offset:]
    version = ip[0] >> 4
    ihl = (ip[0] & 0x0F) * 4
    if version != 4 or ihl < 20 or len(ip) < ihl:
        return None
    total_length = struct.unpack("!H", ip[2:4])[0]
    if total_length < ihl or len(ip) < total_length:
        return None
    protocol = ip[9]
    src_ip = socket.inet_ntoa(ip[12:16])
    dst_ip = socket.inet_ntoa(ip[16:20])
    body = ip[ihl:total_length]
    timestamp = timestamp if timestamp is not None else now()
    if protocol == socket.IPPROTO_UDP:
        if len(body) < 8:
            return None
        src_port, dst_port, length, _ = struct.unpack("!HHHH", body[:8])
        return Packet(timestamp, src_ip, dst_ip, "udp", src_port, dst_port, body[8:length])
    if protocol == socket.IPPROTO_TCP:
        if len(body) < 20:
            return None
        src_port, dst_port, seq, _, offset_flags, _ = struct.unpack("!HHIIHH", body[:16])
        tcp_header = (offset_flags >> 12) * 4
        if tcp_header < 20 or len(body) < tcp_header:
            return None
        return Packet(
            timestamp,
            src_ip,
            dst_ip,
            "tcp",
            src_port,
            dst_port,
            body[tcp_header:],
            seq,
            offset_flags & 0x01FF,
            raw,
        )
    return None


class ByteRanges:
    """Count unique TCP byte offsets, ignoring retransmissions."""

    def __init__(self) -> None:
        self.ranges: list[tuple[int, int]] = []

    def add(self, start: int, length: int) -> int:
        if length <= 0:
            return 0
        end = start + length
        before = self.total
        merged: list[tuple[int, int]] = []
        inserted = False
        for left, right in self.ranges:
            if right < start:
                merged.append((left, right))
            elif end < left:
                if not inserted:
                    merged.append((start, end))
                    inserted = True
                merged.append((left, right))
            else:
                start = min(start, left)
                end = max(end, right)
        if not inserted:
            merged.append((start, end))
        self.ranges = merged
        return self.total - before

    @property
    def total(self) -> int:
        return sum(right - left for left, right in self.ranges)


class TcpReassembler:
    def __init__(self) -> None:
        self.next_seq: Optional[int] = None
        self.pending: dict[int, bytes] = {}

    def feed(self, sequence: int, payload: bytes) -> bytes:
        if not payload:
            return b""
        if self.next_seq is None:
            self.next_seq = sequence
        if sequence < self.next_seq:
            trim = self.next_seq - sequence
            payload = payload[trim:]
            sequence = self.next_seq
        if payload:
            self.pending.setdefault(sequence, payload)
        output = bytearray()
        while self.next_seq in self.pending:
            chunk = self.pending.pop(self.next_seq)
            output.extend(chunk)
            self.next_seq += len(chunk)
        return bytes(output)


@dataclass
class Session:
    key: str
    client_ip: str
    mac: Optional[str] = None
    target: Optional[str] = None
    started: float = field(default_factory=now)
    last_seen: float = field(default_factory=now)
    phase: str = "PXE"


@dataclass
class Transfer:
    key: str
    session_key: str
    protocol: str
    path: str
    started: float = field(default_factory=now)
    updated: float = field(default_factory=now)
    total: Optional[int] = None
    received: int = 0
    state: str = "active"
    status: Optional[int] = None
    note: str = ""
    _ranges: ByteRanges = field(default_factory=ByteRanges, repr=False)

    def add_bytes(self, sequence: int, length: int) -> None:
        self.received += self._ranges.add(sequence, length)
        self.updated = now()

    @property
    def progress(self) -> Optional[float]:
        if self.total and self.total > 0:
            return min(1.0, self.received / self.total)
        return None


@dataclass
class Event:
    kind: str
    session_key: Optional[str] = None
    transfer_key: Optional[str] = None
    message: str = ""
    data: dict[str, Any] = field(default_factory=dict)


def normalize_mac(raw: bytes) -> Optional[str]:
    if not raw or raw == b"\x00" * len(raw):
        return None
    return ":".join(f"{byte:02x}" for byte in raw[:6])


def dhcp_details(payload: bytes) -> Optional[dict[str, Any]]:
    if len(payload) < 240 or payload[0] != 1:
        return None
    xid = struct.unpack("!I", payload[4:8])[0]
    yiaddr = socket.inet_ntoa(payload[16:20])
    mac = normalize_mac(payload[28:34])
    if payload[236:240] != b"\x63\x82\x53\x63":
        return None
    options = payload[240:]
    values: dict[int, bytes] = {}
    index = 0
    while index < len(options):
        option = options[index]
        index += 1
        if option == 255:
            break
        if option == 0:
            continue
        if index >= len(options):
            break
        length = options[index]
        index += 1
        values[option] = options[index : index + length]
        index += length
    message_type = values.get(53, b"\x00")[:1]
    return {
        "xid": xid,
        "yiaddr": yiaddr,
        "mac": mac,
        "message_type": message_type[0] if message_type else 0,
        "vendor_class": values.get(60, b"").decode(errors="replace"),
        "user_class": values.get(77, b"").decode(errors="replace"),
    }


def parse_dnsmasq_line(line: str) -> Optional[dict[str, str]]:
    match = re.search(r"DHCP(?:DISCOVER|REQUEST|ACK|OFFER|NAK).*?(?:from|on)\s+([0-9a-f:]{17})", line, re.I)
    if match:
        return {"mac": match.group(1).lower(), "message": line.strip()}
    match = re.search(r"DHCP(?:ACK|OFFER).*?([0-9.]+)", line, re.I)
    if match:
        return {"ip": match.group(1), "message": line.strip()}
    if re.search(r"PXE|BOOT|iPXE", line, re.I):
        return {"message": line.strip()}
    return None


def parse_caddy_line(line: str) -> Optional[dict[str, Any]]:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    request = value.get("request") or {}
    remote = request.get("remote_ip") or request.get("remote")
    if isinstance(remote, str) and ":" in remote and remote.count(":") == 1:
        remote = remote.rsplit(":", 1)[0]
    uri = request.get("uri") or request.get("path") or "/"
    status = value.get("status")
    size = value.get("size")
    return {"ip": remote, "path": uri.split("?", 1)[0], "status": status, "size": size}


class MonitorState:
    def __init__(self, tftp_root: Path, http_root: Path, history_limit: int = 100) -> None:
        self.tftp_root = tftp_root
        self.http_root = http_root
        self.history_limit = history_limit
        self.sessions: OrderedDict[str, Session] = OrderedDict()
        self.transfers: OrderedDict[str, Transfer] = OrderedDict()
        self.history: deque[Transfer] = deque(maxlen=history_limit)
        self.log: deque[tuple[float, str]] = deque(maxlen=history_limit)
        self.warnings: deque[str] = deque(maxlen=5)
        self.http_flows: dict[tuple[str, int, str, int], HttpFlow] = {}
        self.tftp_requests: dict[tuple[str, int, str], Transfer] = {}
        self.tftp_blocks: dict[str, set[int]] = {}
        self.mac_by_ip: dict[str, str] = {}
        self.lock = threading.Lock()

    def emit(self, event: Event) -> None:
        with self.lock:
            if event.kind == "warning":
                self.warnings.append(event.message)
                self._log(f"! {event.message}")
            elif event.kind == "session":
                self._session(event.data.get("ip"), event.data.get("mac"), event.message)
            elif event.kind == "transfer_start":
                self._start_transfer(event)
            elif event.kind == "transfer_update":
                transfer = self.transfers.get(event.transfer_key or "")
                if transfer:
                    if event.data.get("total") is not None:
                        transfer.total = int(event.data["total"])
                    if event.data.get("received") is not None:
                        transfer.received = max(transfer.received, int(event.data["received"]))
                    transfer.updated = now()
            elif event.kind == "transfer_complete":
                self._complete_transfer(event)
            elif event.kind == "journal":
                self._log(event.message)

    def _session(self, ip: Optional[str], mac: Optional[str], message: str) -> Session:
        ip = ip or "unknown"
        key = mac or ip
        session = self.sessions.get(key)
        if session is None:
            session = Session(key, ip, mac)
            self.sessions[key] = session
            self._log(f"{ip}  session started" + (f"  {mac}" if mac else ""))
        else:
            session.last_seen = now()
            if ip != "unknown":
                session.client_ip = ip
            if mac:
                session.mac = mac
        if mac:
            self.mac_by_ip[ip] = mac
        if message:
            self._log(f"{ip}  {safe_text(message, 100)}")
        return session

    def session_for_ip(self, ip: str) -> Session:
        return self._session(ip, self.mac_by_ip.get(ip), "")

    def _start_transfer(self, event: Event) -> None:
        key = event.transfer_key or f"{event.data.get('protocol')}:{event.data.get('path')}:{now()}"
        if key in self.transfers:
            return
        ip = event.data.get("ip") or "unknown"
        session = self.session_for_ip(ip)
        transfer = Transfer(
            key,
            session.key,
            event.data.get("protocol", "HTTP"),
            event.data.get("path", "/"),
            total=event.data.get("total"),
        )
        self.transfers[key] = transfer
        session.phase = "transferring"
        session.last_seen = now()
        target = self.target_from_path(transfer.path)
        if target:
            session.target = target
        self._log(f"{ip}  → {transfer.path}")

    def _complete_transfer(self, event: Event) -> None:
        transfer = self.transfers.get(event.transfer_key or "")
        if transfer is None:
            return
        transfer.state = "completed" if event.data.get("status", 200) < 400 else "failed"
        transfer.status = event.data.get("status")
        if event.data.get("total") is not None:
            transfer.total = int(event.data["total"])
        if transfer.total is not None:
            transfer.received = max(transfer.received, transfer.total)
        transfer.updated = now()
        self.history.append(transfer)
        self.transfers.pop(transfer.key, None)
        marker = "✓" if transfer.state == "completed" else "✗"
        self._log(f"{marker} {transfer.path}  {format_bytes(transfer.received)}")

    def complete_by_path(self, ip: Optional[str], path: str, status: int = 200, size: Optional[int] = None) -> None:
        candidates = [
            transfer
            for transfer in self.transfers.values()
            if transfer.path == path and (not ip or self.sessions.get(transfer.session_key, Session("", "")).client_ip == ip)
        ]
        if candidates:
            transfer = max(candidates, key=lambda item: item.started)
            self.emit(Event("transfer_complete", transfer_key=transfer.key, data={"status": status, "total": size}))
            return
        if ip and path.startswith("/"):
            session = self.session_for_ip(ip)
            key = f"journal:{ip}:{path}:{now()}"
            self._start_transfer(Event("transfer_start", transfer_key=key, data={"ip": ip, "protocol": "HTTP", "path": path, "total": size}))
            self.emit(Event("transfer_complete", transfer_key=key, data={"status": status, "total": size}))

    def target_from_path(self, path: str) -> Optional[str]:
        parts = path.strip("/").split("/")
        if len(parts) >= 2 and parts[1] in {"boot.ipxe", "main.ipxe"}:
            return parts[0]
        if parts and parts[0] == "menu":
            return "menu"
        return None

    def _log(self, message: str) -> None:
        self.log.append((now(), safe_text(message, 160)))


class HttpFlow:
    def __init__(self, state: MonitorState, key: tuple[str, int, str, int], client_ip: str) -> None:
        self.state = state
        self.key = key
        self.client_ip = client_ip
        self.request_reassembler = TcpReassembler()
        self.response_reassembler = TcpReassembler()
        self.request_buffer = bytearray()
        self.response_buffer = bytearray()
        self.requests: deque[tuple[str, str]] = deque()
        self.current: Optional[Transfer] = None
        self.counter = 0

    def feed(self, packet: Packet, server_to_client: bool) -> None:
        if server_to_client:
            chunk = self.response_reassembler.feed(packet.seq or 0, packet.payload)
            if chunk:
                self.response_buffer.extend(chunk)
                self._parse_responses()
            return
        chunk = self.request_reassembler.feed(packet.seq or 0, packet.payload)
        if chunk:
            self.request_buffer.extend(chunk)
            self._parse_requests()

    def _parse_requests(self) -> None:
        while b"\r\n\r\n" in self.request_buffer:
            raw, remainder = self.request_buffer.split(b"\r\n\r\n", 1)
            self.request_buffer = bytearray(remainder)
            lines = raw.decode("iso-8859-1", errors="replace").split("\r\n")
            if not lines:
                continue
            match = re.match(r"(?:GET|HEAD)\s+(\S+)\s+HTTP/", lines[0])
            if not match:
                continue
            method = lines[0].split(" ", 1)[0]
            path = match.group(1).split("?", 1)[0]
            key = f"http:{self.client_ip}:{self.counter}:{path}"
            self.counter += 1
            event = Event(
                "transfer_start",
                transfer_key=key,
                data={"ip": self.client_ip, "protocol": "HTTP", "path": path},
            )
            self.state.emit(event)
            self.requests.append((key, method))

    def _parse_responses(self) -> None:
        while True:
            if self.current is None:
                if b"\r\n\r\n" not in self.response_buffer or not self.requests:
                    return
                raw, remainder = self.response_buffer.split(b"\r\n\r\n", 1)
                self.response_buffer = bytearray(remainder)
                lines = raw.decode("iso-8859-1", errors="replace").split("\r\n")
                status = 0
                if lines:
                    status_match = re.match(r"HTTP/\d(?:\.\d)?\s+(\d+)", lines[0])
                    if status_match:
                        status = int(status_match.group(1))
                headers: dict[str, str] = {}
                for line in lines[1:]:
                    if ":" in line:
                        name, value = line.split(":", 1)
                        headers[name.lower()] = value.strip()
                transfer_key, method = self.requests.popleft()
                transfer = self.state.transfers.get(transfer_key)
                if transfer is None:
                    continue
                total = int(headers["content-length"]) if headers.get("content-length", "").isdigit() else None
                transfer.total = total
                transfer.status = status
                self.current = transfer
                if method == "HEAD" or status in (204, 304) or status >= 400:
                    self.state.emit(Event("transfer_complete", transfer_key=transfer.key, data={"status": status, "total": total or 0}))
                    self.current = None
                    continue
            if self.current is None:
                continue
            transfer = self.current
            if transfer.total is None:
                if b"\r\n\r\n" in self.response_buffer:
                    continue
                return
            needed = max(0, transfer.total - transfer.received)
            if needed:
                consumed = min(needed, len(self.response_buffer))
                if consumed:
                    transfer.add_bytes(transfer.received, consumed)
                    del self.response_buffer[:consumed]
                    self.state.emit(Event("transfer_update", transfer_key=transfer.key, data={"received": transfer.received, "total": transfer.total}))
            if transfer.received >= transfer.total:
                self.state.emit(Event("transfer_complete", transfer_key=transfer.key, data={"status": transfer.status or 200, "total": transfer.total}))
                self.current = None
                continue
            return


class PassiveObserver:
    def __init__(self, state: MonitorState, server_ip: str, http_port: int) -> None:
        self.state = state
        self.server_ip = server_ip
        self.http_port = http_port

    def feed(self, packet: Packet) -> None:
        if packet.protocol == "udp":
            self._udp(packet)
        elif packet.protocol == "tcp" and self.http_port in (packet.src_port, packet.dst_port):
            self._http(packet)

    def _udp(self, packet: Packet) -> None:
        if packet.src_port in (67, 68) or packet.dst_port in (67, 68):
            details = dhcp_details(packet.payload)
            if details:
                ip = details["yiaddr"] if details["yiaddr"] != "0.0.0.0" else packet.src_ip
                self.state.emit(Event("session", data={"ip": ip, "mac": details["mac"]}, message="DHCP/PXE activity"))
            return
        if packet.dst_port == 69 and packet.payload[:2] == b"\x00\x01":
            parts = packet.payload[2:].split(b"\x00")
            if not parts:
                return
            path = parts[0].decode("utf-8", errors="replace")
            safe_path = Path(path.lstrip("/"))
            if ".." in safe_path.parts:
                return
            total = self._file_size(self.state.tftp_root / safe_path)
            transfer_key = f"tftp:{packet.src_ip}:{packet.src_port}:{path}"
            self.state.tftp_requests[(packet.src_ip, packet.src_port or 0, packet.dst_ip)] = self._make_transfer(
                transfer_key, packet.src_ip, "TFTP", path, total
            )
            self.state.tftp_blocks[transfer_key] = set()
            return
        if packet.src_port and packet.src_port >= 1024 and packet.payload[:2] == b"\x00\x03":
            transfer = self.state.tftp_requests.get((packet.dst_ip, packet.dst_port or 0, packet.src_ip))
            if transfer is None:
                return
            block_number = struct.unpack("!H", packet.payload[2:4])[0] if len(packet.payload) >= 4 else 0
            blocks = self.state.tftp_blocks.setdefault(transfer.key, set())
            if block_number in blocks:
                return
            blocks.add(block_number)
            data = packet.payload[4:]
            if data:
                transfer.add_bytes(transfer.received, len(data))
            if len(data) < 512:
                self.state.emit(Event("transfer_complete", transfer_key=transfer.key, data={"status": 200, "total": transfer.total or transfer.received}))
                self.state.tftp_requests.pop((packet.dst_ip, packet.dst_port or 0, packet.src_ip), None)

    def _make_transfer(self, key: str, ip: str, protocol: str, path: str, total: Optional[int]) -> Transfer:
        self.state.emit(Event("transfer_start", transfer_key=key, data={"ip": ip, "protocol": protocol, "path": path, "total": total}))
        transfer = self.state.transfers[key]
        return transfer

    def _http(self, packet: Packet) -> None:
        if packet.src_port == self.http_port:
            client_ip, client_port = packet.dst_ip, packet.dst_port or 0
            key = (packet.dst_ip, client_port, packet.src_ip, packet.src_port or 0)
            server_to_client = True
        else:
            client_ip, client_port = packet.src_ip, packet.src_port or 0
            key = (client_ip, client_port, packet.dst_ip, packet.dst_port or 0)
            server_to_client = False
        flow = self.state.http_flows.get(key)
        if flow is None:
            flow = HttpFlow(self.state, key, client_ip)
            self.state.http_flows[key] = flow
        self.state.session_for_ip(client_ip)
        flow.feed(packet, server_to_client)

    @staticmethod
    def _file_size(path: Path) -> Optional[int]:
        try:
            return path.stat().st_size if path.is_file() else None
        except OSError:
            return None


def packet_capture(interface: str, observer: PassiveObserver, stop: threading.Event, emit: Any) -> None:
    try:
        capture = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
        capture.bind((interface, 0))
        capture.settimeout(1.0)
    except (PermissionError, OSError) as error:
        emit(Event("warning", message=f"packet capture unavailable: {error}"))
        return
    emit(Event("journal", message=f"capturing DHCP/TFTP/HTTP on {interface}"))
    with capture:
        while not stop.is_set():
            try:
                raw = capture.recv(65535)
            except socket.timeout:
                continue
            except OSError as error:
                emit(Event("warning", message=f"packet capture stopped: {error}"))
                return
            packet = decode_packet(raw)
            if packet:
                observer.feed(packet)


def log_tail(label: str, path: Path, state: MonitorState, stop: threading.Event) -> None:
    try:
        handle = path.open("r", encoding="utf-8", errors="replace")
        handle.seek(0, 2)
    except OSError as error:
        state.emit(Event("warning", message=f"{label} log unavailable: {error}"))
        return
    try:
        while not stop.is_set():
            line = handle.readline()
            if not line:
                time.sleep(0.1)
                continue
            line = line.strip()
            if label == "caddy":
                record = parse_caddy_line(line)
                if record and record.get("path"):
                    state.complete_by_path(record.get("ip"), record["path"], int(record.get("status") or 200), record.get("size"))
            else:
                record = parse_dnsmasq_line(line)
                if record:
                    state.emit(Event("session", data={"ip": record.get("ip"), "mac": record.get("mac")}, message=record["message"]))
    finally:
        handle.close()


def draw_bar(width: int, progress: Optional[float], active: bool) -> str:
    width = max(4, width)
    if progress is None:
        glyphs = "▰▱" if active else "··"
        offset = int(now() * 4) % width if active else 0
        return "".join(glyphs[(index + offset) % 2] for index in range(width))
    filled = max(0, min(width, int(progress * width)))
    return "█" * filled + "░" * (width - filled)


def render(stdscr: Any, state: MonitorState, stop: threading.Event, refresh: float) -> None:
    curses.curs_set(0)
    stdscr.nodelay(True)
    while not stop.is_set():
        try:
            key = stdscr.getch()
            if key in (ord("q"), ord("Q"), 27):
                stop.set()
                break
        except curses.error:
            pass
        with state.lock:
            height, width = stdscr.getmaxyx()
            stdscr.erase()
            title = "NETBOOT VISIBILITY  (q quit)"
            stdscr.addnstr(0, 0, title, max(0, width - 1), curses.A_BOLD)
            stdscr.addnstr(1, 0, "PASSIVE / BEST-EFFORT — byte counts are observed on the wire", max(0, width - 1))
            line = 3
            sessions = list(state.sessions.values())[-6:]
            stdscr.addnstr(line, 0, "SESSIONS", max(0, width - 1), curses.A_BOLD)
            line += 1
            if not sessions:
                stdscr.addnstr(line, 0, "  waiting for PXE/DHCP activity", max(0, width - 1))
                line += 1
            for session in sessions:
                label = f"  {session.client_ip:<15} {session.mac or 'MAC unknown':17} {session.phase:<13} {session.target or '-':16} {format_age(session.started)}"
                stdscr.addnstr(line, 0, label, max(0, width - 1))
                line += 1
            line += 1
            stdscr.addnstr(line, 0, "ACTIVE TRANSFERS", max(0, width - 1), curses.A_BOLD)
            line += 1
            active = list(state.transfers.values())
            if not active:
                stdscr.addnstr(line, 0, "  none", max(0, width - 1))
                line += 1
            bar_width = max(8, min(28, width // 4))
            for transfer in active[-8:]:
                percent = f"{transfer.progress * 100:5.1f}%" if transfer.progress is not None else "  ..."
                label = f"  {transfer.protocol:<4} {percent} {draw_bar(bar_width, transfer.progress, True)} {format_bytes(transfer.received)}/{format_bytes(transfer.total):<18} {safe_text(transfer.path, max(10, width - bar_width - 45))}"
                stdscr.addnstr(line, 0, label, max(0, width - 1))
                line += 1
            line += 1
            if line < height - 1:
                stdscr.addnstr(line, 0, "TRANSFER LOG", max(0, width - 1), curses.A_BOLD)
                line += 1
            for timestamp, message in list(state.log)[-(height - line - 1) :]:
                stamp = datetime.fromtimestamp(timestamp, timezone.utc).strftime("%H:%M:%S")
                stdscr.addnstr(line, 0, f"{stamp} {message}", max(0, width - 1))
                line += 1
            if state.warnings and height > 2:
                warning = " | ".join(state.warnings)
                stdscr.addnstr(height - 1, 0, safe_text(warning, width - 1), max(0, width - 1), curses.A_REVERSE)
            stdscr.refresh()
        time.sleep(refresh)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", default=DEFAULT_INTERFACE)
    parser.add_argument("--server-ip", default=DEFAULT_SERVER_IP)
    parser.add_argument("--http-port", type=int, default=DEFAULT_HTTP_PORT)
    parser.add_argument("--tftp-root", type=Path, default=DEFAULT_TFTP_ROOT)
    parser.add_argument("--http-root", type=Path, default=DEFAULT_HTTP_ROOT)
    parser.add_argument("--history", type=int, default=100)
    parser.add_argument("--refresh", type=float, default=0.2)
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    state = MonitorState(args.tftp_root, args.http_root, max(10, args.history))
    observer = PassiveObserver(state, args.server_ip, args.http_port)
    stop = threading.Event()
    threads = [
        threading.Thread(target=packet_capture, args=(args.interface, observer, stop, state.emit), daemon=True),
        threading.Thread(target=log_tail, args=("dnsmasq", Path(NETBOOT_ENV.get("NETBOOT_DNSMASQ_LOG", ".runtime/logs/dnsmasq.log")), state, stop), daemon=True),
        threading.Thread(target=log_tail, args=("caddy", Path(NETBOOT_ENV.get("NETBOOT_CADDY_LOG", ".runtime/logs/caddy.log")), state, stop), daemon=True),
    ]
    for thread in threads:
        thread.start()
    try:
        curses.wrapper(lambda stdscr: render(stdscr, state, stop, max(0.05, args.refresh)))
    except KeyboardInterrupt:
        stop.set()
    finally:
        stop.set()
        for thread in threads:
            thread.join(timeout=1.5)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
