#!/usr/bin/env python3
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).parent / "scripts" / "netbootctl"


class NetbootCtlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "scripts"
        self.bin = self.root / "bin"
        self.scripts.mkdir()
        self.bin.mkdir()
        self.log = self.root / "commands.log"
        self.cli = self.scripts / "netbootctl"
        shutil.copy2(SOURCE, self.cli)
        self.write_executable(
            self.bin / "sudo",
            '#!/usr/bin/env bash\nprintf "sudo %s\\n" "$*" >> "$NETBOOTCTL_TEST_LOG"\nexec "$@"\n',
        )
        self.write_executable(
            self.bin / "systemctl",
            '#!/usr/bin/env bash\nprintf "systemctl %s\\n" "$*" >> "$NETBOOTCTL_TEST_LOG"\n'
            'if [[ $1 == is-active ]]; then echo active; fi\n',
        )
        self.write_executable(
            self.bin / "journalctl",
            '#!/usr/bin/env bash\nprintf "journalctl %s\\n" "$*" >> "$NETBOOTCTL_TEST_LOG"\n',
        )
        self.write_executable(
            self.scripts / "apply-netboot-config.sh",
            '#!/usr/bin/env bash\necho apply >> "$NETBOOTCTL_TEST_LOG"\n',
        )
        self.write_executable(
            self.scripts / "netboot-tui.py",
            '#!/usr/bin/env bash\nprintf "tui %s\\n" "$*" >> "$NETBOOTCTL_TEST_LOG"\n',
        )
        self.environment = os.environ.copy()
        self.environment["PATH"] = f"{self.bin}:{self.environment['PATH']}"
        self.environment["NETBOOTCTL_TEST_LOG"] = str(self.log)

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def write_executable(path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def run_cli(self, *arguments):
        return subprocess.run(
            [str(self.cli), *arguments],
            env=self.environment,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            check=False,
        )

    def commands(self, prefix):
        if not self.log.exists():
            return []
        return [line for line in self.log.read_text(encoding="utf-8").splitlines() if line.startswith(prefix)]

    def test_start_orders_caddy_before_dnsmasq_and_reports_state(self):
        result = self.run_cli("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.commands("systemctl"),
            [
                "systemctl start caddy.service",
                "systemctl start dnsmasq.service",
                "systemctl is-active caddy.service",
                "systemctl is-active dnsmasq.service",
            ],
        )
        self.assertIn("caddy.service", result.stdout)
        self.assertIn("dnsmasq.service", result.stdout)

    def test_stop_orders_dnsmasq_before_caddy(self):
        result = self.run_cli("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.commands("systemctl"),
            ["systemctl stop dnsmasq.service", "systemctl stop caddy.service"],
        )

    def test_reload_delegates_to_apply_script(self):
        result = self.run_cli("reload")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands("apply"), ["apply"])

    def test_logs_follow_both_units(self):
        result = self.run_cli("logs")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.commands("journalctl")
        self.assertEqual(len(command), 1)
        self.assertIn("-n 100 -f", command[0])
        self.assertIn("-u dnsmasq.service", command[0])
        self.assertIn("-u caddy.service", command[0])

    def test_tui_forwards_options(self):
        result = self.run_cli("tui", "--interface", "eth9", "--history", "25")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands("tui"), ["tui --interface eth9 --history 25"])

    def test_help_and_invalid_invocations(self):
        help_result = self.run_cli("--help")
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("start         Start Caddy and dnsmasq", help_result.stdout)

        unknown = self.run_cli("unknown")
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("unknown command", unknown.stderr)

        no_command = self.run_cli()
        self.assertEqual(no_command.returncode, 2)
        self.assertIn("command is required", no_command.stderr)


if __name__ == "__main__":
    unittest.main()
