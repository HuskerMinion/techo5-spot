#!/usr/bin/env python3
"""Back up every partition that boots an Echo Spot (rook) to this computer, each copy checked against an
md5 read on the device. Writes nothing to the unit.

    python3 tools/backup-spot.py --serial <serial>
    python3 tools/backup-spot.py --serial <serial> --include-system

Run it with the unit in TWRP (where amonet-rook leaves it), or in Fire OS or LineageOS with adb as root.
Windows, Linux and macOS alike; needs Python 3 and adb.

What it copies:
  - the GPT (the first 34 sectors of the eMMC), for amonet's gpt-fix and for comparing layouts
  - the preloader (eMMC boot area, mmcblk0boot0)
  - the bootloader, TEE, factory and boot partitions: lk, tee1, tee2, expdb, MISC, logo, para, kb, dkb,
    nvram, proinfo, seccfg, persistbackup, frp, persist, metadata, boot, recovery
  - with --include-system, also system and cache (large; userdata is never copied)

A partition name the unit does not have is reported and skipped. An existing backup is never
overwritten: a partition that changed since (MISC does on every boot) is saved beside it with a
timestamp. Every copy is written to a .partial file first and kept only when its md5 matches the device.
Keep backups/<serial> safe and off GitHub: it holds the unit's serial number and factory data.
"""
import argparse
import glob
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from techo5lib import Adb, default_dir, fail, md5, need, note, run_main, step  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--serial', required=True, help="the unit's adb serial (adb devices)")
    ap.add_argument('--include-system', action='store_true', help='also system and cache')
    ap.add_argument('--backups', default=default_dir('TECHO5_BACKUPS', 'backups'))
    ap.add_argument('--adb', default='adb')
    a = ap.parse_args()
    need(a.adb, 'install the Android platform tools (adb)')
    adb = Adb(a.serial, a.adb)

    step('device %s' % a.serial)
    state = adb.state()
    if state not in ('device', 'recovery'):
        fail("adb does not see %s (state '%s'). Boot it into TWRP, or Fire OS/LineageOS with root adb, with USB connected." % (a.serial, state))
    product = adb.sh('getprop ro.product.device; getprop ro.build.product')
    if 'rook' not in product:
        fail("%s reports '%s', not rook" % (a.serial, product))
    if not adb.sh('id').startswith('uid=0'):
        fail('adb is not root on %s. Use TWRP, or enable rooted debugging.' % a.serial)
    bn = adb.sh('for d in /dev/block/platform/bootdevice/by-name /dev/block/platform/mtk-msdc.0/by-name '
                '/dev/block/platform/soc/by-name /dev/block/by-name; do [ -e $d/boot ] && { echo $d; break; }; done')
    if not bn:
        fail('no by-name partition links with a boot partition on %s' % a.serial)
    note('rook in %s, partitions under %s' % (state, bn))

    unit = os.path.join(a.backups, a.serial)
    os.makedirs(unit, exist_ok=True)
    step('backups to %s' % unit)
    with open(os.path.join(unit, 'partitions.txt'), 'w', newline='\n') as f:
        f.write(adb.sh('cat /proc/partitions; echo; ls -l %s' % bn) + '\n')

    def backup(name, src, read_cmd=None):
        out = os.path.join(unit, name + '.img')
        hash_cmd = ('%s 2>/dev/null | md5sum' % read_cmd) if read_cmd else ('md5sum %s 2>/dev/null' % src)
        dev = adb.sh(hash_cmd).split('\n')[-1].split(' ')[0].strip()
        if len(dev) != 32:
            fail('could not read %s (%s) on %s' % (name, src, a.serial))
        if os.path.exists(out) and md5(out) == dev:
            note('%s already backed up' % name)
            return
        for other in glob.glob(os.path.join(unit, name + '-*.img')):
            if md5(other) == dev:
                note('%s already backed up as %s' % (name, os.path.basename(other)))
                return
        dest = out if not os.path.exists(out) else os.path.join(unit, '%s-%s.img' % (name, time.strftime('%Y%m%d-%H%M%S')))
        tmp = dest + '.partial'
        if read_cmd:
            # exec-out, for short reads only: TWRP's adbd runs it without a shell, and a long stream stalls.
            ok = adb.exec_out_to_file(read_cmd, tmp) == 0
        else:
            # adb pull reads a block device to its end through the sync protocol, which does not stall.
            ok = adb.pull(src, tmp)
        if not ok:
            if os.path.exists(tmp):
                os.remove(tmp)
            fail('reading %s failed' % name)
        got = md5(tmp)
        if got != dev:
            os.remove(tmp)
            fail('%s copy does not match the device (%s vs %s)' % (name, got, dev))
        os.replace(tmp, dest)
        note('%s %d bytes, md5 ok%s' % (name, os.path.getsize(dest), '' if dest == out else ' (changed since %s.img; saved as %s)' % (name, os.path.basename(dest))))

    backup('gpt', '/dev/block/mmcblk0', 'head -c 17408 /dev/block/mmcblk0')
    if adb.sh('test -e /dev/block/mmcblk0boot0 && echo yes') == 'yes':
        backup('preloader', '/dev/block/mmcblk0boot0')
    else:
        note('no /dev/block/mmcblk0boot0 on this kernel; preloader not copied')
    parts = ['lk', 'tee1', 'tee2', 'expdb', 'MISC', 'logo', 'para', 'kb', 'dkb', 'nvram', 'proinfo', 'seccfg',
             'persistbackup', 'frp', 'persist', 'metadata', 'boot', 'recovery']
    if a.include_system:
        parts += ['system', 'cache']
    for p in parts:
        # amonet's TWRP on other Echos points bootloader partitions at decoy files so an OTA zip cannot
        # overwrite the unlock; the real partition is then the *_real link. A copy of a decoy restores nothing.
        src = adb.sh('s=%s/%s; [ -e $s ] || { echo missing; exit; }; [ -e ${s}_real ] && s=${s}_real; r=$(readlink -f $s); '
                     'case $r in /tmp/*|/dev/null) echo decoy;; *) echo $r;; esac' % (bn, p))
        if src == 'missing':
            note('%s: not on this unit, skipped' % p)
            continue
        if src == 'decoy':
            fail('%s on %s points at a decoy with no real partition beside it' % (p, a.serial))
        backup(p, src)

    step('done')
    note('keep %s off the device; boot.img and recovery.img are the way back' % unit)


if __name__ == '__main__':
    run_main(main)
