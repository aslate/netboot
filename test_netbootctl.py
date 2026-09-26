#!/usr/bin/env python3
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).parent / "scripts" / "netbootctl"
RENDERER = Path(__file__).parent / "scripts" / "render-netboot-config.py"


class NetbootCtlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "scripts"
        self.config = self.root / "config"
        self.scripts.mkdir()
        self.config.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.cli = self.scripts / "netbootctl"
        shutil.copy2(SOURCE, self.cli)
        shutil.copy2(RENDERER, self.scripts / "render-netboot-config.py")
        runtime = self.root / ".runtime"
        (self.config / "netboot.env").write_text(
            f"NETBOOT_PROJECT_ROOT={self.root}\n"
            "NETBOOT_INTERFACE=eth99\nNETBOOT_SERVER_IP=10.8.0.2\n"
            "NETBOOT_SUBNET=10.8.0.0/24\nNETBOOT_DHCP_PROXY_RANGE=10.8.0.0\n"
            "NETBOOT_DNSMASQ_PORT=0\nNETBOOT_HTTP_PORT=8080\n"
            f"NETBOOT_HTTP_ROOT={self.root / 'http'}\nNETBOOT_TFTP_ROOT={self.root / 'tftp'}\n"
            f"NETBOOT_RUNTIME_ROOT={runtime}\nNETBOOT_GENERATED_ROOT={runtime / 'generated'}\n"
            f"NETBOOT_LOG_ROOT={runtime / 'logs'}\nNETBOOT_UEFI_BOOTSTRAP=ipxe.efi\n"
            "NETBOOT_BIOS_BOOTSTRAP=undionly.kpxe\n"
            "NETBOOT_IPXE_MENU_URL=http://10.8.0.2/menu/main.ipxe\n"
            f"NETBOOT_DNSMASQ_CONFIG_SOURCE={self.config / 'dnsmasq.conf'}\n"
            f"NETBOOT_CADDY_CONFIG_SOURCE={self.config / 'Caddyfile'}\n"
            f"NETBOOT_DNSMASQ_CONFIG_RUNTIME={runtime / 'generated/dnsmasq.conf'}\n"
            f"NETBOOT_CADDY_CONFIG_RUNTIME={runtime / 'generated/Caddyfile'}\n"
            f"NETBOOT_DNSMASQ_PIDFILE={runtime / 'dnsmasq.pid'}\nNETBOOT_CADDY_PIDFILE={runtime / 'caddy.pid'}\n"
            f"NETBOOT_DNSMASQ_LOG={runtime / 'logs/dnsmasq.log'}\nNETBOOT_CADDY_LOG={runtime / 'logs/caddy.log'}\n"
            "NETBOOT_DNSMASQ_EXECUTABLE=dnsmasq\nNETBOOT_CADDY_EXECUTABLE=caddy\n"
        )
        (self.config / "dnsmasq.conf").write_text("interface=${NETBOOT_INTERFACE}\n")
        (self.config / "Caddyfile").write_text(":${NETBOOT_HTTP_PORT} { root * ${NETBOOT_HTTP_ROOT} }\n")
        self.environment = os.environ.copy()
        self.environment["PATH"] = f"{self.bin}:{self.environment['PATH']}"

    def tearDown(self):
        self.temporary.cleanup()

    def run_cli(self, *arguments):
        return subprocess.run([str(self.cli), *arguments], env=self.environment, capture_output=True, text=True, check=False)

    def test_help_and_invalid_invocations(self):
        result = self.run_cli("help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("standalone daemons", result.stdout)
        unknown = self.run_cli("unknown")
        self.assertEqual(unknown.returncode, 2)

    def test_render_uses_central_configuration(self):
        result = self.run_cli("render")
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = self.root / ".runtime/generated"
        self.assertIn("interface=eth99", (generated / "dnsmasq.conf").read_text())
        self.assertIn(":8080", (generated / "Caddyfile").read_text())

    def test_status_rejects_missing_records(self):
        result = self.run_cli("status")
        self.assertEqual(result.returncode, 0)
        self.assertIn("caddy    stopped", result.stdout)
        self.assertIn("dnsmasq  stopped", result.stdout)


if __name__ == "__main__":
    unittest.main()
