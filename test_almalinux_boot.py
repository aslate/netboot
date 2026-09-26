#!/usr/bin/env python3
import unittest
from pathlib import Path


ROOT = Path(__file__).parent


class AlmaLinuxBootRecipeTests(unittest.TestCase):
    def read(self, relative_path):
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def assert_grub_handoff(self, recipe):
        self.assertIn("imgfree", recipe)
        self.assertIn("chain ", recipe)
        self.assertNotIn("kernel ", recipe)
        self.assertNotIn("initrd ", recipe)

    def test_live_uses_direct_dracut_http_handoff(self):
        recipe = self.read("packages/almalinux-live/boot.ipxe")
        self.assert_grub_handoff(recipe)
        self.assertIn("/almalinux-live/grubx64.efi", recipe)

    def test_installer_uses_local_stage2_and_kickstart(self):
        recipe = self.read("packages/almalinux/boot.ipxe")
        self.assert_grub_handoff(recipe)
        self.assertIn("/boot/grub/x86_64-efi/core.efi", recipe)

    def test_kickstart_has_kde_repositories_and_dynamic_disk_policy(self):
        kickstart = self.read("packages/almalinux/alma10-server-gui.ks")
        for repository in ("appstream", "extras", "crb", "epel"):
            self.assertIn(f'repo --name="{repository}"', kickstart)
        self.assertIn("%pre --erroronfail", kickstart)
        self.assertIn("lsblk -dnpo NAME,TYPE,RM,RO", kickstart)
        self.assertIn("%include /tmp/alma10-storage.ks", kickstart)
        self.assertNotIn("--only-use=sda", kickstart)

if __name__ == "__main__":
    unittest.main()
