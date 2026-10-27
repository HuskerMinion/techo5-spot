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


if __name__ == '__main__':
    unittest.main()
