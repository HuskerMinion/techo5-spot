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
        self.assertIn('console-ramoops*', spot.EVIDENCE)
        self.assertIn('tail -100 /data/techo5-linux/rescue.log', spot.EVIDENCE)


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


if __name__ == '__main__':
    unittest.main()
