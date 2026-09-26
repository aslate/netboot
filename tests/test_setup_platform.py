import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / 'scripts/setup'
SETUP_FILES = (
    '_common.sh',
    '10-install-packages.sh',
    '10-install-packages-arch.sh',
    '10-install-packages-fedora.sh',
    '20-install-ipxe-bootstrap.sh',
)


class PlatformSetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'netboot'
        setup = self.root / 'scripts/setup'
        setup.mkdir(parents=True)
        (self.root / 'config').mkdir()
        (self.root / 'tftp').mkdir()
        for name in SETUP_FILES:
            shutil.copy2(SOURCE / name, setup / name)
        (self.root / 'config/netboot.env').write_text(
            f'NETBOOT_PROJECT_ROOT={self.root}\n'
            'NETBOOT_INTERFACE=eth99\n'
            'NETBOOT_SERVER_IP=10.8.0.2\n'
            'NETBOOT_SUBNET=10.8.0.0/24\n'
        )
        self.os_release = self.root / 'os-release'
        self.log = self.root / 'calls.log'
        self.share = self.root / 'ipxe-share'
        (self.share / 'x86_64').mkdir(parents=True)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.executable('sudo', '#!/usr/bin/env bash\nexec "$@"\n')
        self.executable('pacman', '#!/usr/bin/env bash\nprintf "pacman %s\\n" "$*" >> "$NETBOOT_TEST_LOG"\n')
        self.executable('dnf', '''#!/usr/bin/env bash
printf 'dnf %s\\n' "$*" >> "$NETBOOT_TEST_LOG"
if [[ $1 == repoquery ]]; then
    for spec in "$@"; do
        case "$spec" in repoquery|--*) continue ;; esac
        [[ $spec == "${NETBOOT_TEST_MISSING:-}" ]] || printf '%s\\n' "$spec"
    done
fi
''')
        self.env = os.environ.copy()
        self.env.update({
            'PATH': f'{self.bin}:{self.env["PATH"]}',
            'NETBOOT_OS_RELEASE': str(self.os_release),
            'NETBOOT_IPXE_SHARE_DIR': str(self.share),
            'NETBOOT_TEST_LOG': str(self.log),
        })

    def executable(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def host(self, identifier, like=''):
        self.os_release.write_text(f'ID={identifier}\nID_LIKE="{like}"\n')

    def run_setup(self, name, **extra_env):
        return subprocess.run(
            [str(self.root / 'scripts/setup' / name)],
            env={**self.env, **extra_env},
            capture_output=True,
            text=True,
            check=False,
        )

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_fedora_dispatch_checks_all_packages_before_install(self):
        self.host('fedora')
        result = self.run_setup('10-install-packages.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[0].startswith('dnf repoquery --available '))
        self.assertTrue(calls[1].startswith('dnf install -y '))
        for package in ('bsdtar', 'ipxe-bootimgs-x86', 'policycoreutils-python-utils',
                        'libselinux-utils', 'unzip', 'xorriso', 'zstd', 'gzip'):
            self.assertIn(package, calls[1].split())

    def test_missing_fedora_provider_prevents_install(self):
        self.host('fedora')
        result = self.run_setup('10-install-packages.sh', NETBOOT_TEST_MISSING='xorriso')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing Fedora package provider: xorriso', result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_arch_and_id_like_dispatch(self):
        for identifier, like in (('arch', ''), ('cachyos', 'arch'), ('custom', 'arch')):
            with self.subTest(identifier=identifier):
                self.host(identifier, like)
                self.log.unlink(missing_ok=True)
                result = self.run_setup('10-install-packages.sh')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(self.calls()), 1)
                self.assertTrue(self.calls()[0].startswith('pacman -S --needed '))
                for package in ('unzip', 'xorriso', 'zstd', 'gzip'):
                    self.assertIn(package, self.calls()[0].split())
        self.host('custom', 'fedora')
        self.log.unlink(missing_ok=True)
        result = self.run_setup('10-install-packages.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.calls()[0].startswith('dnf repoquery '))

    def test_unsupported_and_ambiguous_hosts_do_not_mutate(self):
        for identifier, like in (('ubuntu', 'debian'), ('custom', 'arch fedora')):
            with self.subTest(identifier=identifier):
                self.host(identifier, like)
                self.log.unlink(missing_ok=True)
                result = self.run_setup('10-install-packages.sh')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_fedora_bootstrap_preserves_existing_and_prefers_supplied_bios(self):
        self.host('fedora')
        (self.share / 'ipxe-x86_64.efi').write_bytes(b'fedora-uefi')
        (self.share / 'undionly.kpxe').write_bytes(b'packaged-bios')
        (self.root / 'undionly.kpxe').write_bytes(b'supplied-bios')
        result = self.run_setup('20-install-ipxe-bootstrap.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'tftp/ipxe.efi').read_bytes(), b'fedora-uefi')
        self.assertEqual((self.root / 'tftp/undionly.kpxe').read_bytes(), b'supplied-bios')
        repeated = self.run_setup('20-install-ipxe-bootstrap.sh')
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(repeated.stdout.count('Unchanged iPXE bootstrap'), 2)
        (self.root / 'tftp/ipxe.efi').write_bytes(b'custom-uefi')
        rejected = self.run_setup('20-install-ipxe-bootstrap.sh')
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual((self.root / 'tftp/ipxe.efi').read_bytes(), b'custom-uefi')
        forced = self.run_setup('20-install-ipxe-bootstrap.sh', FORCE_IPXE='1')
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertEqual((self.root / 'tftp/ipxe.efi').read_bytes(), b'fedora-uefi')

    def test_arch_bootstrap_uses_packaged_bios_fallback(self):
        self.host('arch')
        (self.share / 'x86_64/ipxe.efi').write_bytes(b'arch-uefi')
        (self.share / 'x86_64/undionly.kpxe').write_bytes(b'arch-bios')
        result = self.run_setup('20-install-ipxe-bootstrap.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'tftp/ipxe.efi').read_bytes(), b'arch-uefi')
        self.assertEqual((self.root / 'tftp/undionly.kpxe').read_bytes(), b'arch-bios')

    def test_unsupported_bootstrap_does_not_write(self):
        self.host('ubuntu', 'debian')
        (self.share / 'ipxe-x86_64.efi').write_bytes(b'uefi')
        result = self.run_setup('20-install-ipxe-bootstrap.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((self.root / 'tftp').iterdir()), [])


if __name__ == '__main__':
    unittest.main()
