"""Checks of the slot store command sequence in install-spot.py (run: python tools/test_install_spot.py)."""
import importlib.util
import os
import sys
import unittest

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
spec = importlib.util.spec_from_file_location('install_spot', os.path.join(here, 'install-spot.py'))
spot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spot)
import techo5lib  # noqa: E402


class SlotStoreCommands(unittest.TestCase):
    def test_wifi_stack_is_stopped(self):
        for name in ('wpa_supplicant', 'udhcpc', 'dropbear', 'ntpd'):
            self.assertIn(name, spot.STOP_WIFI)
        self.assertIn('rmmod amzn_bcmdhd', spot.STOP_WIFI)
        self.assertTrue(spot.STOP_WIFI.endswith('true'))  # tolerant of "not running"
        self.assertIn(os.path.basename(spot.WIFI_MODULE).replace('-', '_')[:-3], spot.STOP_WIFI)

    def test_unmount_reports_both_ways(self):
        self.assertIn('umount /android', spot.UNMOUNT_ANDROID)
        self.assertIn('STILL-MOUNTED', spot.UNMOUNT_ANDROID)
        self.assertIn('echo UNMOUNTED', spot.UNMOUNT_ANDROID)

    def test_mkstore_syncs_before_ok(self):
        self.assertLess(spot.MKSTORE.index('mkstore'), spot.MKSTORE.index('sync'))
        self.assertLess(spot.MKSTORE.index('sync'), spot.MKSTORE.index('MKSTORE-OK'))

    def test_evidence_commands(self):
        # The restart evidence is techo5lib's, shared with the Show's installer.
        self.assertIn('console-ramoops*', techo5lib.EVIDENCE)
        self.assertIn('tail -100 /data/techo5-linux/rescue.log', techo5lib.EVIDENCE)
        self.assertIs(spot.collect_evidence, techo5lib.collect_evidence)


class Followups(unittest.TestCase):
    def test_lineage_kernel(self):
        self.assertIsNone(spot.lineage_kernel_problem('4.9.337-lineage\n','vermagic=4.9.337 SMP'))
        self.assertIsNone(spot.lineage_kernel_problem('4.9.337', ''))  # module unreadable: not held against it
        self.assertIn('4.9.113', spot.lineage_kernel_problem('4.9.113', ''))
        self.assertIsNone(spot.lineage_kernel_problem('', ''))  # nothing read: the console checks later
        self.assertIsNone(spot.lineage_kernel_problem('error: closed', ''))
        self.assertIn('4.14.1', spot.lineage_kernel_problem('4.9.337', 'vermagic=4.14.1 SMP'))

    def test_first_boot_state(self):
        f = spot.first_boot_state
        self.assertEqual(f('slot=a- daemon=123-'), 'running')
        self.assertEqual(f('slot=- daemon=-'), 'rescue')
        self.assertEqual(f('slot=a- daemon=-'), 'bad')
        self.assertEqual(f('slot=b- daemon=9-'), 'bad')
        self.assertEqual(f(None), 'gone')
        self.assertEqual(f(''), 'gone')

    def test_first_boot_probably_up(self):
        up = spot.first_boot_probably_up
        self.assertTrue(up(True, None))                   # slot a seen, then the console went quiet
        self.assertFalse(up(True, 'slot=a- daemon=-'))    # still answering: the daemon never started
        self.assertFalse(up(True, 'slot=- daemon=-'))     # back in rescue
        self.assertFalse(up(False, None))                 # slot a never seen


class GiftInstall(unittest.TestCase):
    def run_main(self, *argv):
        old = sys.argv
        sys.argv = ['install-spot.py'] + list(argv)
        try:
            spot.main()
        except techo5lib.Fail as e:
            return str(e)
        finally:
            sys.argv = old

    def test_cannot_be_combined_with_name_wifi_or_key(self):
        for extra in (['--name', 'Kitchen'], ['--wifi', 'Net'], ['--wifi-passphrase-file', 'p.txt'],
                      ['--key-file', 'k.key']):
            err = self.run_main('--for-someone-else', *extra)
            self.assertIn('--for-someone-else', err or '', extra)
            self.assertIn(extra[0], err, extra)

    def test_gift_writes_only_the_marker(self):
        files = dict(spot.provision_files(True, None, None, None, None))
        self.assertEqual(sorted(files), ['../../techo5-linux/wpa_supplicant.conf', 'firstrun'])
        self.assertEqual(files['firstrun'], '')
        # a configuration with no network, so LineageOS's saved ones are not imported at the first boot
        self.assertNotIn('network={', files['../../techo5-linux/wpa_supplicant.conf'])
        self.assertIn('ctrl_interface', files['../../techo5-linux/wpa_supplicant.conf'])

    def test_gift_still_takes_an_ssh_key(self):
        self.assertEqual(spot.provision_files(True, None, None, 'ssh-ed25519 AAAA', None),
                         [('firstrun', ''), ('../../techo5-linux/wpa_supplicant.conf', spot.EMPTY_WIFI_CONF),
                          ('ssh/authorized_keys', 'ssh-ed25519 AAAA\n')])

    def test_usual_install_writes_name_and_key_and_no_marker(self):
        files = spot.provision_files(False, 'Kitchen', 'KEY', None, None)
        self.assertEqual(files, [('name', 'Kitchen'), ('psk', 'KEY')])

    def test_gift_clears_an_earlier_name_key_and_network(self):
        with open(os.path.join(here, 'install-spot.py'), encoding='utf-8') as f:
            src = f.read()
        self.assertIn("rm -f /data/misc/techo5/name /data/misc/techo5/psk /data/techo5-linux/wifi.conf", src)

    def test_gift_needs_no_wifi_from_twrp(self):
        # without --for-someone-else, TWRP says --wifi is needed; with it, the check is skipped
        with open(os.path.join(here, 'install-spot.py'), encoding='utf-8') as f:
            self.assertIn("if not a.wifi and not gift:", f.read())


if __name__ == '__main__':
    unittest.main()
