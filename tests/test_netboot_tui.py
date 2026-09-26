#!/usr/bin/env python3
import importlib.util
import struct
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "netboot-tui.py"
SPEC = importlib.util.spec_from_file_location("netboot_tui", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules["netboot_tui"] = MODULE
SPEC.loader.exec_module(MODULE)


class NetbootTuiTests(unittest.TestCase):
    def test_byte_ranges_ignore_retransmissions(self):
        ranges = MODULE.ByteRanges()
        self.assertEqual(ranges.add(0, 10), 10)
        self.assertEqual(ranges.add(0, 10), 0)
        self.assertEqual(ranges.add(10, 5), 5)
        self.assertEqual(ranges.total, 15)

    def test_dhcp_details_extracts_mac_and_message_type(self):
        payload = bytearray(240)
        payload[0] = 1
        payload[4:8] = struct.pack("!I", 0x12345678)
        payload[16:20] = bytes((192, 168, 1, 175))
        payload[28:34] = bytes.fromhex("001122334455")
        payload[236:244] = bytes.fromhex("63825363350101ff")
        details = MODULE.dhcp_details(bytes(payload))
        self.assertEqual(details["yiaddr"], "192.168.1.175")
        self.assertEqual(details["mac"], "00:11:22:33:44:55")
        self.assertEqual(details["message_type"], 1)

    def test_http_transfer_progress_and_completion(self):
        state = MODULE.MonitorState(Path("/tmp"), Path("/tmp"))
        observer = MODULE.PassiveObserver(state, "192.168.1.2", 80)
        request = b"GET /fedora-workstation/squashfs.img HTTP/1.1\r\nHost: 192.168.1.2\r\n\r\n"
        response = b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello world"
        header_end = response.index(b"\r\n\r\n") + 4
        observer.feed(MODULE.Packet(1, "192.168.1.175", "192.168.1.2", "tcp", 40000, 80, request, 100))
        self.assertEqual(len(state.transfers), 1)
        observer.feed(MODULE.Packet(2, "192.168.1.2", "192.168.1.175", "tcp", 80, 40000, response[:header_end], 200))
        active = next(iter(state.transfers.values()))
        self.assertEqual(active.total, 11)
        self.assertEqual(active.received, 0)
        observer.feed(MODULE.Packet(3, "192.168.1.2", "192.168.1.175", "tcp", 80, 40000, response[header_end:], 200 + header_end))
        self.assertEqual(len(state.transfers), 0)
        self.assertEqual(len(state.history), 1)
        self.assertEqual(state.history[0].state, "completed")
        self.assertEqual(state.history[0].received, 11)

    def test_tftp_transfer_uses_unique_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "ipxe.efi").write_bytes(b"x" * 700)
            state = MODULE.MonitorState(root, root)
            observer = MODULE.PassiveObserver(state, "192.168.1.2", 80)
            rrq = b"\x00\x01ipxe.efi\x00octet\x00"
            observer.feed(MODULE.Packet(1, "192.168.1.175", "192.168.1.2", "udp", 40000, 69, rrq))
            data = b"\x00\x03\x00\x01" + b"x" * 512
            observer.feed(MODULE.Packet(2, "192.168.1.2", "192.168.1.175", "udp", 50000, 40000, data))
            observer.feed(MODULE.Packet(3, "192.168.1.2", "192.168.1.175", "udp", 50000, 40000, data))
            final = b"\x00\x03\x00\x02" + b"x" * 188
            observer.feed(MODULE.Packet(4, "192.168.1.2", "192.168.1.175", "udp", 50000, 40000, final))
            self.assertEqual(len(state.transfers), 0)
            self.assertEqual(state.history[0].received, 700)

    def test_caddy_line_extracts_request_fields(self):
        line = '{"request":{"remote_ip":"192.168.1.175","uri":"/menu/main.ipxe?x=1"},"status":200,"size":42}'
        record = MODULE.parse_caddy_line(line)
        self.assertEqual(record["ip"], "192.168.1.175")
        self.assertEqual(record["path"], "/menu/main.ipxe")
        self.assertEqual(record["size"], 42)


if __name__ == "__main__":
    unittest.main()
